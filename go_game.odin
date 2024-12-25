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
	None, Move, Pass, Resign
}

Coord :: distinct i16

Position :: [2]Coord

GameNode :: struct {
	pos : Position,
	tile : GoTile,
	moveType : MoveType,
	comment : string,

	addedBlack: [dynamic]Position,
	addedWhite: [dynamic]Position,
	cleared: [dynamic]Position,

	siblingNext: ^GameNode,
	parent: ^GameNode,
	children: ^GameNode,
}

GoGame :: struct {
	headNode : ^GameNode,
	arena : vm.Arena,
	alloc : mem.Allocator,

	boardSize : Coord,
	board : [dynamic]GoTile,
	currentPosition : ^GameNode,
}

init_game :: proc (game : ^GoGame, boardSize : Coord = 19) {

	err := vm.arena_init_growing(&game.arena)
	if (err != .None) {
		panic("Error initing go allocator")
	}
	game.alloc = vm.arena_allocator(&game.arena)
	game.boardSize = boardSize
	game.board = make([dynamic]GoTile, boardSize * boardSize, allocator = game.alloc)
}

get_tile :: proc(game : ^GoGame, x, y : Coord) -> GoTile {
	if y * game.boardSize + x >= game.boardSize * game.boardSize do return .Empty
	return game.board[y * game.boardSize + x]
}

set_tile :: proc(game : ^GoGame, x, y : Coord, tile : GoTile) {
	if y * game.boardSize + x >= game.boardSize * game.boardSize do return
	game.board[y * game.boardSize + x] = tile
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

	switch node.moveType {
		case .Move:
			set_tile(game, node.pos.x, node.pos.y, node.tile)
		case .Pass:
		case .Resign:
		case .None:
	}
	game.currentPosition = node
}