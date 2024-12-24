package godin

import vm "core:mem/virtual"
import "core:mem"

GoTile :: enum {
	Empty,
	White,
	Black
}

MoveType :: enum {
	None, Move, Pass, Resign
}

Position :: [2]i32

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
	allocator : mem.Allocator,
}

init_game :: proc () -> GoGame {
	game : GoGame

	err := vm.arena_init_growing(&game.arena)
	game.allocator = vm.arena_allocator(&game.arena)

	return game
}