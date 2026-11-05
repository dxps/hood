package main

import "core:fmt"
import "core:os"
import "core:strings"
import cf "core:sys/darwin/CoreFoundation"
import cg "core:sys/darwin/CoreGraphics"
import objcrt "core:sys/darwin/ObjectiveC"
import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

Shelf_Layout :: struct {
	horizontal:                                      bool,
	length, thickness, shelf_thickness, start, step: i32,
}

shelf_layout :: proc(settings: Settings, count: int) -> Shelf_Layout {
	horizontal := settings.edge == .Top || settings.edge == .Bottom
	along := horizontal ? settings.horizontal_margin : settings.vertical_margin
	across := horizontal ? settings.vertical_margin : settings.horizontal_margin
	step := settings.icon_size + settings.icon_gap
	length := 2 * along + settings.icon_size + i32(max(0, count - 1)) * step
	start := along
	shelf_thickness := settings.icon_size + 2 * across
	thickness := shelf_thickness
	if settings.magnification_percent > 0 {
		grown := (settings.icon_size * (100 + settings.magnification_percent) + 99) / 100
		lift := (settings.icon_size * 45 + 99) / 100 if settings.hover_wave else 0
		// Keep an inward, transparent canvas around the shelf. The background
		// remains shelf_thickness wide while magnified icons use this extra room.
		overflow := max(0, (grown - settings.icon_size + 1) / 2 + lift - across)
		thickness += overflow
		if length < grown {
			start += (grown - length) / 2
			length = grown
		}
	}
	return {horizontal, length, thickness, shelf_thickness, start, step}
}

App :: struct {
	order_id:    u64,
	pid:         i32,
	bundle_id:   string,
	name:        string,
	icon:        rawptr,
	hover_scale: f32,
}

next_app_order_id: u64 = 1

new_app_order_id :: proc() -> u64 {
	id := next_app_order_id
	next_app_order_id += 1
	return id
}

native_class :: proc(name: cstring) -> ^ns.Object {
	return (^ns.Object)(objcrt.objc_lookUpClass(name))
}


cocoa_window :: proc() -> ^ns.Object {
	window := (^ns.Object)(rl.GetWindowHandle())
	if send(ns.BOOL, window, "isKindOfClass:", objcrt.objc_lookUpClass("NSView")) {
		window = send(^ns.Object, window, "window")
	}
	return window
}

application_has_visible_window :: proc(pid: i32) -> bool {
	windows := cg.WindowListCopyWindowInfo(.OnScreenOnly, 0)
	if windows == nil {
		return true
	}
	defer cf.Release(cast(cf.TypeRef)windows)
	return application_has_window(windows, pid)
}

application_has_window :: proc(windows: cf.ArrayRef, pid: i32) -> bool {
	// Keep apps available if the system cannot provide a window snapshot.
	if windows == nil {
		return true
	}
	for index in 0 ..< cf.ArrayGetCount(windows) {
		info := cast(cf.DictionaryRef)cf.ArrayGetValueAtIndex(windows, index)
		owner_value := cast(cf.NumberRef)cf.DictionaryGetValue(info, cg.WindowOwnerPID)
		layer_value := cast(cf.NumberRef)cf.DictionaryGetValue(info, cg.WindowLayer)
		if owner_value == nil || layer_value == nil {
			continue
		}
		owner, layer: i32
		if !cf.NumberGetValue(owner_value, .SInt32Type, &owner) ||
		   !cf.NumberGetValue(layer_value, .SInt32Type, &layer) {
			continue
		}
		if owner == pid && layer == 0 {
			return true
		}
	}
	return false
}

reopen_application :: proc(workspace: ^ns.Object, bundle_id: string) {
	if bundle_id == "" {
		return
	}
	identifier := send(
		^ns.Object,
		native_class("NSString"),
		"stringWithUTF8String:",
		strings.clone_to_cstring(bundle_id, context.temp_allocator),
	)
	url := send(^ns.Object, workspace, "URLForApplicationWithBundleIdentifier:", identifier)
	if url != nil {
		send(ns.BOOL, workspace, "openURL:", url)
	}
}

app_bundle_identifier :: proc(app: ^ns.Object) -> string {
	value := send(^ns.Object, app, "bundleIdentifier")
	if value == nil {
		return ""
	}
	return string(send(cstring, value, "UTF8String"))
}

load_pinned_app :: proc(workspace: ^ns.Object, identifier: string) -> (App, bool) {
	id := send(^ns.Object, native_class("NSString"), "stringWithUTF8String:", strings.clone_to_cstring(identifier, context.temp_allocator))
	url := send(^ns.Object, workspace, "URLForApplicationWithBundleIdentifier:", id)
	if url == nil {
		return {}, false
	}
	path := send(^ns.Object, url, "path")
	if path == nil {
		return {}, false
	}
	name := send(^ns.Object, path, "lastPathComponent")
	name = send(^ns.Object, name, "stringByDeletingPathExtension")
	icon := send(^ns.Object, workspace, "iconForFile:", path)
	return App {
		order_id  = new_app_order_id(),
		bundle_id = strings.clone(identifier),
		name      = strings.clone(string(send(cstring, name, "UTF8String"))),
		icon      = load_icon_image(icon),
	}, true
}

refresh_apps :: proc(workspace: ^ns.Object, apps: ^[dynamic]App, pinned, app_order: []string) -> i32 {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	running := send(^ns.Object, workspace, "runningApplications")
	// Include minimized windows and windows on other Spaces, not just on-screen ones.
	windows := cg.WindowListCopyWindowInfo(.All, 0)
	defer if windows != nil {
		cf.Release(cast(cf.TypeRef)windows)
	}
	next: [dynamic]App
	for index in 0 ..< send(uint, running, "count") {
		app := send(^ns.Object, running, "objectAtIndex:", index)
		if send(int, app, "activationPolicy") != 0 || send(ns.BOOL, app, "isTerminated") {
			continue
		}
		pid := send(i32, app, "processIdentifier")
		bundle_id := app_bundle_identifier(app)
		if pinned_app_index(pinned, bundle_id) < 0 && !application_has_window(windows, pid) {
			continue
		}
		candidate: App
		for &previous in apps^ {
			if (bundle_id != "" && previous.bundle_id == bundle_id) || previous.pid == pid {
				candidate = previous
				previous.bundle_id = ""
				previous.name = ""
				previous.icon = {}
				break
			}
		}
		if candidate.order_id == 0 {
			label := send(cstring, send(^ns.Object, app, "localizedName"), "UTF8String")
			candidate = App {
				order_id  = new_app_order_id(),
				pid       = pid,
				bundle_id = strings.clone(bundle_id),
				name      = strings.clone(string(label)),
				icon      = load_icon(app),
			}
		} else {
			candidate.pid = pid
			if candidate.bundle_id == "" && bundle_id != "" {
				candidate.bundle_id = strings.clone(bundle_id)
			}
		}
		append(&next, candidate)
	}
	for identifier in pinned {
		found := false
		for candidate in next {
			if candidate.bundle_id == identifier {
				found = true
				break
			}
		}
		if found {
			continue
		}
		candidate: App
		for &previous in apps^ {
			if previous.bundle_id == identifier {
				candidate = previous
				candidate.pid = 0
				previous.bundle_id = ""
				previous.name = ""
				previous.icon = {}
				break
			}
		}
		if candidate.order_id == 0 {
			loaded: bool
			candidate, loaded = load_pinned_app(workspace, identifier)
			if !loaded {
				continue
			}
		}
		append(&next, candidate)
	}
	ordered: [dynamic]App
	for identifier in app_order {
		for &candidate in next {
			if candidate.bundle_id == identifier {
				append(&ordered, candidate)
				candidate = {}
				break
			}
		}
	}
	for previous in apps^ {
		for &candidate in next {
			if candidate.order_id == previous.order_id {
				append(&ordered, candidate)
				candidate = {}
				break
			}
		}
	}
	for candidate in next {
		if candidate.order_id != 0 {
			append(&ordered, candidate)
		}
	}
	delete(next)
	free_apps(apps^)
	apps^ = ordered
	return send(i32, send(^ns.Object, workspace, "frontmostApplication"), "processIdentifier")
}

free_apps :: proc(apps: [dynamic]App) {
	for app in apps {
		delete(app.bundle_id)
		delete(app.name)
		if app.icon != nil {
			CGImageRelease(app.icon)
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
	case .Left:
		x = available.origin.x + gap
	case .Right:
		x = available.origin.x + available.size.width - width - gap
	case .Bottom:
		y = available.origin.y + gap
	case .Top:
		y = available.origin.y + available.size.height - height - gap
	}
	resting = ns.Rect {
		origin = {x, y},
		size   = {width, height},
	}
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
	config_dir, config_path, pinned_path, order_path: string
	settings := DEFAULT_SETTINGS
	if home_err == nil {
		config_dir = fmt.aprintf("%s/.config/hood", home)
		config_path = fmt.aprintf("%s/hood.toml", config_dir)
		pinned_path = fmt.aprintf("%s/pinned-apps", config_dir)
		order_path = fmt.aprintf("%s/app-order", config_dir)
		settings = load_settings(config_path)
	}

	if len(os.args) > 1 && os.args[1] == "--settings" {
		run_settings(config_dir, config_path, settings)
		return
	}
	executable, executable_err := os.get_executable_path(context.allocator)
	pinned_apps := load_pinned_apps(pinned_path)
	defer free_pinned_apps(pinned_apps)
	app_order := load_pinned_apps(order_path)
	defer free_pinned_apps(app_order)

	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	window := hood_create()
	if window == nil {
		fmt.eprintln("Hood could not create its native shelf window.")
		return
	}
	defer hood_close(window)
	workspace := send(^ns.Object, native_class("NSWorkspace"), "sharedWorkspace")

	apps: [dynamic]App
	defer {
		free_apps(apps)
	}
	active_pid: i32
	next_refresh, next_app_refresh: f64
	visibility := Shelf_Visibility {
		progress  = 1,
		requested = true,
		showing   = true,
	}
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
	hovered_id: u64
	hover_started: f64
	last_pointer := ns.Point{-1e9, -1e9}
	redraw_until: f64
	startup_visible_until := hood_time() + 2
	last_frame := hood_time()
	input: Native_Input
	wait: f64 = 0
	for {
		// Bound temporary Cocoa and Odin allocations to one event-loop iteration.
		frame_pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
		defer notify(frame_pool, "drain")
		defer free_all(context.temp_allocator)

		hood_poll(window, &input, wait)
		if input.escape != 0 {
			break
		}
		now := hood_time()
		delta := min(now - last_frame, 0.05)
		last_frame = now
		wait = 1.0 / 60
		redraw := false
		if now >= next_app_refresh {
			active_pid = refresh_apps(workspace, &apps, pinned_apps[:], app_order[:])
			_, order_err := sync_app_order(config_dir, order_path, &app_order, apps[:])
			if order_err != nil {
				fmt.eprintfln("Could not save app order: %v", order_err)
			}
			next_app_refresh = now + 1.0
			redraw = true
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
			old_frame := visibility.resting
			visibility.resting, visibility.display = shelf_frames(window, len(apps), settings)
			redraw = redraw || old_frame != visibility.resting || settings_process.pid != 0
			next_refresh = now + 0.25
		}

		frontmost := send(i32, send(^ns.Object, workspace, "frontmostApplication"), "processIdentifier")
		redraw = redraw || frontmost != active_pid
		active_pid = frontmost
		was_hidden := visibility.hidden
		interactive := update_shelf_visibility(
			window,
			&visibility,
			settings,
			now, delta,
			keep_visible = now < startup_visible_until || settings_process.pid != 0,
		)
		if visibility.hidden {
			hide_tooltip(&tooltip)
			hovered_id = 0
			// Keep Cocoa responsive and check the reveal edge without drawing or swapping buffers.
			wait = 0.04
			continue
		}
		if was_hidden {
			next_app_refresh = 0
		}
		pointer := send(ns.Point, window, "mouseLocationOutsideOfEventStream")
		bounds := send_rect(window, "frame").size
		pointer_inside := pointer.x >= 0 && pointer.y >= 0 && pointer.x < bounds.width && pointer.y < bounds.height
		previous_inside := last_pointer.x >= 0 && last_pointer.y >= 0 && last_pointer.x < bounds.width && last_pointer.y < bounds.height
		if (pointer != last_pointer && (pointer_inside || previous_inside)) || input.down != 0 ||
		   input.released != 0 || input.right != 0 ||
		   f32(input.wheel) != 0 {
			redraw_until = now + max(f64(settings.hover_animation_tenths) / 10, f64(settings.tooltip_delay_ms) / 1000) + 0.1
		}
		last_pointer = pointer
		if !redraw && !was_hidden && now > redraw_until &&
		   (visibility.progress == 0 || visibility.progress == 1) && input.escape == 0 {
			// Preserve the last frame; still pump input so clicks and reveal remain responsive.
			wait = 0.04
			continue
		}
		width, height := i32(bounds.width), i32(bounds.height)
		layout := shelf_layout(settings, len(apps))
		viewport := layout.horizontal ? width : height
		max_scroll := f32(max(0, layout.length - viewport))
		scroll = clamp(scroll - f32(input.wheel) * f32(layout.step), 0, max_scroll)
		context_click := interactive && input.right != 0
		if context_click {
			hide_tooltip(&tooltip)
		}
		if input.escape != 0 {
			break
		}

		result := ui_shelf(&ui, window, &input, f32(delta), apps[:], settings, width, height, scroll, context_click || !interactive)
		if result.order_changed {
			_, order_err := sync_app_order(config_dir, order_path, &app_order, apps[:])
			if order_err != nil {
				fmt.eprintfln("Could not save app order: %v", order_err)
			}
		}
		menu_choice := Menu_Choice.None
		if context_click {
			context_app: ^App
			for &app in apps {
				if app.order_id == result.pointed_id {
					context_app = &app
					break
				}
			}
			kept := context_app != nil && pinned_app_index(pinned_apps[:], context_app.bundle_id) >= 0
			menu_choice = show_context_menu(window, context_app, kept)
			if menu_choice == .Keep_In_Dock && context_app != nil {
				err := set_pinned_app(config_dir, pinned_path, &pinned_apps, context_app.bundle_id, !kept)
				if err != nil {
					fmt.eprintfln("Could not save pinned apps: %v", err)
				} else {
					next_app_refresh = 0
				}
			}
		}
		open_settings := menu_choice == .Settings
		if result.clicked_id != 0 {
			clicked: ^App
			for &app in apps {
				if app.order_id == result.clicked_id {
					clicked = &app
					break
				}
			}
			if clicked != nil && clicked.pid != 0 {
				target := send(
					^ns.Object,
					native_class("NSRunningApplication"),
					"runningApplicationWithProcessIdentifier:",
					clicked.pid,
				)
				hidden := send(ns.BOOL, target, "isHidden")
				active := send(ns.BOOL, target, "isActive") || clicked.pid == active_pid
				visible := application_has_visible_window(clicked.pid)
				activate_all := ns.ApplicationActivationOptions{.ActivateAllWindows}
				if hidden {
					send(ns.BOOL, target, "unhide")
					send(ns.BOOL, target, "activateWithOptions:", activate_all)
				} else if active && visible {
					send(ns.BOOL, target, "hide")
				} else {
					if !visible {
						reopen_application(workspace, clicked.bundle_id)
					}
					send(ns.BOOL, target, "activateWithOptions:", activate_all)
				}
			} else if clicked != nil && clicked.bundle_id != "" {
				identifier := send(
					^ns.Object,
					native_class("NSString"),
					"stringWithUTF8String:",
					strings.clone_to_cstring(clicked.bundle_id, context.temp_allocator),
				)
				url := send(^ns.Object, workspace, "URLForApplicationWithBundleIdentifier:", identifier)
				if url != nil {
					send(ns.BOOL, workspace, "openURL:", url)
					next_app_refresh = 0
				}
			}
		}
		hovered := result.hovered
		if hovered.order_id != hovered_id {
			hovered_id = hovered.order_id
			hover_started = hood_time()
		}
		if hovered.name != "" && hood_time() - hover_started >= f64(settings.tooltip_delay_ms) / 1000 && !open_settings {
			show_tooltip(&tooltip, window, hovered, result.tooltip_center, settings.edge)
		} else {
			hide_tooltip(&tooltip)
		}
		if open_settings {
			fmt.eprintln("Hood: Settings selected")
			if settings_process.pid != 0 {
				target := send(
					^ns.Object,
					native_class("NSRunningApplication"),
					"runningApplicationWithProcessIdentifier:",
					i32(settings_process.pid),
				)
				send(ns.BOOL, target, "activateWithOptions:", uint(0))
			} else if executable_err == nil {
				err: os.Error
				settings_process, err = os.process_start({command = {executable, "--settings"}, stderr = os.stderr})
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
