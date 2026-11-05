package main

import ns "vendor:darwin/AppKit"

foreign import hood_native "../build/native/libhood_native.a"
@(require)
foreign import quartz_core "system:QuartzCore.framework"

Native_Input :: struct {
	pressed, released, down, right, escape: i32,
	wheel: f64,
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
	hood_tooltip_show :: proc "c" (tip, window: ^ns.Object, text: cstring, x, y: f32, edge: i32) ---
}
