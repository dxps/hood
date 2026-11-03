package main

import "core:math"
import ns "core:sys/darwin/Foundation"

set_color_panel_rgb :: proc(panel: ^ns.Object, rgb: u32) {
	channel :: proc(value: u32) -> ns.Float {
		return ns.Float(value & 0xFF) / 255
	}
	make_color := cast(proc "c" (
		_: ^ns.Object,
		_: ns.SEL,
		_: ns.Float,
		_: ns.Float,
		_: ns.Float,
		_: ns.Float,
	) -> ^ns.Object)objc_msgSend
	color := make_color(
		native_class("NSColor"),
		ns.sel_registerName("colorWithSRGBRed:green:blue:alpha:"),
		channel(rgb >> 16),
		channel(rgb >> 8),
		channel(rgb),
		1,
	)
	notify(panel, "setColor:", color)
}

color_panel_rgb :: proc(panel: ^ns.Object) -> (u32, bool) {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	color := send(^ns.Object, panel, "color")
	srgb := send(^ns.Object, native_class("NSColorSpace"), "sRGBColorSpace")
	color = send(^ns.Object, color, "colorUsingColorSpace:", srgb)
	if color == nil {
		return 0, false
	}
	channel :: proc(color: ^ns.Object, selector: cstring) -> u32 {
		value := f64(send(ns.Float, color, selector))
		return u32(math.round(clamp(value, 0, 1) * 255))
	}
	return channel(color, "redComponent") << 16 | channel(color, "greenComponent") << 8 | channel(color, "blueComponent"), true
}
