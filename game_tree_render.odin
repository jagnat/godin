package godin

import rl "vendor:raylib"

GameTreeRender :: struct {
	// top left x, y and w / h
	viewX, viewY, viewW, viewH: i32,

	game: ^GoGame,
}

draw_game_tree :: proc(render: ^GameTreeRender) {
	rl.DrawRectangleV(rl_vec2_from_i32(render.viewX, render.viewY), rl_vec2_from_i32(render.viewW, render.viewH), rl.BLACK)
}
