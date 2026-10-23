extends TestSuite

## The eval bar for looking over a finished game: EvalBar's scale and text,
## the request PlusfishLink sends, the game screen showing it only once the
## game is over, and (when Plusfish has been built) the real engine.

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

func _frames(count: int) -> void:
	for i in count:
		await (Engine.get_main_loop() as SceneTree).process_frame

func _play_all(game: Node, moves: Array) -> void:
	for san in moves:
		game.play(Notation.find_move(game.state, san))

const FOOLS_MATE := ["f3", "e5", "g4", "Qh4#"]

func _open_game() -> Node:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	_root().add_child(game)
	game.board_view.move_time = 0.0
	return game

## The best move the screen names, "" for none: in the Top moves list
## ("Best: Nf3  (+0.4)") or, where that isn't shown, the status line ("best: Nf3").
func _named_best(game: Node) -> String:
	var status: String = game.status_label.text
	if status.contains("best: "):
		return status.get_slice("best: ", 1)
	var top: OptionButton = game.top_moves_button
	if game._top_row.visible and top.text.begins_with("Best: "):
		return top.text.trim_prefix("Best: ").get_slice("  (", 0)
	return ""

func _finish() -> void:
	PlusfishLink.enabled = false
	PlusfishLink.pretend_available = false

# --- EvalBar -------------------------------------------------------------------------

func test_bar_scale_and_text() -> void:
	var bar := EvalBar.new()
	check_eq(bar.score_text(), "...", "Unknown until evaluated")
	check_eq(bar.target(), 0.5, "Unknown sits in the middle")
	bar.set_score(0, null)
	check_eq(bar.score_text(), "0.0", "Level")
	check_eq(bar.target(), 0.5, "Level = half")
	bar.set_score(300, null)
	check_eq(bar.score_text(), "+3.0", "White better")
	check(bar.target() > 0.75 and bar.target() < 0.96, "Mostly White's: %s" % bar.target())
	bar.set_score(-150, null)
	check_eq(bar.score_text(), "-1.5", "Black better")
	check(bar.target() < 0.5, "Mostly Black's")
	bar.set_score(5000, null)
	check_eq(bar.target(), 0.96, "Never quite full without a mate")
	bar.set_score(19995, 3)
	check_eq(bar.score_text(), "M3", "White mates in 3")
	check_eq(bar.target(), 1.0, "Mate fills it")
	bar.set_score(-19997, -2)
	check_eq(bar.score_text(), "M2", "Black mates in 2")
	check_eq(bar.target(), 0.0, "Black's mate empties it")
	bar.set_score(-20000, 0, "0-1")
	check_eq(bar.score_text(), "0-1", "Game over shows the result")
	bar.set_score(0, null, "1/2-1/2")
	check_eq(bar.score_text(), "½", "Draw")
	bar.free()

# --- The request ----------------------------------------------------------------------

func test_request_describes_the_game() -> void:
	var start := ArmySetup.create_game(StandardSetup.army(), StandardSetup.army(), StandardSetup.create_rules())
	var request := PlusfishLink.request_for(start, ["e2-e4", "e7-e5"])
	var ids: Array = request["pieces"].map(func(p: Dictionary) -> String: return p["id"])
	for def in PieceCatalog.all_defs():
		check(ids.has(def.id), "Sends piece type " + def.id)
	check_eq(request["board"].size(), 32, "Every piece on the board")
	check(request["board"].has(["king", Piece.Team.BLACK, 4, 7, false, false, false, false]), "Black's king on e8, unmoved")
	check_eq(request["moves"], ["e2-e4", "e7-e5"], "The moves")
	check_eq(request["promo"].size(), 4, "Promotion choices from the armies")
	var pawn: Dictionary = request["pieces"][ids.find("pawn")]
	check_eq(pawn["rules"][0]["first_move_max_steps"], 2, "Move rules go with it")
	# JSON can carry it (no Godot-only values inside).
	check(JSON.parse_string(JSON.stringify(request)) is Dictionary, "Turns into JSON")

func test_request_mirrors_black_armies_as_the_game_does() -> void:
	var army := Army.new()
	army.place(load("res://data/pieces/king.tres"), Vector2i(4, 0))
	army.place(load("res://data/pieces/rook.tres"), Vector2i(0, 0))
	var start := ArmySetup.create_game(army, army, StandardSetup.create_rules())
	var board: Array = PlusfishLink.request_for(start, [])["board"]
	check(board.has(["rook", Piece.Team.BLACK, 7, 7, false, false, false, false]), "Black's rook where the game put it (h8)")

## A start with the new pieces' state: a Vampire's gained shield, a lost Ghost
## that can still Haunt, and a Werewolf (whose wolf form goes along too).
func _new_pieces_start() -> GameState:
	var start := Fen.parse("4k3/8/8/3v+4/8/8/(WW)7/4K2(BD) w - - 0 1", PieceCatalog.all_defs(), StandardSetup.create_rules())
	start.lost[Piece.Team.WHITE].append(Piece.new(load("res://data/pieces/ghost.tres"), Piece.Team.WHITE))
	return start

func test_request_carries_the_new_rules() -> void:
	var request := PlusfishLink.request_for(_new_pieces_start(), ["@e4"])
	var pieces := {}
	for p: Dictionary in request["pieces"]:
		pieces[p["id"]] = p
	check(pieces.has("werewolf_wolf"), "The wolf form is sent with the Werewolf")
	check_eq(pieces["werewolf"]["transforms_into"], "werewolf_wolf", "And linked to it")
	check_eq(pieces["parapet"]["blocks_jumps"], true, "The Parapet blocks jumps")
	check_eq(pieces["vampire"]["shield_on_capture"], true, "The Vampire gains shields")
	check_eq(pieces["squire"]["protects"], ["knight"], "The Squire protects knights")
	check_eq(pieces["jester"]["decoy"], true, "The Jester takes hits")
	check(request["board"].has(["vampire", Piece.Team.BLACK, 3, 4, false, false, false, true]), "The Vampire's gained shield")
	check_eq(request["lost"], [["ghost", Piece.Team.WHITE, false]], "The lost Ghost, Haunt unused")
	check(JSON.parse_string(JSON.stringify(request)) is Dictionary, "Turns into JSON")

# --- The game screen --------------------------------------------------------------------

func test_bar_during_the_game_only_when_chosen() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_game()
	game.eval_bar_on = true
	_play_all(game, ["e4"])
	check(game.eval_bar.visible, "Chosen: shown during the game")
	game.plusfish.results[1] = {"ply": 1, "cp": 30, "mate": null, "outcome": "none", "best": "e7-e5", "best_san": "e5"}
	game._on_evaluated(1, game.plusfish.results[1])
	check(game.eval_bar.known, "Shows the score")
	check(game.board_view.hint_arrow.is_empty(), "But no best-move arrow while the game is on")
	check_eq(_named_best(game), "", "...and names no best move")
	game.free()
	PlusfishLink.pretend_available = false
	PlusfishLink.enabled = false

func test_best_move_live_in_testing_mode() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.testing_position = TestingPosition.standard()
	_root().add_child(game)
	game.board_view.move_time = 0.0
	check(game.live_best_move(), "Testing mode shows the best move while playing")
	_play_all(game, ["e4"])
	check(game.board_view.hint_arrow.is_empty(), "No arrow until Plusfish answers")
	game.plusfish.results[1] = {"ply": 1, "cp": 30, "mate": null, "outcome": "none", "best": "e7-e5", "best_san": "e5"}
	game._on_evaluated(1, game.plusfish.results[1])
	check_eq(game.board_view.hint_arrow, [Vector2i(4, 6), Vector2i(4, 4)], "Best move arrow e7-e5")
	check_eq(_named_best(game), "e5", "Names the best move")
	_play_all(game, ["e5"])
	check(game.board_view.hint_arrow.is_empty(), "The old arrow goes once a move is played")
	check_eq(_named_best(game), "", "...and so does the old best move")
	game.undo()
	check_eq(game.board_view.hint_arrow, [Vector2i(4, 6), Vector2i(4, 4)], "Undo: the known best move is back")
	game.plusfish.results[0] = {"ply": 0, "cp": 25, "mate": null, "outcome": "none", "best": "d2-d4", "best_san": "d4"}
	game.view_move(0)
	check_eq(game.board_view.hint_arrow, [Vector2i(3, 1), Vector2i(3, 3)], "Looking back: that position's best move")
	game.free()
	_finish()

func _open_bot_game(best_move: bool) -> Node:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.white_army = StandardSetup.army()
	game.black_army = StandardSetup.army()
	game.bot_team = Piece.Team.BLACK
	game.bot_level = PracticeBot.Level.EASY
	game.bot_delay_frames = 1
	game.bot_min_seconds = 0.0
	game.best_move_on = best_move
	_root().add_child(game)
	game.board_view.move_time = 0.0
	return game

## Play your move and wait (up to 5 s) for the bot's reply.
func _play_and_wait_for_bot(game: Node, san: String) -> void:
	var moves: int = game.state.history.size()
	game.play(Notation.find_move(game.state, san))
	var started := Time.get_ticks_msec()
	while game.state.history.size() < moves + 2 and Time.get_ticks_msec() - started < 5000:
		await _frames(1)

func test_best_move_against_the_bot_when_chosen() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_bot_game(true)
	check(game.live_best_move(), "Your turn: best move shown")
	game.play(Notation.find_move(game.state, "e4"))
	check(not game.live_best_move(), "Not while the bot is to move")
	game.plusfish.results[1] = {"ply": 1, "cp": 30, "mate": null, "outcome": "none", "best": "e7-e5", "best_san": "e5"}
	game._on_evaluated(1, game.plusfish.results[1])
	check(game.board_view.hint_arrow.is_empty(), "No arrow for the bot's move")
	check_eq(_named_best(game), "", "...and names none")
	var started := Time.get_ticks_msec()
	while game.state.history.size() < 2 and Time.get_ticks_msec() - started < 5000:
		await _frames(1)
	check_eq(game.state.history.size(), 2, "The bot answered")
	check(game.live_best_move(), "Your turn again")
	game.plusfish.results[2] = {"ply": 2, "cp": 40, "mate": null, "outcome": "none", "best": "g1-f3", "best_san": "Nf3"}
	game._on_evaluated(2, game.plusfish.results[2])
	check_eq(game.board_view.hint_arrow, [Vector2i(6, 0), Vector2i(5, 2)], "Best move arrow g1-f3")
	check_eq(_named_best(game), "Nf3", "Names the best move")
	game.view_move(1)
	check(game.live_best_move(), "Looking back: shown even where the bot was to move")
	check_eq(game.board_view.hint_arrow, [Vector2i(4, 6), Vector2i(4, 4)], "That position's best move")
	game.free()
	_finish()

func test_no_best_move_against_the_bot_unless_chosen() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_bot_game(false)
	await _play_and_wait_for_bot(game, "e4")
	check_eq(game.state.history.size(), 2, "The bot answered")
	check(not game.live_best_move(), "Not chosen: no best move")
	game.plusfish.results[2] = {"ply": 2, "cp": 40, "mate": null, "outcome": "none", "best": "g1-f3", "best_san": "Nf3"}
	game._on_evaluated(2, game.plusfish.results[2])
	check(game.eval_bar.known, "The eval bar still shows against the bot")
	check(game.board_view.hint_arrow.is_empty(), "But no arrow")
	check_eq(_named_best(game), "", "...and names no best move")
	game.free()
	_finish()

func test_switches_during_a_bot_game() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_bot_game(false)
	await _play_and_wait_for_bot(game, "e4")
	check(game.hint_toggles.visible, "Switches shown against the bot")
	check(game.eval_toggle.button_pressed, "Eval bar starts on")
	check(not game.best_move_toggle.button_pressed, "Best move starts off")
	game.plusfish.results[2] = {"ply": 2, "cp": 40, "mate": null, "outcome": "none", "best": "g1-f3", "best_san": "Nf3"}
	game._on_evaluated(2, game.plusfish.results[2])
	check(game.board_view.hint_arrow.is_empty(), "No arrow yet")
	game.best_move_toggle.button_pressed = true
	check(game.best_move_on, "Best move switched on")
	check_eq(game.board_view.hint_arrow, [Vector2i(6, 0), Vector2i(5, 2)], "Arrow straight away")
	check_eq(_named_best(game), "Nf3", "And names it")
	game.eval_toggle.button_pressed = false
	check(not game.eval_bar.visible, "Eval bar switched off")
	check(is_equal_approx(game._board_area.ratio, 1.0), "Board area back to square")
	check_eq(game.board_view.hint_arrow, [Vector2i(6, 0), Vector2i(5, 2)], "Best move still shown without the bar")
	var saved := SavedGame.load_saved()
	check(saved != null and saved.best_move and saved.eval_bar_hidden, "Both switches saved with the game")
	game.best_move_toggle.button_pressed = false
	check(game.board_view.hint_arrow.is_empty(), "Best move switched off: arrow gone")
	check_eq(_named_best(game), "", "...and names none")
	game.eval_toggle.button_pressed = true
	check(game.eval_bar.visible, "Eval bar back on")
	game.free()
	SavedGame.delete_saved()
	_finish()

func test_no_switches_for_two_players() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_game()
	game.eval_bar_on = true
	_play_all(game, ["e4"])
	check(not game.hint_toggles.visible, "Two players: no switches")
	game.free()
	_finish()

func test_best_move_choice_is_saved_with_the_game() -> void:
	SavedGame.delete_saved()
	var game := _open_bot_game(true)
	await _play_and_wait_for_bot(game, "e4")
	var saved := SavedGame.load_saved()
	check(saved != null and saved.best_move, "Saved with the game")
	game.free()
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	_root().add_child(main)
	main.continue_game()
	check(main.screen.best_move_on, "Continuing keeps it on")
	check(not main.screen.eval_bar_hidden, "And the eval bar as it was")
	main.free()
	SavedGame.delete_saved()

func _def(id: String) -> PieceDef:
	for def in PieceCatalog.all_defs():
		if def.id == id:
			return def
	return null

## Kings on a1 and h8, a White pawn on b7 and a Black one on g2, a White Rook
## on h1 and a Black Queen on h5 (pawns promote to types on the board), a White
## Necromancer on d2 with a lost Queen and Rook, and a Black Necromancer on f7
## with a lost Bishop.
func _promotion_position(to_move: Piece.Team) -> TestingPosition:
	var position := TestingPosition.new()
	position.place(Board.parse_square("a1"), _def("king"), Piece.Team.WHITE)
	position.place(Board.parse_square("h8"), _def("king"), Piece.Team.BLACK)
	position.place(Board.parse_square("b7"), _def("pawn"), Piece.Team.WHITE)
	position.place(Board.parse_square("g2"), _def("pawn"), Piece.Team.BLACK)
	position.place(Board.parse_square("d2"), _def("necromancer"), Piece.Team.WHITE)
	position.place(Board.parse_square("f7"), _def("necromancer"), Piece.Team.BLACK)
	position.place(Board.parse_square("h1"), _def("rook"), Piece.Team.WHITE)
	position.place(Board.parse_square("h5"), _def("queen"), Piece.Team.BLACK)
	position.captured.append([_def("queen"), Piece.Team.WHITE])
	position.captured.append([_def("rook"), Piece.Team.WHITE])
	position.captured.append([_def("bishop"), Piece.Team.BLACK])
	position.side_to_move = to_move
	return position

func _open_testing_game(position: TestingPosition) -> Node:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.testing_position = position
	_root().add_child(game)
	game.board_view.move_time = 0.0
	return game

func _hand_in_best(game: Node, ply: int, best: String, best_san: String) -> void:
	game.plusfish.results[ply] = {"ply": ply, "cp": 500, "mate": null, "outcome": "none", "best": best, "best_san": best_san}
	game._on_evaluated(ply, game.plusfish.results[ply])

func test_best_move_shows_what_a_pawn_promotes_to() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_testing_game(_promotion_position(Piece.Team.WHITE))
	check(game.state.find_move("b7-b8=R") != null, "The position allows the promotion")
	check(game.testing_position.problems().is_empty(), "A fine position: %s" % [game.testing_position.problems()])
	_hand_in_best(game, 0, "b7-b8=R", "b8=R")
	check_eq(game.board_view.hint_arrow, [Board.parse_square("b7"), Board.parse_square("b8")], "Arrow to the promotion square")
	var hint: Dictionary = game.board_view.hint_piece
	check_eq(hint.get("square"), Board.parse_square("b8"), "Badge on the promotion square")
	check(hint.get("def") == _def("rook"), "Showing the Rook to promote to")
	check_eq(hint.get("team"), Piece.Team.WHITE, "A White Rook")
	check(not hint.get("ring", true), "No ring: the arrow shows which piece")
	_hand_in_best(game, 0, "d2-e3", "NCe3")
	check(game.board_view.hint_piece.is_empty(), "An ordinary move has no badge")
	game.free()
	_finish()

func test_best_move_shows_what_raise_dead_brings_back() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_testing_game(_promotion_position(Piece.Team.BLACK))
	check(game.state.find_move("f7!=B") != null, "Black's Necromancer can raise the Bishop")
	_hand_in_best(game, 0, "f7!=B", "NC!=B")
	check(game.board_view.hint_arrow.is_empty(), "Raise Dead has no arrow")
	var hint: Dictionary = game.board_view.hint_piece
	check_eq(hint.get("square"), Board.parse_square("f7"), "Badge on the Necromancer's square")
	check(hint.get("def") == _def("bishop"), "Showing the Bishop it brings back")
	check_eq(hint.get("team"), Piece.Team.BLACK, "A Black Bishop: the side to move")
	check(hint.get("ring", false), "A ring marks the Necromancer")
	game.play(game.state.find_move("g2-g1=Q"))
	check(game.board_view.hint_piece.is_empty(), "Gone once a move is played")
	game.free()
	_finish()

func test_bar_only_after_the_game() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_game()
	_play_all(game, ["f3", "e5"])
	check(not game.eval_bar.visible, "No bar during the game")
	game.view_move(1)
	check(not game.eval_bar.visible, "Not even when looking back mid-game")
	game.back_to_game()
	_play_all(game, ["g4", "Qh4#"])
	check(game.eval_bar.visible, "Bar once it's over")
	check(game._board_area.ratio > 1.0, "Board area widens for it")
	check(not game.eval_bar.known, "Waiting for Plusfish")
	# Hand in Plusfish's answers (the real engine is tested below).
	game.plusfish.results[4] = {"ply": 4, "cp": -20000, "mate": 0, "outcome": "checkmate", "best": "", "best_san": ""}
	game._on_evaluated(4, game.plusfish.results[4])
	check(game.eval_bar.known, "Final position known")
	check_eq(game.eval_bar.score_text(), "0-1", "Shows the result")
	game.view_move(3)
	check(not game.eval_bar.known, "Earlier position not known yet")
	game.plusfish.results[3] = {"ply": 3, "cp": -19999, "mate": -1, "outcome": "none", "best": "d8-h4", "best_san": "Qh4#"}
	game._on_evaluated(3, game.plusfish.results[3])
	check_eq(game.eval_bar.score_text(), "M1", "Mate in one for Black")
	check_eq(game.board_view.hint_arrow, [Vector2i(3, 7), Vector2i(7, 3)], "Best move arrow d8-h4")
	check_eq(_named_best(game), "Qh4#", "Names the best move")
	game.undo()
	check(not game.eval_bar.visible, "Undo: game on again, bar gone")
	check_eq(game.board_view.hint_arrow, [], "Arrow gone too")
	game.free()
	_finish()

func test_bar_follows_the_board_round() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game := _open_game()
	game.board_view.flipped = true
	_play_all(game, FOOLS_MATE)
	check(game.eval_bar.flipped, "White's end at the top when Black is at the bottom")
	game.free()
	_finish()

# --- The real engine (only if Plusfish has been built) -------------------------------------

func test_real_engine_finds_the_mate() -> void:
	if PlusfishLink.program_path() == "" or OS.has_feature("web"):
		print("    (Plusfish not built: cargo build --release in engine/plusfish to run this test)")
		return
	PlusfishLink.enabled = true
	var game := _open_game()
	game.plusfish.desktop_nodes = 20000
	_play_all(game, FOOLS_MATE)
	# Wait (up to ~20 s) for every position.
	for i in 2000:
		if game.plusfish.results.size() == 5:
			break
		await _frames(1)
		OS.delay_msec(10)
	check_eq(game.plusfish.results.size(), 5, "All five positions evaluated")
	var before_mate: Dictionary = game.plusfish.results.get(3, {})
	check_eq(before_mate.get("best"), "d8-h4", "Plusfish finds Qh4#")
	check_eq(before_mate.get("mate"), -1.0, "Black mates in 1")
	var start: Dictionary = game.plusfish.results.get(0, {})
	check(absi(int(start.get("cp", 999))) < 100, "Start position about level: %s" % start.get("cp"))
	check_eq(game.plusfish.results.get(4, {}).get("outcome"), "checkmate", "Final position is mate")
	game.view_move(3)
	check(game.eval_bar.known and game.eval_bar.score_text() == "M1", "Bar shows the mate")
	game.free()
	_finish()

func test_real_engine_shows_the_best_move_live_in_testing_mode() -> void:
	if PlusfishLink.program_path() == "" or OS.has_feature("web"):
		print("    (Plusfish not built: cargo build --release in engine/plusfish to run this test)")
		return
	PlusfishLink.enabled = true
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.testing_position = TestingPosition.standard()
	_root().add_child(game)
	game.board_view.move_time = 0.0
	game.plusfish.desktop_nodes = 20000
	_play_all(game, ["f3", "e5", "g4"])
	# Wait (up to ~20 s) for the newest position.
	for i in 2000:
		if not game.board_view.hint_arrow.is_empty():
			break
		await _frames(1)
		OS.delay_msec(10)
	check_eq(game.board_view.hint_arrow, [Vector2i(3, 7), Vector2i(7, 3)], "Arrow for Qh4# while the game is on")
	check_eq(_named_best(game), "Qh4#", "Names it")
	game.free()
	_finish()

func test_real_engine_follows_the_new_abilities() -> void:
	if PlusfishLink.program_path() == "" or OS.has_feature("web"):
		print("    (Plusfish not built: cargo build --release in engine/plusfish to run this test)")
		return
	# Haunt, a capture of the Ghost by the shielded Vampire, Full Moon, then
	# Song of Slumber: Plusfish must replay every one to evaluate each position.
	var start := _new_pieces_start()
	var moves := ["@e4", "d5xe4", "a2!", "e8-d8", "h1~e4"]
	var replay := _new_pieces_start()
	for text: String in moves:
		var move := replay.find_move(text)
		check(move != null, "The game allows " + text)
		replay.make_move(move)
	PlusfishLink.enabled = true
	var link := PlusfishLink.new()
	_root().add_child(link)
	link.desktop_nodes = 5000
	link.analyse(start, moves)
	for i in 2000:
		if link.results.size() == moves.size() + 1:
			break
		await _frames(1)
		OS.delay_msec(10)
	check_eq(link.results.size(), moves.size() + 1, "Every position evaluated")
	check(str(link.results.get(0, {}).get("best", "")) != "", "A best move at the start")
	link.free()
	_finish()

func test_real_engine_knows_the_parapet_rule() -> void:
	if PlusfishLink.program_path() == "" or OS.has_feature("web"):
		print("    (Plusfish not built: cargo build --release in engine/plusfish to run this test)")
		return
	# Mac (Oct 2026): a Parapet only stops the opponent's jumps. The Knight
	# jumps over its own Parapet on b2, which Plusfish must accept to go on.
	var start := Fen.parse("k7/8/8/8/8/8/1(PA)6/1N5K w - - 0 1", PieceCatalog.all_defs(), StandardSetup.create_rules())
	check(PlusfishLink.supports(start), "The eval bar works with Parapets")
	var moves := ["b1-c3", "a8-b8"]
	PlusfishLink.enabled = true
	var link := PlusfishLink.new()
	_root().add_child(link)
	link.desktop_nodes = 5000
	link.analyse(start, moves)
	for i in 2000:
		if link.results.size() == moves.size() + 1:
			break
		await _frames(1)
		OS.delay_msec(10)
	check_eq(link.results.size(), moves.size() + 1, "Plusfish follows a Knight over its own Parapet")
	link.free()
	_finish()

func test_real_engine_knows_the_squire_and_berserker_rules() -> void:
	if PlusfishLink.program_path() == "" or OS.has_feature("web"):
		print("    (Plusfish not built: cargo build --release in engine/plusfish to run this test)")
		return
	# Mac (Oct 2026): a Squire protects Knights anywhere in its move pattern,
	# even with a piece in between (c2 here), so the free-looking Knight on
	# c3 can't be taken. And the Berserker's L-moves go 2 straight then 1
	# sideways: d4 to c6 passes d5 and d6, so the pawn on c5 is no block.
	var start := Fen.parse("k7/8/8/b1P5/3(BR)4/2N5/2P5/2(SQ)4K b - - 0 1", PieceCatalog.all_defs(), StandardSetup.create_rules())
	check(start.find_move("a5xc3") == null, "The game doesn't allow a5xc3")
	var moves := ["a8-b8", "d4-c6"]
	PlusfishLink.enabled = true
	var link := PlusfishLink.new()
	_root().add_child(link)
	link.desktop_nodes = 5000
	link.analyse(start, moves)
	for i in 2000:
		if link.results.size() == moves.size() + 1:
			break
		await _frames(1)
		OS.delay_msec(10)
	check_eq(link.results.size(), moves.size() + 1, "Plusfish follows the Berserker's d4-c6")
	check(str(link.results.get(0, {}).get("best", "")) not in ["", "a5xc3"], "Plusfish doesn't take the protected Knight")
	link.free()
	_finish()

func test_real_engine_lets_the_attacker_choose_the_jester() -> void:
	if PlusfishLink.program_path() == "" or OS.has_feature("web"):
		print("    (Plusfish not built: cargo build --release in engine/plusfish to run this test)")
		return
	# Mac (Oct 2026): if more than one Jester could take the hit, the attacker
	# chooses which, and the move names it ("c7xe5/f4"). Plusfish must read
	# that to go on, and name its own best move the same way.
	# TWO_JESTERS in third_batch_test.gd: the Bishop on c7 takes the Rook on e5,
	# and the Jester on d4 or f4 takes the hit.
	var start := Fen.parse("k7/2b5/8/4R3/3J1J2/8/8/7K b - - 0 1", PieceCatalog.all_defs(), StandardSetup.create_rules())
	check(PlusfishLink.supports(start), "The eval bar works with two Jesters on a side")
	var moves := ["c7xe5/f4", "h1-g1"]
	PlusfishLink.enabled = true
	var link := PlusfishLink.new()
	_root().add_child(link)
	link.desktop_nodes = 5000
	link.analyse(start, moves)
	for i in 2000:
		if link.results.size() == moves.size() + 1:
			break
		await _frames(1)
		OS.delay_msec(10)
	check_eq(link.results.size(), moves.size() + 1, "Plusfish follows the capture taken by the f4 Jester")
	var best := str(link.results.get(0, {}).get("best", ""))
	check(start.find_move(best) != null, "Its best move at the start is one the game knows: " + best)
	link.free()
	_finish()

# --- Plusfish never holds up the game ----------------------------------------------

func test_bar_holds_its_place_while_waiting() -> void:
	var bar := EvalBar.new()
	bar.set_score(300, null)
	bar.shown = bar.target()
	bar.set_unknown()
	check_eq(bar.score_text(), "...", "Waiting for the new position")
	check_eq(bar.target(), bar.shown, "The bar stays where it was instead of jumping to the middle")
	bar.reset()
	check_eq(bar.target(), 0.5, "A new game: back to the middle")
	check(not bar.known, "And unknown")
	bar.free()

func test_answers_are_kept_for_every_position() -> void:
	var start := StandardSetup.create_game()
	var link := PlusfishLink.new()
	link.desktop_nodes = 20000
	link.web_nodes = 20000
	link.analyse_live(start, ["e2-e4"])
	link.results[1] = {"ply": 1, "cp": 30, "best": "e7-e5", "asked": 20000}
	link.analyse_live(start, [])
	check(not link.results.has(1), "Taken back: not part of this line")
	link.analyse_live(start, ["d2-d4"])
	check(not link.results.has(1), "A different move: a different position")
	link.analyse_live(start, ["e2-e4"])
	check_eq(link.results.get(1, {}).get("best"), "e7-e5", "e4 again: the answer comes straight back")
	check(not link.is_running(), "Nothing to ask Plusfish")
	link.analyse(start, ["e2-e4"])
	check_eq(link._queue, [0], "Looking over the game: only the unknown position is asked about")
	link.desktop_nodes = 400000
	link.web_nodes = 400000
	link.analyse_live(start, ["e2-e4"])
	check(not link.results.has(1), "A smaller search doesn't do for a bigger one")
	link.free()

func test_the_plusfish_bot_and_the_eval_bar_share_answers() -> void:
	PlusfishLink.enabled = true
	PlusfishLink.pretend_available = true
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.white_army = StandardSetup.army()
	game.black_army = StandardSetup.army()
	game.bot_team = Piece.Team.BLACK
	game.bot_level = PracticeBot.Level.PLUSFISH
	_root().add_child(game)
	check(is_same(game.bot_engine.cache, game.plusfish.cache), "One store of answers")
	game.free()
	_finish()

func test_real_engine_never_holds_up_the_screen() -> void:
	if PlusfishLink.program_path() == "" or OS.has_feature("web"):
		print("    (Plusfish not built: cargo build --release in engine/plusfish to run this test)")
		return
	PlusfishLink.enabled = true
	var start := StandardSetup.create_game()
	var link := PlusfishLink.new()
	_root().add_child(link)
	# A long search (several seconds), so it's still going below.
	link.desktop_nodes = 3000000
	link.analyse_live(start, [])
	var started := Time.get_ticks_usec()
	link.analyse_live(start, ["e2-e4"])
	check(Time.get_ticks_usec() - started < 10000, "Asking takes no time on the screen's side")
	started = Time.get_ticks_msec()
	await _frames(10)
	check(Time.get_ticks_msec() - started < 1000, "Frames keep coming while it searches")
	check(link.is_running(), "Still searching")
	# Taking the move back drops that search: the start is answered at once.
	link.desktop_nodes = 5000
	link.analyse_live(start, [])
	for i in 300:
		if link.results.has(0):
			break
		await _frames(1)
		OS.delay_msec(10)
	check(link.results.has(0), "The new position answered without waiting for the old search")
	started = Time.get_ticks_msec()
	link.free()
	check(Time.get_ticks_msec() - started < 500, "Closing stops Plusfish straight away")
	_finish()
