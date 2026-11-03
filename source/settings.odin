package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ns "core:sys/darwin/Foundation"
import "core:sys/posix"
import rl "vendor:raylib"

SETTINGS_WIDTH :: 400

MIN_ICON_SIZE :: 24
MAX_ICON_SIZE :: 48
MAX_CORNER_RADIUS :: 24
MAX_ICON_SPACING :: 48


TOOLTIP_DELAYS_MS := [6]i32{0, 100, 250, 450, 750, 1000}

DEFAULT_SETTINGS :: Settings {
	icon_size      = 32,
	background_rgb = 0x1D1D20,
	icon_gap = 20,
	horizontal_margin = 18,
	vertical_margin = 14,
	animation_tenths = 3,
	tooltip_delay_ms = 450,
}

Shelf_Edge :: enum { Left, Right, Bottom, Top }
EDGE_KEYS := [Shelf_Edge]string{.Left = "left", .Right = "right", .Bottom = "bottom", .Top = "top"}
EDGE_LABELS := [Shelf_Edge]cstring{.Left = "Left", .Right = "Right", .Bottom = "Bottom", .Top = "Top"}

Settings :: struct {
	edge:           Shelf_Edge,
	icon_size:      i32,
	corner_radius:  i32,
	background_rgb: u32,
	icon_gap, horizontal_margin, vertical_margin: i32,
	auto_hide: bool,
	animation_tenths: i32,
	tooltip_delay_ms: i32,
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
		key = strings.trim_space(key)
		switch key {
		case "auto_hide":
			if value == "true" || value == "false" {
				settings.auto_hide = value == "true"
			}
		case "tooltip_delay_ms":
			delay, valid := strconv.parse_int(value)
			if valid {
				for option in TOOLTIP_DELAYS_MS {
					if delay == int(option) {
						settings.tooltip_delay_ms = option
						break
					}
				}
			}
		case "animation_tenths":
			duration, valid := strconv.parse_int(value)
			if valid && duration >= 0 && duration <= 10 {
				settings.animation_tenths = i32(duration)
			}
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
		case "icon_gap", "horizontal_margin", "vertical_margin":
			spacing, valid := strconv.parse_int(value)
			if valid && spacing >= 0 && spacing <= MAX_ICON_SPACING {
				switch key {
				case "icon_gap": settings.icon_gap = i32(spacing)
				case "horizontal_margin": settings.horizontal_margin = i32(spacing)
				case "vertical_margin": settings.vertical_margin = i32(spacing)
				}
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
		"edge = \"%s\"\nicon_size = %d\ncorner_radius = %d\nbackground_color = \"#%06X\"\nicon_gap = %d\nhorizontal_margin = %d\nvertical_margin = %d\nauto_hide = %v\nanimation_tenths = %d\ntooltip_delay_ms = %d\n",
		edge,
		settings.icon_size,
		settings.corner_radius,
		settings.background_rgb,
		settings.icon_gap,
		settings.horizontal_margin,
		settings.vertical_margin,
		settings.auto_hide,
		settings.animation_tenths,
		settings.tooltip_delay_ms,
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

// Raylib owns one window per process. The shelf launches this mode as a child.
run_settings :: proc(config_dir, config_path: string, initial: Settings) {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	rl.SetConfigFlags({.WINDOW_HIGHDPI, .VSYNC_HINT, .WINDOW_TOPMOST})
	rl.InitWindow(SETTINGS_WIDTH, settings_height(initial), "Settings")
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

	ui: Live_UI
	defer close_live_ui(&ui)
	draft := initial
	failed := false
	dropdown := Settings_Dropdown.None
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
		pick_color, done := ui_settings(&ui, window, &draft, failed, &dropdown)
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
		if draft.auto_hide != previous.auto_hide {
			rl.SetWindowSize(SETTINGS_WIDTH, settings_height(draft))
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
