package godin

import "core:os"
import str "core:strings"
import "core:io"

GoTile :: enum {
	Empty,
	White,
	Black
}

MoveType :: enum {
	None, Move, Pass, Resign
}

GameNode :: struct {
	x, y : int,
	tile : GoTile,
	moveType : MoveType,
	comment : string,

	siblingNext: ^GameNode,
	parent: ^GameNode,
	children: ^GameNode,
}

SgfParseContext :: struct {
	nodePool: ^[dynamic]GameNode,
	reader: str.Reader,
}

parse_from_file :: proc (filepath: string) -> ^GameNode {

	data, ok := os.read_entire_file(filepath, context.allocator)
	if !ok { return nil }

	defer delete(data, context.allocator)

	sgf := string(data)
	return parse(sgf)
}

parse :: proc(sgf : string) -> ^GameNode {
	nodePool: [dynamic]GameNode
	append(&nodePool, GameNode{})

	parse := SgfParseContext{&nodePool, str.Reader{}}

	str.reader_init(&parse.reader, sgf)

	return &nodePool[0]
}

parse_gametree :: proc(parse : ^SgfParseContext) -> io.Error {
	match_char(parse, '(') or_return

	return .None
}

match_char :: proc (parse : ^SgfParseContext, c: rune) -> io.Error {
	r, _ := str.reader_read_rune(&parse.reader) or_return
	if r != c {
		str.reader_unread_rune(&parse.reader)
		return .Unknown
	}
	return .None
}

skip_whitespace :: proc(parse: ^SgfParseContext) -> io.Error {
	for {
		r, _ := str.reader_read_rune(&parse.reader) or_return
		if !str.is_ascii_space(r) {
			str.reader_unread_rune(&parse.reader)
			return .None
		}
	}
}