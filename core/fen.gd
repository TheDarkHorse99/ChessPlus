class_name Fen
extends RefCounted

## Reads and writes FEN, the standard one-line text format for a chess position.
## It has six fields separated by spaces:
##   pieces (top rank first, "/" between ranks, digits = that many empty squares)
##   side to move (w or b), castling rights (KQkq or -), en passant square (or -),
##   halfmove clock, move number.
## Uppercase letters are White, lowercase are Black. Chess Plus can add, after
## the six, "unchanged=N" (the 75-move rule's count of plies since the pieces
## last changed): parse() always reads it (left out, it equals the halfmove
## clock); write() adds it only when asked (`with_count`), so FENs stay
## standard text. Nothing keeps a game as FEN mid-game, so that's enough.

const STANDARD_START := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

## Builds a GameState from FEN text. `defs` are the piece types the letters may
## refer to (matched on PieceDef.symbol). Returns null if the text can't be read.
static func parse(text: String, defs: Array[PieceDef], rules: GameRules) -> GameState:
	var fields := text.strip_edges().split(" ", false)
	if fields.is_empty():
		push_error("FEN is empty")
		return null
	var board := _parse_pieces(fields[0], defs)
	if board == null:
		return null
	var state := GameState.new(board, rules)
	state.side_to_move = Piece.Team.BLACK if fields.size() > 1 and fields[1] == "b" else Piece.Team.WHITE
	_set_moved_flags(board, fields[2] if fields.size() > 2 else "-")
	if fields.size() > 3 and fields[3] != "-":
		var square := Board.parse_square(fields[3])
		if not board.in_bounds(square):
			push_error("FEN has a bad en passant square: " + fields[3])
			return null
		state.en_passant_squares = [square]
		# The piece that just moved stands one step past the square it skipped.
		var forward := 1 if state.side_to_move == Piece.Team.BLACK else -1
		state.en_passant_victim = square + Vector2i(0, forward)
	state.halfmove_clock = fields[4].to_int() if fields.size() > 4 else 0
	state.fullmove_number = fields[5].to_int() if fields.size() > 5 else 1
	state.change_clock = state.halfmove_clock
	for extra in fields.slice(6):
		if extra.begins_with("unchanged="):
			state.change_clock = extra.trim_prefix("unchanged=").to_int()
	return state

## The FEN text for a game state.
static func write(state: GameState, with_count := false) -> String:
	var board := state.board
	var rows: PackedStringArray = []
	for rank in range(board.height - 1, -1, -1):
		var row := ""
		var empty := 0
		for file in range(board.width):
			var piece := board.get_piece(Vector2i(file, rank))
			if piece == null:
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			row += piece.letter() if piece.def.symbol.length() == 1 else "(%s)" % piece.letter()
			if piece.shield_broken:
				row += "'"
			if piece.gained_shield:
				row += "+"
			if piece.ability_used:
				row += "^"
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var side := "w" if state.side_to_move == Piece.Team.WHITE else "b"
	var en_passant := "-"
	if not state.en_passant_squares.is_empty():
		en_passant = Board.square_name(state.en_passant_squares[0])
	var text := " ".join(["/".join(rows), side, _castling_text(board), en_passant,
			str(state.halfmove_clock), str(state.fullmove_number)])
	if with_count and state.change_clock != state.halfmove_clock:
		text += " unchanged=%d" % state.change_clock
	return text

## Reads the piece-placement field. The board's size comes from the text itself.
static func _parse_pieces(text: String, defs: Array[PieceDef]) -> Board:
	var by_symbol := {}
	# What each changed form started as (a wolf was a Werewolf).
	var started_as := {}
	for def in defs:
		by_symbol[def.symbol.to_upper()] = def
		if def.transforms_into:
			by_symbol[def.transforms_into.symbol.to_upper()] = def.transforms_into
			started_as[def.transforms_into] = def
	var rows := text.split("/")
	var height := rows.size()
	var width := _row_width(rows[0])
	var board := Board.new(width, height)
	for i in range(height):
		var rank := height - 1 - i
		var file := 0
		var last: Piece = null
		for token in _tokens(rows[i]):
			if token.is_valid_int():
				file += token.to_int()
				continue
			if token == "'":
				# The piece just before this mark has lost its shield.
				if last:
					last.shield_broken = true
				continue
			if token == "+":
				# The piece just before this mark has gained a shield (a Vampire).
				if last:
					last.gained_shield = true
				continue
			if token == "^":
				# The piece just before this mark has used its special ability.
				if last:
					last.ability_used = true
				continue
			var letters := token.trim_prefix("(").trim_suffix(")")
			var def: PieceDef = by_symbol.get(letters.to_upper())
			if def == null:
				push_error("FEN has an unknown piece: " + token)
				return null
			if file >= width:
				push_error("FEN rank %d is too long" % (rank + 1))
				return null
			var team := Piece.Team.WHITE if letters == letters.to_upper() else Piece.Team.BLACK
			last = Piece.new(def, team)
			last.base_def = started_as.get(def)
			board.set_piece(Vector2i(file, rank), last)
			file += 1
		if file != width:
			push_error("FEN rank %d has the wrong length" % (rank + 1))
			return null
	return board

static func _row_width(row: String) -> int:
	var width := 0
	for token in _tokens(row):
		if token.is_valid_int():
			width += token.to_int()
		elif token != "'" and token != "^" and token != "+":
			width += 1
	return width

## Splits one rank of the placement field into pieces: a number of empty squares
## ("3", or "10" on wide boards), a one-letter piece ("N"), a two-letter piece in
## brackets ("(PD)"), or a "'" mark meaning the piece before it lost its shield.
static func _tokens(row: String) -> PackedStringArray:
	var tokens: PackedStringArray = []
	var i := 0
	while i < row.length():
		var c := row[i]
		if c.is_valid_int():
			var digits := ""
			while i < row.length() and row[i].is_valid_int():
				digits += row[i]
				i += 1
			tokens.append(digits)
			continue
		if c == "(":
			var close := row.find(")", i)
			if close < 0:
				close = row.length() - 1
			tokens.append(row.substr(i, close - i + 1))
			i = close + 1
			continue
		tokens.append(c)
		i += 1
	return tokens

## FEN doesn't store has_moved, so work it out:
## - castling pieces count as moved unless the castling rights say otherwise;
## - pieces with a first-move rule (pawns) are unmoved only on their starting rank;
## - pieces with a special ability count as moved (an ability needs a move
##   first, Mac's rule; a FEN position is assumed to be mid-game).
static func _set_moved_flags(board: Board, castling: String) -> void:
	for rank in range(board.height):
		for file in range(board.width):
			var pos := Vector2i(file, rank)
			var piece := board.get_piece(pos)
			if piece == null:
				continue
			if piece.def.is_king_type() or piece.def.has_castle() or piece.def.ability != PieceDef.Ability.NONE:
				piece.has_moved = true
			elif _has_first_move_rule(piece.def):
				var home_rank := 1 if piece.team == Piece.Team.WHITE else board.height - 2
				piece.has_moved = rank != home_rank
	for c in castling:
		if c.to_upper() != "K" and c.to_upper() != "Q":
			continue
		var team := Piece.Team.WHITE if c == c.to_upper() else Piece.Team.BLACK
		var king_pos := _find_castler(board, team)
		if king_pos == Board.NO_SQUARE:
			continue
		# K = the partner toward the h-file side, Q = toward the a-file side.
		var dir := 1 if c.to_upper() == "K" else -1
		var partner_pos := _outermost_partner(board, team, king_pos, dir)
		if partner_pos == Board.NO_SQUARE:
			continue
		board.get_piece(king_pos).has_moved = false
		board.get_piece(partner_pos).has_moved = false

static func _castling_text(board: Board) -> String:
	var text := ""
	for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
		var king_pos := _find_castler(board, team)
		if king_pos == Board.NO_SQUARE or board.get_piece(king_pos).has_moved:
			continue
		var rights := ""
		if _has_unmoved_partner(board, team, king_pos, 1):
			rights += "K"
		if _has_unmoved_partner(board, team, king_pos, -1):
			rights += "Q"
		text += rights if team == Piece.Team.WHITE else rights.to_lower()
	return text if text != "" else "-"

## Where the team's castling piece (the king) is, or NO_SQUARE.
static func _find_castler(board: Board, team: Piece.Team) -> Vector2i:
	for rank in range(board.height):
		for file in range(board.width):
			var piece := board.get_piece(Vector2i(file, rank))
			if piece and piece.team == team and piece.def.is_king_type():
				return Vector2i(file, rank)
	return Board.NO_SQUARE

## The castle partner farthest from the king in direction `dir` (+1 or -1 files)
## on the king's rank, or NO_SQUARE.
static func _outermost_partner(board: Board, team: Piece.Team, king_pos: Vector2i, dir: int) -> Vector2i:
	var file := board.width - 1 if dir > 0 else 0
	while file != king_pos.x:
		var piece := board.get_piece(Vector2i(file, king_pos.y))
		if piece and piece.team == team and piece.def.has_castle():
			return Vector2i(file, king_pos.y)
		file -= dir
	return Board.NO_SQUARE

static func _has_unmoved_partner(board: Board, team: Piece.Team, king_pos: Vector2i, dir: int) -> bool:
	var pos := king_pos + Vector2i(dir, 0)
	while board.in_bounds(pos):
		var piece := board.get_piece(pos)
		if piece and piece.team == team and piece.def.has_castle() and not piece.has_moved:
			return true
		pos.x += dir
	return false

static func _has_first_move_rule(def: PieceDef) -> bool:
	for rule in def.move_rules:
		if rule.first_move_max_steps > 0:
			return true
	return false
