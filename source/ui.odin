package main

import "core:fmt"
import ns "core:sys/darwin/Foundation"
import rl "vendor:raylib"

SETTINGS_BUTTON_RADIUS :: 9.0

Settings_Theme :: struct {
	background, text, button, highlight, hover, error, popup_border, popup_shadow: rl.Color,
}

LIGHT_SETTINGS_THEME :: Settings_Theme {
	{246, 246, 246, 255},
	{28, 28, 28, 255},
	{231, 231, 231, 255},
	{208, 221, 238, 255},
	{195, 208, 225, 255},
	{153, 30, 45, 255},
	{183, 183, 183, 255},
	{0, 0, 0, 34},
}

DARK_SETTINGS_THEME :: Settings_Theme {
	{37, 37, 37, 255},
	{242, 242, 242, 255},
	{54, 54, 54, 255},
	{76, 83, 96, 255},
	{65, 71, 82, 255},
	{255, 158, 170, 255},
	{92, 92, 92, 255},
	{0, 0, 0, 72},
}

settings_theme :: proc(window: ^ns.Object) -> Settings_Theme {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	string_class := native_class("NSString")
	aqua := send(
		^ns.Object,
		string_class,
		"stringWithUTF8String:",
		cstring("NSAppearanceNameAqua"),
	)
	dark := send(
		^ns.Object,
		string_class,
		"stringWithUTF8String:",
		cstring("NSAppearanceNameDarkAqua"),
	)
	names := send(^ns.Object, native_class("NSArray"), "arrayWithObject:", aqua)
	names = send(^ns.Object, names, "arrayByAddingObject:", dark)
	appearance := send(^ns.Object, window, "effectiveAppearance")
	match := send(^ns.Object, appearance, "bestMatchFromAppearancesWithNames:", names)
	return(
		DARK_SETTINGS_THEME if send(ns.BOOL, match, "isEqualToString:", dark) else LIGHT_SETTINGS_THEME \
	)
}

ui_button :: proc(
	theme: Settings_Theme,
	rect: rl.Rectangle,
	text: cstring,
	selected := false,
	font_size: i32 = 16,
	left_padding: f32 = 0,
) -> bool {
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	color := theme.button
	if selected {
		color = theme.highlight
	} else if hover {
		color = theme.hover
	}
	roundness := min(1, 2 * SETTINGS_BUTTON_RADIUS / min(rect.width, rect.height))
	rl.DrawRectangleRounded(rect, roundness, 12, color)
	text_offset := (rect.width - text_width(text, font_size)) / 2
	if left_padding > 0 {
		text_offset = left_padding
	}
	x := i32(rect.x + text_offset)
	draw_text(text, x, i32(rect.y + (rect.height - f32(font_size)) / 2), font_size, theme.text)
	return hover && rl.IsMouseButtonReleased(.LEFT)
}

spacing_row :: proc(theme: Settings_Theme, label: cstring, y: i32, value: ^i32, enabled: bool) {
	draw_text(label, 20, y + 8, 16, theme.text)
	if ui_button(theme, {176, f32(y), 34, 32}, "-") && enabled {
		value^ = max(0, value^ - 2)
	}
	draw_text(fmt.ctprintf("%d px", value^), 219, y + 8, 16, theme.text)
	if ui_button(theme, {280, f32(y), 34, 32}, "+") && enabled {
		value^ = min(MAX_ICON_SPACING, value^ + 2)
	}
}

settings_view :: proc(
	draft: ^Settings,
	failed: bool,
	theme: Settings_Theme,
	dropdown: ^bool,
) -> (
	pick_color, done: bool,
) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(theme.background)
	draw_text("Appearance", 20, 20, 20, theme.text)
	draw_text("Position", 20, 64, 16, theme.text)
	was_open := dropdown^
	if ui_button(theme, {150, 56, 164, 32}, EDGE_LABELS[draft.edge], left_padding = 16) {
		dropdown^ = !was_open
	}
	rl.DrawTriangle({294, 69}, {299, 75}, {304, 69}, theme.text)
	draw_text("Icon size", 20, 114, 16, theme.text)
	if ui_button(theme, {150, 106, 40, 32}, "-") && !was_open {
		draft.icon_size = max(MIN_ICON_SIZE, draft.icon_size - 4)
	}
	draw_text(fmt.ctprintf("%d px", draft.icon_size), 204, 114, 16, theme.text)
	if ui_button(theme, {274, 106, 40, 32}, "+") && !was_open {
		draft.icon_size = min(MAX_ICON_SIZE, draft.icon_size + 4)
	}
	draw_text("Corner radius", 20, 164, 16, theme.text)
	if ui_button(theme, {150, 156, 40, 32}, "-") && !was_open {
		draft.corner_radius = max(0, draft.corner_radius - 2)
	}
	draw_text(fmt.ctprintf("%d px", draft.corner_radius), 204, 164, 16, theme.text)
	if ui_button(theme, {274, 156, 40, 32}, "+") && !was_open {
		draft.corner_radius = min(MAX_CORNER_RADIUS, draft.corner_radius + 2)
	}

	draw_text("Background color", 20, 211, 16, theme.text)
	draw_text(fmt.ctprintf("#%06X", draft.background_rgb), 150, 211, 16, theme.text)
	pick_color = ui_button(theme, {240, 204, 74, 30}, "Choose", font_size = 13) && !was_open
	rl.DrawLine(20, 246, 314, 246, theme.popup_border)
	draw_text("Spacing", 20, 260, 20, theme.text)
	spacing_row(theme, "Between icons", 292, &draft.icon_gap, !was_open)
	spacing_row(theme, "Left / right margins", 336, &draft.horizontal_margin, !was_open)
	spacing_row(theme, "Top / bottom margins", 380, &draft.vertical_margin, !was_open)
	if failed {
		draw_text("Could not save hood.toml", 20, 426, 16, theme.error)
	}
	done = ui_button(theme, {240, 442, 74, 32}, "OK") && !was_open
	if dropdown^ {
		popup := rl.Rectangle{150, 92, 164, 132}
		roundness := 2 * SETTINGS_BUTTON_RADIUS / min(popup.width, popup.height)
		shadow := popup
		shadow.y += 3
		rl.DrawRectangleRounded(shadow, roundness, 8, theme.popup_shadow)
		rl.DrawRectangleRounded(popup, roundness, 8, theme.button)
		rl.DrawRectangleRoundedLinesEx(popup, roundness, 8, 1, theme.popup_border)
		for edge in Shelf_Edge {
			if ui_button(theme, {154, 96 + f32(edge) * 31, 156, 30}, EDGE_LABELS[edge], draft.edge == edge, left_padding = 12) {
				draft.edge = edge
			}
		}
		if was_open && rl.IsMouseButtonReleased(.LEFT) {
			dropdown^ = false
		}
	}
	return
}

draw_shelf :: proc(apps: []App, settings: Settings, width, height: i32,
	scroll: f32, active_pid: i32, context_click: bool) -> (result: Shelf_Frame) {
	layout := shelf_layout(settings, len(apps))
	mouse := rl.GetMousePosition()
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLANK)
	shelf_rect := rl.Rectangle{0, 0, f32(width), f32(height)}
	roundness := min(1, 2 * f32(settings.corner_radius) / min(shelf_rect.width, shelf_rect.height))
	rl.DrawRectangleRounded(shelf_rect, roundness, 12, rl.GetColor(settings.background_rgb << 8 | 0xFF))
	
	for app, index in apps {
		size := f32(settings.icon_size)
		offset := f32(layout.start + i32(index) * layout.step) - scroll
		icon := rl.Rectangle{f32(settings.horizontal_margin), offset, size, size}
		if layout.horizontal {
			icon = {offset, f32(settings.vertical_margin), size, size}
		}
		center := rl.Vector2{icon.x + size / 2, icon.y + size / 2}
		padding := min(4, f32(settings.icon_gap) / 2)
		x_padding := min(padding, f32(settings.horizontal_margin))
		y_padding := min(padding, f32(settings.vertical_margin))
		row := rl.Rectangle{icon.x - x_padding, icon.y - y_padding, size + 2 * x_padding, size + 2 * y_padding}
		hover := !context_click && rl.IsCursorOnScreen() && rl.CheckCollisionPointRec(mouse, row)
		if hover {
			result.hovered = app
			result.tooltip_center = center
		}
		if hover || app.pid == active_pid {
			rl.DrawRectangleRounded(row, 0.24, 8, {63, 63, 69, 255})
		}
		if app.icon.id != 0 {
			source := rl.Rectangle{0, 0, f32(app.icon.width), f32(app.icon.height)}
			rl.DrawTexturePro(app.icon, source, icon, {}, 0, rl.WHITE)
		} else {
			rl.DrawCircle(i32(center.x), i32(center.y), 10, rl.GRAY)
		}
		if hover && rl.IsMouseButtonReleased(.LEFT) {
			result.clicked_pid = app.pid
		}
	}
	rl.EndDrawing()
	return
}
