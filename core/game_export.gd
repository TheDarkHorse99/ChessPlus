class_name GameExport
extends RefCounted

## A finished game as one line of text, to keep or send to someone, which
## Testing mode can read back ("Import game") to look over the game there.
## One line, since a phone's text box can't hold more:
##   Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w; captured: -; moves: e2-e4 e7-e5
## - the starting position: the pieces as in a FEN (top row first, uppercase =
##   White, two-letter symbols in brackets, digits = empty squares), then who
##   moved first (w or b);
## - pieces already captured at the start (only in games from Testing mode),
##   uppercase = White's, or - for none;
## - the moves, as Move.to_text() (the same as saved games use).
## Every piece starts unmoved, as in any game from armies or from Testing mode.

## What the text starts with.
const TEXT_START := "Overchess game"
## What it started with before the game was renamed (Mac, 26 Oct 2026):
## still read, so games exported before then import as before.
const OLD_TEXT_STARTS: Array[String] = ["Chess Plus game"]
const NONE := "-"

## The game that started from `start` (a fresh copy of the starting position)
## and went on with `moves`, as one line of text.
static func to_text(start: GameState, moves: Array[Move]) -> String:
	var placement := Fen.write(start).split(" ")[0]
	var side := "w" if start.side_to_move == Piece.Team.WHITE else "b"
	var captured := PackedStringArray()
	for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
		for piece: Piece in start.lost[team]:
			captured.append(piece.letter())
	var move_texts := PackedStringArray()
	for move in moves:
		move_texts.append(move.to_text())
	return "%s: %s %s; captured: %s; moves: %s" % [TEXT_START, placement, side,
			" ".join(captured) if not captured.is_empty() else NONE, " ".join(move_texts)]

## The game written in `text` by to_text(), checked move by move. Returns
## {"position": TestingPosition, "moves": PackedStringArray, "error": ""}, or
## {"position": null, "moves": [], "error": what's wrong, in plain words}.
static func from_text(text: String) -> Dictionary:
	var line := text.strip_edges()
	var colon := line.find(":")
	var label := line.left(colon).strip_edges().to_lower() if colon >= 0 else ""
	if not ([TEXT_START] + OLD_TEXT_STARTS).any(func(start: String) -> bool: return start.to_lower() == label):
		return _error("That isn't game text. It should start with \"%s:\" (from Export game)." % TEXT_START)
	var parts := {}
	var fields := line.substr(colon + 1).split(";")
	parts["start"] = fields[0].strip_edges()
	for i in range(1, fields.size()):
		var field := fields[i].strip_edges()
		var label_end := field.find(":")
		if label_end < 0:
			continue
		parts[field.left(label_end).strip_edges().to_lower()] = field.substr(label_end + 1).strip_edges()
	if not parts.has("moves"):
		return _error("The game text has no moves part; copy the whole line.")
	var by_symbol := _defs_by_symbol()
	# The starting position.
	var start: PackedStringArray = parts["start"].split(" ", false)
	if start.size() != 2 or not start[1] in ["w", "b"]:
		return _error("The starting position should be the pieces, then w or b.")
	var position := TestingPosition.new()
	position.side_to_move = Piece.Team.WHITE if start[1] == "w" else Piece.Team.BLACK
	var rows := start[0].split("/")
	if rows.size() != position.height:
		return _error("The board should have %d rows, but it has %d." % [position.height, rows.size()])
	var token_pattern := RegEx.create_from_string("\\(([A-Za-z]+)\\)|([A-Za-z])|([0-9]+)|(['+^])|(.)")
	for i in rows.size():
		var rank := position.height - 1 - i
		var file := 0
		for found: RegExMatch in token_pattern.search_all(rows[i]):
			if found.get_string(3) != "":
				file += found.get_string(3).to_int()
				continue
			if found.get_string(4) != "":
				continue  # A mark on the piece before it (a used ability): every piece starts fresh.
			var letters := found.get_string(1) + found.get_string(2)
			if letters.is_empty():
				return _error("The starting position has a stray \"%s\"." % found.get_string(5))
			var def: PieceDef = by_symbol.get(letters.to_upper())
			if def == null:
				return _unknown_piece(letters)
			if file < position.width:
				position.place(Vector2i(file, rank), def, _team_of(letters))
			file += 1
		if file != position.width:
			return _error("Row %d of the board should have %d squares, but it has %d." % [rank + 1, position.width, file])
	# Pieces captured before the first move.
	var captured: String = parts.get("captured", NONE)
	if captured != NONE:
		for letters in captured.split(" ", false):
			var def: PieceDef = by_symbol.get(letters.to_upper())
			if def == null:
				return _unknown_piece(letters)
			position.captured.append([def, _team_of(letters)])
	var problems := position.problems()
	if not problems.is_empty():
		return _error("That game can't be set up: " + problems[0])
	# The moves: each must be legal where it was played.
	var moves: PackedStringArray = parts["moves"].split(" ", false)
	var state := position.create_state()
	for move_text in moves:
		var move := state.find_move(move_text)
		if move == null:
			return _error("%s's move %d (%s) can't be played there. The text may be cut short or changed, or from another version of the game." % [
					"White" if state.side_to_move == Piece.Team.WHITE else "Black", state.fullmove_number, move_text])
		state.make_move(move)
	return {"position": position, "moves": moves, "error": ""}

## Every piece's letters (uppercase) -> its type, changed forms (the wolf) too.
static func _defs_by_symbol() -> Dictionary:
	var by_symbol := {}
	for def in PieceCatalog.all_defs():
		by_symbol[def.symbol.to_upper()] = def
		if def.transforms_into:
			by_symbol[def.transforms_into.symbol.to_upper()] = def.transforms_into
	return by_symbol

## Uppercase letters are White's pieces, lowercase Black's.
static func _team_of(letters: String) -> Piece.Team:
	return Piece.Team.WHITE if letters == letters.to_upper() else Piece.Team.BLACK

static func _unknown_piece(letters: String) -> Dictionary:
	return _error("There's no piece with the letters %s (it may be from a newer version of the game)." % letters.to_upper())

static func _error(error: String) -> Dictionary:
	return {"position": null, "moves": PackedStringArray(), "error": error}
