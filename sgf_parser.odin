package godin

import "core:os"
import str "core:strings"
import "core:io"
import "core:fmt"
import "core:mem"
import "core:strconv"

SgfParseContext :: struct {
	game: ^GoGame,
	reader: str.Reader,
	line_no: i32,
	error_message: string,
}

SgfProperty :: struct {
	id : string,
	values : [dynamic]string,
}

ParseError :: enum {
	None,
	SyntaxError,
	ValueError,
	IoError,
}

parse_from_file :: proc (filepath: string) -> ^GoGame {

	data, ok := os.read_entire_file(filepath, context.allocator)
	if !ok { return nil }

	defer delete(data, context.allocator)

	sgf := string(data)
	return parse(sgf)
}

parse :: proc(sgf : string) -> ^GoGame {
	game := new(GoGame)
	init_game(game, generateHeadNode = false)
	parse := SgfParseContext{game, str.Reader{}, 1, ""}

	str.reader_init(&parse.reader, sgf)
	node : ^GameNode
	err : ParseError
	fmt.println("total used before parse:", parse.game.arena.total_used)

	node, err = parse_gametree(&parse)

	fmt.println("total used after parse:", parse.game.arena.total_used)

	if err != .None {
		fmt.println("ERRORRRRRRRRRRRRRR", err)
		return nil
	}
	game.headNode = node
	game.currentPosition = node

	free_all(context.temp_allocator)

	return game
}

parse_gametree :: proc(parse : ^SgfParseContext) -> (node: ^GameNode, err: ParseError) {
	skip_whitespace(parse) or_return
	match_char(parse, '(') or_return
	node, err = parse_sequence(parse)
	if err != .None {
		return node, err
	}

	tailNode := node
	for tailNode.children != nil {
		tailNode = tailNode.children
	}

	skip_whitespace(parse) or_return

	c := peek_char(parse) or_return

	for c == '(' {
		tmpNode := parse_gametree(parse) or_return
		add_child_node(tailNode, tmpNode)
		skip_whitespace(parse) or_return
		c = peek_char(parse) or_return
	}

	e := match_char(parse, ')')
	if e != .None {
		return node, e
	}

	return node, .None
}

parse_sequence :: proc(parse: ^SgfParseContext) -> (node: ^GameNode, err: ParseError) {
	skip_whitespace(parse) or_return

	node, err = parse_node(parse)
	if err != .None {
		return node, err
	}
	currentNode := node

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

	return node, .None
}

parse_node :: proc(parse: ^SgfParseContext) -> (ret: ^GameNode, err: ParseError) {
	ret = gamenode_new(parse.game)
	properties : [dynamic]SgfProperty = make([dynamic]SgfProperty, allocator=context.temp_allocator)
	match_char(parse, ';') or_return
	skip_whitespace(parse) or_return

	r := peek_char(parse) or_return
	for r >= 'A' && r <= 'Z' {
		property := parse_property(parse) or_return
		append(&properties, property)

		skip_whitespace(parse) or_return

		r = peek_char(parse) or_return
	}

	foundMove: bool = false

	setupPoints : [dynamic]SetupStone = make([dynamic]SetupStone, allocator=context.temp_allocator)

	for prop in properties {
		switch prop.id {
			case "W", "B": {
				if foundMove {
					return ret, .ValueError
				}
				ret.tile = .Black if str.contains(prop.id, "B") else .White
				ret.pos = pos_from_value(prop.values[0]) or_return
				ret.moveType = .Pass if (ret.pos[0] == -1 && ret.pos[1] == -1) else .Move
				foundMove = true
			}
			case "AB", "AW", "AE": {
				tile : GoTile = .Black if str.contains(prop.id, "AB") else (.White if str.contains(prop.id, "AW") else .Liberty)
				for val in prop.values {
					p := pos_from_value(val) or_return
					append(&setupPoints, SetupStone{p, tile})
				}
			}
			case "C": {
				ret.comment = prop.values[0]
			}
			case "KM": {
				komi, ok := strconv.parse_f32(prop.values[0])
				if !ok {
					return ret, .ValueError
				}
				parse.game.komi = komi
			}
			case "SZ": {
				size, ok := strconv.parse_int(prop.values[0])
				if !ok {
					return ret, .ValueError
				}
				parse.game.boardSize = Coord(size)
			}
			case: break
		}
	}

	if len(setupPoints) > 0 {
		ret.setupStones = make([dynamic]SetupStone, len(setupPoints), allocator=parse.game.alloc)
		copy_slice(ret.setupStones[:], setupPoints[:])
	}

	return ret, .None
}

pos_from_value :: proc(val : string) -> (Position, ParseError) {
	p := Position{-1, -1}

	if val == "" || val == "tt" {
		return p, .None
	}

	if len(val) != 2 {
		return p, .ValueError
	}

	xC := val[0]
	yC := val[1]

	if xC < 'a' || xC > 's' || yC < 'a' || yC > 's' {
		return p, .ValueError
	}

	p[0] = Coord(xC - 'a')
	p[1] = Coord(yC - 'a')

	return p, .None
}

parse_property :: proc(parse: ^SgfParseContext) -> (p: SgfProperty, err: ParseError) {

	c := peek_char(parse) or_return
	property_start := parse.reader.i

	for ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) {
		skip_char(parse) or_return
		c = peek_char(parse) or_return
	}

	property_end := parse.reader.i

	prop := SgfProperty{}
	prop.values = make([dynamic]string, allocator=context.temp_allocator)
	st, er := str.cut_clone(parse.reader.s, int(property_start), int(property_end - property_start), allocator=context.temp_allocator)
	if (er != .None) {
		return prop, .IoError
	}
	prop.id = st

	skip_whitespace(parse) or_return

	c = peek_char(parse) or_return
	for c == '[' {
		val := parse_property_value(parse) or_return
		append(&prop.values, val)
		skip_whitespace(parse) or_return
		c = peek_char(parse) or_return
	}

	return prop, .None
}

parse_property_value :: proc(parse: ^SgfParseContext) -> (s: string, err: ParseError) {
	propBuilder := str.Builder{}
	str.builder_init(&propBuilder, allocator = parse.game.alloc)
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

get_child_count :: proc(parent: ^GameNode) -> i64 {
	if parent.children == nil { return 0 }

	count : i64 = 1
	child := parent.children

	for child.siblingNext != nil {
		child = child.siblingNext
		count += 1
	}

	return count
}

match_char :: proc (parse : ^SgfParseContext, c: rune) -> ParseError {
	r, i, er := str.reader_read_rune(&parse.reader)
	if er != .None {
		return .SyntaxError
	}
	if r != c {
		str.reader_unread_rune(&parse.reader)
		return .SyntaxError
	}
	return .None
}

peek_char :: proc (parse: ^SgfParseContext) -> (r: rune, err: ParseError) {
	re, _, ioe := str.reader_read_rune(&parse.reader)
	if ioe != .None {

	}
	str.reader_unread_rune(&parse.reader)
	return re, .None
}

skip_char :: proc(parse: ^SgfParseContext) -> ParseError {
	r, _, err := str.reader_read_rune(&parse.reader)
	if err == .EOF {
		return .SyntaxError
	}
	if r == '\n' {
		parse.line_no += 1
	}
	return .None
}

skip_whitespace :: proc(parse: ^SgfParseContext) -> ParseError {
	for {
		r, _, err := str.reader_read_rune(&parse.reader)
		if err == .EOF {
			return .None
		}
		if r == '\n' {
			parse.line_no += 1
		}
		if !str.is_ascii_space(r) {
			str.reader_unread_rune(&parse.reader)
			return .None
		}
	}
}

print_sgf :: proc(node: ^GameNode) {
	prefix := str.Builder{}
	str.builder_init(&prefix)
	print_sgf_recurse(node, &prefix, false)
	fmt.println()
}

@private
print_sgf_recurse :: proc(node: ^GameNode, prefix: ^str.Builder, last: bool) {
	if node == nil {
		fmt.println("Nothing to print, node is nil")
		return
	}

	fmt.print(str.to_string(prefix^), sep="")

	if last {
		fmt.print("\\-", sep="")
		str.write_string(prefix, "  ")
	} else {
		fmt.print("|-", sep="")
		str.write_string(prefix, "| ")
	}

	if node.tile != .Liberty {
		col := "W " if node.tile == .White else "B "
		if node.pos.x == -1 && node.pos.y == -1 {
			fmt.println(col, "passes", sep="")
		} else {
			fmt.println(col, node.pos.x, ",", node.pos.y, sep="")
		}
	}

	child := node.children

	for child != nil {
		print_sgf_recurse(child, prefix, child.siblingNext == nil)
		child = child.siblingNext
	}

	str.pop_rune(prefix)
	str.pop_rune(prefix)
}