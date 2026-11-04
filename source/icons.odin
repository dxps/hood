package main

import ns "vendor:darwin/AppKit"


foreign import core_graphics "system:CoreGraphics.framework"

foreign core_graphics {
	CGBitmapContextCreateImage :: proc "c" (bitmap: rawptr) -> rawptr ---
	CGImageRelease :: proc "c" (image: rawptr) ---
	CGColorSpaceCreateDeviceRGB :: proc "c" () -> rawptr ---
	CGColorSpaceRelease :: proc "c" (space: rawptr) ---
	CGBitmapContextCreate :: proc "c" (pixels: rawptr, width, height, bits, stride: uint,
		space: rawptr, format: u32) -> rawptr ---
	CGContextRelease :: proc "c" (graphics: rawptr) ---
}

load_icon :: proc(app: ^ns.Object) -> rawptr {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	icon := send(^ns.Object, app, "icon")
	return load_icon_image(icon)
}

load_icon_image :: proc(icon: ^ns.Object) -> rawptr {
	if icon == nil {
		return {}
	}

	// Allow for a 48-point icon magnified by 60% at Retina resolution.
	side :: 160
	premultiplied_last :: 1
	pixels: [side * side * 4]u8
	space := CGColorSpaceCreateDeviceRGB()
	if space == nil {
		return {}
	}
	defer CGColorSpaceRelease(space)
	bitmap := CGBitmapContextCreate(raw_data(pixels[:]), side, side, 8, side * 4,
		space, premultiplied_last)
	if bitmap == nil {
		return {}
	}
	defer CGContextRelease(bitmap)

	graphics_class := native_class("NSGraphicsContext")
	graphics := send(^ns.Object, graphics_class, "graphicsContextWithCGContext:flipped:", bitmap, ns.BOOL(false))
	if graphics == nil {
		return {}
	}
	notify(graphics_class, "saveGraphicsState")
	defer notify(graphics_class, "restoreGraphicsState")
	notify(graphics_class, "setCurrentContext:", graphics)
	notify(icon, "drawInRect:", ns.Rect{size = {side, side}})

	return CGBitmapContextCreateImage(bitmap)
}
