extends TestSuite

## The third batch of custom pieces (Mac's designs, Oct 2026).

func _game(fen: String) -> GameState:
	return Fen.parse(fen, PieceCatalog.all_defs(), StandardSetup.create_rules())

## Where the piece on `from` can go: "d4-e5" style moves (a capture is "x").
func _targets(state: GameState, from: String) -> Array:
	var square := Board.parse_square(from)
	var found := []
	for move in state.moves():
		if move.from == square:
			found.append(Board.square_name(move.to) + ("x" if move.is_capture() else ""))
	found.sort()
	return found

func _def(id: String) -> PieceDef:
	return PieceCatalog.all_defs().filter(func(d: PieceDef) -> bool: return d.id == id)[0]

func test_costs_and_symbols() -> void:
	check_eq([_def("princess").value, _def("galleon").value, _def("catapult").value, _def("assassin").value], [8.5, 3.0, 3.0, 0.5], "Costs (Mac, Oct 2026: Princess 8.5, was 7; Galleon 3, was 4.5; Assassin 0.5, was 2)")
	var symbols := PieceCatalog.all_defs().map(func(d: PieceDef) -> String: return d.symbol)
	for symbol: String in symbols:
		check_eq(symbols.count(symbol), 1, "Symbol %s is unique" % symbol)

func test_princess_slides_up_to_four() -> void:
	var state := _game("k7/8/8/8/3(PR)4/8/8/7K w - - 0 1")
	var targets := _targets(state, "d4")
	check("h8" in targets and "d8" in targets and "a1" in targets, "Reaches 4 away: %s" % [targets])
	check_eq(targets.size(), 27, "8 directions, up to 4 squares (fewer near the edge)")
	state = _game("7k/8/8/8/8/8/8/(PR)6K w - - 0 1")
	targets = _targets(state, "a1")
	check("a5" in targets and not "a6" in targets, "No further than 4")

func test_galleon_moves_like_a_queen_captures_close() -> void:
	var state := _game("k7/8/8/3p4/2p(GA)p3/2p1p3/8/7K w - - 0 1")
	var targets := _targets(state, "d4")
	check("c4x" in targets and "e4x" in targets, "Captures sideways")
	check("c3x" in targets and "e3x" in targets, "Captures diagonally (backwards too)")
	check(not "d5x" in targets, "Can't capture straight ahead")
	state = _game("k7/8/8/8/3(GA)4/8/8/7K w - - 0 1")
	check("d8" in _targets(state, "d4") and "h8" in _targets(state, "d4"), "Moves like a queen")

func test_catapult_steps_and_throws() -> void:
	var state := _game("k7/8/3p4/3p4/3(CT)4/8/8/7K w - - 0 1")
	var targets := _targets(state, "d4")
	check("d6x" in targets, "Captures 2 away, over a piece in between")
	check(not "d5x" in targets, "Can't capture next to it")
	check("c4" in targets and "e5" in targets, "Steps like a king")
	check(_def("catapult").has_jump(), "Jump keyword")

func test_assassin_moves_forward_captures_back() -> void:
	var state := _game("k7/8/8/8/3(AS)4/2ppp3/8/7K w - - 0 1")
	var targets := _targets(state, "d4")
	check_eq(targets, ["c3x", "c5", "d3x", "d5", "d6", "e3x", "e5"], "Up to 2 forward, 1 diagonally forward; captures the 3 squares behind")
	state = _game("k7/8/8/3p4/3(AS)4/8/8/7K w - - 0 1")
	check(not "d6" in _targets(state, "d4"), "Forward move is blocked")

# --- Batch 2: Parapet, Vampire, Squire, Jester -----------------------------------

func _has_move(state: GameState, text: String) -> bool:
	return state.find_move(text) != null

func test_parapet_stops_knights_two_straight_then_one() -> void:
	var state := _game("k7/8/8/8/8/8/8/1N5K w - - 0 1")
	check_eq(_targets(state, "b1"), ["a3", "c3", "d2"], "A free knight")
	state = _game("k7/8/8/8/8/8/1(pa)6/1N5K w - - 0 1")
	check_eq(_targets(state, "b1"), ["d2"], "An enemy Parapet on b2: a3 and c3 pass over it (b2, b3 first)")
	state = _game("k7/8/8/8/8/8/1(PA)6/1N5K w - - 0 1")
	check_eq(_targets(state, "b1"), ["a3", "c3", "d2"], "Your own Parapet doesn't stop your Knight (Mac)")
	state = _game("k7/8/8/8/8/8/8/1N(pa)4K w - - 0 1")
	check(not "d2" in _targets(state, "b1"), "An enemy Parapet on c1 stops b1-d2 (c1, d1 first)")

func test_parapet_stops_leaps() -> void:
	var state := _game("k7/8/8/8/8/8/3(pa)4/2E4K w - - 0 1")
	check(not "e3" in _targets(state, "c1"), "Elephant can't jump over an enemy Parapet")
	state = _game("k7/8/8/8/8/3(pa)4/8/3W3K w - - 0 1")
	check(not "d4" in _targets(state, "d1"), "Wizard can't leap it")
	state = _game("k7/8/8/8/8/8/3(PA)4/2E4K w - - 0 1")
	check("e3" in _targets(state, "c1"), "But it can jump its own side's")

func test_parapet_is_no_screen() -> void:
	var state := _game("r6k/8/8/8/P7/8/8/C6K w - - 0 1")
	check("a8x" in _targets(state, "a1"), "A pawn is a screen")
	state = _game("r6k/8/8/8/(pa)7/8/8/C6K w - - 0 1")
	check(not "a8x" in _targets(state, "a1"), "An enemy Parapet isn't")
	state = _game("r6k/8/8/8/(PA)7/8/8/C6K w - - 0 1")
	check("a8x" in _targets(state, "a1"), "Your own Parapet is")

func test_parapet_blocks_check() -> void:
	check(_game("4k3/8/8/8/8/3n4/8/4K3 w - - 0 1").is_in_check(), "The knight on d3 checks e1")
	check(not _game("4k3/8/8/8/8/3n4/3(PA)4/4K3 w - - 0 1").is_in_check(), "Not over White's Parapet on d2")
	check(_game("4k3/8/8/8/8/3n4/3(pa)4/4K3 w - - 0 1").is_in_check(), "But Black's own Parapet doesn't stop its Knight")

func test_vampire_gains_a_shield_by_capturing() -> void:
	var state := _game("k7/8/8/8/4p3/3V4/8/7K w - - 0 1")
	var vampire := state.board.get_piece(Board.parse_square("d3"))
	check(not vampire.has_active_shield(), "No shield to start with")
	var move := state.find_move("d3xe4")
	state.make_move(move)
	check(vampire.has_active_shield(), "Shield after capturing")
	check(Fen.write(state).contains("V+"), "Saved in positions: " + Fen.write(state))
	check(Fen.parse(Fen.write(state), PieceCatalog.all_defs(), StandardSetup.create_rules()).board.get_piece(Board.parse_square("e4")).gained_shield, "And read back")
	state.undo_move(move)
	check(not vampire.has_active_shield(), "Undo takes it away")

func test_vampire_shield_breaks_like_a_paladin() -> void:
	var state := _game("k3r3/8/8/8/4V+3/8/8/7K b - - 0 1")
	var vampire := state.board.get_piece(Board.parse_square("e4"))
	var hit := state.find_move("e8xe4")
	check(hit != null and hit.breaks_shield(), "The first capture only breaks the shield")
	state.make_move(hit)
	check(not vampire.has_active_shield(), "Shield gone")
	check(state.board.get_piece(Board.parse_square("e4")) == vampire, "Vampire still there")
	state.undo_move(hit)
	check(vampire.has_active_shield(), "Undo puts it back")

func test_squire_protects_knights() -> void:
	var state := _game("k7/8/8/b7/8/2N5/8/7K b - - 0 1")
	check(_has_move(state, "a5xc3"), "Without a Squire the knight can be taken")
	state = _game("k7/8/8/b7/8/2N5/8/2(SQ)4K b - - 0 1")
	check(not _has_move(state, "a5xc3"), "With a Squire 2 squares away, it can't")
	state = _game("k7/8/8/b7/8/2N5/2P5/2(SQ)4K b - - 0 1")
	check(not _has_move(state, "a5xc3"), "...even with a piece in between (Mac: anywhere in its move range)")
	state = _game("k7/8/8/b7/8/2N5/8/4(SQ)2K b - - 0 1")
	check(_has_move(state, "a5xc3"), "Out of its range (e1 to c3 is no Squire move): takeable")
	check(PlusfishLink.supports(state), "Plusfish knows the Squire's rule (eval_bar_test checks the real engine)")

func test_jester_takes_the_hit() -> void:
	var state := _game("k7/2b5/8/4R3/3J4/8/8/7K b - - 0 1")
	var rook := state.board.get_piece(Board.parse_square("e5"))
	var jester := state.board.get_piece(Board.parse_square("d4"))
	var move := state.find_move("c7xe5")
	check(move != null and move.captured == jester, "Capturing the rook takes the Jester instead")
	state.make_move(move)
	check_eq(state.board.get_piece(Board.parse_square("d4")), rook, "The rook moved to the Jester's square")
	check_eq(state.board.get_piece(Board.parse_square("e5")).def.id, "bishop", "The bishop took the Jester on e5")
	check(state.lost[Piece.Team.WHITE].has(jester), "The Jester is lost")
	state.undo_move(move)
	check_eq(state.board.get_piece(Board.parse_square("e5")), rook, "Undo: rook back")
	check_eq(state.board.get_piece(Board.parse_square("d4")), jester, "Undo: Jester back")
	state = _game("k7/2b5/8/4P3/3J4/8/8/7K b - - 0 1")
	check_eq(state.find_move("c7xe5").captured.def.id, "pawn", "Pawns aren't swapped")

## Two White Jesters (d4, f4) that could both take the hit on the rook (e5).
const TWO_JESTERS := "k7/2b5/8/4R3/3J1J2/8/8/7K b - - 0 1"

func test_attacker_chooses_which_jester_takes_the_hit() -> void:
	var state := _game(TWO_JESTERS)
	var rook := state.board.get_piece(Board.parse_square("e5"))
	var d4_jester := state.board.get_piece(Board.parse_square("d4"))
	var f4_jester := state.board.get_piece(Board.parse_square("f4"))
	var via_d4 := state.find_move("c7xe5/d4")
	var via_f4 := state.find_move("c7xe5/f4")
	check(via_d4 != null and via_f4 != null, "One capture per Jester, named by its square")
	check(via_d4.captured == d4_jester and via_f4.captured == f4_jester, "Each takes its own Jester")
	check_eq(state.moves().filter(func(m: Move) -> bool: return m.to == Board.parse_square("e5")).size(), 2, "Just those two")
	state.make_move(via_f4)
	check_eq(state.board.get_piece(Board.parse_square("f4")), rook, "The rook went to the f4 Jester's square")
	check_eq(state.board.get_piece(Board.parse_square("d4")), d4_jester, "The other Jester stays")
	check(state.lost[Piece.Team.WHITE].has(f4_jester), "The chosen Jester is lost")
	state.undo_move(via_f4)
	check_eq(state.board.get_piece(Board.parse_square("e5")), rook, "Undo: rook back")
	check_eq(state.board.get_piece(Board.parse_square("f4")), f4_jester, "Undo: Jester back")
	# Saved before the choice existed (no Jester named): the first one, as then.
	check(state.find_move("c7xe5") != null and state.find_move("c7xe5").decoy_choice, "Old move text still loads")
	# Notation names the Jester too.
	check_eq(Notation.san(state, via_d4), "Bxe5/d4", "SAN")
	check_eq(Notation.find_move(state, "Bxe5/f4").decoy_square, Board.parse_square("f4"), "Found by SAN")
	var picture := Notation.picture(state, via_d4)
	check(picture.has({"text": "d4"}) and picture.any(func(p: Dictionary) -> bool: return p.get("piece") == d4_jester.def),
		"The picture shows the Jester and its square")
	# Only one Jester able to: nothing to choose, nothing extra written.
	state = _game("k7/2b5/8/4R3/3J4/8/8/7K b - - 0 1")
	check(not state.find_move("c7xe5").decoy_choice, "One Jester: no choice")
	check(_def("jester").special_rule.ends_with("If more than one Jester could take the hit, the attacking player chooses which."),
		"The Jester's card says so (Mac's words)")

func test_tapping_the_jester_to_take_the_hit() -> void:
	var view := BoardView.new()
	view.show_game(_game(TWO_JESTERS))
	view.size = Vector2(800, 800)
	var chosen: Array[Move] = []
	view.move_chosen.connect(func(move: Move) -> void: chosen.append(move))
	view.tap(Board.parse_square("c7"))
	check(view.tap(Board.parse_square("e5")), "Tapping the rook...")
	check(chosen.is_empty(), "...doesn't move yet")
	check_eq(view.jester_choices.size(), 2, "...it waits for a Jester to be picked")
	view.tap(Board.parse_square("f4"))
	check_eq(chosen.size(), 1, "Tapping a Jester plays the capture")
	if chosen.size() == 1:
		check_eq(chosen[0].decoy_square, Board.parse_square("f4"), "...with that Jester")
	check(view.jester_choices.is_empty(), "Done choosing")
	view.tap(Board.parse_square("c7"))
	view.tap(Board.parse_square("e5"))
	view.tap(Board.parse_square("h8"))
	check_eq(chosen.size(), 1, "Tapping anywhere else calls the capture off")
	check(view.jester_choices.is_empty(), "...and stops choosing")
	view.free()

func test_plusfish_knows_the_attacker_chooses_the_jester() -> void:
	check(PlusfishLink.supports(_game(TWO_JESTERS)), "Two Jesters on one side: the eval bar still works")

func test_jester_swap_animates_and_plusfish_knows_it() -> void:
	var state := _game("k7/2b5/8/4R3/3J4/8/8/7K b - - 0 1")
	var jester := state.board.get_piece(Board.parse_square("d4"))
	check(PlusfishLink.supports(state), "Plusfish knows the Jester's rule")
	check(PlusfishLink.supports(StandardSetup.create_game()), "And standard chess")
	var move := state.find_move("c7xe5")
	state.make_move(move)
	var animation := MoveAnimation.for_move(move, state, false)
	check(animation.has_segment(jester, "dash"), "The Jester flashes into the way")
	check(animation.has_segment(jester, "burst"), "And bursts like a balloon")
	check(animation.has_extra("confetti"), "In a shower of confetti")
	check(animation.has_segment(move.decoy_piece, "dash"), "The rook flashes to the Jester's square")
	check(GameSounds.Sound.GIGGLE in animation.all_sounds() and GameSounds.Sound.POP in animation.all_sounds(), "A giggle, then a pop")

# --- Parapets and Squires react when they stop a move (Mac, Oct 2026) ---------------

func test_blocker_finds_the_parapet_or_squire() -> void:
	var state := _game("4k3/8/8/8/R2(pa)4/8/8/4K3 w - - 0 1")
	check_eq(MoveGenerator.blocker(state, Board.parse_square("a4"), Board.parse_square("h4")), Board.parse_square("d4"), "A Parapet in the Rook's way")
	check_eq(MoveGenerator.blocker(state, Board.parse_square("a4"), Board.parse_square("b5")), Board.NO_SQUARE, "Rooks can't go diagonally anyway")
	state = _game("4k3/8/8/8/8/8/1(pa)6/1N2K3 w - - 0 1")
	check_eq(MoveGenerator.blocker(state, Board.parse_square("b1"), Board.parse_square("c3")), Board.parse_square("b2"), "A Knight can't leap an enemy Parapet")
	state = _game("r6k/8/8/8/(pa)7/8/8/C6K w - - 0 1")
	check_eq(MoveGenerator.blocker(state, Board.parse_square("a1"), Board.parse_square("a8")), Board.parse_square("a4"), "Nor can a Cannon fire over one (Mac)")
	state = _game("k7/4(sq)3/8/4n3/8/8/8/K3R3 w - - 0 1")
	check_eq(MoveGenerator.blocker(state, Board.parse_square("e1"), Board.parse_square("e5")), Board.parse_square("e7"), "The Squire protecting the Knight")

func test_tapping_a_blocked_square_thocks_and_pulses() -> void:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.start_fen = "4k3/8/8/8/R2(pa)4/8/8/4K3 w - - 0 1"
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	game.board_view.tap(Board.parse_square("a4"))
	game.board_view.tap(Board.parse_square("h4"))
	check_eq(game.sounds.last_played, GameSounds.Sound.BLOCKED, "A thock, like hitting a wall")
	check(game.board_view._pulses.has(Board.parse_square("d4")), "The Parapet swells")
	game.board_view.tap(Board.parse_square("a4"))
	game.board_view.tap(Board.parse_square("b5"))
	check_eq(game.sounds.last_played, GameSounds.Sound.ILLEGAL, "Anywhere else it can't go: a buzz")
	game.free()

func test_aiming_whirrs_until_a_target_is_chosen() -> void:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.start_fen = "4k3/8/8/8/8/2n5/8/A3K3 w - - 0 1"
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	game.board_view.tap(Board.parse_square("a1"))
	game.use_ability()
	check(game.sounds.is_looping(), "A whirr while aiming")
	game.board_view.tap(Board.parse_square("c3"))
	check(not game.sounds.is_looping(), "It stops once the shot is taken")
	game.free()
