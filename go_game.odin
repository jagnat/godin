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

	// 
	setupStones : [dynamic]SetupStone,
	captures : []Position,

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

	currentPosition : ^GameNode,
	board : [dynamic]GoTile,
	whiteCaptures: i32,
	blackCaptures: i32,
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
	}
	game.capturePool = make([dynamic]Position, CapturePoolSize, allocator=game.alloc)
	game.nextTile = .Black
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

clear_board :: proc(game : ^GoGame) {
	for i in 0..<(game.boardSize * game.boardSize) {
		game.board[i] = .Liberty
	}
}

advance :: proc(game : ^GoGame) {
	if game.currentPosition == nil do game.currentPosition = game.headNode

	if game.currentPosition == nil do return

	node := game.currentPosition.children

	if node == nil do return

	#partial switch node.moveType {
		case .Move:
			set_tile(game, node.pos, node.tile)
		case: break
	}
	game.currentPosition = node
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

do_move :: proc(game : ^GoGame, pos : Position) {
	
}

undo_move :: proc(game: ^GoGame) {

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