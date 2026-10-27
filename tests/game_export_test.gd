extends TestSuite

## Exporting a game as a line of text (GameExport) from the result screen, and
## importing it into Testing mode to look over.

const FOOLS_MATE := ["f3", "e5", "g4", "Qh4#"]

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

func _def(id: String) -> PieceDef:
	for def in PieceCatalog.all_defs():
		if def.id == id:
			return def
		if def.transforms_into and def.transforms_into.id == id:
			return def.transforms_into
	return null

## `text` read back, with its moves replayed on the position it sets up.
func _replayed(text: String) -> GameState:
	var found := GameExport.from_text(text)
	check_eq(found.error, "", "Reads back")
	if found.position == null:
		return null
	var state: GameState = found.position.create_state()
	for move_text in found.moves:
		state.make_move(state.find_move(move_text))
	return state

func test_standard_game_round_trip() -> void:
	var state := StandardSetup.create_game()
	for san in ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Bxc6", "dxc6", "O-O"]:
		state.make_move(Notation.find_move(state, san))
	var text := GameExport.to_text(StandardSetup.create_game(), state.history)
	check_eq(text, "Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w; captured: -; moves: e2-e4 e7-e5 g1-f3 b8-c6 f1-b5 a7-a6 b5xc6 d7xc6 e1-g1", "One line")
	var back := _replayed(text)
	check_eq(Fen.write(back), Fen.write(state), "Same game after reading it back")

func test_custom_pieces_black_first_and_captured_round_trip() -> void:
	var position := TestingPosition.new()
	position.place(Board.parse_square("e1"), _def("king"), Piece.Team.WHITE)
	position.place(Board.parse_square("e8"), _def("king"), Piece.Team.BLACK)
	position.place(Board.parse_square("d4"), _def("paladin"), Piece.Team.WHITE)
	position.place(Board.parse_square("d6"), _def("rook"), Piece.Team.BLACK)
	position.place(Board.parse_square("b2"), _def("werewolf_wolf"), Piece.Team.WHITE)
	position.place(Board.parse_square("g7"), _def("necromancer"), Piece.Team.BLACK)
	position.captured.append([_def("queen"), Piece.Team.WHITE])
	position.captured.append([_def("cannon"), Piece.Team.BLACK])
	position.side_to_move = Piece.Team.BLACK
	var state := position.create_state()
	# Black breaks the Paladin's shield, then raises the lost Cannon.
	for move_text in ["d6xd4", "b2-b4", "g7!=C"]:
		var move := state.find_move(move_text)
		check(move != null, "Can play " + move_text)
		state.make_move(move)
	var text := GameExport.to_text(position.create_state(), state.history)
	check(text.contains(" b; captured: Q c; moves: d6xd4 b2-b4 g7!=C"), "Black first, captured pieces, ability: " + text)
	check(text.contains("(PD)") and text.contains("(WF)") and text.contains("(nc)"), "Two-letter pieces: " + text)
	var found := GameExport.from_text(text)
	var read: TestingPosition = found.position
	check_eq(read.side_to_move, Piece.Team.BLACK, "Black moved first")
	check_eq(read.pieces.size(), 6, "Six pieces")
	check_eq(read.get_at(Board.parse_square("b2")), [_def("werewolf_wolf"), Piece.Team.WHITE], "The wolf")
	check_eq(read.captured, [[_def("queen"), Piece.Team.WHITE], [_def("cannon"), Piece.Team.BLACK]], "Captured pieces")
	check_eq(Fen.write(_replayed(text)), Fen.write(state), "Same game after reading it back")

func test_bad_text_says_what_is_wrong() -> void:
	var start := "Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w; captured: -; moves: "
	var cases := {
		"hello": "isn't game text",
		'Overchess army "A": P P P P P P P P / R N B Q K B N R': "isn't game text",
		"Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w": "no moves",
		"Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBZR w; captured: -; moves: ": "letters Z",
		"Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w; captured: -; moves: ": "Row 1",
		"Overchess game: 4k3/8/8/8/8/8/8/8 w; captured: -; moves: ": "White needs exactly one King",
		"Overchess game: 4k3/8/8/8/8/8/8/4K3 w; captured: (XX); moves: ": "letters (XX)",
		start + "e2-e4 e7-e5 e4-e5": "White's move 2 (e4-e5)",
	}
	for text: String in cases:
		var found := GameExport.from_text(text)
		check(found.position == null, "Not read: " + text)
		check(found.error.contains(cases[text]), "%s -> %s" % [text, found.error])
	# Spaces and letter case round the edges don't matter.
	check_eq(GameExport.from_text("  overchess game : " + start.substr(start.find(":") + 1) + "e2-e4  ").error, "", "Loose spacing is fine")

# --- The game screen -----------------------------------------------------------------

func test_export_from_the_result_screen() -> void:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.white_army = StandardSetup.army()
	game.black_army = StandardSetup.army()
	_root().add_child(game)
	check_eq(game.resign_button.text, "Resign", "Resign during the game")
	for san in FOOLS_MATE:
		game.play(Notation.find_move(game.state, san))
	game.board_view.advance_animation(5.0)
	check(game.game_over_panel.visible, "Result shown")
	var export: Button = game.game_over_panel.button("export")
	check(export != null, "Export game button")
	export.pressed.emit()
	var panel: ModalPanel = game.export_panel
	check(panel != null and panel.is_inside_tree(), "Export pop-up shown")
	var shown: Label = panel.find_child("GameText", true, false)
	check_eq(shown.text, "Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w; captured: -; moves: f2-f3 e7-e5 g2-g4 d8-h4", "The game's text")
	panel.close()
	# After View board, the Resign button (now Results) brings the result back.
	game.game_over_panel.button("board").pressed.emit()
	check(not game.game_over_panel.visible, "Looking at the board")
	check_eq(game.resign_button.text, "Results", "Resign became Results")
	check(not game.resign_button.disabled, "...and works")
	game.resign_button.pressed.emit()
	check(game.game_over_panel.visible, "Result shown again")
	game.undo()
	check_eq(game.resign_button.text, "Resign", "Back to Resign once the mate is undone")
	game.free()
	SavedGame.delete_saved()

func test_import_into_testing_mode() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	_root().add_child(main)
	main.show_testing_setup()
	var setup: Node = main.screen
	setup.ask_import_game()
	var message: Label = setup.import_panel.find_child("Message", true, false)
	setup.import_game("")
	check(message.text.contains("Paste"), "Asks for the text: " + message.text)
	setup.import_game("Overchess game: 8/8 w; captured: -; moves: ")
	check(message.text.contains("rows"), "Says what's wrong: " + message.text)
	check(main.screen == setup, "Still setting up")
	setup.import_game("Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w; captured: -; moves: f2-f3 e7-e5 g2-g4 d8-h4")
	var game: Node = main.screen
	check(game != setup and game.testing_position != null, "A testing game opened")
	check_eq(game.state.history.size(), 4, "With the game's moves played")
	check_eq(game.state.outcome(), GameState.Outcome.CHECKMATE, "Ending in checkmate")
	check(game.live_eval(), "Eval bar on, as in any testing game")
	# Play from here, as against the bot.
	game.game_over_panel.button("board").pressed.emit()
	game.view_move(2)
	check(game.play_from_here_button.visible, "Play from here while looking back")
	game.play_from_here()
	check_eq(game.state.history.size(), 2, "Carries on from move 2")
	check(not game.is_over(), "The game is on again")
	game.new_game()
	check_eq(game.state.history.size(), 0, "New game starts from the imported start")
	# Setup goes back to the imported game's start.
	game.menu_requested.emit()
	check_eq(main.screen.setup.pieces.size(), 32, "Its start on the setup board")
	main.free()

## An imported game in Testing mode: try another move (a side line), then
## Play from here carries on with it.
func test_imported_game_side_line_play_from_here() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	_root().add_child(main)
	main.show_testing_setup()
	main.screen.import_game("Overchess game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w; captured: -; moves: f2-f3 e7-e5 g2-g4 d8-h4")
	var game: Node = main.screen
	game.game_over_panel.button("board").pressed.emit()
	game.view_move(2)
	game.choose(Notation.find_move(game.board_view.state, "d4"))
	check_eq(game.side_lines.size(), 1, "A side line from 1. f3 e5")
	check(game.play_from_here_button.visible, "Play from here on the side line")
	game.play_from_here()
	check_eq(Notation.move_list(game.state), "1. f3 e5 2. d4", "The game carries on with the side line's move")
	check(game.side_lines.is_empty(), "It's the game's now, not a side line")
	check(not game.is_over(), "The game is on again")
	main.free()

func test_game_text_from_before_the_rename() -> void:
	# The game was Chess Plus until 26 Oct 2026; games exported then still import.
	var old := GameExport.from_text("Chess Plus game: rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w; captured: -; moves: e2-e4 e7-e5")
	check_eq(old.error, "", "Old game text still reads")
	check_eq(old.moves.size(), 2, "Both moves")
	check(GameExport.to_text(StandardSetup.create_game(), [] as Array[Move]).begins_with("Overchess game: "), "New texts say Overchess")
