package godin

import "base:runtime"
import "core:fmt"
import "core:time"
import str "core:strings"
import "core:strconv"
import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import "core:mem"

// pixel margin of board from edge of screen
BOARD_MARGIN :: 12

MIN_GAMETREE_WIDTH :: 120

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

CLEAR_COLOR :: 0xF3E0D9FF
TEXT_COLOR :: 0x4A4A4AFF

WIDTH : i32 = 1024
HEIGHT : i32 = 768

tx : Homothetic

boardX : f32
boardY : f32

stoneSounds : [4]rl.Sound
captureSounds : [2]rl.Sound

hoshi_19 : []rl.Vector2 : {{3, 3}, {3, 9}, {3, 15}, {9, 3}, {9, 9}, {9, 15}, {15, 3}, {15, 9}, {15, 15}}
hoshi_13 : []rl.Vector2 : {{3, 3}, {3, 9}, {9, 3}, {9, 9}, {6, 6}}
hoshi_9  : []rl.Vector2 : {{2, 2}, {2, 6}, {6, 2}, {6, 6}, {4, 4}}

stoneAtlas: rl.Texture2D
blackStoneTexCoords: rl.Rectangle
whiteStoneTexCoords: rl.Rectangle
blackMarkerTexCoords: rl.Rectangle
whiteMarkerTexCoords: rl.Rectangle

boardAtlas: rl.Texture2D
gameTreeAtlas: rl.Texture2D

font: rl.Font

@(private="file")
game : ^GoGame

pixelRender : PixelGoRender

renderGameTree: bool
gameTreeRender: GameTreeRender

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

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.SetTraceLogLevel(.ERROR)

	rl.InitWindow(WIDTH, HEIGHT, "Bamboo Joint")
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

		rl.ClearBackground(rl.GetColor(CLEAR_COLOR))

		handle_input()

		layout_tree(game)
		
		pixel_render_board(game, &pixelRender)
		draw_pixel_render()

		if renderGameTree do draw_game_tree(&gameTreeRender, game)

		fps := rl.GetFPS()
		fpsBuf: [8]u8
		fpsStr := strconv.append_int(fpsBuf[:], i64(fps), 10)
		fpsSize := rl.MeasureTextEx(font, cstring(&fpsBuf[0]), 30, 2)
		rl.DrawTextEx(font, cstring(&fpsBuf[0]), rl.Vector2{f32(WIDTH) - (fpsSize.x + 10), 8}, 30, 2, rl.GetColor(TEXT_COLOR))

		// rl.DrawFPS(10, 10)

		scorePrint: str.Builder
		str.builder_init(&scorePrint, allocator=context.temp_allocator)
		str.write_string(&scorePrint, "Black: ")
		str.write_int(&scorePrint, game.blackCaptures)
		str.write_string(&scorePrint, ", White: ")
		str.write_int(&scorePrint, game.whiteCaptures)

		// rl.DrawText(str.to_cstring(&scorePrint), 10, 30, 20, rl.WHITE)
		scoreStr, err := str.to_cstring(&scorePrint)
		scoreSize := rl.MeasureTextEx(font, scoreStr, 30, 2)
		rl.DrawTextEx(font, scoreStr, rl.Vector2{f32(WIDTH) - (scoreSize.x + 10), 10 + fpsSize.y}, 30, 2, rl.GetColor(TEXT_COLOR))

		free_all(context.temp_allocator)
	}
}

init :: proc() {

	stoneSounds[0] = rl_sound_from_memory(#load("resource/click1.wav"))
	stoneSounds[1] = rl_sound_from_memory(#load("resource/click2.wav"))
	stoneSounds[2] = rl_sound_from_memory(#load("resource/click3.wav"))
	stoneSounds[3] = rl_sound_from_memory(#load("resource/click4.wav"))

	captureSounds[0] = rl_sound_from_memory(#load("resource/capture1.wav"))
	captureSounds[1] = rl_sound_from_memory(#load("resource/capture2.wav"))

	stoneAtlas = rl_tex_from_memory(#load("resource/stone-atlas.png"))
	blackStoneTexCoords = rl.Rectangle{0, 0, 12, 12}
	whiteStoneTexCoords = rl.Rectangle{12, 0, 12, 12}
	blackMarkerTexCoords = rl.Rectangle{0, 12, 12, 12}
	whiteMarkerTexCoords = rl.Rectangle{12, 12, 12, 12}

	gameTreeAtlas = rl_tex_from_memory(#load("resource/gametree-atlas.png"))

	font = rl_font_from_memory(#load("resource/munro.ttf"))

	// Render with -height to flip again
	boardAtlas = rl_tex_from_memory(#load("resource/board-atlas.png"))

	for s in stoneSounds {
		rl.SetSoundVolume(s, 0.6)
	}

	for s in captureSounds {
		rl.SetSoundVolume(s, 0.6)
	}
	// node := parse_from_file("sgfs/test.sgf")
	// game = parse_from_file("sgfs/5265-yly-TheCaptain-Vegetarian.sgf")
	game = parse_from_file("sgfs/testcase_layout4.sgf")
	// game = parse_from_file("sgfs/test_9x9.sgf")
	// game = new(GoGame)
	// init_game(game)
	// print_sgf(node)

	pixel_init(game, &pixelRender)

	when false {
		img := rl.LoadImageFromTexture(pixelRender.target.texture)
		rl.ImageFlipVertical(&img)
		res := rl.ExportImage(img, "test.png")
		assert(res == true)
	}

	init_transform()
}

init_transform :: proc() {
	board_pix_max : f32 = f32(WIDTH if WIDTH < HEIGHT else HEIGHT) - 2 * BOARD_MARGIN
	boardPixX: f32
	boardPixY: f32

	multiples_of_pixelraster : [5]f32

	for i in 0..<5 {
		multiples_of_pixelraster[i] = f32((i+1) * int(pixelRender.target.texture.width))
	}

	board_pix := board_pix_max

	#reverse for dim in multiples_of_pixelraster {
		if dim < board_pix_max {
			board_pix = dim
			break
		}
	}

	pix_for_tree := WIDTH - (BOARD_MARGIN * 3 + i32(board_pix))

	if pix_for_tree >= MIN_GAMETREE_WIDTH {
		renderGameTree = true
		tx.translateX = BOARD_MARGIN
		gameTreeRender.viewW = pix_for_tree
		gameTreeRender.viewH = HEIGHT - 2 * BOARD_MARGIN
		gameTreeRender.viewX = BOARD_MARGIN * 2 + i32(board_pix)
		gameTreeRender.viewY = BOARD_MARGIN
	} else {
		renderGameTree = false
		tx.translateX = (f32(WIDTH / 2) - (board_pix / 2))
	}

	// tx.translateX = (f32(WIDTH / 2) - (board_pix / 2))
	// tx.translateX = BOARD_MARGIN
	tx.translateY = (f32(HEIGHT / 2) - (board_pix / 2))
	tx.scaleX = f32(board_pix) / f32(game.boardSize)
	tx.scaleY = f32(board_pix) / f32(game.boardSize)
	tx.translateX += tx.scaleX / 2;
	tx.translateY += tx.scaleY / 2;
}

cleanup :: proc() {
	free(game)
	pixel_cleanup(&pixelRender)
}

handle_input :: proc() {
	pos := rl.GetMousePosition()

	stone_pos := px_to_stone(pos)
	cx, cy := Coord(math.round_f32(stone_pos.x)), Coord(math.round_f32(stone_pos.y))

	game.hoverPos = Position{-1, -1}

	if cx >= 0 && cx < game.boardSize && cy >= 0 && cy < game.boardSize {

		if can_move(game, Position{cx, cy}) {
			if rl.IsMouseButtonPressed(.LEFT) {
				captured := do_move(game, Position{cx, cy})
				if !captured {
					play_random_click()
				} else {
					play_random_capture()
				}
			}
			else {
				game.hoverPos = Position{cx, cy}
			}
		}
	}

	mouseMove := rl.GetMouseWheelMove()
	if abs(mouseMove) > 0.001 {
		if mouseMove < 0 {
			move_forward(game)
		} else {
			move_backward(game)
		}
	}

	if rl.IsKeyPressed(.C) {
		clear_board(game)
	}

	if rl.IsKeyPressed(.P) {
		img := rl.LoadImageFromTexture(pixelRender.target.texture)
		rl.ImageFlipVertical(&img)
		res := rl.ExportImage(img, "test.png")
		assert(res == true)
	}
}

play_random_click :: proc() {
	rand := rand.int31() % len(stoneSounds)
	rl.PlaySound(stoneSounds[rand])
}

play_random_capture :: proc() {
	rand := rand.int31() % len(captureSounds)
	rl.PlaySound(captureSounds[rand])
}

stone_to_px :: proc(a: rl.Vector2) -> rl.Vector2 {
	ret : rl.Vector2
	ret.x = tx.translateX + a.x * tx.scaleX
	ret.y = tx.translateY + a.y * tx.scaleY
	return ret
}

px_to_stone :: proc(a: rl.Vector2) -> rl.Vector2 {
	ret : rl.Vector2
	ret.x = (a.x - tx.translateX) / tx.scaleX
	ret.y = (a.y - tx.translateY) / tx.scaleY
	return ret
}

draw_pixel_render :: proc() {
	boardOrigin := stone_to_px({-0.5, -0.5})
	bs := f32(game.boardSize)
	boardW := stone_to_px({bs - 0.5, bs - 0.5}) - boardOrigin
	destRect := rl.Rectangle{boardOrigin.x, boardOrigin.y, boardW.x, boardW.y}

	sourceRect := rl.Rectangle{0, 0, f32(pixelRender.target.texture.width), f32(-pixelRender.target.texture.height)}

	rl.DrawTexturePro(pixelRender.target.texture, sourceRect, destRect, {}, 0, rl.WHITE)
}
