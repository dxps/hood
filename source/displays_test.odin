package main

import "core:testing"
import "core:os"
import "core:strings"

@(test)
display_settings_roundtrip :: proc(t: ^testing.T) {
	file, err := os.create_temp_file("/tmp", "hood-display-settings-*.toml")
	testing.expect(t, err == nil)
	if err != nil { return }
	path := strings.clone(os.name(file), context.temp_allocator)
	os.close(file)
	defer os.remove(path)
	choices := []string{"", "all", "00000000-1234-5678-9ABC-000000000001"}
	for choice in choices {
		settings := DEFAULT_SETTINGS
		copy(settings.display[:], transmute([]u8)choice)
		settings.edge = .Bottom
		settings.icon_size = 40
		testing.expect(t, save_settings("/tmp", path, settings) == nil)
		loaded := load_settings(path)
		testing.expect(t, loaded == settings)
		testing.expect(t, settings_from_native(native_settings_state(settings)) == settings)
		testing.expect(t, string_from_display(loaded.display) == choice)
	}
	testing.expect(t, valid_display_choice("all"))
	testing.expect(t, !valid_display_choice("not-a-display"))
	testing.expect(t, !valid_display_choice(strings.repeat("x", 36, context.temp_allocator)))
}
