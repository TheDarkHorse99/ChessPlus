extends TestSuite

## The Wizard, Rogue, Chariot, Cavalry and Berserker: leaping lines (MoveRule
## leap_steps / leap_over) and bent paths (MoveRule path).

func _parse(fen: String) -> GameState:
	return Fen.parse(fen, PieceCatalog.all_defs(), StandardSetup.create_rules())

func _def(id: String) -> PieceDef:
	return load("res://data/pieces/%s.tres" % id)

## The squares the piece on `from` can move to, sorted, e.g. ["d6", "d7"].
func _targets(state: GameState, from: String) -> Array:
	var square := Board.parse_square(from)
	var names := []
	for move in state.moves():
		if move.from == square and not names.has(Board.square_name(move.to)):
			names.append(Board.square_name(move.to))
	names.sort()
	return names

func test_costs_symbols_and_tags() -> void:
	var expected := {"wizard": ["W", 8.5], "rogue": ["RO", 3.5], "chariot": ["CH", 4.0], "cavalry": ["CV", 3.0], "berserker": ["BR", 2.5]}
	for id in expected:
		check_eq([_def(id).symbol, _def(id).value], expected[id], id)
	check(_def("wizard").is_royal_type() and _def("wizard").has_jump(), "Wizard: Royal, Jump")
	check(_def("rogue").has_jump(), "Rogue: Jump")
	check(_def("chariot").has_castle() and not _def("chariot").has_promote(), "Chariot: Castle, not Promote")
	check(not _def("berserker").can_promote(), "Berserker doesn't promote")

# --- Wizard ----------------------------------------------------------------------------

func test_wizard_skips_the_squares_next_to_it() -> void:
	# Wizard d4, own pawn d5 (leapt over), black pawn d7.
	var targets := _targets(_parse("4k3/3p4/8/3P4/3W4/8/8/K7 w - - 0 1"), "d4")
	for square in ["d6", "d7", "b6", "f6", "b2", "f2", "d2", "b4", "f4", "h8"]:
		check(targets.has(square), "Reaches " + square)
	for square in ["d5", "c5", "e5", "c4", "e4", "c3", "d3", "e3", "d8"]:
		check(not targets.has(square), "Not " + square)

func test_wizard_checks_past_a_piece_but_not_next_door() -> void:
	check(_parse("3k4/8/8/8/8/8/3P4/3W3K b - - 0 1").is_in_check(), "Leaps the pawn to give check")
	check(not _parse("8/8/8/3k4/3W4/8/8/7K b - - 0 1").is_in_check(), "Next to it: no check")

# --- Rogue -----------------------------------------------------------------------------

func test_rogue_hops_only_its_own_pieces() -> void:
	# Rogue d4; own pawn d5 (hop to d6); black pawn e5 (no hop to f6); c5 empty (no b6).
	var targets := _targets(_parse("4k3/8/8/3Pp3/3(RO)4/8/8/K7 w - - 0 1"), "d4")
	check(targets.has("d6"), "Hops its own pawn")
	check(targets.has("e5"), "Captures next door")
	check(not targets.has("f6"), "Can't hop an enemy")
	check(not targets.has("b6"), "Can't hop an empty square")
	check(not targets.has("d5"), "Can't land on its own piece")

func test_rogue_captures_after_a_hop_and_gives_check() -> void:
	var state := _parse("8/8/3k4/3P4/3(RO)4/8/8/K7 b - - 0 1")
	check(state.is_in_check(), "Hop over its own pawn attacks the king")
	state = _parse("4k3/8/3n4/3P4/3(RO)4/8/8/K7 w - - 0 1")
	check(state.find_move("d4xd6") != null, "Hop and capture")

# --- Chariot ---------------------------------------------------------------------------

func test_chariot_moves_up_to_four_and_castles() -> void:
	var targets := _targets(_parse("4k3/8/8/8/8/8/8/(CH)6K w - - 0 1"), "a1")
	check(targets.has("a5") and not targets.has("a6"), "Up to four squares")
	check(targets.has("e1") and not targets.has("f1"), "Sideways too")
	var state := _parse("4k3/(CH)7/8/8/8/8/8/K7 w - - 0 1")
	check(state.find_move("a7-a8") != null and state.find_move("a7-a8=Q") == null, "Doesn't promote")
	state = _parse("4k3/8/8/8/8/8/8/(CH)3K3 w Q - 0 1")
	check(state.find_move("e1-c1") != null, "The king can castle with it")

# --- Cavalry ---------------------------------------------------------------------------

func test_cavalry_pattern() -> void:
	var targets := _targets(_parse("4k3/8/8/8/3(CV)4/8/8/K7 w - - 0 1"), "d4")
	check_eq(targets, ["b3", "b4", "b5", "c3", "c4", "c5", "e3", "e4", "e5", "f3", "f4", "f5"], "Twelve squares")

func test_cavalry_l_moves_can_be_blocked() -> void:
	# Own pawn on e4 blocks f4, f5 and f3; black pawn on c4 can be taken but blocks the rest.
	var targets := _targets(_parse("4k3/8/8/8/2p(CV)P3/8/8/K7 w - - 0 1"), "d4")
	check(targets.has("c4"), "Captures c4")
	for square in ["f4", "f5", "f3", "b4", "b5", "b3"]:
		check(not targets.has(square), "Blocked: " + square)

func test_cavalry_l_move_gives_check_only_when_open() -> void:
	check(_parse("8/8/8/5k2/3(CV)4/8/8/K7 b - - 0 1").is_in_check(), "Open L attacks f5")
	check(not _parse("8/8/8/5k2/3(CV)p3/8/8/K7 b - - 0 1").is_in_check(), "Blocked L doesn't")

# --- Berserker -------------------------------------------------------------------------

func test_berserker_pattern() -> void:
	check_eq(_targets(_parse("4k3/8/8/8/3(BR)4/8/8/K7 w - - 0 1"), "d4"), ["c5", "c6", "d5", "d6", "e5", "e6"], "Six squares ahead")
	# Black's Berserker goes down the board.
	check_eq(_targets(_parse("4k3/8/8/3(br)4/8/8/8/K7 b - - 0 1"), "d5"), ["c3", "c4", "d3", "d4", "e3", "e4"], "Black: six squares below")

## Mac (Oct 2026): its L-shaped moves are blocked like the Knight's and the
## Cavalry's, 2 squares then 1: d4 to c6 goes d5, d6, then c6.
func test_berserker_l_moves_go_two_then_one() -> void:
	check_eq(_targets(_parse("4k3/8/8/2PP4/3(BR)4/8/8/K7 w - - 0 1"), "d4"), ["e5"], "Own pieces on c5 and d5: d5 blocks d6, c6 and e6")
	check_eq(_targets(_parse("4k3/8/8/2P5/3(BR)4/8/8/K7 w - - 0 1"), "d4"), ["c6", "d5", "d6", "e5", "e6"], "c5 alone doesn't block c6 (the way is d5, d6)")
	check_eq(_targets(_parse("4k3/8/3P4/8/3(BR)4/8/8/K7 w - - 0 1"), "d4"), ["c5", "d5", "e5"], "d6 blocks c6 and e6")
	check(_parse("8/8/2k5/8/3(BR)4/8/8/K7 b - - 0 1").is_in_check(), "Checks c6 with d5 and d6 empty")
	check(_parse("8/8/2k5/2P5/3(BR)4/8/8/K7 b - - 0 1").is_in_check(), "...a piece on c5 is no block")
	check(not _parse("8/8/2k5/3p4/3(BR)4/8/8/K7 b - - 0 1").is_in_check(), "...a piece on d5 is")

# --- Checking the two ways of finding attacks agree --------------------------------------

## For every black piece, "is its square attacked by White?" must match "can a
## white piece actually capture it?". The first walks lines back from the square;
## the second generates moves forward from the pieces.
func test_attack_detection_matches_captures() -> void:
	var positions := [
		"r3k2r/1(RO)1(CV)2W1/2p(BR)2n1/1(CH)1q4/3P(CV)1b1/p(RO)3P2/1W1p2B1/R3K2R w - - 0 1",
		"4k3/2n1p3/1b3W2/3(RO)P3/2(CV)1q1(BR)1/8/1(CH)2N3/4K3 w - - 0 1",
		"(ch)2qk2r/2(ro)1(cv)p2/1n(br)1p3/W2PP1(BR)1/2(CV)3n1/1p1(RO)2(CH)1/3w4/4K3 w - - 0 1",
	]
	for fen in positions:
		var state := _parse(fen)
		check(state != null, "Parses: " + fen)
		if state == null:
			continue
		var captured := {}
		for move in MoveGenerator.pseudo_legal_moves(state):
			if move.is_capture():
				captured[move.capture_square] = true
		for square: Vector2i in state.board.pieces_of(Piece.Team.BLACK):
			check_eq(MoveGenerator.is_attacked(state.board, square, Piece.Team.WHITE), captured.has(square),
					"%s on %s" % [state.board.get_piece(square).def.id, Board.square_name(square)])

# --- The piece card ----------------------------------------------------------------------

func test_cards_show_the_new_moves() -> void:
	var wizard := PieceGuide.guide(_def("wizard"))
	check_eq(wizard.slides.size(), 8, "Wizard: eight lines")
	check(wizard.slides.all(func(s: Array) -> bool: return s[2] == 3), "Its arrows start after the jump square")
	check(wizard.squares.has(Vector2i(0, 2)) and wizard.squares[Vector2i(0, 2)] & PieceGuide.JUMP, "Jump mark two squares away")
	check(not wizard.squares.has(Vector2i(0, 1)), "Nothing next to it")
	var cavalry := PieceGuide.guide(_def("cavalry"))
	check_eq(cavalry.squares.size(), 12, "Cavalry: twelve squares")
	check(cavalry.squares[Vector2i(2, 1)] & PieceGuide.JUMP == 0, "Its L moves aren't jumps")
	var rogue := PieceGuide.guide(_def("rogue"))
	check(rogue.squares[Vector2i(0, 2)] & PieceGuide.JUMP, "Rogue: hop squares are jump marks")
	check_eq(PieceGuide.guide(_def("berserker")).squares.size(), 6, "Berserker: six squares")
