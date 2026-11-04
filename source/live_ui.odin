package main

import "core:dynlib"
import ns "vendor:darwin/AppKit"
import rl "vendor:raylib"

LIVE_UI :: #config(HOOD_LIVE_UI, false)

import "core:fmt"
import "core:os"
import "core:strings"

Settings_Dropdown :: enum {
	None,
	Show,
	Animation,
	Show_Hide_Delay,
	Position,
	Tooltip_Delay,
	Hover_Magnification,
	Hover_Animation,
}

settings_height :: proc(settings: Settings) -> i32 {
	return 688 + (90 if settings.auto_hide else 0)
}

Shelf_Frame :: struct {
	hovered:        App,
	tooltip_center: rl.Vector2,
	clicked_id:     u64,
	pointed_id:     u64,
	order_changed:  bool,
}

// Keep the module boundary here so changes to these signatures rebuild the host.
@(export)
hood_draw_shelf :: proc(
	apps: []App,
	settings: Settings,
	width, height: i32,
	scroll: f32,
	active_pid: i32,
	context_click: bool,
) -> Shelf_Frame {
	return draw_shelf(apps, settings, width, height, scroll, active_pid, context_click)
}

@(export)
hood_draw_settings :: proc(
	font: rl.Font,
	window: ^ns.Object,
	draft: ^Settings,
	failed: bool,
	dropdown: ^Settings_Dropdown,
) -> (
	bool,
	bool,
) {
	work_sans = font
	return settings_view(draft, failed, settings_theme(window), dropdown)
}

Live_UI :: struct {
	library:    dynlib.Library,
	path:       string,
	last_check: f64,
	shelf:      type_of(hood_draw_shelf),
	settings:   type_of(hood_draw_settings),
}

refresh_live_ui :: proc(ui: ^Live_UI) {
	if LIVE_UI {
		now := rl.GetTime()
		if now < ui.last_check {
			return
		}
		ui.last_check = now + 0.2

		manifest := os.get_env("HOOD_UI_MANIFEST", context.allocator)
		if manifest == "" {
			return
		}
		defer delete(manifest)
		bytes, err := os.read_entire_file(manifest, context.allocator)
		if err != nil {
			return
		}
		defer delete(bytes)
		path := strings.trim_space(string(bytes))
		if path == "" || path == ui.path {
			return
		}
		delete(ui.path)
		ui.path = strings.clone(path)

		library, loaded := dynlib.load_library(path, allocator = context.allocator)
		if !loaded {
			fmt.eprintfln("Hood: could not load UI update: %v", dynlib.last_error())
			return
		}
		shelf, shelf_ok := dynlib.symbol_address(library, "hood_draw_shelf", context.allocator)
		settings, settings_ok := dynlib.symbol_address(library, "hood_draw_settings", context.allocator)
		if !shelf_ok || !settings_ok {
			_ = dynlib.unload_library(library)
			fmt.eprintln("Hood: UI update is missing required entry points")
			return
		}
		if ui.library != nil {
			_ = dynlib.unload_library(ui.library)
		}
		ui.library = library
		ui.shelf = cast(type_of(ui.shelf))shelf
		ui.settings = cast(type_of(ui.settings))settings
		fmt.eprintln("Hood: UI reloaded")
	}
}

close_live_ui :: proc(ui: ^Live_UI) {
	if ui.library != nil {
		_ = dynlib.unload_library(ui.library)
	}
	delete(ui.path)
}

ui_shelf :: proc(
	ui: ^Live_UI,
	apps: []App,
	settings: Settings,
	width, height: i32,
	scroll: f32,
	active_pid: i32,
	context_click: bool,
) -> Shelf_Frame {
	refresh_live_ui(ui)
	draw := ui.shelf if ui.shelf != nil else hood_draw_shelf
	return draw(apps, settings, width, height, scroll, active_pid, context_click)
}

ui_settings :: proc(
	ui: ^Live_UI,
	window: ^ns.Object,
	draft: ^Settings,
	failed: bool,
	dropdown: ^Settings_Dropdown,
) -> (
	bool,
	bool,
) {
	refresh_live_ui(ui)
	draw := ui.settings if ui.settings != nil else hood_draw_settings
	return draw(work_sans, window, draft, failed, dropdown)
}
