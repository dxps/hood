package main

import "core:math"
import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

wave_icon_rect :: proc(
	icon: rl.Rectangle,
	scale: f32,
	settings: Settings,
	layout: Shelf_Layout,
	width, height: i32,
) -> rl.Rectangle {
	if scale <= 0 {
		return icon
	}
	size := icon.width
	center := rl.Vector2{icon.x + size / 2, icon.y + size / 2}
	growth := f32(settings.magnification_percent) / 100
	grown := size * (1 + growth * scale)
	x, y := center.x - grown / 2, center.y - grown / 2
	// Keep magnification inside the scroll viewport along the shelf. Across the
	// shelf it is intentionally allowed to rise into the transparent canvas.
	if layout.horizontal && icon.x >= 0 && icon.x + size <= f32(width) {
		x = clamp(x, 0, f32(width) - grown)
	} else if !layout.horizontal && icon.y >= 0 && icon.y + size <= f32(height) {
		y = clamp(y, 0, f32(height) - grown)
	}
	lift_factor: f32 = 0.45 if settings.hover_wave else 0.20
	lift := size * lift_factor * scale
	switch settings.edge {
	case .Left:
		x += lift
	case .Right:
		x -= lift
	case .Bottom:
		y -= lift
	case .Top:
		y += lift
	}
	return {x, y, grown, grown}
}

wave_strength :: proc(distance: f32) -> f32 {
	// Preserve the peak and the two neighboring strengths at icon centers.
	squared := distance * distance
	falloff := 1 / (1 + squared * (1.23 + 0.15 * squared))
	tail := clamp(3 - distance, 0, 1)
	return falloff * tail * tail * (3 - 2 * tail)
}

draw_shelf :: proc(
	window: ^ns.Object,
	interaction: ^Shelf_Interaction,
	input: ^Native_Input,
	now: f64,
	apps: []App,
	settings: Settings,
	width, height: i32,
	scroll: f32,
	context_click: bool,
) -> (
	result: Shelf_Frame,
) {

	layout := shelf_layout(settings, len(apps))
	// Cocoa can report the pointer over a newly revealed window before GLFW
	// receives a cursor-enter or motion event.
	pointer := send(ns.Point, window, "mouseLocationOutsideOfEventStream")
	mouse := rl.Vector2{f32(pointer.x), f32(height) - f32(pointer.y)}
	pointer_inside := mouse.x >= 0 && mouse.x < f32(width) && mouse.y >= 0 && mouse.y < f32(height)
	shelf_x, shelf_y: f32
	shelf_width, shelf_height := f32(width), f32(height)
	if layout.horizontal {
		shelf_height = f32(layout.shelf_thickness)
		if settings.edge == .Bottom {
			shelf_y = f32(height) - shelf_height
		}
	} else {
		shelf_width = f32(layout.shelf_thickness)
		if settings.edge == .Right {
			shelf_x = f32(width) - shelf_width
		}
	}
	hood_begin(
		window,
		settings.background_rgb,
		f64(settings.corner_radius),
		shelf_x,
		shelf_y,
		shelf_width,
		shelf_height,
	)

	hovered_index := -1
	if pointer_inside {
		for _, index in apps {
			size := f32(settings.icon_size)
			offset := f32(layout.start + i32(index) * layout.step) - scroll
			icon := rl.Rectangle{shelf_x + (shelf_width - size) / 2, offset, size, size}
			if layout.horizontal {
				icon = {offset, shelf_y + (shelf_height - size) / 2, size, size}
			}
			padding := min(4, f32(settings.icon_gap) / 2)
			x_padding := min(padding, f32(settings.horizontal_margin))
			y_padding := min(padding, f32(settings.vertical_margin))
			row := rl.Rectangle{icon.x - x_padding, icon.y - y_padding, size + 2 * x_padding, size + 2 * y_padding}
			if rl.CheckCollisionPointRec(mouse, row) {
				hovered_index = index
				break
			}
		}
		// Once an icon has risen beyond the shelf, keep it interactive there.
		if hovered_index < 0 {
			for app, index in apps {
				size := f32(settings.icon_size)
				offset := f32(layout.start + i32(index) * layout.step) - scroll
				icon := rl.Rectangle{shelf_x + (shelf_width - size) / 2, offset, size, size}
				if layout.horizontal {
					icon = {offset, shelf_y + (shelf_height - size) / 2, size, size}
				}
				if app.hover_scale > 0 && rl.CheckCollisionPointRec(mouse, wave_icon_rect(icon, app.hover_scale, settings, layout, width, height)) {
					hovered_index = index
					break
				}
			}
		}
	}
	if (input.pressed != 0) && hovered_index >= 0 {
		interaction.drag_id = apps[hovered_index].order_id
		interaction.drag_start = mouse
		interaction.dragging = false
	}
	if interaction.drag_id != 0 && (input.down != 0) {
		delta := mouse - interaction.drag_start
		if !interaction.dragging && delta.x * delta.x + delta.y * delta.y >= 16 {
			interaction.dragging = true
		}
		if interaction.dragging {
			from := -1
			for app, index in apps {
				if app.order_id == interaction.drag_id {
					from = index
					break
				}
			}
			if from < 0 {
				interaction.drag_id = 0
				interaction.dragging = false
			} else {
				axis := mouse.y if !layout.horizontal else mouse.x
				to := int(
					(axis + scroll - f32(layout.start) - f32(settings.icon_size) / 2 + f32(layout.step) / 2) /
					f32(layout.step),
				)
				to = clamp(to, 0, len(apps) - 1)
				if from != to {
					dragged := apps[from]
					if from < to {
						for index in from ..< to {
							apps[index] = apps[index + 1]
						}
					} else {
						for index := from; index > to; index -= 1 {
							apps[index] = apps[index - 1]
						}
					}
					apps[to] = dragged
					hovered_index = to
					result.order_changed = true
				}
			}
		}
	}
	was_dragging := interaction.dragging
	if interaction.drag_id != 0 && (input.released != 0) {
		if !interaction.dragging && hovered_index >= 0 && apps[hovered_index].order_id == interaction.drag_id {
			result.clicked_id = interaction.drag_id
		}
		interaction.drag_id = 0
		interaction.dragging = false
	} else if interaction.drag_id != 0 && !(input.down != 0) {
		interaction.drag_id = 0
		interaction.dragging = false
	}

	raised_icon: rawptr
	raised_rect: rl.Rectangle
	size := f32(settings.icon_size)
	first_center := f32(layout.start) - scroll + size / 2
	pointer_axis := mouse.x if layout.horizontal else mouse.y
	wave_position := (pointer_axis - first_center) / f32(layout.step)
	cross_axis := mouse.y if layout.horizontal else mouse.x
	shelf_cross := shelf_y if layout.horizontal else shelf_x
	shelf_thickness := f32(layout.shelf_thickness)
	cross_center := shelf_cross + shelf_thickness / 2
	// Keep the wave active through gaps without changing icon hit testing.
	in_icon_band := pointer_inside && abs(cross_axis - cross_center) <= size / 2 &&
	                wave_position >= 0 && wave_position <= f32(len(apps) - 1)
	magnify := !context_click && !was_dragging && settings.magnification_percent > 0

	elapsed := clamp(now - interaction.hover_updated, 0, 1.0 / 30)
	interaction.hover_updated = now
	duration := f64(settings.hover_animation_tenths) / 10
	blend: f32 = 1
	if duration > 0 && settings.magnification_percent > 0 {
		// Cover about 99.9% of a step over the selected duration. A moving
		// target can be followed every frame without restarting an easing curve.
		blend = f32(1 - math.exp(-6.9 * elapsed / duration))
	}
	for &app, index in apps {
		offset := f32(layout.start + i32(index) * layout.step) - scroll
		icon := rl.Rectangle{shelf_x + (shelf_width - size) / 2, offset, size, size}
		if layout.horizontal {
			icon = {offset, shelf_y + (shelf_height - size) / 2, size, size}
		}
		center := rl.Vector2{icon.x + size / 2, icon.y + size / 2}
		hover := !context_click && !was_dragging && index == hovered_index
		if index == hovered_index {
			result.pointed_id = app.order_id
		}
		if hover {
			result.hovered = app
			result.tooltip_center = center
		}
		target: f32
		if magnify {
			if settings.hover_wave && (hovered_index >= 0 || in_icon_band) {
				target = wave_strength(abs(f32(index) - wave_position))
			} else if index == hovered_index {
				target = 1
			}
		}
		app.hover_scale += (target - app.hover_scale) * blend
		if abs(target - app.hover_scale) <= 0.001 {
			app.hover_scale = target
		}
		result.hover_animating = result.hover_animating || app.hover_scale != target
		icon = wave_icon_rect(icon, app.hover_scale, settings, layout, width, height)
		if hover {
			result.tooltip_center = {icon.x + icon.width / 2, icon.y + icon.height / 2}
		}
		if was_dragging && app.order_id == interaction.drag_id {
			icon.x = mouse.x - icon.width / 2
			icon.y = mouse.y - icon.height / 2
			raised_icon = app.icon
			raised_rect = icon
		} else if hover {
			raised_icon = app.icon
			raised_rect = icon
		} else {
			draw_app_icon(window, app.icon, icon)
		}
	}
	if raised_rect.width > 0 {
		draw_app_icon(window, raised_icon, raised_rect)
	}
	hood_end(window)
	return
}

draw_app_icon :: proc(window: ^ns.Object, image: rawptr, icon: rl.Rectangle) {
	hood_icon(window, image, icon.x, icon.y, icon.width, icon.height)
}
