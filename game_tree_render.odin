package godin

import "core:fmt"
import rl "vendor:raylib"

GameTreeRender :: struct {
	// top left x, y and w / h
	viewX, viewY, viewW, viewH: i32,
}

NODE_SIZE :: 12

draw_game_tree :: proc(render: ^GameTreeRender, game: ^GoGame) {
	rl.DrawRectangleV(rl_vec2_from_i32(render.viewX, render.viewY), rl_vec2_from_i32(render.viewW, render.viewH), rl.BLACK)

	treeRows := game.treeH
	treeCols := game.treeW

	treeWidthPix := i32(NODE_SIZE * treeCols)
	treeHeightPix := i32(NODE_SIZE * treeRows)

	fmt.println("twp: ", treeWidthPix, "thp: ", treeHeightPix)

	// For now assume it fits, we will handle scroll layout later
	if treeWidthPix <= render.viewW && treeHeightPix <= render.viewH {
		treeX := render.viewX + (render.viewW - treeWidthPix) / 2
		treeY := render.viewY + (render.viewH - treeHeightPix) / 2
	}

	// Draw border
	// Draw scroll bars
	// Draw 
}
