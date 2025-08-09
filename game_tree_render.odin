package godin

import "core:fmt"
import rl "vendor:raylib"

GameTreeRender :: struct {
	// top left x, y and w / h
	viewX, viewY, viewW, viewH: i32,

	treeX, treeY, treeW, treeH: i32,

	scrollXEnabled, scrollYEnabled: bool,
	scrollXPercent: f32,
	scrollYPercent: f32,

	selectedNode : ^GameNode
}

NODE_SIZE_PX :: 24

SPRITE_SIZE_PX :: 12

SCROLL_BAR_WIDTH :: 16

NODE_ORIGIN :: rl.Vector2{NODE_SIZE_PX / 2, NODE_SIZE_PX / 2}

BLACK_NODE_UNSELECTED :: rl.Rectangle{0,                0,              SPRITE_SIZE_PX, SPRITE_SIZE_PX}
BLACK_NODE_SELECTED   :: rl.Rectangle{0,                SPRITE_SIZE_PX,   SPRITE_SIZE_PX, SPRITE_SIZE_PX}
WHITE_NODE_UNSELECTED :: rl.Rectangle{1 * SPRITE_SIZE_PX, 0,              SPRITE_SIZE_PX, SPRITE_SIZE_PX}
WHITE_NODE_SELECTED   :: rl.Rectangle{1 * SPRITE_SIZE_PX, SPRITE_SIZE_PX,   SPRITE_SIZE_PX, SPRITE_SIZE_PX}
OTHER_NODE_UNSELECTED :: rl.Rectangle{2 * SPRITE_SIZE_PX, 0,              SPRITE_SIZE_PX, SPRITE_SIZE_PX}
OTHER_NODE_SELECTED   :: rl.Rectangle{2 * SPRITE_SIZE_PX, SPRITE_SIZE_PX,   SPRITE_SIZE_PX, SPRITE_SIZE_PX}

VERTICAL_LINK         :: rl.Rectangle{3 * SPRITE_SIZE_PX, 0,              SPRITE_SIZE_PX, SPRITE_SIZE_PX}
DIAG_END              :: rl.Rectangle{4 * SPRITE_SIZE_PX, 0,          SPRITE_SIZE_PX, SPRITE_SIZE_PX}
HORIZ_LINK            :: rl.Rectangle{3 * SPRITE_SIZE_PX, SPRITE_SIZE_PX,          SPRITE_SIZE_PX, SPRITE_SIZE_PX}
HORIZ_DIAG            :: rl.Rectangle{4 * SPRITE_SIZE_PX, SPRITE_SIZE_PX,          SPRITE_SIZE_PX, SPRITE_SIZE_PX}

game_tree_render_init :: proc(render: ^GameTreeRender) {
	render.scrollXPercent = 0.5
	render.scrollYPercent = 0.5
}

draw_game_tree :: proc(render: ^GameTreeRender, game: ^GoGame) {
	rl.DrawRectangleV(rl_vec2_from_i32(render.viewX, render.viewY), rl_vec2_from_i32(render.viewW, render.viewH), rl.Color{255, 255, 255, 80})

	treeRows := game.treeH
	treeCols := game.treeW

	render.treeW = i32(NODE_SIZE_PX * treeCols)
	render.treeH = i32(NODE_SIZE_PX * treeRows)

	render.scrollXEnabled = false
	render.scrollYEnabled = false

	// For now assume it fits, we will handle scroll layout later
	if render.treeW <= render.viewW && render.treeH <= render.viewH {
		render.treeX = render.viewX + (render.viewW - render.treeW) / 2
		render.treeY = render.viewY + (render.viewH - render.treeH) / 2

		render.selectedNode = game.currentPosition

	} else {
		ySub := i32(0)
		if render.treeW > render.viewX {
			render.scrollXEnabled = true
			ySub += SCROLL_BAR_WIDTH
		}
		if render.treeH - ySub > render.viewY {
			render.scrollYEnabled = true
		}
		if render.scrollYEnabled && render.treeW - SCROLL_BAR_WIDTH > render.viewX {
			render.scrollXEnabled = true
		}

	}

	draw_tree_recursively(render, game.headNode)

	// Draw border
	// Draw scroll bars
	// Draw 
}

get_tree_node_rect :: proc(render: ^GameTreeRender, node: ^GameNode) -> rl.Rectangle {
	return get_tree_tile_rect(render, node.treeCol, node.treeRow)
}

get_tree_tile_rect :: proc(render: ^GameTreeRender, col, row: i32) -> rl.Rectangle {
	x := render.treeX + col * NODE_SIZE_PX
	y := render.treeY + row * NODE_SIZE_PX
	return rl.Rectangle{f32(x) + NODE_SIZE_PX / 2, f32(y) + NODE_SIZE_PX / 2, NODE_SIZE_PX, NODE_SIZE_PX}
}

draw_tree_recursively :: proc(render: ^GameTreeRender, node: ^GameNode) {
	if node == nil do return

	// first draw node sprite itself
	sprite := OTHER_NODE_UNSELECTED

	if node.moveType == .Move {
		sprite = node.tile == .Black? BLACK_NODE_UNSELECTED : WHITE_NODE_UNSELECTED
	}

	if node == render.selectedNode {
		switch sprite {
			case OTHER_NODE_UNSELECTED:
			sprite = OTHER_NODE_SELECTED
			case BLACK_NODE_UNSELECTED:
			sprite = BLACK_NODE_SELECTED
			case WHITE_NODE_UNSELECTED:
			sprite = WHITE_NODE_SELECTED
		}
	}

	nodeRect := get_tree_node_rect(render, node)

	rl.DrawTexturePro(gameTreeAtlas, sprite, nodeRect, NODE_ORIGIN, 0, rl.WHITE)

	// then draw parent linkage
	parent := node.parent
	if parent != nil {
		parentRect := get_tree_node_rect(render, parent)
		if parent.treeCol == node.treeCol { // simple link
			rl.DrawTexturePro(gameTreeAtlas, VERTICAL_LINK, nodeRect, NODE_ORIGIN, 0, rl.WHITE)
			rl.DrawTexturePro(gameTreeAtlas, VERTICAL_LINK, parentRect, NODE_ORIGIN, 180, rl.WHITE)
		} else {
			rl.DrawTexturePro(gameTreeAtlas, DIAG_END, nodeRect, NODE_ORIGIN, 0, rl.WHITE)
			if node.treeCol == parent.treeCol + 1 { // only need to draw a single diagonal
				rl.DrawTexturePro(gameTreeAtlas, DIAG_END, parentRect, NODE_ORIGIN, 180, rl.WHITE)
			} else { // need to draw intermediate horizontal bars
				diagRect := get_tree_tile_rect(render, node.treeCol - 1, node.treeRow - 1)
				rl.DrawTexturePro(gameTreeAtlas, HORIZ_DIAG, diagRect, NODE_ORIGIN, 0, rl.WHITE)
				rl.DrawTexturePro(gameTreeAtlas, VERTICAL_LINK, parentRect, NODE_ORIGIN, 90, rl.WHITE)
				for i in parent.treeCol + 1 ..< node.treeCol - 1 {
					horizRect := get_tree_tile_rect(render, i, node.treeRow - 1)
					rl.DrawTexturePro(gameTreeAtlas, HORIZ_LINK, horizRect, NODE_ORIGIN, 0, rl.WHITE)
				}
			}
		}
	}

	draw_tree_recursively(render, node.children)
	draw_tree_recursively(render, node.siblingNext)
}

draw_horiz_scrollbar :: proc () {

}

draw_vert_scrollbar :: proc() {

}
