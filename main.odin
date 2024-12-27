package godin

import "base:runtime"
import "core:fmt"
import "core:time"
import "core:strings"
import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "core:mem"

// pixel margin of board from edge of screen
BOARD_MARGIN :: 20

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

WIDTH : i32 = 1024
HEIGHT : i32 = 768

tx : Homothetic

boardX : f32
boardY : f32

stoneSounds : [4]rl.Sound

game : ^GoGame

main :: proc() {

	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT, .MSAA_4X_HINT})
	rl.SetTraceLogLevel(.ERROR)

	rl.InitWindow(WIDTH, HEIGHT, "Go")
	defer rl.CloseWindow()

	rl.InitAudioDevice()

	init()
	defer cleanup()

	for !rl.WindowShouldClose() {

		if rl.IsWindowResized() {
			WIDTH = rl.GetScreenWidth()
			HEIGHT = rl.GetScreenHeight()
			init_transform()
		}

		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.GetColor(0x1b191cFF))
		
		draw_board()

		handle_input()

		draw_stones()

		rl.DrawFPS(10, 10)
	}
}

init :: proc() {

	stoneSounds[0] = rl.LoadSound("resource/click1.wav");
	stoneSounds[1] = rl.LoadSound("resource/click2.wav");
	stoneSounds[2] = rl.LoadSound("resource/click3.wav");
	stoneSounds[3] = rl.LoadSound("resource/click4.wav");

	for i in 0..<4 {
		rl.SetSoundVolume(stoneSounds[i], 0.6)
	}

	// node := parse_from_file("test.sgf")
	game = parse_from_file("5265-yly-TheCaptain-Vegetarian.sgf")
	// game = new(GoGame)
	// init_game(game)
	// print_sgf(node)

	init_transform()
}

init_transform :: proc() {
	board_pix : f32 = f32(WIDTH if WIDTH < HEIGHT else HEIGHT) - 2 * BOARD_MARGIN
	boardPixX: f32
	boardPixY: f32

	if WIDTH < HEIGHT {

	} else {

	}
	tx.translateX = (f32(WIDTH / 2) - (board_pix / 2))
	tx.translateY = (f32(HEIGHT / 2) - (board_pix / 2))
	tx.scaleX = f32(board_pix) / f32(game.boardSize)
	tx.scaleY = f32(board_pix) / f32(game.boardSize)
	tx.translateX += tx.scaleX / 2;
	tx.translateY += tx.scaleY / 2;
}

cleanup :: proc() {
	free(game)
}

handle_input::proc() {
	pos := rl.GetMousePosition()

	stone_pos := px_to_stone(pos)
	cx, cy := Coord(math.round_f32(stone_pos.x)), Coord(math.round_f32(stone_pos.y))

	if cx >= 0 && cx < game.boardSize && cy >= 0 && cy < game.boardSize {

		if can_move(game, Position{cx, cy}) {
			if rl.IsMouseButtonPressed(.LEFT) {
				set_tile(game, cx, cy, game.nextTile)
				play_random_click()
				game.nextTile = .Black if game.nextTile == .White else .White
			}
			else if get_tile(game, cx, cy) == .Liberty {
				draw_stone(cx, cy, game.nextTile, false)
			}
		}
	}

	mouseMove := rl.GetMouseWheelMove()
	if abs(mouseMove) > 0.001 {
		if mouseMove < 1 {
			advance(game)
		}
	}

	if rl.IsKeyPressed(.C) {
		clear_board(game)
	}
}

play_random_click::proc() {
	rand := rand.int31() % 4
	rl.PlaySound(stoneSounds[rand])
}

draw_stone::proc(x, y: Coord, tile : GoTile, opaque: bool) {
	pos := stone_to_px({f32(x), f32(y)})
	if tile == .Liberty || tile == .None { return }
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

draw_stones :: proc() {
	for j in 0..<game.boardSize {
		for i in 0..<game.boardSize {
			stone := get_tile(game, i, j)
			if stone == .Liberty || stone == .None { continue }
			draw_stone(Coord(i), Coord(j), stone, true)
		}
	}
}

draw_board :: proc() {
	boardOrigin := stone_to_px({-0.5, -0.5})
	bs := f32(game.boardSize)

	rl.DrawRectangleV(boardOrigin, stone_to_px({bs - 0.5, bs - 0.5}) - boardOrigin, rl.GetColor(0xad8d40FF))

	orig := stone_to_px({})
	end := stone_to_px({bs - 1, bs - 1})

	// Draw lines
	for i in 0..<bs {

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
	if (game.boardSize == 19) {
		for i in hoshi_19 {
			for j in hoshi_19 {
				p := stone_to_px({i, j})
				rl.DrawCircleV(p, 5.5, rl.BLACK)
			}
		}
	}
}