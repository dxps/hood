package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/posix"
import ns "core:sys/darwin/Foundation"
import rl "vendor:raylib"

MIN_ICON_SIZE :: 24
MAX_ICON_SIZE :: 48

Settings :: struct {
	right_edge: bool,
	icon_size: i32,
}

load_settings :: proc(path: string) -> Settings {
	settings := Settings{icon_size = 32}
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
		value, _, _ = strings.partition(value, "#")
		value = strings.trim_space(value)
		switch strings.trim_space(key) {
		case "edge":
			switch value {
			case `"left"`, "'left'": settings.right_edge = false
			case `"right"`, "'right'": settings.right_edge = true
			}
		case "icon_size":
			size, valid := strconv.parse_int(value)
			if valid && size >= MIN_ICON_SIZE && size <= MAX_ICON_SIZE {
				settings.icon_size = i32(size)
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
	edge := settings.right_edge ? "right" : "left"
	text := fmt.tprintf("edge = \"%s\"\nicon_size = %d\n", edge, settings.icon_size)
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

ui_button :: proc(rect: rl.Rectangle, text: cstring, selected := false, font_size: i32 = 16) -> bool {
	hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	color := rl.Color{48, 48, 54, 255}
	if hover || selected {
		color = {74, 79, 96, 255}
	}
	rl.DrawRectangleRounded(rect, 0.18, 8, color)
	x := i32(rect.x + (rect.width - text_width(text, font_size)) / 2)
	draw_text(text, x, i32(rect.y + (rect.height - f32(font_size)) / 2), font_size, rl.RAYWHITE)
	return hover && rl.IsMouseButtonReleased(.LEFT)
}

settings_view :: proc(draft: ^Settings, failed: bool) {
	rl.BeginDrawing()
	defer rl.EndDrawing()
	rl.ClearBackground({29, 29, 32, 255})
	draw_text("Hood Settings", 20, 20, 24, rl.RAYWHITE)
	draw_text("Shelf edge", 20, 64, 16, rl.RAYWHITE)
	if ui_button({150, 56, 78, 32}, "Left", !draft.right_edge) {
		draft.right_edge = false
	}
	if ui_button({236, 56, 78, 32}, "Right", draft.right_edge) {
		draft.right_edge = true
	}
	draw_text("Icon size", 20, 114, 16, rl.RAYWHITE)
	if ui_button({150, 106, 40, 32}, "-") {
		draft.icon_size = max(MIN_ICON_SIZE, draft.icon_size - 4)
	}
	draw_text(fmt.ctprintf("%d px", draft.icon_size), 204, 114, 16, rl.RAYWHITE)
	if ui_button({274, 106, 40, 32}, "+") {
		draft.icon_size = min(MAX_ICON_SIZE, draft.icon_size + 4)
	}
	if failed {
		draw_text("Could not save hood.toml", 20, 154, 16, rl.PINK)
	}
}

// Raylib owns one window per process. The shelf launches this mode as a child.
run_settings :: proc(config_dir, config_path: string, initial: Settings) {
	pool := send(^ns.Object, native_class("NSAutoreleasePool"), "new")
	defer notify(pool, "drain")

	rl.SetConfigFlags({.WINDOW_HIGHDPI, .VSYNC_HINT, .WINDOW_TOPMOST})
	rl.InitWindow(334, 190, "Hood Settings")
	defer rl.CloseWindow()
	load_ui_font()
	defer rl.UnloadFont(work_sans)
	rl.SetTargetFPS(60)

	application := send(^ns.Object, native_class("NSApplication"), "sharedApplication")
	send(ns.BOOL, application, "setActivationPolicy:", int(1))
	// Give Raylib a frame to finish processing the window's initial events.
	rl.BeginDrawing()
	rl.ClearBackground({29, 29, 32, 255})
	rl.EndDrawing()
	window := cocoa_window()
	notify(application, "activateIgnoringOtherApps:", ns.BOOL(true))
	notify(window, "makeKeyAndOrderFront:", (^ns.Object)(nil))
	notify(window, "orderFrontRegardless")
	fmt.eprintfln("Hood Settings: window ready (visible: %v)", send(ns.BOOL, window, "isVisible"))

	draft := initial
	failed := false
	for !rl.WindowShouldClose() && posix.getppid() != 1 {
		previous := draft
		settings_view(&draft, failed)
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
		free_all(context.temp_allocator)
	}
}
