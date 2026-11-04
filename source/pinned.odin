package main

import "core:os"
import "core:strings"

load_pinned_apps :: proc(path: string) -> [dynamic]string {
	pinned: [dynamic]string
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		return pinned
	}
	defer delete(data)
	lines := string(data)
	for line in strings.split_lines_iterator(&lines) {
		identifier := strings.trim_space(line)
		if identifier == "" || pinned_app_index(pinned[:], identifier) >= 0 {
			continue
		}
		append(&pinned, strings.clone(identifier))
	}
	return pinned
}

free_pinned_apps :: proc(pinned: [dynamic]string) {
	for identifier in pinned {
		delete(identifier)
	}
	delete(pinned)
}

pinned_app_index :: proc(pinned: []string, identifier: string) -> int {
	for candidate, index in pinned {
		if candidate == identifier {
			return index
		}
	}
	return -1
}

save_pinned_apps :: proc(dir, path: string, pinned: []string) -> os.Error {
	dir_err := os.mkdir_all(dir)
	if dir_err != nil && dir_err != .Exist {
		return dir_err
	}
	file := os.create_temp_file(dir, ".pinned-apps-*") or_return
	temp_path := strings.clone(os.name(file), context.temp_allocator)
	defer os.remove(temp_path)
	for identifier in pinned {
		_, err := os.write(file, transmute([]byte)identifier)
		if err == nil {
			_, err = os.write(file, []byte{'\n'})
		}
		if err != nil {
			_ = os.close(file)
			return err
		}
	}
	close_err := os.close(file)
	if close_err != nil {
		return close_err
	}
	return os.rename(temp_path, path)
}

set_pinned_app :: proc(dir, path: string, pinned: ^[dynamic]string, identifier: string, keep: bool) -> os.Error {
	index := pinned_app_index(pinned^[:], identifier)
	if (index >= 0) == keep {
		return nil
	}
	next: [dynamic]string
	for candidate in pinned^ {
		if candidate != identifier {
			append(&next, strings.clone(candidate))
		}
	}
	if keep {
		append(&next, strings.clone(identifier))
	}
	err := save_pinned_apps(dir, path, next[:])
	if err != nil {
		free_pinned_apps(next)
		return err
	}
	free_pinned_apps(pinned^)
	pinned^ = next
	return nil
}

sync_app_order :: proc(
	dir, path: string,
	order: ^[dynamic]string,
	apps: []App,
) -> (changed: bool, err: os.Error) {
	visible: [dynamic]string
	defer delete(visible)
	for app in apps {
		if app.bundle_id != "" && pinned_app_index(visible[:], app.bundle_id) < 0 {
			append(&visible, app.bundle_id)
		}
	}

	next: [dynamic]string
	visible_index := 0
	for identifier in order^ {
		if pinned_app_index(visible[:], identifier) >= 0 {
			append(&next, strings.clone(visible[visible_index]))
			visible_index += 1
		} else {
			append(&next, strings.clone(identifier))
		}
	}
	for visible_index < len(visible) {
		append(&next, strings.clone(visible[visible_index]))
		visible_index += 1
	}

	changed = len(next) != len(order^)
	if !changed {
		for identifier, index in next {
			if identifier != order^[index] {
				changed = true
				break
			}
		}
	}
	if !changed {
		free_pinned_apps(next)
		return false, nil
	}
	err = save_pinned_apps(dir, path, next[:])
	if err != nil {
		free_pinned_apps(next)
		return true, err
	}
	free_pinned_apps(order^)
	order^ = next
	return true, nil
}
