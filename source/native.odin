package main

import ns "vendor:darwin/AppKit"

foreign import hood_native "../build/native/libhood_native.a"
@(require)
foreign import quartz_core "system:QuartzCore.framework"

Native_Input :: struct {
	pressed, released, down, right, escape: i32,
	wheel: f64,
}

Native_Settings_State :: struct {
	edge, icon_size, corner_radius:                 i32,
	background_rgb:                                u32,
	icon_gap, horizontal_margin, vertical_margin:  i32,
	screen_edge_gap, show_hide_delay_ms:            i32,
	auto_hide, animation_tenths, tooltip_delay_ms:  i32,
	hover_wave, magnification_percent:              i32,
	hover_animation_tenths:                         i32,
	tooltip_opacity_percent:                        i32,
}

Native_Settings_Events :: struct {
	changed, closed, toggle_login, quit_dock: i32,
}

foreign hood_native {
	hood_time :: proc "c" () -> f64 ---
	hood_create :: proc "c" () -> ^ns.Object ---
	hood_close :: proc "c" (window: ^ns.Object) ---
	hood_poll :: proc "c" (window: ^ns.Object, input: ^Native_Input, wait: f64) ---
	hood_begin :: proc "c" (window: ^ns.Object, rgb: u32, radius: f64, x, y, width, height: f32) ---
	hood_icon :: proc "c" (window: ^ns.Object, image: rawptr, x, y, width, height: f32) ---
	hood_end :: proc "c" (window: ^ns.Object) ---
	hood_tooltip_create :: proc "c" () -> ^ns.Object ---
	hood_tooltip_show :: proc "c" (tip, window: ^ns.Object, text: cstring, x, y: f32, edge, opacity_percent: i32) ---
	hood_settings_create :: proc "c" (
		state: ^Native_Settings_State,
		bundled, login_available, login_enabled, login_pending: i32,
	) -> ^ns.Object ---
	hood_settings_close :: proc "c" (window: ^ns.Object) ---
	hood_settings_poll :: proc "c" (
		window: ^ns.Object,
		state: ^Native_Settings_State,
		events: ^Native_Settings_Events,
		wait: f64,
	) ---
	hood_settings_update :: proc "c" (window: ^ns.Object, state: ^Native_Settings_State) ---
	hood_settings_set_save_failed :: proc "c" (window: ^ns.Object, failed: i32) ---
	hood_settings_set_runtime :: proc "c" (
		window: ^ns.Object,
		memory_bytes: u64,
		cpu_percent: f64,
		available, cpu_available, bundled, login_available, login_enabled, login_pending, login_failed: i32,
	) ---
}
