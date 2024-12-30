package godin

import vm "core:mem/virtual"
import "core:mem"
import "core:fmt"

GoTile :: enum u8 {
	Liberty,
	White,
	Black,
	None, // Returned by out of bounds check (to not count as liberty)
}

MoveType :: enum u8 {
	None, Move, Pass, Resign,
}

Coord :: distinct i16

Position :: [2]Coord

SetupStone :: struct {
	pos : Position,
	tile : GoTile
}

GameNode :: struct {
	pos : Position,
	tile : GoTile,
	moveType : MoveType,
	comment : string,

	// Setup stones are allocated dynamically from arena
	setupStones : [dynamic]SetupStone,
	// Capture stones are allocated through a stack that grows as the game progresses
	// Make sure to clean up by backtracing through GameNode path if switching to another branch
	captures : []Position,

	// N-ary tree
	siblingNext: ^GameNode,
	parent: ^GameNode,
	children: ^GameNode,
}

CapturePoolSize :: 512

GoGame :: struct {

	// Variables set at init
	headNode : ^GameNode,
	arena : vm.Arena,
	alloc : mem.Allocator,
	boardSize : Coord,
	capturePool : [dynamic]Position,

	// Variables set relative to current position in the game
	capturePoolIdx : int,
	currentPosition : ^GameNode,
	board : [dynamic]GoTile,
	whiteCaptures: int,
	blackCaptures: int,
	komi: f32,
	nextTile: GoTile
}

@private Neighbors : []Position : {{-1, 0}, {1, 0}, {0, -1}, {0, 1}}

init_game :: proc (game : ^GoGame, boardSize : Coord = 19, generateHeadNode : bool = true) {

	err := vm.arena_init_growing(&game.arena)
	if (err != .None) {
		panic("Error initing go allocator")
	}
	game.alloc = vm.arena_allocator(&game.arena)
	game.boardSize = boardSize
	game.board = make([dynamic]GoTile, boardSize * boardSize, allocator = game.alloc)
	if generateHeadNode {
		game.headNode = new(GameNode, allocator=game.alloc)
		game.currentPosition = game.headNode
	}
	game.capturePool = make([dynamic]Position, CapturePoolSize, allocator=game.alloc)
	game.nextTile = .Black
}

other_tile_type :: proc(tile : GoTile) -> GoTile {
	return .White if tile == .Black else .Black if tile == .White else tile
}

get_tile_pos :: proc(game : ^GoGame, pos : Position) -> GoTile {
	return get_tile_coords(game, pos.x, pos.y)
}

get_tile_coords :: proc (game: ^GoGame, cx, cy : Coord) -> GoTile {
	if cx < 0 || cx >= game.boardSize || cy < 0 || cy >= game.boardSize do return .None
	return game.board[cy * game.boardSize + cx]
}

get_tile :: proc {
	get_tile_pos,
	get_tile_coords,
}

set_tile_pos :: proc(game : ^GoGame, pos : Position, tile : GoTile) {
	set_tile_coords(game, pos.x, pos.y, tile)
}

set_tile_coords :: proc(game : ^GoGame, cx, cy : Coord, tile : GoTile) {
	if cx < 0 || cx >= game.boardSize || cy < 0 || cy >= game.boardSize do return
	game.board[cy * game.boardSize + cx] = tile
}

set_tile :: proc {
	set_tile_pos,
	set_tile_coords,
}

get_child_at :: proc(gameNode : ^GameNode, idx : int) -> ^GameNode {
	currentChild := gameNode.children
	if currentChild == nil do return nil

	for i := idx; i > 0; i -= 1 {
		currentChild = currentChild.siblingNext
		if currentChild == nil do return nil
	}

	return currentChild
}

clear_board :: proc(game : ^GoGame) {
	for i in 0..<(game.boardSize * game.boardSize) {
		game.board[i] = .Liberty
	}
}

gamenode_new :: proc(game: ^GoGame) -> ^GameNode {
	ptr := new(GameNode, allocator = game.alloc)
	return ptr
}

move_forward :: proc(game : ^GoGame, childIndex : int = 0) {
	if game.currentPosition == nil do game.currentPosition = game.headNode

	if game.currentPosition == nil do return

	node := get_child_at(game.currentPosition, childIndex)

	if node == nil do return

	switch node.moveType {
		case .None:
		case .Move:
			captureStackPos := game.capturePoolIdx
			game.nextTile = other_tile_type(game.nextTile)

			// Check for captures
			for add in Neighbors {
				neighbor := add + node.pos
				tile := get_tile(game, neighbor)

				if tile == other_tile_type(node.tile) {
					stones, liberties := get_stone_group(game, neighbor)

					if len(liberties) == 1 { // Capture
						captureSize := len(stones)
						node.captures = game.capturePool[captureStackPos:captureStackPos + captureSize]
						captureStackPos += captureSize
						copy_slice(node.captures, stones[:])

						if game.nextTile == .Black {
							game.blackCaptures += captureSize
						} else {
							game.whiteCaptures += captureSize
						}

						remove_stones(game, stones)
					}
				}
			}
			set_tile(game, node.pos, node.tile)
		case .Pass:
		case .Resign:
		case: break
	}

	game.currentPosition = node
}

move_backward :: proc(game: ^GoGame) {
	currentNode := game.currentPosition
	prevNode := currentNode.parent
	if prevNode == nil do return

	if currentNode.moveType == .Move {
		set_tile(game, currentNode.pos, .Liberty)
		add_stones(game, currentNode.captures, other_tile_type(currentNode.tile))
	}

	game.nextTile = currentNode.tile

	game.currentPosition = prevNode
}

add_stones :: proc(game: ^GoGame, positions: []Position, tile: GoTile) {
	for pos in positions {
		set_tile(game, pos, tile)
	}
}

remove_stones :: proc(game: ^GoGame, positions: []Position) {
	for pos in positions {
		set_tile(game, pos, .Liberty)
	}
}

can_move :: proc(game : ^GoGame, pos: Position) -> bool {
	if get_tile(game, pos) != .Liberty do return false

	// Early exit, check if you have a liberty
	for add in Neighbors {
		neighbor := add + pos
		tile := get_tile(game, neighbor)
		if tile == .Liberty do return true
	}

	// Otherwise check groups neighboring
	for add in Neighbors {
		neighbor := add + pos
		tile := get_tile(game, neighbor)
		if tile != .Liberty && tile != .None {
			_, liberties := get_stone_group(game, neighbor)
			if tile != game.nextTile && len(liberties) <= 1 { // You will capture a group
				return true
			}
			else if tile == game.nextTile && len(liberties) > 1 { // Connected to a group with a liberty besides this
				return true
			}
		}
	}

	return false
}

do_move :: proc(game : ^GoGame, pos : Position) -> (captured: bool) {
	captured = false

	if !can_move(game, pos) {
		return
	}

	if game.currentPosition == nil do game.currentPosition = game.headNode

	node := gamenode_new(game)
	node.pos = pos
	node.tile = game.nextTile
	node.moveType = .Move

	// Add node to thingy
	oldNode := game.currentPosition
	idx := add_child_node(oldNode, node)
	fmt.println("idx:", idx)

	move_forward(game, idx)

	return len(node.captures) > 0
}

get_stone_group :: proc(game : ^GoGame, pos : Position) -> (stones, liberties : []Position) {
	tile := get_tile(game, pos)
	if tile == .Liberty || tile == .None {
		return nil, nil
	}

	markedStones := make([dynamic]Position, 0, 30, allocator=context.temp_allocator)
	markedLiberties := make([dynamic]Position, 0, 30, allocator=context.temp_allocator)
	scanStack := make([dynamic]Position, 0, 30, allocator=context.temp_allocator)
	append(&scanStack, pos)

	for len(scanStack) != 0 {
		currentPos := pop(&scanStack)

		append(&markedStones, currentPos)

		for add in Neighbors {
			neighborPos := add + currentPos
			neighborTile := get_tile(game, neighborPos)
			if neighborTile == .Liberty && !slice_contains(markedLiberties[:], neighborPos) {
				append(&markedLiberties, neighborPos)
			} else if neighborTile == tile && !slice_contains(markedStones[:], neighborPos) {
				append(&scanStack, neighborPos)
			}
		}
	}

	return markedStones[:], markedLiberties[:]
}

add_child_node :: proc(parent, child: ^GameNode) -> (idx: int) {
	idx = 0
	if parent.children == nil {
		parent.children = child
	} else {
		lastChild := parent.children
		idx += 1
		for lastChild.siblingNext != nil {
			lastChild = lastChild.siblingNext
			idx += 1
		}
		lastChild.siblingNext = child
	}
	child.parent = parent
	return idx
}
