package godin

import "core:math/rand"
import rl "vendor:raylib"

STONE_SIZE_PX :: 12
TILE_SIZE_PX :: 13

StoneJitter :: struct {
	x, y: Coord
}

PixelGoRender :: struct {
	target: rl.RenderTexture2D,
	pixOffsets: [dynamic]StoneJitter,
	boardSize: Coord,
}


pixel_init :: proc(game: ^GoGame, render: ^PixelGoRender) -> bool {
	render.boardSize = game.boardSize
	texSize := i32(TILE_SIZE_PX * game.boardSize)
	render.pixOffsets = make([dynamic]StoneJitter, game.boardSize * game.boardSize, 576)

	render.target = rl.LoadRenderTexture(texSize, texSize)
	return rl.IsRenderTextureValid(render.target)
}

pixel_render_board :: proc(game: ^GoGame, render: ^PixelGoRender) {
	bgTexCoords := rl.Rectangle{0, TILE_SIZE_PX,                TILE_SIZE_PX, TILE_SIZE_PX}
	centerLineCoords := rl.Rectangle{0, 0,                      TILE_SIZE_PX, TILE_SIZE_PX}
	cornerLineCoords := rl.Rectangle{1 * TILE_SIZE_PX, 0,       TILE_SIZE_PX, TILE_SIZE_PX}
	sideLineCoords := rl.Rectangle{2 * TILE_SIZE_PX, 0,         TILE_SIZE_PX, TILE_SIZE_PX}
	hoshiLineCoords := rl.Rectangle{3 * TILE_SIZE_PX, 0,        TILE_SIZE_PX, TILE_SIZE_PX}

	fullRect := rl.Rectangle{0, 0, f32(render.target.texture.width), f32(render.target.texture.height)}

	maxCoord := render.boardSize - 1

	using rl

	BeginTextureMode(render.target)
	defer EndTextureMode()

	for j in 0..<render.boardSize {
		for i in 0..<render.boardSize {
			rl.DrawTexturePro(boardAtlas, bgTexCoords, get_tile_rect(i, j), {}, 0, rl.WHITE)
		}
	}

	// Grid
	for j in 1 ..< render.boardSize - 1 {
		for i in 1 ..< render.boardSize - 1 {
			rl.DrawTexturePro(boardAtlas, centerLineCoords, get_tile_rect(i, j), {}, 0, rl.WHITE)
		}
	}

	// Side lines
	for i in 1 ..< render.boardSize - 1 {
		// Top
		rl.DrawTexturePro(boardAtlas, sideLineCoords, get_tile_rect(i, maxCoord), {}, 0, rl.WHITE)
		// Bot
		rect := get_tile_rect(i, 0)
		rect.y += TILE_SIZE_PX
		rect.x += TILE_SIZE_PX
		rl.DrawTexturePro(boardAtlas, sideLineCoords, rect, {}, 180, rl.WHITE)
		// Left
		rect = get_tile_rect(0, i)
		rect.x += TILE_SIZE_PX
		rl.DrawTexturePro(boardAtlas, sideLineCoords, rect, {}, 90, rl.WHITE)
		// Right
		rect = get_tile_rect(maxCoord, i)
		rect.y += TILE_SIZE_PX
		rl.DrawTexturePro(boardAtlas, sideLineCoords, rect, {}, 270, rl.WHITE)		
	}

	// Corners
	{
		rect := get_tile_rect(maxCoord, maxCoord)
		rl.DrawTexturePro(boardAtlas, cornerLineCoords, rect, {}, 0, rl.WHITE)
		rect = get_tile_rect(0, maxCoord)
		rect.x += TILE_SIZE_PX
		rl.DrawTexturePro(boardAtlas, cornerLineCoords, rect, {}, 90, rl.WHITE)
		rect = get_tile_rect(0, 0)
		rect.x += TILE_SIZE_PX
		rect.y += TILE_SIZE_PX
		rl.DrawTexturePro(boardAtlas, cornerLineCoords, rect, {}, 180, rl.WHITE)
		rect = get_tile_rect(maxCoord, 0)
		// rect.x += TILE_SIZE_PX
		rect.y += TILE_SIZE_PX
		rl.DrawTexturePro(boardAtlas, cornerLineCoords, rect, {}, 270, rl.WHITE)
	}

	// Hoshi
	hoshiList :[]rl.Vector2
	switch render.boardSize {
		case 19: hoshiList = hoshi_19
		case 13: hoshiList = hoshi_13
		case 9: hoshiList = hoshi_9
	}

	for p in hoshiList {
		rect := get_tile_rect(Coord(p.x), Coord(p.y))
		rl.DrawTexturePro(boardAtlas, hoshiLineCoords, rect, {}, 0, rl.WHITE)
	}

	// Draw board stones
	for j in 0..<render.boardSize {
		for i in 0..<render.boardSize {
			stone := get_tile(game, i, j)
			if stone == .Liberty || stone == .None {
				set_tile_jitter(render, i, j, {})
				continue
			}
			jitter := get_tile_jitter(render, i, j)
			if jitter == {} {
				jitter = StoneJitter{rand.choice([]Coord{0, 1}), rand.choice([]Coord{0, 1})}
				set_tile_jitter(render, i, j, jitter)
			}
			rect := get_stone_rect(i, j, jitter.x, jitter.y)
			texCoords := blackStoneTexCoords if stone == .Black else whiteStoneTexCoords
			rl.DrawTexturePro(stoneAtlas, texCoords, rect, {}, 0, rl.WHITE)
		}
	}

	// Draw last stone overlay
	if game.currentPosition != nil && game.currentPosition.moveType == .Move {
		pos := game.currentPosition.pos
		tile := game.currentPosition.tile
		jitter := get_tile_jitter(render, pos.x, pos.y)
		rect := get_stone_rect(pos.x, pos.y, jitter.x, jitter.y)
		texCoords := blackMarkerTexCoords if tile == .Black else whiteMarkerTexCoords
		rl.DrawTexturePro(stoneAtlas, texCoords, rect, {}, 0, rl.WHITE)
	}

	// Draw considered move
	if game.hoverPos.x != -1 && game.hoverPos.y != -1 {
		texCoords := blackStoneTexCoords if game.nextTile == .Black else whiteStoneTexCoords
		rect := get_stone_rect(game.hoverPos.x, game.hoverPos.y)
		rect.x += 1
		rect.y -= 1
		rl.DrawTexturePro(stoneAtlas, texCoords, rect, {}, 0, rl.GetColor(0xFFFFFFFF))
	}
}

get_tile_jitter :: proc (render: ^PixelGoRender, cx, cy: Coord) -> StoneJitter {
	if cx < 0 || cx >= render.boardSize || cy < 0 || cy >= render.boardSize do return {}
	return render.pixOffsets[cy * render.boardSize + cx]
}

set_tile_jitter :: proc(render: ^PixelGoRender, cx, cy: Coord, jitter: StoneJitter) {
	if cx < 0 || cx >= render.boardSize || cy < 0 || cy >= render.boardSize do return
	render.pixOffsets[cy * render.boardSize + cx] = jitter
}

get_tile_rect :: proc(i, j: Coord) -> rl.Rectangle {
	rect := rl.Rectangle{f32(i * TILE_SIZE_PX), f32(j * TILE_SIZE_PX), TILE_SIZE_PX, TILE_SIZE_PX}
	return rect
}

get_stone_rect :: proc(i, j: Coord, x_offs: Coord = 0, y_offs: Coord = 0) -> rl.Rectangle {
	rect := rl.Rectangle{f32(i * TILE_SIZE_PX + x_offs), f32(j * TILE_SIZE_PX + y_offs), STONE_SIZE_PX, STONE_SIZE_PX}
	return rect
}