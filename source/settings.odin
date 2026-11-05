package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import ns "vendor:darwin/AppKit"
import "core:sys/posix"

MIN_ICON_SIZE :: 24
MAX_ICON_SIZE :: 48
MAX_CORNER_RADIUS :: 24
MAX_SCREEN_EDGE_GAP :: 20
MAX_MAGNIFICATION_ANIMATION_TENTHS :: 5
MAX_SHOW_ANIMATION_TENTHS :: 5
MAX_ICON_SPACING :: 48


MAGNIFICATION_PERCENTS := [10]i32{0, 5, 10, 15, 20, 25, 30, 40, 50, 60}

SHOW_HIDE_DELAYS_MS := [5]i32{0, 50, 100, 200, 300}

TOOLTIP_DELAYS_MS := [6]i32{0, 100, 250, 450, 750, 1000}

MIN_TOOLTIP_OPACITY_PERCENT :: 20
MAX_TOOLTIP_OPACITY_PERCENT :: 100

DEFAULT_SETTINGS :: Settings {
	icon_size              = 32,
	corner_radius          = 12,
	background_rgb         = 0x474446,
	icon_gap               = 8,
	horizontal_margin      = 6,
	vertical_margin        = 10,
	screen_edge_gap        = 0,
	animation_tenths       = 3,
	tooltip_delay_ms       = 100,
	tooltip_opacity_percent = 100,
	hover_wave             = true,
	magnification_percent  = 60,
	hover_animation_tenths = 3,
}

Shelf_Edge :: enum {
	Left,
	Right,
	Bottom,
	Top,
}
EDGE_KEYS := [Shelf_Edge]string {
	.Left   = "left",
	.Right  = "right",
	.Bottom = "bottom",
	.Top    = "top",
}
Settings :: struct {
	edge:                                         Shelf_Edge,
	icon_size:                                    i32,
	corner_radius:                                i32,
	background_rgb:                               u32,
	icon_gap, horizontal_margin, vertical_margin: i32,
	screen_edge_gap:                              i32,
	show_hide_delay_ms:                           i32,
	auto_hide:                                    bool,
	animation_tenths:                             i32,
	tooltip_delay_ms:                             i32,
	tooltip_opacity_percent:                      i32,
	hover_wave:                                   bool,
	magnification_percent:                        i32,
	hover_animation_tenths:                       i32,
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
		case "hover_magnification":
			// Read the previous on/off setting from existing configs.
			if value == "false" {
				settings.magnification_percent = 0
			}
		case "hover_wave":
			if value == "true" || value == "false" {
				settings.hover_wave = value == "true"
			}
		case "magnification_percent":
			percent, valid := strconv.parse_int(value)
			if valid {
				for option in MAGNIFICATION_PERCENTS {
					if min(percent, 60) == int(option) {
						settings.magnification_percent = option
						break
					}
				}
			}
		case "hover_animation_tenths":
			duration, valid := strconv.parse_int(value)
			if valid && duration >= 0 && duration <= 10 {
				settings.hover_animation_tenths = i32(clamp(duration, 1, MAX_MAGNIFICATION_ANIMATION_TENTHS))
			}
		case "show_hide_delay_ms":
			delay, valid := strconv.parse_int(value)
			if valid {
				for option in SHOW_HIDE_DELAYS_MS {
					if delay == int(option) {
						settings.show_hide_delay_ms = option
						break
					}
				}
			}
		case "screen_edge_gap":
			gap, valid := strconv.parse_int(value)
			if valid && gap >= 0 && gap <= MAX_SCREEN_EDGE_GAP {
				settings.screen_edge_gap = i32(gap)
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
		case "tooltip_opacity_percent":
			opacity, valid := strconv.parse_int(value)
			if valid && opacity >= MIN_TOOLTIP_OPACITY_PERCENT && opacity <= MAX_TOOLTIP_OPACITY_PERCENT {
				settings.tooltip_opacity_percent = i32(opacity)
			}
		case "animation_tenths":
			duration, valid := strconv.parse_int(value)
			if valid && duration >= 0 && duration <= 10 {
				settings.animation_tenths = i32(min(duration, MAX_SHOW_ANIMATION_TENTHS))
			}
		case "edge":
			for edge in Shelf_Edge {
				edge_key := EDGE_KEYS[edge]
				if len(value) == len(edge_key) + 2 &&
				   value[1:len(value) - 1] == edge_key &&
				   (value[0] == '"' || value[0] == '\'') &&
				   value[len(value) - 1] == value[0] {
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
				case "icon_gap":
					settings.icon_gap = i32(spacing)
				case "horizontal_margin":
					settings.horizontal_margin = i32(spacing)
				case "vertical_margin":
					settings.vertical_margin = i32(spacing)
				}
			}
		case "background_color":
			if len(value) == 9 && value[1] == '#' && (value[0] == '"' || value[0] == '\'') && value[8] == value[0] {
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
		"edge = \"%s\"\nicon_size = %d\ncorner_radius = %d\nbackground_color = \"#%06X\"\nicon_gap = %d\nhorizontal_margin = %d\nvertical_margin = %d\nauto_hide = %v\nanimation_tenths = %d\ntooltip_delay_ms = %d\ntooltip_opacity_percent = %d\nhover_wave = %v\nmagnification_percent = %d\nhover_animation_tenths = %d\nshow_hide_delay_ms = %d\nscreen_edge_gap = %d\n",
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
		settings.tooltip_opacity_percent,
		settings.hover_wave,
		settings.magnification_percent,
		settings.hover_animation_tenths,
		settings.show_hide_delay_ms,
		settings.screen_edge_gap,
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

native_settings_state :: proc(settings: Settings) -> Native_Settings_State {
	return {
		i32(settings.edge),
		settings.icon_size,
		settings.corner_radius,
		settings.background_rgb,
		settings.icon_gap,
		settings.horizontal_margin,
		settings.vertical_margin,
		settings.screen_edge_gap,
		settings.show_hide_delay_ms,
		i32(settings.auto_hide),
		settings.animation_tenths,
		settings.tooltip_delay_ms,
		i32(settings.hover_wave),
		settings.magnification_percent,
		settings.hover_animation_tenths,
		settings.tooltip_opacity_percent,
	}
}

settings_from_native :: proc(state: Native_Settings_State) -> Settings {
	return {
		edge                       = Shelf_Edge(state.edge),
		icon_size                  = state.icon_size,
		corner_radius              = state.corner_radius,
		background_rgb             = state.background_rgb,
		icon_gap                   = state.icon_gap,
		horizontal_margin          = state.horizontal_margin,
		vertical_margin            = state.vertical_margin,
		screen_edge_gap            = state.screen_edge_gap,
		show_hide_delay_ms         = state.show_hide_delay_ms,
		auto_hide                  = state.auto_hide != 0,
		animation_tenths           = state.animation_tenths,
		tooltip_delay_ms           = state.tooltip_delay_ms,
		tooltip_opacity_percent    = state.tooltip_opacity_percent,
		hover_wave                 = state.hover_wave != 0,
		magnification_percent      = state.magnification_percent,
		hover_animation_tenths     = state.hover_animation_tenths,
	}
}

settings_runtime_update :: proc(window: ^ns.Object, runtime: ^Runtime_State) {
	hood_settings_set_runtime(
		window,
		runtime.memory_bytes,
		i32(runtime.available),
		i32(runtime.bundled),
		i32(runtime.login_service != nil),
		i32(runtime.login_enabled),
		i32(runtime.login_pending),
		i32(runtime.login_failed),
	)
}

// The shelf launches Settings as a child process. AppKit owns its window and
// controls; Odin remains responsible for persistence and runtime operations.
run_settings :: proc(config_dir, config_path: string, initial: Settings) {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	runtime := Runtime_State{dock_pid = i32(posix.getppid())}
	init_runtime_login(&runtime)
	defer close_runtime_login(&runtime)
	update_runtime(&runtime)

	state := native_settings_state(initial)
	saved := state
	window := hood_settings_create(
		&state,
		i32(runtime.bundled),
		i32(runtime.login_service != nil),
		i32(runtime.login_enabled),
		i32(runtime.login_pending),
	)
	if window == nil {
		fmt.eprintln("Hood could not create its Settings window.")
		return
	}
	defer hood_settings_close(window)
	settings_runtime_update(window, &runtime)

	next_sample := hood_time() + 1
	for posix.getppid() != 1 {
		frame_pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
		defer notify(frame_pool, "drain")
		defer free_all(context.temp_allocator)

		events: Native_Settings_Events
		hood_settings_poll(window, &state, &events, 0.05)
		if events.closed != 0 {
			break
		}
		if events.changed != 0 {
			failed := config_path == ""
			if !failed {
				err := save_settings(config_dir, config_path, settings_from_native(state))
				failed = err != nil
				if failed {
					fmt.eprintfln("Could not save %s: %v", config_path, err)
				}
			}
			if failed {
				state = saved
				hood_settings_update(window, &state)
			} else {
				saved = state
			}
			hood_settings_set_save_failed(window, i32(failed))
		}
		if events.toggle_login != 0 {
			toggle_runtime_login(&runtime)
			settings_runtime_update(window, &runtime)
		}
		if events.quit_dock != 0 {
			if i32(posix.getppid()) == runtime.dock_pid && runtime.dock_pid > 1 && posix.kill(posix.pid_t(runtime.dock_pid), .SIGTERM) == .OK {
				break
			}
			runtime.quit_failed = true
			settings_runtime_update(window, &runtime)
		}
		now := hood_time()
		if now >= next_sample {
			update_runtime(&runtime)
			settings_runtime_update(window, &runtime)
			next_sample = now + 1
		}
	}
}
