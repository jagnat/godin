package godin

import "core:fmt"
import rl "vendor:raylib"

GameTreeRender :: struct {
	// top left x, y and w / h
	viewX, viewY, viewW, viewH: i32,
	treeX, treeY, treeW, treeH: i32,
	selectedNode : ^GameNode
}

NODE_SIZE_PX :: 24

SPRITE_SIZE_PX :: 12

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

draw_game_tree :: proc(render: ^GameTreeRender, game: ^GoGame) {
	// rl.DrawRectangleV(rl_vec2_from_i32(render.viewX, render.viewY), rl_vec2_from_i32(render.viewW, render.viewH), rl.WHITE)

	treeRows := game.treeH
	treeCols := game.treeW

	render.treeW = i32(NODE_SIZE_PX * treeCols)
	render.treeH = i32(NODE_SIZE_PX * treeRows)

	// fmt.println("twp: ", treeWidthPix, "thp: ", treeHeightPix)

	// For now assume it fits, we will handle scroll layout later
	if render.treeW <= render.viewW && render.treeH <= render.viewH {
		render.treeX = render.viewX + (render.viewW - render.treeW) / 2
		render.treeY = render.viewY + (render.viewH - render.treeH) / 2

		render.selectedNode = game.currentPosition

		draw_tree_recursively(render, game.headNode)
	}

	// Draw border
	// Draw scroll bars
	// Draw 
}

get_tree_node_rect :: proc(render: ^GameTreeRender, node: ^GameNode) -> rl.Rectangle {
	// x := render.treeX + node.treeCol * NODE_SIZE_PX
	// y := render.treeY + node.treeRow * NODE_SIZE_PX
	// return rl.Rectangle{f32(x) + NODE_SIZE_PX / 2, f32(y) + NODE_SIZE_PX / 2, NODE_SIZE_PX, NODE_SIZE_PX}
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
			if node.treeCol == parent.treeCol + 1 {
				rl.DrawTexturePro(gameTreeAtlas, DIAG_END, parentRect, NODE_ORIGIN, 180, rl.WHITE)
			} else {
				rl.DrawTexturePro(gameTreeAtlas, HORIZ_DIAG, get_tree_tile_rect(render, node.treeCol - 1, node.treeRow - 1), NODE_ORIGIN, 0, rl.WHITE)
			}
		}
	}

	draw_tree_recursively(render, node.children)
	draw_tree_recursively(render, node.siblingNext)
}