package main

import "core:fmt"
import "core:dynlib"
import "core:strings"
import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

// Matches rusage_info_v0 in the macOS SDK's sys/resource.h.
Runtime_Usage :: struct {
	uuid: [16]u8,
	user_time, system_time, idle_wakeups, interrupt_wakeups, pageins: u64,
	wired_size, resident_size, physical_footprint, start_time, exit_time: u64,
}

foreign import libproc "system:proc"
foreign libproc {
	proc_pid_rusage :: proc "c" (pid: i32, flavor: i32, usage: ^Runtime_Usage) -> i32 ---
}

Runtime_State :: struct {
	selected, available, quit_requested, quit_failed: bool,
	dock_pid: i32,
	memory_bytes: u64,
	next_sample, quit_hover_started: f64,
	quit_hovered: bool,
	bundled, login_enabled, login_pending, login_failed, login_toggle: bool,
	login_service: ^ns.Object,
	service_library: dynlib.Library,
}

update_runtime :: proc(state: ^Runtime_State) {
	usage: Runtime_Usage
	state.available = state.dock_pid > 1 && proc_pid_rusage(state.dock_pid, 0, &usage) == 0
	state.memory_bytes = usage.physical_footprint
	refresh_login_status(state)
}

runtime_view :: proc(theme: Settings_Theme, state: ^Runtime_State) {
	label := fmt.ctprintf("Memory usage: %.1f MB", f64(state.memory_bytes) / 1_000_000) if state.available else cstring("Memory usage: unavailable")
	draw_text(label, 20, 80, 16, theme.text)
	draw_text("Includes graphics memory. Updates every second.", 20, 114, 14, theme.text)
	login_available := state.bundled && state.login_service != nil
	login_color := theme.text
	if !login_available {
		login_color.a = 110
	}
	box := rl.Rectangle{20, 156, 20, 20}
	rl.DrawRectangleRounded(box, 0.25, 8, theme.button)
	rl.DrawRectangleRoundedLinesEx(box, 0.25, 8, 1, theme.popup_border)
	if state.login_enabled || state.login_pending {
		rl.DrawLineEx({24, 166}, {28, 171}, 2, login_color)
		rl.DrawLineEx({28, 171}, {36, 161}, 2, login_color)
	}
	draw_text("Launch at login", 50, 158, 16, login_color)
	if login_available && rl.CheckCollisionPointRec(rl.GetMousePosition(), {20, 152, 200, 28}) && rl.IsMouseButtonReleased(.LEFT) {
		state.login_toggle = true
	}
	draw_text("Automatically starts Hood when you log in.", 20, 187, 14, theme.text)
	if !state.bundled {
		draw_text("Available when running Hood.app.", 20, 209, 14, theme.text)
	} else if state.login_failed {
		draw_text("Could not update login item.", 20, 209, 14, theme.error)
	} else if state.login_pending {
		draw_text("Allow Hood in System Settings > Login Items.", 20, 209, 14, theme.text)
	} else if state.login_service == nil {
		draw_text("Launch at login is unavailable on this Mac.", 20, 209, 14, theme.error)
	}
	rect := rl.Rectangle{20, 250, 100, 34}
	if ui_button(theme, rect, "Quit") {
		state.quit_requested = true
	}
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	if hover && !state.quit_hovered {
		state.quit_hover_started = rl.GetTime()
	}
	state.quit_hovered = hover
	if hover && rl.GetTime() - state.quit_hover_started >= 0.45 {
		rl.DrawRectangleRounded({20, 292, 132, 28}, 0.35, 8, theme.button)
		draw_text("Quit the dock", 30, 299, 14, theme.text)
	}
	if state.quit_failed {
		draw_text("Could not quit the dock. Please try again.", 20, 338, 16, theme.error)
	}
}

init_runtime_login :: proc(state: ^Runtime_State) {
	bundle := send(^ns.Object, native_class("NSBundle"), "mainBundle")
	identifier := send(^ns.Object, bundle, "bundleIdentifier")
	path := send(^ns.Object, bundle, "bundlePath")
	if identifier == nil || path == nil {
		return
	}
	state.bundled = string(send(cstring, identifier, "UTF8String")) == "dev.dxps.hood" &&
		strings.has_suffix(string(send(cstring, path, "UTF8String")), ".app") && !LIVE_UI
	if !state.bundled {
		return
	}
	library, ok := dynlib.load_library("/System/Library/Frameworks/ServiceManagement.framework/ServiceManagement")
	if !ok {
		return
	}
	state.service_library = library
	service_class := native_class("SMAppService")
	if service_class != nil {
		state.login_service = send(^ns.Object, service_class, "mainAppService")
		notify(state.login_service, "retain")
	}
	refresh_login_status(state)
}

refresh_login_status :: proc(state: ^Runtime_State) {
	if state.login_service != nil {
		status := send(int, state.login_service, "status")
		state.login_enabled = status == 1
		state.login_pending = status == 2
	}
}

toggle_runtime_login :: proc(state: ^Runtime_State) {
	state.login_toggle = false
	refresh_login_status(state)
	selector: cstring = "registerAndReturnError:"
	if state.login_enabled || state.login_pending {
		selector = "unregisterAndReturnError:"
	}
	error: ^ns.Object
	state.login_failed = state.login_service == nil || !send(ns.BOOL, state.login_service, selector, &error)
	if error != nil {
		message := send(^ns.Object, error, "localizedDescription")
		fmt.eprintfln("Hood login item: %s", send(cstring, message, "UTF8String"))
	}
	refresh_login_status(state)
}

close_runtime_login :: proc(state: ^Runtime_State) {
	notify(state.login_service, "release")
	if state.service_library != nil {
		_ = dynlib.unload_library(state.service_library)
	}
}
