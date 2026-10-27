extends TestSuite

## Testing mode (Mac's design, Oct 2026): set up any position, with captured
## pieces and either side to move, and play it as two players with the eval bar on.

func _def(id: String) -> PieceDef:
	for def in PieceCatalog.all_defs():
		if def.id == id:
			return def
		if def.transforms_into and def.transforms_into.id == id:
			return def.transforms_into
	return null

func _kings(position: TestingPosition) -> void:
	position.place(Board.parse_square("e1"), _def("king"), Piece.Team.WHITE)
	position.place(Board.parse_square("e8"), _def("king"), Piece.Team.BLACK)

func test_standard_position_plays_like_chess() -> void:
	var state := TestingPosition.standard().create_state()
	check_eq(state.moves().size(), 20, "20 first moves")
	check_eq(Fen.write(state).split(" ")[0], "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", "Same board")

func test_black_to_move_and_captured_pieces() -> void:
	var position := TestingPosition.new()
	_kings(position)
	position.place(Board.parse_square("d2"), _def("necromancer"), Piece.Team.WHITE)
	position.captured.append([_def("queen"), Piece.Team.WHITE])
	position.captured.append([_def("ghost"), Piece.Team.BLACK])
	position.side_to_move = Piece.Team.BLACK
	check(position.problems().is_empty(), "A fine position: %s" % [position.problems()])
	var state := position.create_state()
	check_eq(state.side_to_move, Piece.Team.BLACK, "Black moves first")
	check_eq(state.lost[Piece.Team.WHITE].size(), 1, "White has lost a queen")
	check(state.moves().any(func(m: Move) -> bool: return m.ability == PieceDef.Ability.HAUNT), "Black's captured Ghost can Haunt")
	state.make_move(state.moves()[0])
	check(state.find_move("d2!=Q") != null, "White's Necromancer can raise the captured Queen")

func test_pieces_start_unmoved() -> void:
	var position := TestingPosition.new()
	_kings(position)
	position.place(Board.parse_square("a1"), _def("rook"), Piece.Team.WHITE)
	position.place(Board.parse_square("c2"), _def("pawn"), Piece.Team.WHITE)
	position.place(Board.parse_square("f3"), _def("pawn"), Piece.Team.WHITE)
	position.place(Board.parse_square("b7"), _def("pawn"), Piece.Team.WHITE)
	var state := position.create_state()
	check(state.find_move("c2-c4") != null, "A pawn on the starting rows is unmoved: it gets its double step")
	check(state.find_move("f3-f5") == null and state.find_move("f3-f4") != null, "A pawn beyond them counts as moved (promotion needs a move first)")
	check(state.find_move("b7-b8=R") != null, "...so a pawn set up on the seventh can promote (to the Rook on the board)")
	check(state.find_move("e1-c1") != null, "The King can castle with a Rook in its corner")

func test_wolf_form_can_be_placed() -> void:
	var position := TestingPosition.new()
	_kings(position)
	position.place(Board.parse_square("d4"), _def("werewolf_wolf"), Piece.Team.WHITE)
	var piece := position.create_state().board.get_piece(Board.parse_square("d4"))
	check_eq(piece.starting_def(), _def("werewolf"), "It knows it was a Werewolf")
	check(not piece.can_use_ability(), "No Full Moon left")

func test_problems() -> void:
	var position := TestingPosition.new()
	check_eq(position.problems(), PackedStringArray(["White needs exactly one King.", "Black needs exactly one King."]), "Empty board")
	_kings(position)
	position.place(Board.parse_square("d1"), _def("king"), Piece.Team.WHITE)
	check(position.problems().has("White needs exactly one King."), "Two white Kings")
	position.remove_at(Board.parse_square("d1"))
	position.place(Board.parse_square("a8"), _def("pawn"), Piece.Team.WHITE)
	check(position.problems().has("White's Pawn can't start on the far row."), "Pawn on the far row")
	position.remove_at(Board.parse_square("a8"))
	position.place(Board.parse_square("e4"), _def("rook"), Piece.Team.WHITE)
	check_eq(position.problems(), PackedStringArray(["Black's King is in check, but it's White's move."]), "Black would start in check with White to move")
	position.side_to_move = Piece.Team.BLACK
	check(position.problems().is_empty(), "Fine with Black to move")

func test_copy_is_separate() -> void:
	var position := TestingPosition.standard()
	var other := position.copy()
	other.remove_at(Board.parse_square("e1"))
	check(not position.get_at(Board.parse_square("e1")).is_empty(), "The original keeps its King")

## A small army: King e1, Knight b1, Pawn a2 (as built).
func _small_army(army_name: String) -> Army:
	var army := Army.new()
	army.army_name = army_name
	army.place(_def("king"), Vector2i(4, 0))
	army.place(_def("knight"), Vector2i(1, 0))
	army.place(_def("pawn"), Vector2i(0, 1))
	return army

## The board's pieces as {square name: [piece id, team]}.
func _pieces_by_name(position: TestingPosition) -> Dictionary:
	var result := {}
	for square: Vector2i in position.pieces:
		var entry: Array = position.pieces[square]
		result[Board.square_name(square)] = [entry[0].id, entry[1]]
	return result

func test_load_army_into_position() -> void:
	var position := TestingPosition.standard()
	position.load_army(_small_army("Small"), Piece.Team.BLACK)
	var black := _pieces_by_name(position).values().filter(func(e: Array) -> bool: return e[1] == Piece.Team.BLACK)
	check_eq(black.size(), 3, "Black's old pieces are gone; the army's 3 are there")
	# Turned round for Black, as in a real game: the king on e1 becomes d8.
	check_eq(position.get_at(Board.parse_square("d8")), [_def("king"), Piece.Team.BLACK], "King on d8")
	check_eq(position.get_at(Board.parse_square("g8")), [_def("knight"), Piece.Team.BLACK], "Knight on g8")
	check_eq(position.get_at(Board.parse_square("h7")), [_def("pawn"), Piece.Team.BLACK], "Pawn on h7")
	check_eq(position.pieces.size(), 19, "White's 16 untouched")
	# Same squares as a real game from these armies.
	var real := ArmySetup.create_game(StandardSetup.army(), _small_army("Small"), StandardSetup.create_rules())
	check_eq(Fen.write(position.create_state()).split(" ")[0], Fen.write(real).split(" ")[0], "Same board as a real game")
	# The Standard set isn't turned round: Black's queen is on d8.
	position.load_army(StandardSetup.army(), Piece.Team.BLACK)
	check_eq(position.get_at(Board.parse_square("d8")), [_def("queen"), Piece.Team.BLACK], "Standard queen on d8")
	# An army's piece replaces the other side's piece on its square.
	position.place(Board.parse_square("b1"), _def("rook"), Piece.Team.BLACK)
	position.load_army(_small_army("Small"), Piece.Team.WHITE)
	check_eq(position.get_at(Board.parse_square("b1")), [_def("knight"), Piece.Team.WHITE], "White's knight replaced the black rook")

# --- The setup screen and the game ---------------------------------------------------

func _open_setup() -> Node:
	var setup: Node = load("res://scenes/testing/position_setup.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(setup)
	return setup

func test_setting_up_a_position() -> void:
	var setup := _open_setup()
	check(setup.start_button.disabled == false, "Starts on the standard position, ready to play")
	setup.clear_board()
	check(setup.start_button.disabled, "An empty board can't start")
	check(setup.problems_label.text.contains("needs exactly one King"), "And says why")
	setup.choose(_def("king"))
	setup.tap_square(Board.parse_square("e1"))
	setup.toggle_tray_team()
	setup.tap_square(Board.parse_square("e8"))
	check(not setup.start_button.disabled, "Two Kings: ready")
	setup.choose(_def("rook"))
	setup.tap_square(Board.parse_square("a8"))
	check_eq(setup.setup.get_at(Board.parse_square("a8")), [_def("rook"), Piece.Team.BLACK], "A black Rook on a8")
	setup.tap_square(Board.parse_square("a8"))
	check(setup.setup.get_at(Board.parse_square("a8")).is_empty(), "Tapping the same piece again takes it off")
	setup.tap_square(Board.parse_square("a8"))
	setup.choose(null)
	setup.tap_square(Board.parse_square("a8"))
	check(setup.setup.get_at(Board.parse_square("a8")).is_empty(), "Remove takes off whatever is tapped")
	setup.set_side_to_move(Piece.Team.BLACK)
	check_eq(setup.setup.side_to_move, Piece.Team.BLACK, "Black to move")
	setup.free()

func test_captured_pieces_in_setup() -> void:
	var setup := _open_setup()
	setup.choose(null)
	check(setup.add_captured_button.disabled, "Nothing chosen: nothing to add")
	setup.choose(_def("queen"))
	setup.add_captured()
	setup.toggle_tray_team()
	setup.add_captured()
	check_eq(setup.setup.captured, [[_def("queen"), Piece.Team.WHITE], [_def("queen"), Piece.Team.BLACK]], "A white and a black Queen captured")
	setup.remove_captured(0)
	check_eq(setup.setup.captured, [[_def("queen"), Piece.Team.BLACK]], "Tapping one puts it back")
	setup.free()

func test_load_armies_screen() -> void:
	const TEST_DIR := "user://test_armies/"
	if DirAccess.dir_exists_absolute(TEST_DIR):
		for file in DirAccess.get_files_at(TEST_DIR):
			DirAccess.remove_absolute(TEST_DIR + file)
	var library := ArmyLibrary.new(TEST_DIR)
	library.save(_small_army("Small"))
	var setup: Node = load("res://scenes/testing/position_setup.tscn").instantiate()
	setup.library = library
	(Engine.get_main_loop() as SceneTree).root.add_child(setup)
	check_eq(setup.army_choices(), PackedStringArray(["Leave as it is", "Standard", "Small", "Paste army text"]), "Saved armies offered")
	setup.ask_load_armies()
	var panel: ModalPanel = setup.load_panel
	var white_pick: OptionButton = panel.find_child("WhitePick", true, false)
	var black_pick: OptionButton = panel.find_child("BlackPick", true, false)
	var black_text: LineEdit = panel.find_child("BlackText", true, false)
	var message: Label = panel.find_child("Message", true, false)
	check(not black_text.visible, "The text box shows only for pasted text")
	black_pick.select(3)
	black_pick.item_selected.emit(3)
	check(black_text.visible, "Paste army text shows it")
	# Nothing pasted yet: says so and loads nothing.
	white_pick.select(2)
	setup.load_chosen_armies()
	check(message.text.contains("Black's army") and message.text.contains("Paste"), "Asks for the text: " + message.text)
	check_eq(setup.setup.pieces.size(), 32, "Nothing loaded yet")
	black_text.text = 'Overchess army "Pasted": - - - - - - - - / - - - - K - - (Q)'
	setup.load_chosen_armies()
	check(message.text.contains("Q)"), "Broken text says what's wrong: " + message.text)
	black_text.text = 'Overchess army "Pasted": - - - - - - - - / R - - - K - - -'
	setup.load_chosen_armies()
	check(panel.is_queued_for_deletion(), "Loaded: the pop-up closes")
	var pieces := _pieces_by_name(setup.setup)
	check_eq(pieces.size(), 5, "3 white pieces, 2 black")
	check_eq(pieces.get("e1"), ["king", Piece.Team.WHITE], "White's saved army: King e1")
	check_eq(pieces.get("b1"), ["knight", Piece.Team.WHITE], "Knight b1")
	check_eq(pieces.get("d8"), ["king", Piece.Team.BLACK], "Black's pasted army turned round: King d8")
	check_eq(pieces.get("h8"), ["rook", Piece.Team.BLACK], "Rook h8")
	check(not setup.start_button.disabled, "Ready to start")
	# Leave as it is changes nothing for that side.
	setup.ask_load_armies()
	setup.load_panel.find_child("WhitePick", true, false).select(1)
	setup.load_chosen_armies()
	check_eq(setup.setup.pieces.size(), 18, "White got the Standard set; Black left alone")
	setup.free()
	for file in DirAccess.get_files_at(TEST_DIR):
		DirAccess.remove_absolute(TEST_DIR + file)

func test_tray_has_every_piece_and_the_wolf() -> void:
	var defs: Array[PieceDef] = load("res://scenes/testing/position_setup.gd").tray_defs()
	check_eq(defs.size(), PieceCatalog.all_defs().size() + 1, "Every piece type plus the wolf form")

func test_game_from_a_testing_position() -> void:
	var position := TestingPosition.new()
	position.place(Board.parse_square("e1"), _def("king"), Piece.Team.WHITE)
	position.place(Board.parse_square("e8"), _def("king"), Piece.Team.BLACK)
	position.place(Board.parse_square("d7"), _def("pawn"), Piece.Team.BLACK)
	position.captured.append([_def("rook"), Piece.Team.WHITE])
	position.side_to_move = Piece.Team.BLACK
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.testing_position = position
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	check_eq(game.state.side_to_move, Piece.Team.BLACK, "Black moves first")
	check_eq(game.state.lost[Piece.Team.WHITE].size(), 1, "White's Rook is already captured")
	check(game.live_eval(), "The eval bar is always on")
	game.play(Notation.find_move(game.state, "d5"))
	game.new_game()
	check_eq(game.state.history.size(), 0, "New game starts the same position again")
	check_eq(game.state.side_to_move, Piece.Team.BLACK, "...with Black to move")
	check(SavedGame.load_saved() == null, "Testing games aren't saved")
	game.free()

func test_main_menu_to_testing_and_back() -> void:
	SavedGame.delete_saved()
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(main)
	main.show_testing_setup()
	var setup: Node = main.screen
	check(setup.has_method("tap_square"), "Testing mode's setup screen")
	setup.start_pressed.emit(setup.setup.copy())
	var game: Node = main.screen
	check(game.testing_position != null, "A testing game")
	check_eq(game.menu_button.text, "Setup", "Its Menu button goes back to the setup")
	game.menu_requested.emit()
	check(main.screen.has_method("tap_square"), "Back on the setup screen")
	main.free()
