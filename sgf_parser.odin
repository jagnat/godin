package godin

import "core:os"
import str "core:strings"
import "core:io"
import "core:fmt"

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

SgfParseContext :: struct {
	nodePool: ^[dynamic]GameNode,
	reader: str.Reader,
	line_no: i32,
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

	parse := SgfParseContext{&nodePool, str.Reader{}, 1}

	str.reader_init(&parse.reader, sgf)

	node, err := parse_gametree(&parse)

	if err != .None {
		fmt.println("ERRORRRRRRRRRRRRRR", err)
		return nil
	}

	return &nodePool[0]
}

parse_gametree :: proc(parse : ^SgfParseContext) -> (node: ^GameNode, err: io.Error) {
	match_char(parse, '(') or_return
	headNode := parse_sequence(parse) or_return

	tailNode := headNode
	for tailNode.children != nil {
		tailNode = tailNode.children
	}

	skip_whitespace(parse) or_return

	c := peek_char(parse) or_return

	for c == '(' {
		tmpNode := parse_gametree(parse) or_return
		add_child_node(tailNode, tmpNode)
		skip_whitespace(parse) or_return
	}

	match_char(parse, ')') or_return

	return headNode, .None
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
				if foundMove {
					fmt.println("Found move")
					return ret, .Unknown
				}
				node.tile = .Black if str.contains(prop.id, "B") else .White
				node.pos = pos_from_value(prop.values[0]) or_return
				node.moveType = .Pass if (node.pos[0] == -1 && node.pos[1] == -1) else .Move
				foundMove = true
			}
			case "AB", "AW", "AE": {
				points := &node.addedBlack if str.contains(prop.id, "AB") else
					(&node.addedWhite if str.contains(prop.id, "AW") else &node.cleared)
				for val in prop.values {
					p := pos_from_value(val) or_return
					append(points, p)
				}
			}
			case "C": {
				node.comment = prop.values[0]
			}
			case: break
		}
	}

	return node, .None
}

pos_from_value :: proc(val : string) -> (Position, io.Error) {
	p := Position{-1, -1}

	if val == "" || val == "tt" {
		return p, .None
	}

	if len(val) != 2 {
		fmt.println("pos_from_value: Val not len 2")
		return p, .Unknown
	}

	xC := val[0]
	yC := val[1]

	if xC < 'a' || xC > 's' || yC < 'a' || yC > 's' {
		fmt.println("pos_from_value: Coordinate outside bounds")
		return p, .Unknown
	}

	p[0] = i32(xC - 'a' + 1)
	p[1] = i32(yC - 'a' + 1)

	return p, .None
}

parse_property :: proc(parse: ^SgfParseContext) -> (prop: SgfProperty, err: io.Error) {

	c := peek_char(parse) or_return
	property_start := parse.reader.i

	for ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
		skip_char(parse) or_return
		c = peek_char(parse) or_return
	}

	property_end := parse.reader.i

	p := SgfProperty{}
	er : bool
	p.id, er = str.substring(parse.reader.s, int(property_start), int(property_end))
	if (er == false) {
		fmt.println("parse_property: Failed to get substr")
		return p, .Unknown
	}

	skip_whitespace(parse) or_return

	c = peek_char(parse) or_return
	for c == '[' {
		val := parse_property_value(parse) or_return
		append(&p.values, val)
		c = peek_char(parse) or_return
	}

	fmt.println("parse_property:", p.id, "val:", p.values[0])

	return p, .None
}

parse_property_value :: proc(parse: ^SgfParseContext) -> (s: string, err: io.Error) {
	propBuilder := str.Builder{}
	str.builder_init(&propBuilder)
	match_char(parse, '[') or_return

	c := peek_char(parse) or_return
	for c != ']' {
		if c == '\n' {
			parse.line_no += 1
		}
		if c == '\\' {
			skip_char(parse) or_return
			c = peek_char(parse) or_return
			if c == '\n' {
				parse.line_no += 1
			}
			if str.is_space(c) && c != '\n' && c != '\r' {
				str.write_rune(&propBuilder, ' ')
			}
			else if !str.is_space(c) {
				str.write_rune(&propBuilder, c)
			}
		}
		else {
			str.write_rune(&propBuilder, c)
		}
		skip_char(parse) or_return
		c = peek_char(parse) or_return
	}
	match_char(parse, ']') or_return
	return str.to_string(propBuilder), .None
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
	r, i, er := str.reader_read_rune(&parse.reader)
	if er != .None {
		fmt.println("match_char line: ", parse.line_no)
		return er
	}
	if r != c {
		str.reader_unread_rune(&parse.reader)
		fmt.println("parse_property: Failed to match char, expected", c, "at line no", parse.line_no)
		return .Unknown
	}
	return .None
}

peek_char :: proc (parse: ^SgfParseContext) -> (r: rune, err: io.Error) {
	re, _ := str.reader_read_rune(&parse.reader) or_return
	str.reader_unread_rune(&parse.reader)
	return re, .None
}

skip_char :: proc(parse: ^SgfParseContext) -> io.Error {
	_, _ = str.reader_read_rune(&parse.reader) or_return
	return .None
}

skip_whitespace :: proc(parse: ^SgfParseContext) -> io.Error {
	for {
		r, _ := str.reader_read_rune(&parse.reader) or_return
		if r == '\n' {
			parse.line_no += 1
		}
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