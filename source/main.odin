package main

import "core:fmt"
import "core:os"
import "core:strings"
import ns "core:sys/darwin/Foundation"
import rl "vendor:raylib"

SHELF_WIDTH :: 68
ROW_HEIGHT :: 52
PADDING :: 6

App :: struct {
	pid: i32,
	name: string,
	icon: rl.Texture2D,
}

native_class :: proc(name: cstring) -> ^ns.Object {
	return (^ns.Object)(ns.objc_lookUpClass(name))
}


cocoa_window :: proc() -> ^ns.Object {
	window := (^ns.Object)(rl.GetWindowHandle())
	if send(ns.BOOL, window, "isKindOfClass:", ns.objc_lookUpClass("NSView")) {
		window = send(^ns.Object, window, "window")
	}
	return window
}

load_icon :: proc(app: ^ns.Object) -> rl.Texture2D {
	icon := send(^ns.Object, app, "icon")
	tiff := send(^ns.Object, icon, "TIFFRepresentation")
	if tiff == nil {
		return {}
	}
	bitmap := send(^ns.Object, native_class("NSBitmapImageRep"), "imageRepWithData:", tiff)
	// NSBitmapImageFileTypePNG
	png := send(^ns.Object, bitmap, "representationUsingType:properties:", uint(4),
		send(^ns.Object, native_class("NSDictionary"), "dictionary"))
	if png == nil {
		return {}
	}
	image := rl.LoadImageFromMemory(".png", send(rawptr, png, "bytes"), i32(send(uint, png, "length")))
	if image.data == nil {
		return {}
	}
	defer rl.UnloadImage(image)
	return rl.LoadTextureFromImage(image)
}

refresh_apps :: proc(workspace: ^ns.Object, apps: ^[dynamic]App) -> i32 {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	running := send(^ns.Object, workspace, "runningApplications")
	next: [dynamic]App
	for index in 0..<send(uint, running, "count") {
		app := send(^ns.Object, running, "objectAtIndex:", index)
		if send(int, app, "activationPolicy") != 0 ||
		   send(ns.BOOL, app, "isTerminated") {
			continue
		}
		pid := send(i32, app, "processIdentifier")
		icon: rl.Texture2D
		name: string
		cached := false
		for &previous in apps^ {
			if previous.pid == pid {
				icon = previous.icon
				name = previous.name
				previous.name = ""
				previous.icon = {}
				cached = true
				break
			}
		}
		if !cached {
			icon = load_icon(app)
			label := send(cstring, send(^ns.Object, app, "localizedName"), "UTF8String")
			name = strings.clone(string(label))
		}
		append(&next, App{pid, name, icon})
	}
	free_apps(apps^)
	apps^ = next
	return send(i32, send(^ns.Object, workspace, "frontmostApplication"), "processIdentifier")
}

free_apps :: proc(apps: [dynamic]App) {
	for app in apps {
		delete(app.name)
		if app.icon.id != 0 {
			rl.UnloadTexture(app.icon)
		}
	}
	delete(apps)
}

position_shelf :: proc(window: ^ns.Object, rows: int, settings: Settings) {
	screen := send(^ns.Screen, window, "screen")
	if screen == nil {
		screen = send(^ns.Screen, native_class("NSScreen"), "mainScreen")
	}
	if screen == nil {
		return
	}
	available := send_rect((^ns.Object)(screen), "visibleFrame")
	length := ns.Float(max(1, rows) * ROW_HEIGHT + 2 * PADDING)
	width := ns.Float(SHELF_WIDTH)
	height := min(length, available.size.height)
	if settings.edge == .Top || settings.edge == .Bottom {
		width = min(length, available.size.width)
		height = SHELF_WIDTH
	}
	x := available.origin.x + (available.size.width - width) / 2
	y := available.origin.y + (available.size.height - height) / 2
	switch settings.edge {
	case .Left: x = available.origin.x + 8
	case .Right: x = available.origin.x + available.size.width - width - 8
	case .Bottom: y = available.origin.y + 8
	case .Top: y = available.origin.y + available.size.height - height - 8
	}
	frame := ns.Rect{origin = {x, y}, size = {width, height}}
	if frame != send_rect(window, "frame") {
		notify(window, "setFrame:display:", frame, ns.BOOL(true))
	}
}

main :: proc() {
	home, home_err := os.user_home_dir(context.allocator)
	config_dir, config_path: string
	settings := DEFAULT_SETTINGS
	if home_err == nil {
		config_dir = fmt.aprintf("%s/.config/hood", home)
		config_path = fmt.aprintf("%s/hood.toml", config_dir)
		settings = load_settings(config_path)
	}

	if len(os.args) > 1 && os.args[1] == "--settings" {
		run_settings(config_dir, config_path, settings)
		return
	}
	executable, executable_err := os.get_executable_path(context.allocator)

	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	rl.SetConfigFlags({.WINDOW_UNDECORATED, .WINDOW_TRANSPARENT, .WINDOW_TOPMOST, .WINDOW_HIGHDPI, .VSYNC_HINT})
	rl.InitWindow(SHELF_WIDTH, ROW_HEIGHT + 2 * PADDING, "Hood")
	defer rl.CloseWindow()
	load_ui_font()
	defer rl.UnloadFont(work_sans)
	rl.SetTargetFPS(60)
	rl.SetExitKey(.KEY_NULL)

	window := cocoa_window()
	if !send(ns.BOOL, window, "isKindOfClass:", ns.objc_lookUpClass("NSWindow")) {
		fmt.eprintln("Hood could not obtain the Raylib Cocoa window.")
		return
	}
	application := send(^ns.Object, native_class("NSApplication"), "sharedApplication")
	send(ns.BOOL, application, "setActivationPolicy:", int(1))
	notify(window, "setCollectionBehavior:", ns.WindowCollectionBehaviorMoveToActiveSpace)
	workspace := send(^ns.Object, native_class("NSWorkspace"), "sharedWorkspace")

	apps: [dynamic]App
	defer {
		free_apps(apps)
	}
	active_pid: i32
	next_refresh: f64
	scroll: f32
	settings_process: os.Process
	defer {
		if settings_process.pid != 0 {
			_ = os.process_kill(settings_process)
			_, _ = os.process_wait(settings_process)
		}
	}
	tooltip: Tooltip
	defer close_tooltip(&tooltip)
	hovered_pid: i32
	hover_started: f64
	for !rl.WindowShouldClose() {
		if rl.GetTime() >= next_refresh {
			active_pid = refresh_apps(workspace, &apps)
			if settings_process.pid != 0 {
				if config_path != "" {
					settings = load_settings(config_path)
				}
				state, err := os.process_wait(settings_process, timeout = 0)
				if err != .Timeout {
					if err != nil || !state.success {
						fmt.eprintfln("Hood Settings exited unexpectedly (exit %d, error %v)", state.exit_code, err)
					}
					settings_process = {}
				}
			}
			position_shelf(window, len(apps), settings)
			next_refresh = rl.GetTime() + 0.25
		}

		width, height := rl.GetScreenWidth(), rl.GetScreenHeight()
		horizontal := settings.edge == .Top || settings.edge == .Bottom
		viewport := horizontal ? width : height
		max_scroll := f32(max(0, len(apps) * ROW_HEIGHT + 2 * PADDING - int(viewport)))
		scroll = clamp(scroll - rl.GetMouseWheelMove() * ROW_HEIGHT, 0, max_scroll)
		mouse := rl.GetMousePosition()
		open_settings := false
		context_click := rl.IsMouseButtonReleased(.RIGHT)
		if context_click {
			hide_tooltip(&tooltip)
			open_settings = show_context_menu(window)
		}
		if rl.IsKeyPressed(.ESCAPE) {
			break
		}

		rl.BeginDrawing()
		rl.ClearBackground(rl.BLANK)
		shelf_rect := rl.Rectangle{0, 0, f32(width), f32(height)}
		roundness := min(1, 2 * f32(settings.corner_radius) / min(shelf_rect.width, shelf_rect.height))
		rl.DrawRectangleRounded(shelf_rect, roundness, 12, rl.GetColor(settings.background_rgb << 8 | 0xFF))
		hovered: App
		tooltip_center: rl.Vector2
		for app, index in apps {
			offset := f32(PADDING + index * ROW_HEIGHT) - scroll
			row := rl.Rectangle{8, offset, SHELF_WIDTH - 16, ROW_HEIGHT - 4}
			if horizontal {
				row = {offset, 8, ROW_HEIGHT - 4, SHELF_WIDTH - 16}
			}
			center := rl.Vector2{row.x + row.width / 2, row.y + row.height / 2}
			hover := !context_click && rl.IsCursorOnScreen() && rl.CheckCollisionPointRec(mouse, row)
			if hover {
				hovered = app
				tooltip_center = center
			}
			if hover || app.pid == active_pid {
				rl.DrawRectangleRounded(row, 0.24, 8, {63, 63, 69, 255})
			}
			if app.icon.id != 0 {
				source := rl.Rectangle{0, 0, f32(app.icon.width), f32(app.icon.height)}
				size := f32(settings.icon_size)
				rl.DrawTexturePro(app.icon, source, {center.x - size / 2, center.y - size / 2, size, size}, {}, 0, rl.WHITE)
			} else {
				rl.DrawCircle(i32(center.x), i32(center.y), 10, rl.GRAY)
			}
			if hover && rl.IsMouseButtonReleased(.LEFT) {
				target := send(^ns.Object, native_class("NSRunningApplication"), "runningApplicationWithProcessIdentifier:", app.pid)
				send(ns.BOOL, target, "activateWithOptions:", uint(0))
			}
		}
		if hovered.pid != hovered_pid {
			hovered_pid = hovered.pid
			hover_started = rl.GetTime()
		}
		rl.EndDrawing()
		if hovered.name != "" && rl.GetTime() - hover_started >= 0.45 && !open_settings {
			show_tooltip(&tooltip, window, hovered, tooltip_center, settings.edge)
		} else {
			hide_tooltip(&tooltip)
		}
		if open_settings {
			fmt.eprintln("Hood: Settings selected")
			if settings_process.pid != 0 {
				target := send(^ns.Object, native_class("NSRunningApplication"),
					"runningApplicationWithProcessIdentifier:", i32(settings_process.pid))
				send(ns.BOOL, target, "activateWithOptions:", uint(0))
			} else if executable_err == nil {
				err: os.Error
				settings_process, err = os.process_start({
					command = {executable, "--settings"},
					stderr = os.stderr,
				})
				if err != nil {
					fmt.eprintfln("Could not open Hood Settings: %v", err)
				} else {
					fmt.eprintfln("Hood: Settings started (PID %v)", settings_process.pid)
				}
			} else {
				fmt.eprintfln("Could not locate Hood executable: %v", executable_err)
			}
		}
	}
}
