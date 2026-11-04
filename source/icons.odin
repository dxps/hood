package main

import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

foreign import core_graphics "system:CoreGraphics.framework"

foreign core_graphics {
	CGColorSpaceCreateDeviceRGB :: proc "c" () -> rawptr ---
	CGColorSpaceRelease :: proc "c" (space: rawptr) ---
	CGBitmapContextCreate :: proc "c" (pixels: rawptr, width, height, bits, stride: uint,
		space: rawptr, format: u32) -> rawptr ---
	CGContextRelease :: proc "c" (graphics: rawptr) ---
}

load_icon :: proc(app: ^ns.Object) -> rl.Texture2D {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	icon := send(^ns.Object, app, "icon")
	return load_icon_image(icon)
}

load_icon_image :: proc(icon: ^ns.Object) -> rl.Texture2D {
	if icon == nil {
		return {}
	}

	// Allow for a 48-point icon magnified by 60% at Retina resolution.
	side :: 160
	premultiplied_last :: 1
	pixels: [side * side]rl.Color
	space := CGColorSpaceCreateDeviceRGB()
	if space == nil {
		return {}
	}
	defer CGColorSpaceRelease(space)
	bitmap := CGBitmapContextCreate(raw_data(pixels[:]), side, side, 8, side * size_of(rl.Color),
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

	// Raylib textures use straight alpha. Core Graphics renders premultiplied RGBA.
	for &pixel in pixels {
		if pixel.a > 0 && pixel.a < 255 {
			alpha := u32(pixel.a)
			pixel.r = u8(min(255, (u32(pixel.r) * 255 + alpha / 2) / alpha))
			pixel.g = u8(min(255, (u32(pixel.g) * 255 + alpha / 2) / alpha))
			pixel.b = u8(min(255, (u32(pixel.b) * 255 + alpha / 2) / alpha))
		}
	}
	return rl.LoadTextureFromImage({
		data = raw_data(pixels[:]), width = side, height = side, mipmaps = 1,
		format = .UNCOMPRESSED_R8G8B8A8,
	})
}
