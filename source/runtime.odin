package main

import "core:fmt"
import "core:dynlib"
import "core:strings"
import ns "vendor:darwin/AppKit"

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
	available, quit_failed: bool,
	dock_pid: i32,
	memory_bytes: u64,
	bundled, login_enabled, login_pending, login_failed: bool,
	login_service: ^ns.Object,
	service_library: dynlib.Library,
}

update_runtime :: proc(state: ^Runtime_State) {
	usage: Runtime_Usage
	state.available = state.dock_pid > 1 && proc_pid_rusage(state.dock_pid, 0, &usage) == 0
	state.memory_bytes = usage.physical_footprint
	refresh_login_status(state)
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
