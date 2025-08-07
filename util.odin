package godin

import rl "vendor:raylib"

slice_find :: proc(slice : []$T, val : T) -> int {
	for s, i in slice {
		if s == val do return i
	}
	return -1
}

slice_contains :: proc(slice : []$T, val : T) -> bool {
	return slice_find(slice, val) != -1
}

rl_tex_from_memory :: proc(data: []u8, flip := false) -> rl.Texture2D {
	img := rl.LoadImageFromMemory(".png", rawptr(&data[0]), i32(len(data)))
	if flip {
		rl.ImageFlipVertical(&img)
	}
	return rl.LoadTextureFromImage(img)
}

rl_sound_from_memory :: proc(data: []u8) -> rl.Sound {
	wav := rl.LoadWaveFromMemory(".wav", rawptr(&data[0]), i32(len(data)))
	return rl.LoadSoundFromWave(wav)
}

rl_font_from_memory :: proc(data: []u8) -> rl.Font {
	return rl.LoadFontFromMemory(".ttf", rawptr(&data[0]), i32(len(data)), 30, nil, 95)
}

rl_vec2_from_i32 :: proc(x, y: i32) -> rl.Vector2 {
	return rl.Vector2{f32(x), f32(y)}
}