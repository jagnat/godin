package godin

import vm "core:mem/virtual"
import "core:mem"
import "core:fmt"
import "core:testing"

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

	treeRow, treeCol: i32,

	// N-ary tree
	siblingNext: ^GameNode,
	parent: ^GameNode,
	children: ^GameNode,
}

CapturePoolSize :: 512

GoGame :: struct {

	// Variables set at init
	headNode: ^GameNode,
	arena: vm.Arena,
	alloc: mem.Allocator,
	boardSize: Coord,
	capturePool: [dynamic]Position,

	// width and height of tree layout grid
	treeW, treeH: i32,

	// Variables set relative to current position in the game
	capturePoolIdx: int,
	currentPosition: ^GameNode,
	board: [dynamic]GoTile,
	whiteCaptures: int,
	blackCaptures: int,
	komi: f32,
	nextTile: GoTile,

	hoverPos: Position
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

// Tag tree with column and row coords
layout_tree :: proc(game: ^GoGame) {
	ColRange :: struct {
		rowStart, rowEnd: int,
		next: ^ColRange,
	}

	LayoutCtx :: struct {
		cols: [dynamic]^ColRange,
		grandparent: ^GameNode,
		maxCol, maxRow: int
	}

	ctx: LayoutCtx
	ctx.cols = make([dynamic]^ColRange, 256, context.temp_allocator)
	ctx.grandparent = game.headNode

	goto_leaf :: proc(node: ^GameNode, idx: int = 0) -> (int, ^GameNode) {
		if node.children == nil do return idx, node
		return goto_leaf(node.children, idx + 1)
	}

	columnCollides :: proc(ctx: ^LayoutCtx, colNo, rowStart, rowEnd: int) -> bool {
		colPtr := ctx.cols[colNo]
		for colPtr != nil {
			if colPtr.rowStart <= rowEnd && rowStart <= colPtr.rowEnd do return true
			colPtr = colPtr.next
		}
		return false
	}

	addColRange :: proc(ctx: ^LayoutCtx, colNo, rowStart, rowEnd: int) {
		range := new(ColRange, context.temp_allocator)
		range.rowStart = rowStart
		range.rowEnd = rowEnd
		range.next = ctx.cols[colNo]
		ctx.cols[colNo] = range
	}

	recursive_traverse :: proc(ctx: ^LayoutCtx, mainline: ^GameNode, row, col: int) {
		depth, mainLeaf := goto_leaf(mainline)

		mainNode := mainLeaf
		rowPos := row + depth
		if rowPos > ctx.maxRow do ctx.maxRow = rowPos

		for { // loop up the tree
			mainNode.treeRow = i32(rowPos)
			mainNode.treeCol = i32(col)

			nextCol := col + 1
			nextSibl := mainNode.siblingNext
			for nextSibl != nil {
				siblDepth, siblLeaf := goto_leaf(nextSibl)

				for {
					if !columnCollides(ctx, nextCol, rowPos, rowPos + siblDepth) {
						break
					}
					nextCol += 1
				}

				if nextCol > col + 1 {
					for c in col + 1 ..< nextCol {
						addColRange(ctx, c, rowPos - 1, rowPos - 1)
					}
				}

				if nextCol > ctx.maxCol do ctx.maxCol = nextCol
				recursive_traverse(ctx, nextSibl, rowPos, nextCol)

				nextSibl = nextSibl.siblingNext
			}

			rowPos -= 1
			if rowPos == row - 1 || mainNode.parent == nil do break
			mainNode = mainNode.parent
		}

		addColRange(ctx, col, row, row + depth)
	}

	recursive_traverse(&ctx, game.headNode, 0, 0)

	game.treeW = i32(ctx.maxCol + 1)
	game.treeH = i32(ctx.maxRow + 1)
}

move_forward :: proc(game : ^GoGame, childIndex : int = 0) {
	if game.currentPosition == nil do return

	node := get_child_at(game.currentPosition, childIndex)

	if node == nil do return

	switch node.moveType {
		case .None:
		case .Move:
			game.nextTile = other_tile_type(game.nextTile)

			startStack := game.capturePoolIdx
			endStack := game.capturePoolIdx

			// Check for captures
			for add in Neighbors {
				neighbor := add + node.pos
				tile := get_tile(game, neighbor)

				if tile == other_tile_type(node.tile) {
					stones, liberties := get_stone_group(game, neighbor)

					if len(liberties) == 1 { // Capture
						captureSize := len(stones)
						endStack = game.capturePoolIdx + captureSize
						captures := game.capturePool[game.capturePoolIdx:endStack]
						game.capturePoolIdx = endStack
						copy_slice(captures, stones[:])

						if game.nextTile == .Black {
							game.blackCaptures += captureSize
						} else {
							game.whiteCaptures += captureSize
						}
					}
				}
			}

			if startStack != endStack {
				node.captures = game.capturePool[startStack : endStack]
				remove_stones(game, node.captures)
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
	if currentNode == nil do return
	prevNode := currentNode.parent
	if prevNode == nil do return

	if currentNode.moveType == .Move {
		set_tile(game, currentNode.pos, .Liberty)
		add_stones(game, currentNode.captures, other_tile_type(currentNode.tile))
		if currentNode.tile == .Black {
			game.whiteCaptures -= len(currentNode.captures)
		} else {
			game.blackCaptures -= len(currentNode.captures)
		}
		game.capturePoolIdx -= len(currentNode.captures)
		currentNode.captures = {}
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

				// Ko check
				if game.currentPosition.moveType == .Move &&
					len(game.currentPosition.captures) == 1 &&
					game.currentPosition.captures[0] == pos {
					return false
				}
				
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

@(test)
test_layout_sgf :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testcase1 := "(;GM[1]FF[4]CA[UTF-8]AP[Sabaki:0.52.2]KM[6.5]SZ[19]DT[2025-08-06];B[dd](;W[gg](;B[hj](;W[mh];B[ho])(;W[lf];B[ll]))(;B[mj]))(;W[mf];B[hm];W[fh];B[mk];W[ke];B[kk]))"
	game := parse(testcase1)
	fmt.println("TEST")
	testing.expect(t, game != nil)

	layout_tree(game)
	fmt.println("tree w: ", game.treeW, " tree h: ", game.treeH)
	testing.expect(t, game.treeW == 3 && game.treeH == 8)

	nodeMap := make([dynamic]^GameNode, game.treeW * game.treeH)

	dfs_fill :: proc(node: ^GameNode, m: [dynamic]^GameNode, numCols: i32) {
		if node == nil do return

		m[node.treeRow * numCols + node.treeCol] = node

		dfs_fill(node.children, m, numCols)
		dfs_fill(node.siblingNext, m, numCols)
	}

	dfs_fill(game.headNode, nodeMap, game.treeW)

	col0, col1, col2: int
	for i in 0..< game.treeH {
		col0 += nodeMap[i * game.treeW + 0] == nil? 0 : 1
		col1 += nodeMap[i * game.treeW + 1] == nil? 0 : 1
		col2 += nodeMap[i * game.treeW + 2] == nil? 0 : 1
	}

	testing.expect(t, col0 == 6)
	testing.expect(t, col1 == 3)
	testing.expect(t, col2 == 6)
}
