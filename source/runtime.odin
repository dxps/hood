package main

import "core:fmt"
import "core:dynlib"
import "core:os"
import "core:strings"
import ns "vendor:darwin/AppKit"

// Matches rusage_info_v0 in the macOS SDK's sys/resource.h.
Runtime_Usage :: struct {
	uuid: [16]u8,
	user_time, system_time, idle_wakeups, interrupt_wakeups, pageins: u64,
	wired_size, resident_size, physical_footprint, start_time, exit_time: u64,
}

Mach_Timebase_Info :: struct {
	numer, denom: u32,
}

CPU_HISTORY_LENGTH :: 6
LOGIN_STATUS_UNAVAILABLE :: 20
LOGIN_STATUS_DISABLED :: 21
LOGIN_STATUS_ENABLED :: 22
LOGIN_STATUS_PENDING :: 23
LOGIN_STATUS_FAILED :: 24

foreign import libproc "system:proc"
foreign libproc {
	proc_pid_rusage :: proc "c" (pid: i32, flavor: i32, usage: ^Runtime_Usage) -> i32 ---
}
foreign import libsystem "system:System"
foreign libsystem {
	mach_timebase_info :: proc "c" (info: ^Mach_Timebase_Info) -> i32 ---
}

Runtime_State :: struct {
	available, cpu_available, quit_failed: bool,
	dock_pid: i32,
	memory_bytes: u64,
	cpu_ticks: [CPU_HISTORY_LENGTH]u64,
	cpu_times: [CPU_HISTORY_LENGTH]f64,
	cpu_history_count, cpu_history_next: int,
	cpu_percent, cpu_tick_ns: f64,
	bundled, login_available, login_enabled, login_pending, login_failed: bool,
	login_executable: string,
	login_service: ^ns.Object,
	service_library: dynlib.Library,
}

update_runtime :: proc(state: ^Runtime_State) {
	// The nested Settings app delegates login-item changes to the outer app.
	// Avoid launching a status helper every second unless approval is pending.
	if state.login_executable == "" || state.login_pending {
		refresh_login_status(state)
	}
	usage: Runtime_Usage
	state.available = state.dock_pid > 1 && proc_pid_rusage(state.dock_pid, 0, &usage) == 0
	if !state.available {
		state.cpu_available = false
		state.cpu_history_count = 0
		state.cpu_history_next = 0
		return
	}
	if state.cpu_tick_ns == 0 {
		timebase: Mach_Timebase_Info
		if mach_timebase_info(&timebase) != 0 || timebase.denom == 0 {
			state.cpu_available = false
			return
		}
		state.cpu_tick_ns = f64(timebase.numer) / f64(timebase.denom)
	}
	state.memory_bytes = usage.physical_footprint
	now := hood_time()
	total_ticks := usage.user_time + usage.system_time
	index := state.cpu_history_next
	state.cpu_ticks[index] = total_ticks
	state.cpu_times[index] = now
	state.cpu_history_next = (index + 1) % CPU_HISTORY_LENGTH
	state.cpu_history_count = min(state.cpu_history_count + 1, CPU_HISTORY_LENGTH)
	oldest := 0 if state.cpu_history_count < CPU_HISTORY_LENGTH else state.cpu_history_next
	old_ticks := state.cpu_ticks[oldest]
	old_time := state.cpu_times[oldest]
	if state.cpu_history_count > 1 && now > old_time && total_ticks >= old_ticks {
		state.cpu_percent = f64(total_ticks - old_ticks) * state.cpu_tick_ns / 1e9 / (now - old_time) * 100
		state.cpu_available = true
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
	state.login_available = state.login_service != nil
	refresh_login_status(state)
}

init_remote_runtime_login :: proc(state: ^Runtime_State, executable: string) {
	state.login_executable = executable
	refresh_login_status(state)
}

refresh_login_status :: proc(state: ^Runtime_State) {
	if state.login_executable != "" {
		result, stdout, stderr, err := os.process_exec(
			{command = {state.login_executable, "--login-status"}},
			context.temp_allocator,
		)
		_ = stdout
		_ = stderr
		state.login_available = err == nil && result.exit_code != LOGIN_STATUS_UNAVAILABLE
		state.bundled = state.login_available
		state.login_enabled = err == nil && result.exit_code == LOGIN_STATUS_ENABLED
		state.login_pending = err == nil && result.exit_code == LOGIN_STATUS_PENDING
		return
	}
	if state.login_service != nil {
		status := send(int, state.login_service, "status")
		state.login_enabled = status == 1
		state.login_pending = status == 2
	}
}

toggle_runtime_login :: proc(state: ^Runtime_State) {
	if state.login_executable != "" {
		result, stdout, stderr, err := os.process_exec(
			{command = {state.login_executable, "--toggle-login"}},
			context.temp_allocator,
		)
		_ = stdout
		_ = stderr
		state.login_failed = err != nil || result.exit_code == LOGIN_STATUS_FAILED
		refresh_login_status(state)
		return
	}
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

runtime_login_exit_code :: proc(toggle: bool) -> int {
	state: Runtime_State
	init_runtime_login(&state)
	defer close_runtime_login(&state)
	if !state.login_available {
		return LOGIN_STATUS_UNAVAILABLE
	}
	if toggle {
		toggle_runtime_login(&state)
	}
	if state.login_failed {
		return LOGIN_STATUS_FAILED
	}
	if state.login_pending {
		return LOGIN_STATUS_PENDING
	}
	if state.login_enabled {
		return LOGIN_STATUS_ENABLED
	}
	return LOGIN_STATUS_DISABLED
}
