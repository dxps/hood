package main

import "core:fmt"
import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

Tooltip :: struct {
	window: ^ns.Object,
	view:   ^ns.Object,
	pid:    i32,
}

close_tooltip :: proc(tooltip: ^Tooltip) {
	notify(tooltip.window, "close")
	notify(tooltip.window, "release")
}

hide_tooltip :: proc(tooltip: ^Tooltip) {
	if tooltip.pid != 0 {
		notify(tooltip.window, "orderOut:", (^ns.Object)(nil))
		tooltip.pid = 0
	}
}

show_tooltip :: proc(tooltip: ^Tooltip, shelf: ^ns.Object, app: App, center: rl.Vector2, edge: Shelf_Edge) {
	size :: 14
	height :: 26
	gap :: 6

	screen := send(^ns.Object, shelf, "screen")
	if screen == nil {
		hide_tooltip(tooltip)
		return
	}
	available := send_rect(screen, "visibleFrame")
	shelf_frame := send_rect(shelf, "frame")
	max_width := available.size.width
	if edge == .Left || edge == .Right {
		max_width -= shelf_frame.size.width + 2 * gap + 8
	}
	if max_width < 32 {
		hide_tooltip(tooltip)
		return
	}

	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	label := fmt.ctprintf("%s", app.name)
	if ns.Float(text_width(label, size)) + 17 > max_width {
		label = "..."
		for _, offset in app.name {
			candidate := fmt.ctprintf("%s...", app.name[:offset])
			if ns.Float(text_width(candidate, size)) + 17 > max_width {
				break
			}
			label = candidate
		}
	}
	width := i32(text_width(label, size) + 17)
	x := shelf_frame.origin.x + shelf_frame.size.width + gap
	y := shelf_frame.origin.y + shelf_frame.size.height - ns.Float(center.y) - height / 2
	switch edge {
	case .Left:
	case .Right:
		x = shelf_frame.origin.x - ns.Float(width) - gap
	case .Bottom, .Top:
		x = clamp(
			shelf_frame.origin.x + ns.Float(center.x) - ns.Float(width) / 2,
			available.origin.x,
			available.origin.x + available.size.width - ns.Float(width),
		)
		y = shelf_frame.origin.y + shelf_frame.size.height + gap
		if edge == .Top {
			y = shelf_frame.origin.y - height - gap
		}
	}
	frame := ns.Rect {
		origin = {x, y},
		size   = {ns.Float(width), height},
	}

	if tooltip.window == nil {
		tooltip.window = send(^ns.Object, native_class("NSWindow"), "new")
		notify(tooltip.window, "setStyleMask:", uint(0))
		notify(tooltip.window, "setOpaque:", ns.BOOL(false))
		clear := send(^ns.Object, native_class("NSColor"), "clearColor")
		notify(tooltip.window, "setBackgroundColor:", clear)
		notify(tooltip.window, "setReleasedWhenClosed:", ns.BOOL(false))
		notify(tooltip.window, "setIgnoresMouseEvents:", ns.BOOL(true))
		notify(tooltip.window, "setLevel:", send(int, shelf, "level") + 1)
		notify(tooltip.window, "setCollectionBehavior:", ns.WindowCollectionBehavior{.MoveToActiveSpace})
		tooltip.view = send(^ns.Object, native_class("NSImageView"), "new")
		notify(tooltip.window, "setContentView:", tooltip.view)
		notify(tooltip.view, "release")
		notify(tooltip.view, "setWantsLayer:", ns.BOOL(true))
		layer := send(^ns.Object, tooltip.view, "layer")
		notify(layer, "setCornerRadius:", ns.Float(7))
		notify(layer, "setMasksToBounds:", ns.BOOL(true))
	}
	if tooltip.pid != app.pid || send_rect(tooltip.window, "frame").size.width != ns.Float(width) {
		// Render with the same Raylib font as the shelf, at Retina resolution.
		image := rl.GenImageColor(width * 2, height * 2, {54, 54, 60, 255})
		defer rl.UnloadImage(image)
		rl.ImageDrawTextEx(&image, work_sans, label, {16, 12}, size * 2, 0, rl.RAYWHITE)
		length: i32
		png := rl.ExportImageToMemory(image, ".png", &length)
		if png == nil {
			hide_tooltip(tooltip)
			return
		}
		defer rl.MemFree(png)
		data := send(^ns.Object, native_class("NSData"), "dataWithBytes:length:", png, uint(length))
		icon := send(^ns.Object, native_class("NSImage"), "alloc")
		icon = send(^ns.Object, icon, "initWithData:", data)
		notify(icon, "setSize:", frame.size)
		notify(tooltip.view, "setImage:", icon)
		notify(icon, "release")
		tooltip.pid = app.pid
	}
	if frame != send_rect(tooltip.window, "frame") {
		notify(tooltip.window, "setFrame:display:", frame, ns.BOOL(true))
	}
	if !send(ns.BOOL, tooltip.window, "isVisible") {
		notify(tooltip.window, "orderFrontRegardless")
	}
}
