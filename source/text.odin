package main

import rl "vendor:raylib"

work_sans: rl.Font

load_ui_font :: proc() {
	font_data := #load("fonts/WorkSans.ttf")
	codepoints: [448]rune
	for &codepoint, index in codepoints {
		codepoint = rune(index) + 32
	}
	work_sans = rl.LoadFontFromMemory(
		".ttf",
		raw_data(font_data),
		i32(len(font_data)),
		48,
		raw_data(codepoints[:]),
		i32(len(codepoints)),
	)
	rl.SetTextureFilter(work_sans.texture, .BILINEAR)
}

draw_text :: proc(text: cstring, x, y, size: i32, color: rl.Color) {
	rl.DrawTextEx(work_sans, text, {f32(x), f32(y)}, f32(size), 0, color)
}

text_width :: proc(text: cstring, size: i32) -> f32 {
	return rl.MeasureTextEx(work_sans, text, f32(size), 0).x
}
