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

Coord :: distinct i8

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
}

init_game :: proc (game : ^GoGame) {

	err := vm.arena_init_growing(&game.arena)
	if (err != .None) {
		fmt.println("Error allocating")
	}
	game.alloc = vm.arena_allocator(&game.arena)
}

