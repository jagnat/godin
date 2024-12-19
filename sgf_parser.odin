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

SgfProperty :: struct {
	id : string,
	values : [dynamic]string,
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

parse_gametree :: proc(parse : ^SgfParseContext) -> (node: ^GameNode, err: io.Error) {
	node = parse_sequence(parse) or_return
	match_char(parse, '(') or_return

	return nil, .None
}

parse_sequence :: proc(parse: ^SgfParseContext) -> (node: ^GameNode, err: io.Error) {
	node = nil
	skip_whitespace(parse) or_return

	firstNode := parse_node(parse) or_return
	currentNode := firstNode

	skip_whitespace(parse) or_return

	r := peek_char(parse) or_return
	for r == ';' {
		childNode := parse_node(parse) or_return
		add_child_node(currentNode, childNode)
		childNode.parent = currentNode
		currentNode = childNode

		skip_whitespace(parse) or_return

		r = peek_char(parse) or_return
	}

	return firstNode, .None
}

parse_node :: proc(parse: ^SgfParseContext) -> (ret: ^GameNode, err: io.Error) {
	node := gamenode_new(parse)
	properties : [dynamic]SgfProperty
	match_char(parse, ';') or_return
	skip_whitespace(parse) or_return
	ret = nil

	r := peek_char(parse) or_return
	for r >= 'A' && r <= 'Z' {
		property := parse_property(parse) or_return
		append(&properties, property)

		skip_whitespace(parse) or_return

		r = peek_char(parse) or_return
	}

	foundMove: bool = false

	for prop in properties {
		switch prop.id {
			case "W", "B": {
				if foundMove { return ret, .Unknown }
				node.tile = .Black if str.contains(prop.id, "B") else .White
				
			}
			case "AB", "AW", "AE": {

			}
			case "C": {

			}
			case: break
		}
	}

	return nil, .None
}

parse_property :: proc(parse: ^SgfParseContext) -> (prop: SgfProperty, err: io.Error) {
	return SgfProperty{}, .None
}

add_child_node :: proc(parent, child: ^GameNode) {
	if parent.children == nil {
		parent.children = child
	} else {
		lastChild := parent.children
		for lastChild.siblingNext != nil {
			lastChild = lastChild.siblingNext
		}
		lastChild.siblingNext = child
	}
}

match_char :: proc (parse : ^SgfParseContext, c: rune) -> io.Error {
	r, _ := str.reader_read_rune(&parse.reader) or_return
	if r != c {
		str.reader_unread_rune(&parse.reader)
		return .Unknown
	}
	return .None
}

peek_char :: proc (parse: ^SgfParseContext) -> (r: rune, err: io.Error) {
	re, _ := str.reader_read_rune(&parse.reader) or_return
	str.reader_unread_rune(&parse.reader)
	return re, .None
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

gamenode_new :: proc(parse: ^SgfParseContext) -> ^GameNode {
	append(parse.nodePool, GameNode{})
	return &parse.nodePool[len(parse.nodePool) - 1]
}