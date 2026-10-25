extends TestSuite

## Mac's three pawn-type pieces (25 Oct 2026): Grunt (GR, 1.5, Shield: moves
## and captures 1 forward, 2 on its first move), Abatis (AB, 1, Wall: 1 forward
## or back, 2 forward on its first move), Vassal (VS, 1: 1 forward or sideways,
## takes en passant sideways). All promote, any number per army.

const GRUNT = preload("res://data/pieces/grunt.tres")
const ABATIS = preload("res://data/pieces/abatis.tres")
const VASSAL = preload("res://data/pieces/vassal.tres")
const KING = preload("res://data/pieces/king.tres")

func _parse(text: String) -> GameState:
	return Fen.parse(text, PieceCatalog.all_defs(), StandardSetup.create_rules())

func _texts(state: GameState) -> Array:
	return state.moves().map(func(m: Move) -> String: return m.to_text())

func test_data() -> void:
	check(GRUNT.is_pawn_type() and GRUNT.has_shield() and GRUNT.symbol == "GR" and GRUNT.value == 1.5, "Grunt: Pawn type, Shield, GR, 1.5")
	check(ABATIS.is_pawn_type() and ABATIS.has_wall() and ABATIS.symbol == "AB" and ABATIS.value == 1.0, "Abatis: Pawn type, Wall, AB, 1")
	check(VASSAL.is_pawn_type() and VASSAL.keywords == 0 and VASSAL.symbol == "VS" and VASSAL.value == 1.0, "Vassal: Pawn type, VS, 1")
	var rules := StandardSetup.create_rules()
	for def: PieceDef in [GRUNT, ABATIS, VASSAL]:
		check_eq(Army.max_copies(def, rules), -1, def.display_name + ": any number per army")
		check(def.can_promote(), def.display_name + " promotes")
	check_eq(PieceCard.keyword_names(GRUNT), PackedStringArray(["Promote", "Shield"]), "Grunt keywords")
	check_eq(PieceCard.keyword_names(ABATIS), PackedStringArray(["Promote", "Wall"]), "Abatis keywords")
	check_eq(PieceCard.keyword_names(VASSAL), PackedStringArray(["Promote"]), "Vassal keywords")
	check_eq(GRUNT.special_rule, "On its first move, the Grunt can move 2 squares forward.", "Grunt text (Mac)")
	check_eq(ABATIS.special_rule, "On its first move, the Abatis can move 2 squares forward.", "Abatis text (Mac)")
	check_eq(VASSAL.special_rule, "", "The Vassal has no special rule text (Mac)")
	check_eq(PieceCard.EXPLANATIONS["Wall"], "The opponent's pieces can't jump over it.", "Wall bubble (Mac)")
	check_eq(PieceCard.EXPLANATIONS["Pawn"], "Any number per army. It can take part in en passant.", "Pawn bubble (Mac)")
	# Any number: a King and ten Vassals is a legal army.
	var army := Army.new()
	army.place(KING, Vector2i(4, 0))
	for file in range(8):
		army.place(VASSAL, Vector2i(file, 1))
	army.place(VASSAL, Vector2i(0, 0))
	army.place(VASSAL, Vector2i(7, 0))
	check(army.problems(rules, 8).is_empty(), "Ten Vassals are allowed: " + str(army.problems(rules, 8)))

func test_grunt_moves_and_captures_forward() -> void:
	# An unmoved Grunt on e2: e3, and the double step, which may capture (Mac).
	var state := _parse("4k3/8/8/8/4r3/8/4(GR)3/4K3 w - - 0 1")
	var texts := _texts(state)
	check(texts.has("e2-e3") and texts.has("e2xe4"), "Forward 1, and the double step takes the rook on e4: " + str(texts))
	check(not texts.has("e2xd3") and not texts.has("e2xf3") and not texts.has("e2-d2"), "Nothing diagonal or sideways")
	state.make_move(state.find_move("e2-e3"))
	check_eq(state.halfmove_clock, 0, "A pawn-type move resets the 50-move clock")
	state.make_move(state.find_move("e8-d8"))
	check(not _texts(state).has("e3-e5"), "No double step once it has moved")
	# A piece one square ahead: captured, not jumped.
	state = _parse("4k3/8/8/8/8/4r3/4(GR)3/4K3 w - - 0 1")
	texts = _texts(state)
	check(texts.has("e2xe3") and not texts.has("e2-e4"), "Takes the piece in front; can't jump it: " + str(texts))

func test_grunt_can_be_taken_en_passant_but_never_takes() -> void:
	var state := _parse("4k3/8/8/8/3p4/8/4(GR)3/4K3 w - - 0 1")
	state.make_move(state.find_move("e2-e4"))
	check_eq(state.en_passant_squares, [Vector2i(4, 2)] as Array[Vector2i], "The double step skips e3")
	var ep := state.find_move("d4xe3")
	check(ep != null and ep.capture_square == Vector2i(4, 3), "The Black pawn takes the Grunt en passant")
	state.make_move(ep)
	check(state.board.get_piece(Vector2i(4, 3)) == null, "The Grunt is gone")
	# A Black pawn double-steps past a White Grunt: it only captures straight ahead, so no en passant.
	state = _parse("4k3/3p4/8/4(GR)3/8/8/8/4K3 b - - 0 1")
	state.make_move(state.find_move("d7-d5"))
	check(not state.en_passant_squares.is_empty(), "d6 is skipped")
	check(_texts(state).filter(func(t: String) -> bool: return t.begins_with("e5x")).is_empty(), "The Grunt can't take en passant")

func test_grunt_shield_breaks_first() -> void:
	var state := _parse("4k3/8/8/2r5/8/8/2(GR)5/4K3 b - - 0 1")
	var hit := state.find_move("c5xc2")
	check(hit != null and hit.breaks_shield(), "The first hit only breaks the shield")
	state.make_move(hit)
	var grunt := state.board.get_piece(Board.parse_square("c2"))
	check(grunt != null and grunt.shield_broken, "The Grunt stays, shield broken")
	check(state.board.get_piece(Board.parse_square("c5")) != null, "The rook stays where it was")
	check(Fen.write(state).begins_with("4k3/8/8/2r5/8/8/2(GR)'5/4K3"), "FEN marks the broken shield: " + Fen.write(state))
	state.make_move(state.find_move("e1-d1"))
	var take := state.find_move("c5xc2")
	check(take != null and not take.breaks_shield(), "The second hit takes it")

func test_grunt_promotes() -> void:
	var state := _parse("4k3/2(GR)5/8/8/8/8/8/4K3 w - - 0 1")
	var texts := _texts(state)
	check(texts.has("c7-c8=Q"), "Promotes on the far rank (queen among the choices): " + str(texts))

func test_abatis_moves_forward_or_back() -> void:
	var state := _parse("4k3/8/8/8/8/8/3(AB)4/4K3 w - - 0 1")
	var texts := _texts(state)
	check(texts.has("d2-d3") and texts.has("d2-d4") and texts.has("d2-d1"), "1 forward, 2 forward (first move), 1 back: " + str(texts))
	check(not texts.has("d2-c2") and not texts.has("d2-e3"), "Not sideways or diagonal")
	state.make_move(state.find_move("d2-d4"))
	check_eq(state.en_passant_squares, [Vector2i(3, 2)] as Array[Vector2i], "The double step skips d3")
	state.make_move(state.find_move("e8-e7"))
	texts = _texts(state)
	check(texts.has("d4-d5") and texts.has("d4-d3") and not texts.has("d4-d6"), "After moving: one square each way")
	state = _parse("4k3/8/8/8/3(AB)4/3r4/8/4K3 w - - 0 1")
	check(_texts(state).has("d4xd3"), "Captures backwards too")

func test_abatis_is_a_wall() -> void:
	# A Black Elephant can't jump over a White Abatis; a White one can.
	var state := _parse("4k3/8/2e5/3(AB)4/8/8/8/4K3 b - - 0 1")
	var texts := _texts(state)
	check(not texts.has("c6-e4") and texts.has("c6-a4"), "The opponent's Elephant can't leap over it: " + str(texts))
	state = _parse("4k3/8/2E5/3(AB)4/8/8/8/4K3 w - - 0 1")
	check(_texts(state).has("c6-e4"), "Its own side's Elephant can")
	# No screen for the opponent's Cannon.
	state = _parse("3ck3/8/8/3(AB)4/8/8/3R4/4K3 b - - 0 1")
	check(not _texts(state).has("d8xd2"), "The Black Cannon can't fire over it")
	state = _parse("3ck3/8/8/3P4/8/8/3R4/4K3 b - - 0 1")
	check(_texts(state).has("d8xd2"), "...but can over a pawn")

func test_vassal_moves_forward_or_sideways() -> void:
	var state := _parse("4k3/8/8/8/3(VS)4/8/8/4K3 w - - 0 1")
	var texts := _texts(state)
	check(texts.has("d4-d5") and texts.has("d4-c4") and texts.has("d4-e4"), "Forward and sideways: " + str(texts))
	check(not texts.has("d4-d3") and not texts.has("d4-c5") and not texts.has("d4-d6"), "Not back, diagonal or two squares")
	state = _parse("4k3/8/8/8/2r(VS)r3/8/8/K7 w - - 0 1")
	texts = _texts(state)
	check(texts.has("d4xc4") and texts.has("d4xe4"), "Captures sideways: " + str(texts))
	state = _parse("4k3/8/8/8/3p4/8/4(VS)3/4K3 w - - 0 1")
	check(not _texts(state).has("e2-e4"), "Never a double step")

func test_vassal_takes_en_passant_sideways() -> void:
	# Black's pawn e7-e5 skips e6; the White Vassal on d6 steps sideways onto e6 and takes it.
	var state := _parse("4k3/4p3/3(VS)4/8/8/8/8/4K3 b - - 0 1")
	state.make_move(state.find_move("e7-e5"))
	var ep := state.find_move("d6xe6")
	check(ep != null and ep.capture_square == Vector2i(4, 4), "En passant onto the skipped square: " + str(_texts(state)))
	state.make_move(ep)
	check(state.board.get_piece(Vector2i(4, 4)) == null, "The pawn is gone")
	check(state.board.get_piece(Vector2i(4, 5)) != null and state.board.get_piece(Vector2i(4, 5)).def == VASSAL, "The Vassal stands on e6")
