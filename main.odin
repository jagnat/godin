package main

import "core:fmt"
import "core:time"
import "core:strings"
import rl "vendor:raylib"
import "core:math"

BOARD_SIZE :: 19

// pixel margin of board from edge of screen
BOARD_MARGIN :: 20

GoTile :: enum u8 {
	Empty,
	White,
	Black
}

// board space - 0, 0 in top left corner,
// 18,18 in bottom right corner
Homothetic :: struct {
	// Asymmetric go board
	scaleX: f32,
	scaleY: f32,
	translateX : f32,
	translateY : f32,
}

// Variables

// WIDTH : i32 : 1440
// HEIGHT : i32 : 900
WIDTH : i32 : 1024
HEIGHT : i32 : 768

board : [dynamic]GoTile

tx : Homothetic

nextTile : GoTile = .Black

boardX : f32
boardY : f32

main :: proc() {

	rl.SetConfigFlags({.VSYNC_HINT, .MSAA_4X_HINT})

	rl.InitWindow(WIDTH, HEIGHT, "game")
	defer rl.CloseWindow()

	// SetTargetFPS(144)

	init()

	defer delete(board)

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.GetColor(0x1b191cFF))
		
		draw_board()

		handle_input()

		draw_stones()

		b := strings.builder_make()
		fps := rl.GetFPS()

		strings.write_int(&b, int(fps))
		rl.DrawText(strings.to_cstring(&b), 10, 10, 18, rl.BLACK)
	}
}

init :: proc() {
	board = make([dynamic]GoTile, BOARD_SIZE * BOARD_SIZE, BOARD_SIZE * BOARD_SIZE)

	board_pix : f32 = f32(WIDTH if WIDTH < HEIGHT else HEIGHT) - 2 * BOARD_MARGIN
	boardPixX: f32
	boardPixY: f32
	if WIDTH < HEIGHT {

	} else {

	}
	tx.translateX = (f32(WIDTH / 2) - (board_pix / 2))
	tx.translateY = (f32(HEIGHT / 2) - (board_pix / 2))
	tx.scaleX = f32(board_pix) / (BOARD_SIZE)
	tx.scaleY = f32(board_pix) / (BOARD_SIZE)
	tx.translateX += tx.scaleX / 2;
	tx.translateY += tx.scaleY / 2;
}

handle_input::proc() {
	pos := rl.GetMousePosition()

	stone_pos := px_to_stone(pos)
	cx, cy := i32(math.round_f32(stone_pos.x)), i32(math.round_f32(stone_pos.y))

	if cx >= 0 && cx < BOARD_SIZE && cy >= 0 && cy < BOARD_SIZE {
		if (get_tile(cx, cy) != .Empty) { return }
		if rl.IsMouseButtonPressed(.LEFT) {
			set_tile(cx, cy, nextTile)
			nextTile = .Black if nextTile == .White else .White
		}
		else if get_tile(cx, cy) == .Empty {
			draw_stone(cx, cy, nextTile, false)
		}
	}
}

draw_stone::proc(x, y: i32, tile : GoTile, opaque: bool) {
	pos := stone_to_px({f32(x), f32(y)})
	if tile == .Empty { return }
	hex : u32 = 0xFFFFFF00 if tile == .White else 0x00000000
	hex += 0x000000FF if opaque else 0x00000088
	rl.DrawCircleV(pos, tx.scaleX / 2, rl.GetColor(hex))
}

stone_to_px::proc(a: rl.Vector2) -> rl.Vector2 {
	ret : rl.Vector2
	ret.x = tx.translateX + a.x * tx.scaleX
	ret.y = tx.translateY + a.y * tx.scaleY
	return ret
}

px_to_stone::proc(a: rl.Vector2) -> rl.Vector2 {
	ret : rl.Vector2
	ret.x = (a.x - tx.translateX) / tx.scaleX
	ret.y = (a.y - tx.translateY) / tx.scaleY
	return ret
}

get_tile::proc(x, y: i32) -> GoTile {
	return board[y * BOARD_SIZE + x]
}

set_tile::proc(x, y: i32, tile: GoTile) {
	board[y * BOARD_SIZE + x] = tile
}

draw_stones :: proc() {
	for j in 0..<BOARD_SIZE {
		for i in 0..<BOARD_SIZE {
			stone := board[j * BOARD_SIZE + i]
			if stone == .Empty { continue }
			draw_stone(i32(i), i32(j), stone, true)
		}
	}
}

draw_board :: proc() {
	boardOrigin := stone_to_px({-0.5, -0.5})

	rl.DrawRectangleV(boardOrigin, stone_to_px({BOARD_SIZE - 0.5, BOARD_SIZE - 0.5}) - boardOrigin, rl.GetColor(0xad8d40FF))

	orig := stone_to_px({})
	end := stone_to_px({BOARD_SIZE - 1, BOARD_SIZE - 1})

	// Draw lines
	for i in 0..<BOARD_SIZE {

		STROKE :: 2

		// Vert
		p := stone_to_px({f32(i), f32(i)})
		rl.DrawLineEx({p.x, end.y}, {p.x, orig.y}, STROKE, rl.BLACK)
		// Horiz
		rl.DrawLineEx({end.x, p.y}, {orig.x, p.y}, STROKE, rl.BLACK)
	}

	// Draw hoshi
	// Hardcode for now
	hoshi_19 := []f32{3, 9, 15}
	if (BOARD_SIZE == 19) {
		for i in hoshi_19 {
			for j in hoshi_19 {
				p := stone_to_px({i, j})
				rl.DrawCircleV(p, 5.5, rl.BLACK)
			}
		}
	}
}