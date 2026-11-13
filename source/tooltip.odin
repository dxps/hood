package main

import "core:strings"
import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

Tooltip :: struct {
	window: ^ns.Object,
	app_id: u64,
}

close_tooltip :: proc(tooltip: ^Tooltip) {
	if tooltip.window != nil {
		hood_close(tooltip.window)
	}
}

hide_tooltip :: proc(tooltip: ^Tooltip) {
	if tooltip.app_id != 0 {
		notify(tooltip.window, "orderOut:", (^ns.Object)(nil))
		tooltip.app_id = 0
	}
}

show_tooltip :: proc(tooltip: ^Tooltip, shelf: ^ns.Object, app: App, center: rl.Vector2, settings: Settings) {
	if tooltip.window == nil {
		menu_font()
		tooltip.window = hood_tooltip_create()
	}
	hood_tooltip_show(
		tooltip.window,
		shelf,
		strings.clone_to_cstring(app.name, context.temp_allocator),
		center.x,
		center.y,
		i32(settings.edge),
		settings.tooltip_opacity_percent,
		0 if app.ax_window != nil else app.pid,
	)
	tooltip.app_id = app.order_id
}
