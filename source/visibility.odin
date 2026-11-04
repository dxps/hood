package main

import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

Shelf_Visibility :: struct {
	resting, display:   ns.Rect,
	progress:           f64,
	approaching:        bool,
	hidden:             bool,
	requested, showing: bool,
	request_started:    f64,
}

contains_point :: proc(rect: ns.Rect, point: ns.Point) -> bool {
	return(
		point.x >= rect.origin.x &&
		point.x <= rect.origin.x + rect.size.width &&
		point.y >= rect.origin.y &&
		point.y <= rect.origin.y + rect.size.height \
	)
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

delayed_visibility :: proc(state: ^Shelf_Visibility, requested: bool, now: f64, delay_ms: i32) -> bool {
	if requested != state.requested {
		state.requested = requested
		state.request_started = now
	}
	if now - state.request_started >= f64(delay_ms) / 1000 {
		state.showing = requested
	}
	return state.showing
}

update_shelf_visibility :: proc(window: ^ns.Object, state: ^Shelf_Visibility, settings: Settings, keep_visible: bool) -> bool {
	if state.resting.size.width <= 0 || state.resting.size.height <= 0 {
		return false
	}

	show := true
	if settings.auto_hide && !keep_visible {
		mouse := send(ns.Point, native_class("NSEvent"), "mouseLocation")
		trigger, corridor := reveal_area(state.resting, state.display, settings.edge)
		inside := contains_point(state.resting, mouse)
		if contains_point(trigger, mouse) {
			state.approaching = true
		} else if (inside && !state.hidden) || !contains_point(corridor, mouse) {
			state.approaching = false
		}
		requested := state.approaching || (inside && !state.hidden)
		show = delayed_visibility(state, requested, rl.GetTime(), settings.show_hide_delay_ms)
		if settings.animation_tenths == 0 {
			state.progress = 1 if show else 0
		} else {
			step := f64(min(rl.GetFrameTime(), 0.05)) / (f64(settings.animation_tenths) / 10)
			state.progress = clamp(state.progress + (step if show else -step), 0, 1)
		}
	} else {
		state.approaching = false
		state.requested = true
		state.showing = true
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
	case .Left:
		frame.origin.x -= offset
	case .Right:
		frame.origin.x += offset
	case .Bottom:
		frame.origin.y -= offset
	case .Top:
		frame.origin.y += offset
	}
	if frame != send_rect(window, "frame") {
		notify(window, "setFrame:display:", frame, ns.BOOL(true))
	}
	if send(ns.Float, window, "alphaValue") != ns.Float(eased) {
		notify(window, "setAlphaValue:", ns.Float(eased))
	}
	if state.hidden {
		notify(window, "orderFrontRegardless")
		state.hidden = false
	}
	return show && state.progress > 0
}
