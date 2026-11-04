package main

import "core:fmt"
import ns "vendor:darwin/AppKit"
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
	aqua := send(^ns.Object, string_class, "stringWithUTF8String:", cstring("NSAppearanceNameAqua"))
	dark := send(^ns.Object, string_class, "stringWithUTF8String:", cstring("NSAppearanceNameDarkAqua"))
	names := send(^ns.Object, native_class("NSArray"), "arrayWithObject:", aqua)
	names = send(^ns.Object, names, "arrayByAddingObject:", dark)
	appearance := send(^ns.Object, window, "effectiveAppearance")
	match := send(^ns.Object, appearance, "bestMatchFromAppearancesWithNames:", names)
	return DARK_SETTINGS_THEME if send(ns.BOOL, match, "isEqualToString:", dark) else LIGHT_SETTINGS_THEME
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

SETTINGS_CONTROL_LEFT :: 246
SETTINGS_CONTROL_RIGHT :: SETTINGS_WIDTH - 20
SETTINGS_DROPDOWN_WIDTH :: 168
SETTINGS_DROPDOWN_RIGHT :: SETTINGS_CONTROL_LEFT + SETTINGS_DROPDOWN_WIDTH

repeat_button :: proc(theme: Settings_Theme, rect: rl.Rectangle, label: cstring, enabled: bool) -> bool {
	initial_delay :: 0.35
	repeat_interval :: 0.08
	@(static) held: rl.Rectangle
	@(static) next_repeat: f64

	ui_button(theme, rect, label)
	if !rl.IsMouseButtonDown(.LEFT) {
		held = {}
		return false
	}

	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	now := rl.GetTime()
	if enabled && hover && rl.IsMouseButtonPressed(.LEFT) {
		held = rect
		next_repeat = now + initial_delay
		return true
	}
	if held == rect {
		if !enabled || !hover {
			held = {}
		} else if now >= next_repeat {
			next_repeat = now + repeat_interval
			return true
		}
	}
	return false
}

stepper_row :: proc(theme: Settings_Theme, label: cstring, y: i32, value: ^i32, minimum, maximum, step: i32, enabled: bool) {
	button_width :: 40
	stepper_width :: SETTINGS_DROPDOWN_WIDTH
	left := f32(SETTINGS_CONTROL_LEFT)
	right := left + stepper_width
	draw_text(label, 20, y + 8, 16, theme.text)
	if repeat_button(theme, {left, f32(y), button_width, 32}, "-", enabled) {
		value^ = max(minimum, value^ - step)
	}
	if repeat_button(theme, {right - button_width, f32(y), button_width, 32}, "+", enabled) {
		value^ = min(maximum, value^ + step)
	}
	label_value := fmt.ctprintf("%d px", value^)
	center := left + stepper_width / 2
	draw_text(label_value, i32(center - text_width(label_value, 16) / 2), y + 8, 16, theme.text)
}

dropdown_button :: proc(theme: Settings_Theme, dropdown: ^Settings_Dropdown, kind: Settings_Dropdown, y: i32, label: cstring) {
	top := f32(y)
	if ui_button(theme, {SETTINGS_CONTROL_LEFT, top, SETTINGS_DROPDOWN_WIDTH, 32}, label, left_padding = 16) &&
	   dropdown^ == .None {
		dropdown^ = kind
	}
	rl.DrawTriangle(
		{SETTINGS_DROPDOWN_RIGHT - 20, top + 13},
		{SETTINGS_DROPDOWN_RIGHT - 15, top + 19},
		{SETTINGS_DROPDOWN_RIGHT - 10, top + 13},
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
	popup_height := f32(len(labels) * 31 + 8)
	popup_y := min(f32(y), f32(rl.GetScreenHeight()) - popup_height - 8)
	popup := rl.Rectangle{SETTINGS_CONTROL_LEFT - extra_width, popup_y, SETTINGS_DROPDOWN_WIDTH + extra_width, popup_height}
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
	animation_labels := [6]cstring{"0 seconds (no animation)", "100 ms", "200 ms", "300 ms", "400 ms", "500 ms"}
	was_open := dropdown^ != .None
	offset: i32 = 50
	draw_text("Show", 20, 28, 16, theme.text)
	dropdown_button(theme, dropdown, .Show, 20, show_labels[int(draft.auto_hide)])
	delay_labels := [5]cstring{"Immediate", "50 ms", "100 ms", "200 ms", "300 ms"}
	delay_choice := 0
	for delay, index in SHOW_HIDE_DELAYS_MS {
		if draft.show_hide_delay_ms == delay {
			delay_choice = index
			break
		}
	}
	if draft.auto_hide {
		offset += 90
		draw_text("Show/hide animation", 20, 78, 16, theme.text)
		dropdown_button(
			theme,
			dropdown,
			.Animation,
			70,
			"0 seconds" if draft.animation_tenths == 0 else animation_labels[draft.animation_tenths],
		)
		draw_text("Show/hide delay", 20, 118, 16, theme.text)
		dropdown_button(theme, dropdown, .Show_Hide_Delay, 110, delay_labels[delay_choice])
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
	magnification_labels := [10]cstring{"Off", "5%", "10%", "15%", "20%", "25%", "30%", "40%", "50%", "60%"}
	magnification_choice := 0
	for percent, index in MAGNIFICATION_PERCENTS {
		if draft.magnification_percent == percent {
			magnification_choice = index
			break
		}
	}
	stepper_row(theme, "Corner radius", 110 + offset, &draft.corner_radius, 0, MAX_CORNER_RADIUS, 2, !was_open)
	draw_text("Background color", 20, 158 + offset, 16, theme.text)
	draw_text(fmt.ctprintf("#%06X", draft.background_rgb), SETTINGS_CONTROL_LEFT, 158 + offset, 16, theme.text)
	pick_color =
		ui_button(theme, {SETTINGS_DROPDOWN_RIGHT - 74, f32(150 + offset), 74, 30}, "Choose", font_size = 13) && !was_open

	rl.DrawLine(20, 192 + offset, SETTINGS_CONTROL_RIGHT, 192 + offset, theme.popup_border)
	draw_text("Icons", 20, 205 + offset, 20, theme.text)
	stepper_row(theme, "Size", 234 + offset, &draft.icon_size, MIN_ICON_SIZE, MAX_ICON_SIZE, 4, !was_open)
	draw_text("Magnification size", 20, 282 + offset, 16, theme.text)
	dropdown_button(theme, dropdown, .Hover_Magnification, 274 + offset, magnification_labels[magnification_choice])
	draw_text("Magnification animation", 20, 322 + offset, 16, theme.text)
	dropdown_button(theme, dropdown, .Hover_Animation, 314 + offset, animation_labels[draft.hover_animation_tenths])

	rl.DrawLine(20, 356 + offset, SETTINGS_CONTROL_RIGHT, 356 + offset, theme.popup_border)
	draw_text("Spacing", 20, 370 + offset, 20, theme.text)
	stepper_row(theme, "Between icons", 402 + offset, &draft.icon_gap, 0, MAX_ICON_SPACING, 2, !was_open)
	stepper_row(theme, "Left / right margins", 446 + offset, &draft.horizontal_margin, 0, MAX_ICON_SPACING, 2, !was_open)
	stepper_row(theme, "Top / bottom margins", 490 + offset, &draft.vertical_margin, 0, MAX_ICON_SPACING, 2, !was_open)
	stepper_row(
		theme,
		"Between Dock and screen edge",
		530 + offset,
		&draft.screen_edge_gap,
		0,
		MAX_SCREEN_EDGE_GAP,
		1,
		!was_open,
	)
	if failed {
		draw_text("Could not save hood.toml", 20, 568 + offset, 16, theme.error)
	}
	done = ui_button(theme, {SETTINGS_DROPDOWN_RIGHT - 74, f32(584 + offset), 74, 32}, "OK") && !was_open
	if dropdown^ != .None {
		switch dropdown^ {
		case .None:
		case .Show:
			if choice := dropdown_popup(theme, 56, show_labels[:], int(draft.auto_hide), was_open); choice >= 0 {
				draft.auto_hide = choice == 1
			}
		case .Animation:
			if choice := dropdown_popup(
				theme,
				106,
				animation_labels[:MAX_SHOW_ANIMATION_TENTHS + 1],
				int(draft.animation_tenths),
				was_open,
				extra_width = 32,
			); choice >= 0 {
				draft.animation_tenths = i32(choice)
			}
		case .Show_Hide_Delay:
			if choice := dropdown_popup(theme, 146, delay_labels[:], delay_choice, was_open); choice >= 0 {
				draft.show_hide_delay_ms = SHOW_HIDE_DELAYS_MS[choice]
			}
		case .Hover_Magnification:
			if choice := dropdown_popup(theme, 310 + offset, magnification_labels[:], magnification_choice, was_open);
			   choice >= 0 {
				draft.magnification_percent = MAGNIFICATION_PERCENTS[choice]
			}
		case .Hover_Animation:
			if choice := dropdown_popup(
				theme,
				350 + offset,
				animation_labels[1:MAX_MAGNIFICATION_ANIMATION_TENTHS + 1],
				int(draft.hover_animation_tenths - 1),
				was_open,
			); choice >= 0 {
				draft.hover_animation_tenths = i32(choice + 1)
			}
		case .Tooltip_Delay:
			if choice := dropdown_popup(theme, 106 + offset, tooltip_labels[:], tooltip_choice, was_open); choice >= 0 {
				draft.tooltip_delay_ms = TOOLTIP_DELAYS_MS[choice]
			}
		case .Position:
			position_labels := [4]cstring{"Left", "Right", "Bottom", "Top"}
			if choice := dropdown_popup(theme, 56 + offset, position_labels[:], int(draft.edge), was_open); choice >= 0 {
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
	@(static) drag_pid: i32
	@(static) drag_start: rl.Vector2
	@(static) dragging: bool

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
	rl.DrawRectangleRounded(shelf_rect, roundness, 12, rl.GetColor(settings.background_rgb << 8 | 0xFF))

	hovered_index := -1
	if !context_click && pointer_inside {
		for _, index in apps {
			size := f32(settings.icon_size)
			offset := f32(layout.start + i32(index) * layout.step) - scroll
			icon := rl.Rectangle{(f32(width) - size) / 2, offset, size, size}
			if layout.horizontal {
				icon = {offset, (f32(height) - size) / 2, size, size}
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
	}
	if rl.IsMouseButtonPressed(.LEFT) && hovered_index >= 0 {
		drag_pid = apps[hovered_index].pid
		drag_start = mouse
		dragging = false
	}
	if drag_pid != 0 && rl.IsMouseButtonDown(.LEFT) {
		delta := mouse - drag_start
		if !dragging && delta.x * delta.x + delta.y * delta.y >= 16 {
			dragging = true
		}
		if dragging {
			from := -1
			for app, index in apps {
				if app.pid == drag_pid {
					from = index
					break
				}
			}
			if from < 0 {
				drag_pid = 0
				dragging = false
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
				}
			}
		}
	}
	was_dragging := dragging
	if drag_pid != 0 && rl.IsMouseButtonReleased(.LEFT) {
		if !dragging && hovered_index >= 0 && apps[hovered_index].pid == drag_pid {
			result.clicked_pid = drag_pid
		}
		drag_pid = 0
		dragging = false
	} else if drag_pid != 0 && !rl.IsMouseButtonDown(.LEFT) {
		drag_pid = 0
		dragging = false
	}

	raised_icon: rl.Texture2D
	raised_rect: rl.Rectangle
	for &app, index in apps {
		size := f32(settings.icon_size)
		offset := f32(layout.start + i32(index) * layout.step) - scroll
		icon := rl.Rectangle{(f32(width) - size) / 2, offset, size, size}
		if layout.horizontal {
			icon = {offset, (f32(height) - size) / 2, size, size}
		}
		center := rl.Vector2{icon.x + size / 2, icon.y + size / 2}
		padding := min(4, f32(settings.icon_gap) / 2)
		x_padding := min(padding, f32(settings.horizontal_margin))
		y_padding := min(padding, f32(settings.vertical_margin))
		row := rl.Rectangle{icon.x - x_padding, icon.y - y_padding, size + 2 * x_padding, size + 2 * y_padding}
		hover := !was_dragging && index == hovered_index
		if hover {
			result.hovered = app
			result.tooltip_center = center
		}
		if app.pid == active_pid {
			rl.DrawRectangleRounded(row, 0.24, 8, {63, 63, 69, 255})
		}
		target: f32 = 1 if hover && settings.magnification_percent > 0 else 0
		if settings.magnification_percent > 0 && settings.hover_animation_tenths > 0 {
			step := rl.GetFrameTime() * 10 / f32(settings.hover_animation_tenths)
			app.hover_scale += clamp(target - app.hover_scale, -step, step)
		} else {
			app.hover_scale = target
		}
		if app.hover_scale > 0 {
			progress := app.hover_scale
			eased := progress * progress * (3 - 2 * progress)
			growth := f32(settings.magnification_percent) / 100
			grown := min(size * (1 + growth * eased), f32(min(width, height)))
			x, y := center.x - grown / 2, center.y - grown / 2
			// A partially scrolled icon keeps its center while it grows.
			if icon.x >= 0 && icon.x + size <= f32(width) {
				x = clamp(x, 0, f32(width) - grown)
			}
			if icon.y >= 0 && icon.y + size <= f32(height) {
				y = clamp(y, 0, f32(height) - grown)
			}
			icon = {x, y, grown, grown}
		}
		if was_dragging && app.pid == drag_pid {
			icon.x = mouse.x - icon.width / 2
			icon.y = mouse.y - icon.height / 2
			raised_icon = app.icon
			raised_rect = icon
		} else if hover {
			raised_icon = app.icon
			raised_rect = icon
		} else {
			draw_app_icon(app.icon, icon)
		}
	}
	if raised_rect.width > 0 {
		draw_app_icon(raised_icon, raised_rect)
	}
	rl.EndDrawing()
	return
}

draw_app_icon :: proc(texture: rl.Texture2D, icon: rl.Rectangle) {
	if texture.id != 0 {
		source := rl.Rectangle{0, 0, f32(texture.width), f32(texture.height)}
		rl.DrawTexturePro(texture, source, icon, {}, 0, rl.WHITE)
	} else {
		rl.DrawCircleV({icon.x + icon.width / 2, icon.y + icon.height / 2}, icon.width / 3, rl.GRAY)
	}
}
