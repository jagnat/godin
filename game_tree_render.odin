package godin

import "core:fmt"
import "core:math"
import rl "vendor:raylib"

GameTreeRender :: struct {
	// top left x, y and w / h
	view: rl.Rectangle,
	centeredTree: rl.Rectangle,

	// panning state
	panOffset: rl.Vector2,

	panStarting: bool,
	isPanning: bool,
	panStartMousePos: rl.Vector2,

	// tween state
	panTarget: rl.Vector2,
	activeTweenSpeed: f32,
	panStart: rl.Vector2,

	selectedNode : ^GameNode
}

NODE_SIZE_PX :: 24

SPRITE_SIZE_PX :: 12

TWEEN_DRAG_SECONDS :: 0.06
TWEEN_SELECT_SECONDS :: 0.18
TWEEN_MOVE_SECONDS :: 0.14

DRAG_PX_THRESHOLD :: 4

PAN_CLAMP_PADDING : f32 : NODE_SIZE_PX

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
	
}

draw_game_tree :: proc(render: ^GameTreeRender, game: ^GoGame) {
	rl.BeginScissorMode(i32(render.view.x), i32(render.view.y), i32(render.view.width), i32(render.view.height))
	defer rl.EndScissorMode()

	rl.DrawRectangleV(rl.Vector2{render.view.x, render.view.y}, rl.Vector2{render.view.width, render.view.height}, rl.Color{255, 255, 255, 80})

	treeRows := game.treeH
	treeCols := game.treeW

	render.centeredTree.width = f32(NODE_SIZE_PX * treeCols)
	render.centeredTree.height = f32(NODE_SIZE_PX * treeRows)
	render.centeredTree.x = render.view.x + (render.view.width - render.centeredTree.width) / 2
	render.centeredTree.y = render.view.y + (render.view.height - render.centeredTree.height) / 2

	update_tree_panning(render, game)

	dt := rl.GetFrameTime()
	update_tween(render, f32(dt))

	render.selectedNode = game.currentPosition

	draw_tree_recursively(render, game.headNode)
}

get_tree_node_rect :: proc(render: ^GameTreeRender, node: ^GameNode) -> rl.Rectangle {
	return get_tree_tile_rect(render, node.treeCol, node.treeRow)
}

get_tree_tile_rect :: proc(render: ^GameTreeRender, col, row: i32) -> rl.Rectangle {
	x := render.centeredTree.x + render.panOffset.x + f32(col) * NODE_SIZE_PX
	y := render.centeredTree.y + render.panOffset.y + f32(row) * NODE_SIZE_PX
	return rl.Rectangle{x + NODE_SIZE_PX / 2, y + NODE_SIZE_PX / 2, NODE_SIZE_PX, NODE_SIZE_PX}
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

clamp_tree_pan :: proc(render: ^GameTreeRender) {
	// require at least PAN_CLAMP_PADDING pixels on panel
	pad := PAN_CLAMP_PADDING
	minX := (render.view.x + pad) - (render.centeredTree.x + render.centeredTree.width)
	maxX := (render.view.x + render.view.width) - pad - render.centeredTree.x
	minY := (render.view.y + pad) - (render.centeredTree.y + render.centeredTree.height)
	maxY := (render.view.y + render.view.height) - pad - render.centeredTree.y

	if render.panOffset.x < minX do render.panOffset.x = minX
	if render.panOffset.x > maxX do render.panOffset.x = maxX
	if render.panOffset.y < minY do render.panOffset.y = minY
	if render.panOffset.y > maxY do render.panOffset.y = maxY
}

update_tree_panning :: proc(render: ^GameTreeRender, game: ^GoGame) {
	pos := rl.GetMousePosition()

	mouseInsidePanel := is_mouse_inside_tree_panel(render)

	if rl.IsMouseButtonPressed(.LEFT) && mouseInsidePanel {
		render.panStartMousePos = pos
		render.panStarting = true
		render.panStart = render.panOffset
	} else if rl.IsMouseButtonPressed(.LEFT) {
		render.panStarting = false
	}

	if rl.IsMouseButtonDown(.LEFT) && !render.isPanning && render.panStarting {
		dx := pos.x - render.panStartMousePos.x
		dy := pos.y - render.panStartMousePos.y
		if math.abs(dx) >= DRAG_PX_THRESHOLD || math.abs(dy) >= DRAG_PX_THRESHOLD {
			render.isPanning = true
		}
	}

	if rl.IsMouseButtonDown(.LEFT) && render.isPanning {
		totalDx := pos.x - render.panStartMousePos.x
		totalDy := pos.y - render.panStartMousePos.y
		render.panTarget.x = render.panStart.x + totalDx
		render.panTarget.y = render.panStart.y + totalDy
		render.activeTweenSpeed = TWEEN_DRAG_SECONDS
	}

	if rl.IsMouseButtonReleased(.LEFT) && render.isPanning {
		render.panTarget.x = render.panOffset.x
		render.panTarget.y = render.panOffset.y
		render.activeTweenSpeed = 0
		render.isPanning = false
	} else if rl.IsMouseButtonReleased(.LEFT) && mouseInsidePanel {
		picked := pick_tree_node(render, game, pos)
		if picked != nil {
			replay_to_node(game, picked)
			center_tree_on_node(render, picked)
		}
	}
}

// convert center-anchored draw rect to top-left anchored pick rect
get_node_pick_rect :: proc(render: ^GameTreeRender, node: ^GameNode) -> rl.Rectangle {
	rect := get_tree_node_rect(render, node)
	return rl.Rectangle{rect.x - rect.width / 2, rect.y - rect.height / 2, rect.width, rect.height}
}

// DFS to pick node under mouse
pick_tree_node :: proc(render: ^GameTreeRender, game: ^GoGame, mouse: rl.Vector2) -> ^GameNode {
	return pick_tree_node_dfs(render, game.headNode, mouse)
}

pick_tree_node_dfs :: proc(render: ^GameTreeRender, node: ^GameNode, mouse: rl.Vector2) -> ^GameNode {
	if node == nil do return nil

	rect := get_node_pick_rect(render, node)
	if rl.CheckCollisionPointRec(mouse, rect) do return node

	res := pick_tree_node_dfs(render, node.children, mouse)
	if res != nil do return res
	return pick_tree_node_dfs(render, node.siblingNext, mouse)
}

center_tree_on_node :: proc(render: ^GameTreeRender, node: ^GameNode) {
	centerX := render.view.x + render.view.width / 2
	centerY := render.view.y + render.view.height / 2

	nodeLocalX := node.treeCol * NODE_SIZE_PX + NODE_SIZE_PX / 2
	nodeLocalY := node.treeRow * NODE_SIZE_PX + NODE_SIZE_PX / 2

	newOffX := centerX - render.centeredTree.x - f32(nodeLocalX)
	newOffY := centerY - render.centeredTree.y - f32(nodeLocalY)

	render.panTarget.x = newOffX
	render.panTarget.y = newOffY
	render.activeTweenSpeed = TWEEN_SELECT_SECONDS
}

update_tween :: proc(render: ^GameTreeRender, dt: f32) {
	if dt <= 0 do return

	if render.activeTweenSpeed > 0 {
		// X axis
		dx := f32(render.panTarget.x - render.panOffset.x)
		speedX := dx / render.activeTweenSpeed
		stepX := speedX * dt
		if math.abs(stepX) > math.abs(dx) {
			stepX = dx
		}
		// render.panOffset.x += math.round_f32(stepX)
		render.panOffset.x += stepX

		// Y axis
		dy := f32(render.panTarget.y - render.panOffset.y)
		speedY := dy / render.activeTweenSpeed
		stepY := speedY * dt
		if math.abs(stepY) > math.abs(dy) {
			stepY = dy
		}
		render.panOffset.y += stepY
	}

	clamp_tree_pan(render)
}

is_mouse_inside_tree_panel :: proc(render: ^GameTreeRender) -> bool {
	pos := rl.GetMousePosition()
	return pos.x >= render.view.x &&
		pos.x < (render.view.x + render.view.width) &&
		pos.y >= render.view.y &&
		pos.y < (render.view.y + render.view.height)
}
