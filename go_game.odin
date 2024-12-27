package godin

import vm "core:mem/virtual"
import "core:mem"
import "core:fmt"

GoTile :: enum u8 {
	Empty,
	White,
	Black
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
	turnColor: GoTile
}

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
	game.turnColor = .Black
}

get_tile_pos :: proc(game : ^GoGame, pos : Position) -> GoTile {
	return get_tile_coords(game, pos.x, pos.y)
}

get_tile_coords :: proc (game: ^GoGame, cx, cy : Coord) -> GoTile {
	if cy * game.boardSize + cx >= game.boardSize * game.boardSize do return .Empty
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
	if cy * game.boardSize + cx >= game.boardSize * game.boardSize do return
	game.board[cy * game.boardSize + cx] = tile
}

set_tile :: proc {
	set_tile_pos,
	set_tile_coords,
}

clear_board :: proc(game : ^GoGame) {
	for i in 0..<(game.boardSize * game.boardSize) {
		game.board[i] = .Empty
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

can_move :: proc(game : ^GoGame, pos: Position) {
	
}

do_move :: proc(game : ^GoGame, pos : Position) {
	
}

undo_move :: proc(game: ^GoGame) {

}