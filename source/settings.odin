package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ns "core:sys/darwin/Foundation"
import "core:sys/posix"
import rl "vendor:raylib"

MIN_ICON_SIZE :: 24
MAX_ICON_SIZE :: 48
MAX_CORNER_RADIUS :: 24
SETTINGS_BUTTON_RADIUS :: 9.0


DEFAULT_SETTINGS :: Settings {
	icon_size      = 32,
	background_rgb = 0x1D1D20,
}

Shelf_Edge :: enum { Left, Right, Bottom, Top }
EDGE_KEYS := [Shelf_Edge]string{.Left = "left", .Right = "right", .Bottom = "bottom", .Top = "top"}
EDGE_LABELS := [Shelf_Edge]cstring{.Left = "Left", .Right = "Right", .Bottom = "Bottom", .Top = "Top"}

Settings :: struct {
	edge:           Shelf_Edge,
	icon_size:      i32,
	corner_radius:  i32,
	background_rgb: u32,
}

load_settings :: proc(path: string) -> Settings {
	settings := DEFAULT_SETTINGS
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return settings
	}
	defer delete(data)
	lines := string(data)
	for line in strings.split_lines_iterator(&lines) {
		key, separator, value := strings.partition(line, "=")
		if separator == "" {
			continue
		}
		value = strings.trim_space(value)
		if len(value) > 0 && (value[0] == '"' || value[0] == '\'') {
			_, closing, tail := strings.partition(value[1:], value[:1])
			if closing != "" {
				value = value[:len(value) - len(tail)]
			}
		} else {
			value, _, _ = strings.partition(value, "#")
			value = strings.trim_space(value)
		}
		switch strings.trim_space(key) {
		case "edge":
			for edge in Shelf_Edge {
				edge_key := EDGE_KEYS[edge]
				if len(value) == len(edge_key) + 2 && value[1:len(value)-1] == edge_key &&
				   (value[0] == '"' || value[0] == '\'') && value[len(value)-1] == value[0] {
					settings.edge = edge
				}
			}
		case "icon_size":
			size, valid := strconv.parse_int(value)
			if valid && size >= MIN_ICON_SIZE && size <= MAX_ICON_SIZE {
				settings.icon_size = i32(size)
			}
		case "corner_radius":
			radius, valid := strconv.parse_int(value)
			if valid && radius >= 0 && radius <= MAX_CORNER_RADIUS {
				settings.corner_radius = i32(radius)
			}
		case "background_color":
			if len(value) == 9 &&
			   value[1] == '#' &&
			   (value[0] == '"' || value[0] == '\'') &&
			   value[8] == value[0] {
				rgb, valid := strconv.parse_uint(value[2:8], 16)
				if valid && rgb <= 0xFFFFFF {
					settings.background_rgb = u32(rgb)
				}
			}
		}
	}
	return settings
}

save_settings :: proc(dir, path: string, settings: Settings) -> os.Error {
	dir_err := os.mkdir_all(dir)
	if dir_err != nil && dir_err != .Exist {
		return dir_err
	}
	file := os.create_temp_file(dir, ".hood-*.toml") or_return
	temp_path := strings.clone(os.name(file), context.temp_allocator)
	defer os.remove(temp_path)
	edge := EDGE_KEYS[settings.edge]
	text := fmt.tprintf(
		"edge = \"%s\"\nicon_size = %d\ncorner_radius = %d\nbackground_color = \"#%06X\"\n",
		edge,
		settings.icon_size,
		settings.corner_radius,
		settings.background_rgb,
	)
	_, err := os.write(file, transmute([]byte)text)
	close_err := os.close(file)
	if err != nil {
		return err
	}
	if close_err != nil {
		return close_err
	}
	return os.rename(temp_path, path)
}

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
	if failed {
		draw_text("Could not save hood.toml", 20, 251, 16, theme.error)
	}
	done = ui_button(theme, {240, 275, 74, 32}, "OK") && !was_open
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

// Raylib owns one window per process. The shelf launches this mode as a child.
run_settings :: proc(config_dir, config_path: string, initial: Settings) {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	rl.SetConfigFlags({.WINDOW_HIGHDPI, .VSYNC_HINT, .WINDOW_TOPMOST})
	rl.InitWindow(334, 327, "Settings")
	defer rl.CloseWindow()
	load_ui_font()
	defer rl.UnloadFont(work_sans)
	rl.SetTargetFPS(60)

	application := send(^ns.Object, native_class("NSApplication"), "sharedApplication")
	send(ns.BOOL, application, "setActivationPolicy:", int(1))
	// Give Raylib a frame to finish processing the window's initial events.
	window := cocoa_window()
	rl.BeginDrawing()
	rl.ClearBackground(settings_theme(window).background)
	rl.EndDrawing()
	notify(application, "activateIgnoringOtherApps:", ns.BOOL(true))
	notify(window, "makeKeyAndOrderFront:", (^ns.Object)(nil))
	notify(window, "orderFrontRegardless")
	fmt.eprintfln("Hood Settings: window ready (visible: %v)", send(ns.BOOL, window, "isVisible"))

	draft := initial
	failed := false
	dropdown := false
	color_panel: ^ns.Object
	picker_active := false
	picker_rgb := draft.background_rgb
	for !rl.WindowShouldClose() && posix.getppid() != 1 {
		previous := draft
		if picker_active {
			if rgb, ok := color_panel_rgb(color_panel); ok && rgb != picker_rgb {
				picker_rgb = rgb
				draft.background_rgb = rgb
			}
			picker_active = send(ns.BOOL, color_panel, "isVisible")
		}
		pick_color, done := settings_view(&draft, failed, settings_theme(window), &dropdown)
		if draft != previous {
			failed = true
			if config_path != "" {
				err := save_settings(config_dir, config_path, draft)
				failed = err != nil
				if failed {
					fmt.eprintfln("Could not save %s: %v", config_path, err)
				}
			}
			if failed {
				draft = previous
			}
		}
		if done {
			break
		}
		if pick_color {
			color_panel = send(^ns.Object, native_class("NSColorPanel"), "sharedColorPanel")
			notify(color_panel, "setShowsAlpha:", ns.BOOL(false))
			notify(color_panel, "setContinuous:", ns.BOOL(true))
			notify(color_panel, "setLevel:", send(int, window, "level") + 1)
		}
		if pick_color || (picker_active && draft.background_rgb != picker_rgb) {
			picker_rgb = draft.background_rgb
			set_color_panel_rgb(color_panel, picker_rgb)
		}
		if pick_color {
			notify(color_panel, "makeKeyAndOrderFront:", (^ns.Object)(nil))
			picker_active = true
		}
		free_all(context.temp_allocator)
	}
}
