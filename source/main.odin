package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"
import ns "core:sys/darwin/Foundation"
import rl "vendor:raylib"

Shelf_Layout :: struct {
	horizontal: bool,
	length, thickness, start, step: i32,
}

shelf_layout :: proc(settings: Settings, count: int) -> Shelf_Layout {
	horizontal := settings.edge == .Top || settings.edge == .Bottom
	along := horizontal ? settings.horizontal_margin : settings.vertical_margin
	across := horizontal ? settings.vertical_margin : settings.horizontal_margin
	step := settings.icon_size + settings.icon_gap
	length := 2 * along + settings.icon_size + i32(max(0, count - 1)) * step
	start := along
	thickness := settings.icon_size + 2 * across
	if settings.magnification_percent > 0 {
		grown := (settings.icon_size * (100 + settings.magnification_percent) + 99) / 100
		thickness = max(thickness, grown)
		if length < grown {
			start += (grown - length) / 2
			length = grown
		}
	}
	return {horizontal, length, thickness, start, step}
}

App :: struct {
	pid: i32,
	name: string,
	icon: rl.Texture2D,
	hover_scale: f32,
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
		hover_scale: f32
		name: string
		cached := false
		for &previous in apps^ {
			if previous.pid == pid {
				icon = previous.icon
				hover_scale = previous.hover_scale
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
		append(&next, App{pid, name, icon, hover_scale})
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

shelf_frames :: proc(window: ^ns.Object, rows: int, settings: Settings) -> (resting, display: ns.Rect) {
	screen := send(^ns.Screen, window, "screen")
	if screen == nil {
		screen = send(^ns.Screen, native_class("NSScreen"), "mainScreen")
	}
	if screen == nil {
		return
	}
	available := send_rect((^ns.Object)(screen), "visibleFrame")
	layout := shelf_layout(settings, rows)
	width := ns.Float(layout.thickness)
	height := min(ns.Float(layout.length), available.size.height)
	if layout.horizontal {
		width = min(ns.Float(layout.length), available.size.width)
		height = ns.Float(layout.thickness)
	}
	x := available.origin.x + (available.size.width - width) / 2
	y := available.origin.y + (available.size.height - height) / 2
	gap := ns.Float(settings.screen_edge_gap)
	switch settings.edge {
	case .Left: x = available.origin.x + gap
	case .Right: x = available.origin.x + available.size.width - width - gap
	case .Bottom: y = available.origin.y + gap
	case .Top: y = available.origin.y + available.size.height - height - gap
	}
	resting = ns.Rect{origin = {x, y}, size = {width, height}}
	display = send_rect((^ns.Object)(screen), "frame")
	return
}

when !#config(HOOD_UI_MODULE, false) {
	main :: proc() {
		run_shelf()
	}
}

run_shelf :: proc() {
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
	initial_layout := shelf_layout(settings, 0)
	rl.InitWindow(initial_layout.thickness, initial_layout.length, "Hood")
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
	next_refresh, next_app_refresh: f64
	visibility := Shelf_Visibility{progress = 1, requested = true, showing = true}
	scroll: f32
	settings_process: os.Process
	defer {
		if settings_process.pid != 0 {
			_ = os.process_kill(settings_process)
			_, _ = os.process_wait(settings_process)
		}
	}
	ui: Live_UI
	defer close_live_ui(&ui)
	tooltip: Tooltip
	defer close_tooltip(&tooltip)
	hovered_pid: i32
	hover_started: f64
	for !rl.WindowShouldClose() {
		now := rl.GetTime()
		if now >= next_app_refresh {
			active_pid = refresh_apps(workspace, &apps)
			next_app_refresh = now + (1.0 if visibility.hidden else 0.25)
		}
		if now >= next_refresh {
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
			visibility.resting, visibility.display = shelf_frames(window, len(apps), settings)
			next_refresh = now + 0.25
		}

		was_hidden := visibility.hidden
		interactive := update_shelf_visibility(window, &visibility, settings, keep_visible = settings_process.pid != 0)
		if visibility.hidden {
			hide_tooltip(&tooltip)
			hovered_pid = 0
			// Keep Cocoa responsive and check the reveal edge without drawing or swapping buffers.
			rl.PollInputEvents()
			time.sleep(40 * time.Millisecond)
			continue
		}
		if was_hidden {
			next_app_refresh = 0
		}
		width, height := rl.GetScreenWidth(), rl.GetScreenHeight()
		layout := shelf_layout(settings, len(apps))
		viewport := layout.horizontal ? width : height
		max_scroll := f32(max(0, layout.length - viewport))
		scroll = clamp(scroll - rl.GetMouseWheelMove() * f32(layout.step), 0, max_scroll)
		open_settings := false
		context_click := interactive && rl.IsMouseButtonReleased(.RIGHT)
		if context_click {
			hide_tooltip(&tooltip)
			open_settings = show_context_menu(window)
		}
		if rl.IsKeyPressed(.ESCAPE) {
			break
		}

		result := ui_shelf(&ui, apps[:], settings, width, height, scroll, active_pid, context_click || !interactive)
		if result.clicked_pid != 0 {
			target := send(^ns.Object, native_class("NSRunningApplication"),
				"runningApplicationWithProcessIdentifier:", result.clicked_pid)
			send(ns.BOOL, target, "activateWithOptions:", uint(0))
		}
		hovered := result.hovered
		if hovered.pid != hovered_pid {
			hovered_pid = hovered.pid
			hover_started = rl.GetTime()
		}
		if hovered.name != "" && rl.GetTime() - hover_started >= f64(settings.tooltip_delay_ms) / 1000 && !open_settings {
			show_tooltip(&tooltip, window, hovered, result.tooltip_center, settings.edge)
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
