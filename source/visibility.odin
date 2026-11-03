package main

import ns "core:sys/darwin/Foundation"
import rl "vendor:raylib"

Shelf_Visibility :: struct {
	resting, display: ns.Rect,
	progress: f64,
	approaching: bool,
	hidden: bool,
}

contains_point :: proc(rect: ns.Rect, point: ns.Point) -> bool {
	return point.x >= rect.origin.x && point.x <= rect.origin.x + rect.size.width &&
	       point.y >= rect.origin.y && point.y <= rect.origin.y + rect.size.height
}

reveal_area :: proc(resting, display: ns.Rect, edge: Shelf_Edge) -> (trigger, corridor: ns.Rect) {
	threshold :: 2
	corridor = resting
	switch edge {
	case .Left:
		corridor.origin.x = display.origin.x
		corridor.size.width = resting.origin.x + resting.size.width - display.origin.x
		trigger = {corridor.origin, {threshold, corridor.size.height}}
	case .Right:
		right := display.origin.x + display.size.width
		corridor.size.width = right - resting.origin.x
		trigger = {{right - threshold, corridor.origin.y}, {threshold, corridor.size.height}}
	case .Bottom:
		corridor.origin.y = display.origin.y
		corridor.size.height = resting.origin.y + resting.size.height - display.origin.y
		trigger = {corridor.origin, {corridor.size.width, threshold}}
	case .Top:
		top := display.origin.y + display.size.height
		corridor.size.height = top - resting.origin.y
		trigger = {{corridor.origin.x, top - threshold}, {corridor.size.width, threshold}}
	}
	return
}

update_shelf_visibility :: proc(window: ^ns.Object, state: ^Shelf_Visibility, settings: Settings) -> bool {
	if state.resting.size.width <= 0 || state.resting.size.height <= 0 {
		return false
	}

	show := true
	if settings.auto_hide {
		mouse := send(ns.Point, native_class("NSEvent"), "mouseLocation")
		trigger, corridor := reveal_area(state.resting, state.display, settings.edge)
		inside := contains_point(state.resting, mouse)
		if inside || !contains_point(corridor, mouse) {
			state.approaching = false
		} else if contains_point(trigger, mouse) {
			state.approaching = true
		}
		show = state.approaching || (inside && !state.hidden)
		if settings.animation_tenths == 0 {
			state.progress = 1 if show else 0
		} else {
			step := f64(min(rl.GetFrameTime(), 0.05)) / (f64(settings.animation_tenths) / 10)
			state.progress = clamp(state.progress + (step if show else -step), 0, 1)
		}
	} else {
		state.approaching = false
		state.progress = 1
	}

	if state.progress == 0 && !show {
		if !state.hidden {
			notify(window, "orderOut:", (^ns.Object)(nil))
			state.hidden = true
		}
		return false
	}

	progress := state.progress
	eased := progress * progress * (3 - 2 * progress)
	frame := state.resting
	offset := ns.Float(12 * (1 - eased))
	switch settings.edge {
	case .Left: frame.origin.x -= offset
	case .Right: frame.origin.x += offset
	case .Bottom: frame.origin.y -= offset
	case .Top: frame.origin.y += offset
	}
	if frame != send_rect(window, "frame") {
		notify(window, "setFrame:display:", frame, ns.BOOL(true))
	}
	notify(window, "setAlphaValue:", ns.Float(eased))
	if state.hidden {
		notify(window, "orderFrontRegardless")
		state.hidden = false
	}
	return show && state.progress > 0
}
