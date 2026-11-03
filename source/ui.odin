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

SETTINGS_CONTROL_LEFT :: 192
SETTINGS_CONTROL_RIGHT :: SETTINGS_WIDTH - 20
SETTINGS_CONTROL_WIDTH :: SETTINGS_CONTROL_RIGHT - SETTINGS_CONTROL_LEFT

stepper_row :: proc(
	theme: Settings_Theme,
	label: cstring,
	y: i32,
	value: ^i32,
	minimum, maximum, step: i32,
	enabled: bool,
) {
	button_width :: 40
	draw_text(label, 20, y + 8, 16, theme.text)
	if ui_button(theme, {SETTINGS_CONTROL_LEFT, f32(y), button_width, 32}, "-") && enabled {
		value^ = max(minimum, value^ - step)
	}
	if ui_button(theme, {SETTINGS_CONTROL_RIGHT - button_width, f32(y), button_width, 32}, "+") &&
	   enabled {
		value^ = min(maximum, value^ + step)
	}
	label_value := fmt.ctprintf("%d px", value^)
	center := SETTINGS_CONTROL_LEFT + SETTINGS_CONTROL_WIDTH / 2
	draw_text(
		label_value,
		i32(f32(center) - text_width(label_value, 16) / 2),
		y + 8,
		16,
		theme.text,
	)
}

dropdown_button :: proc(
	theme: Settings_Theme,
	dropdown: ^Settings_Dropdown,
	kind: Settings_Dropdown,
	y: i32,
	label: cstring,
) {
	top := f32(y)
	if ui_button(
		   theme,
		   {SETTINGS_CONTROL_LEFT, top, SETTINGS_CONTROL_WIDTH, 32},
		   label,
		   left_padding = 16,
	   ) &&
	   (dropdown^ == .None || dropdown^ == kind) {
		dropdown^ = kind if dropdown^ == .None else .None
	}
	rl.DrawTriangle(
		{SETTINGS_CONTROL_RIGHT - 20, top + 13},
		{SETTINGS_CONTROL_RIGHT - 15, top + 19},
		{SETTINGS_CONTROL_RIGHT - 10, top + 13},
		theme.text,
	)
}

dropdown_popup :: proc(
	theme: Settings_Theme,
	y: i32,
	labels: []cstring,
	selected: int,
	accept: bool,
	extra_width: f32 = 0,
) -> int {
	popup := rl.Rectangle {
		SETTINGS_CONTROL_LEFT - extra_width,
		f32(y),
		SETTINGS_CONTROL_WIDTH + extra_width,
		f32(len(labels) * 31 + 8),
	}
	roundness := 2 * SETTINGS_BUTTON_RADIUS / min(popup.width, popup.height)
	shadow := popup
	shadow.y += 3
	rl.DrawRectangleRounded(shadow, roundness, 8, theme.popup_shadow)
	rl.DrawRectangleRounded(popup, roundness, 8, theme.button)
	rl.DrawRectangleRoundedLinesEx(popup, roundness, 8, 1, theme.popup_border)
	for label, index in labels {
		if ui_button(
			   theme,
			   {popup.x + 4, popup.y + 4 + f32(index) * 31, popup.width - 8, 30},
			   label,
			   index == selected,
			   left_padding = 12,
		   ) &&
		   accept {
			return index
		}
	}
	return -1
}

settings_view :: proc(
	draft: ^Settings,
	failed: bool,
	theme: Settings_Theme,
	dropdown: ^Settings_Dropdown,
) -> (
	pick_color, done: bool,
) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground(theme.background)
	show_labels := [2]cstring{"Always", "Auto-Hide"}
	animation_labels := [11]cstring {
		"0 seconds (no animation)",
		"0.1 seconds",
		"0.2 seconds",
		"0.3 seconds",
		"0.4 seconds",
		"0.5 seconds",
		"0.6 seconds",
		"0.7 seconds",
		"0.8 seconds",
		"0.9 seconds",
		"1 second",
	}
	was_open := dropdown^ != .None
	offset: i32 = 50
	draw_text("Show", 20, 28, 16, theme.text)
	dropdown_button(theme, dropdown, .Show, 20, show_labels[int(draft.auto_hide)])
	if draft.auto_hide {
		offset += 50
		draw_text("Show/hide animation", 20, 78, 16, theme.text)
		dropdown_button(
			theme,
			dropdown,
			.Animation,
			70,
			"0 seconds" if draft.animation_tenths == 0 else animation_labels[draft.animation_tenths],
		)
	}
	draw_text("Position", 20, 28 + offset, 16, theme.text)
	dropdown_button(theme, dropdown, .Position, 20 + offset, EDGE_LABELS[draft.edge])
	tooltip_labels := [6]cstring{"Immediate", "100 ms", "250 ms", "450 ms", "750 ms", "1 second"}
	tooltip_choice := 0
	for delay, index in TOOLTIP_DELAYS_MS {
		if draft.tooltip_delay_ms == delay {
			tooltip_choice = index
			break
		}
	}
	draw_text("Tooltip delay", 20, 78 + offset, 16, theme.text)
	dropdown_button(theme, dropdown, .Tooltip_Delay, 70 + offset, tooltip_labels[tooltip_choice])
	controls_offset := offset + 50
	stepper_row(
		theme,
		"Icon size",
		70 + controls_offset,
		&draft.icon_size,
		MIN_ICON_SIZE,
		MAX_ICON_SIZE,
		4,
		!was_open,
	)
	stepper_row(
		theme,
		"Corner radius",
		120 + controls_offset,
		&draft.corner_radius,
		0,
		MAX_CORNER_RADIUS,
		2,
		!was_open,
	)

	draw_text("Background color", 20, 175 + controls_offset, 16, theme.text)
	draw_text(
		fmt.ctprintf("#%06X", draft.background_rgb),
		SETTINGS_CONTROL_LEFT,
		175 + controls_offset,
		16,
		theme.text,
	)
	pick_color =
		ui_button(
			theme,
			{SETTINGS_CONTROL_RIGHT - 74, f32(168 + controls_offset), 74, 30},
			"Choose",
			font_size = 13,
		) &&
		!was_open
	rl.DrawLine(20, 210 + controls_offset, SETTINGS_CONTROL_RIGHT, 210 + controls_offset, theme.popup_border)
	draw_text("Spacing", 20, 224 + controls_offset, 20, theme.text)
	stepper_row(
		theme,
		"Between icons",
		256 + controls_offset,
		&draft.icon_gap,
		0,
		MAX_ICON_SPACING,
		2,
		!was_open,
	)
	stepper_row(
		theme,
		"Left / right margins",
		300 + controls_offset,
		&draft.horizontal_margin,
		0,
		MAX_ICON_SPACING,
		2,
		!was_open,
	)
	stepper_row(
		theme,
		"Top / bottom margins",
		344 + controls_offset,
		&draft.vertical_margin,
		0,
		MAX_ICON_SPACING,
		2,
		!was_open,
	)
	if failed {
		draw_text("Could not save hood.toml", 20, 390 + controls_offset, 16, theme.error)
	}
	done =
		ui_button(theme, {SETTINGS_CONTROL_RIGHT - 74, f32(406 + controls_offset), 74, 32}, "OK") &&
		!was_open
	if dropdown^ != .None {
		switch dropdown^ {
		case .None:
		case .Show:
			if choice := dropdown_popup(theme, 56, show_labels[:], int(draft.auto_hide), was_open);
			   choice >= 0 {
				draft.auto_hide = choice == 1
			}
		case .Animation:
			if choice := dropdown_popup(
				theme,
				106,
				animation_labels[:],
				int(draft.animation_tenths),
				was_open,
				extra_width = 32,
			); choice >= 0 {
				draft.animation_tenths = i32(choice)
			}
		case .Tooltip_Delay:
			if choice := dropdown_popup(theme, 106 + offset, tooltip_labels[:], tooltip_choice, was_open);
			   choice >= 0 {
				draft.tooltip_delay_ms = TOOLTIP_DELAYS_MS[choice]
			}
		case .Position:
			position_labels := [4]cstring{"Left", "Right", "Bottom", "Top"}
			if choice := dropdown_popup(
				theme,
				56 + offset,
				position_labels[:],
				int(draft.edge),
				was_open,
			); choice >= 0 {
				draft.edge = Shelf_Edge(choice)
			}
		}
		if was_open && rl.IsMouseButtonReleased(.LEFT) {
			dropdown^ = .None
		}
	}
	return
}

draw_shelf :: proc(
	apps: []App,
	settings: Settings,
	width, height: i32,
	scroll: f32,
	active_pid: i32,
	context_click: bool,
) -> (
	result: Shelf_Frame,
) {
	layout := shelf_layout(settings, len(apps))
	// Cocoa can report the pointer over a newly revealed window before GLFW
	// receives a cursor-enter or motion event.
	pointer := send(ns.Point, cocoa_window(), "mouseLocationOutsideOfEventStream")
	mouse := rl.Vector2{f32(pointer.x), f32(height) - f32(pointer.y)}
	pointer_inside := mouse.x >= 0 && mouse.x < f32(width) && mouse.y >= 0 && mouse.y < f32(height)
	rl.BeginDrawing()
	rl.ClearBackground(rl.BLANK)
	shelf_rect := rl.Rectangle{0, 0, f32(width), f32(height)}
	roundness := min(1, 2 * f32(settings.corner_radius) / min(shelf_rect.width, shelf_rect.height))
	rl.DrawRectangleRounded(
		shelf_rect,
		roundness,
		12,
		rl.GetColor(settings.background_rgb << 8 | 0xFF),
	)

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
		row := rl.Rectangle {
			icon.x - x_padding,
			icon.y - y_padding,
			size + 2 * x_padding,
			size + 2 * y_padding,
		}
		hover := !context_click && pointer_inside && rl.CheckCollisionPointRec(mouse, row)
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
