extends TestSuite

## The piece card, the pop-up version in games (opened by holding a piece), and
## the always-showing card in the army builder.

var infos: Array[Piece] = []

func _def(id: String) -> PieceDef:
	return load("res://data/pieces/%s.tres" % id)

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

# --- What the card says ---------------------------------------------------------------

func test_cost_and_types() -> void:
	check_eq(PieceCard.cost_text(_def("king")), "Free", "King cost")
	check_eq(PieceCard.cost_text(_def("pawn")), "1 point", "Pawn cost")
	check_eq(PieceCard.cost_text(_def("paladin")), "1.5 points", "Paladin cost")
	check_eq(PieceCard.cost_text(_def("elephant")), "1 point", "Elephant cost")
	check_eq(PieceCard.cost_text(_def("assassin")), "0.5 points", "Assassin cost")
	check_eq(PieceCard.type_names(_def("king")), PackedStringArray(["King", "Royal"]), "King types")
	check_eq(PieceCard.type_names(_def("queen")), PackedStringArray(["Royal"]), "Queen types")
	check_eq(PieceCard.type_names(_def("cannon")), PackedStringArray(), "Cannon: no types")

func test_every_type_and_keyword_has_an_explanation() -> void:
	for def in PieceCatalog.all_defs():
		for tag in PieceCard.type_names(def) + PieceCard.keyword_names(def):
			check(PieceCard.EXPLANATIONS.has(tag), tag + " is explained")

func test_keywords() -> void:
	check_eq(PieceCard.keyword_names(_def("knight")), PackedStringArray(["Jump"]), "Knight")
	check_eq(PieceCard.keyword_names(_def("rook")), PackedStringArray(["Castle"]), "Rook")
	check_eq(PieceCard.keyword_names(_def("lance")), PackedStringArray(["Promote"]), "Lance")
	check_eq(PieceCard.keyword_names(_def("paladin")), PackedStringArray(["Shield"]), "Paladin")
	check_eq(PieceCard.keyword_names(_def("parapet")), PackedStringArray(["Castle", "Wall"]), "Parapet: the Wall keyword (Oct 2026)")
	check(_def("parapet").blocks_jumps() and not _def("paladin").blocks_jumps(), "Wall = blocks the opponent's jumps")
	check_eq(RuleText.plain("{Wall}"), "WALL", "Wall has a box")
	for def in PieceCatalog.all_defs():
		for keyword in PieceCard.keyword_names(def):
			check(PieceCard.KEYWORD_COLORS.has(keyword), keyword + " has a colour")

func test_special_rules_come_from_the_data() -> void:
	check(PieceCard.special_rules(_def("cannon"))[0].begins_with("Captures by jumping"), "Cannon")
	check_eq(PieceCard.special_rules(_def("rogue")).size(), 1, "Rogue has a special rule")
	# The double step isn't in the legend, so the Pawn's card says it here (Mac).
	check_eq(PieceCard.special_rules(_def("pawn")), PackedStringArray(["On its first move, the Pawn can move 2 squares forward."]), "Pawn")
	for id in ["king", "queen", "knight", "wizard", "chariot", "cavalry", "berserker"]:
		check(PieceCard.special_rules(_def(id)).is_empty(), id + " has nothing special")

func test_pawn_types_show_promote() -> void:
	check_eq(PieceCard.keyword_names(_def("pawn")), PackedStringArray(["Promote"]), "Pawn")
	check_eq(PieceCard.keyword_names(_def("chariot")), PackedStringArray(["Castle"]), "Chariot")
	check_eq(PieceCard.keyword_names(_def("wizard")), PackedStringArray(["Jump"]), "Wizard")
	check_eq(PieceCard.type_names(_def("wizard")), PackedStringArray(["Royal"]), "Wizard is royal")

func test_alternate_pictures() -> void:
	check_eq(PieceArt.all_textures(_def("paladin"), Piece.Team.WHITE).size(), 2, "Paladin with and without shield")
	check_eq(PieceArt.all_textures(_def("knight"), Piece.Team.WHITE).size(), 1, "Knight: one picture")

func _marks(id: String) -> Array[String]:
	return PieceGuideBoard.kinds_used(PieceGuide.guide(_def(id)))

func test_each_piece_gets_the_right_marks() -> void:
	check_eq(_marks("pawn"), ["move", "capture"] as Array[String], "Pawn")
	check_eq(_marks("knight"), ["jump"] as Array[String], "Knight")
	check_eq(_marks("rook"), ["slide"] as Array[String], "Rook")
	check_eq(_marks("cannon"), ["slide_move"] as Array[String], "Cannon")
	check_eq(_marks("man"), ["both"] as Array[String], "Man")
	check_eq(_marks("galleon"), ["slide_move", "capture"] as Array[String], "Galleon")
	# Steps it can't capture with, and leaps 2 away that must capture: a yellow X.
	check_eq(_marks("catapult"), ["move", "jump_capture"] as Array[String], "Catapult")
	check_eq(_marks("wizard"), ["slide", "jump"] as Array[String], "Wizard")

func test_jumps_get_yellow_versions_of_the_marks() -> void:
	check_eq(PieceGuideBoard._kind(PieceGuide.MOVE | PieceGuide.CAPTURE | PieceGuide.JUMP), "jump", "Yellow dot")
	check_eq(PieceGuideBoard._kind(PieceGuide.MOVE | PieceGuide.JUMP), "jump_move", "Yellow empty circle")
	check_eq(PieceGuideBoard._kind(PieceGuide.CAPTURE | PieceGuide.JUMP), "jump_capture", "Yellow X")
	# First move only (the pawn's double step): no mark; its Special Rule says it (Mac).
	var pawn := PieceGuide.guide(_def("pawn"))
	check(pawn.squares.has(Vector2i(0, 2)), "The guide still knows the double step")
	check(not PieceGuideBoard.shown_squares(pawn).has(Vector2i(0, 2)), "No mark for the double step")
	check(PieceGuideBoard.shown_squares(pawn).has(Vector2i(0, 1)), "The single step is marked")

func test_every_card_shows_the_whole_legend() -> void:
	# In Mac's order, shortened (Mac); no plain dot or arrow (Mac).
	var texts := ["Moves, can't capture", "Slides, can't capture", "Captures only",
		"Jumps", "Jumps, can't capture", "Jumps, captures only"]
	var card: PieceCard = load("res://scenes/common/piece_card.tscn").instantiate()
	_root().add_child(card)
	for id in ["man", "knight", "pawn", "werewolf"]:
		card.show_piece(_def(id))
		check_eq(_legend_texts(card), texts, id + ": the whole legend")
	# Turning the Werewolf over changes the mini board, not the legend.
	card.turn_over()
	check_eq(_legend_texts(card), texts, "Still the whole legend after Wolf moves")
	card.free()

## The legend's texts as shown (old rows are freed at the end of the frame).
func _legend_texts(card: PieceCard) -> Array:
	var rows := card.get_node("%Legend").get_children().filter(func(row: Node) -> bool: return not row.is_queued_for_deletion())
	return rows.map(func(row: Node) -> String: return (row.get_child(1) as Label).text)

func test_card_fills_in() -> void:
	var card: PieceCard = load("res://scenes/common/piece_card.tscn").instantiate()
	card.show_piece(_def("paladin"))
	_root().add_child(card)
	check_eq(card.get_node("%Name").text, "Paladin", "Name")
	check_eq(card.get_node("%Pictures").get_child_count(), 2, "Both pictures")
	check_eq(card.get_node("%Keywords").get_child_count(), 1, "One keyword box")
	check(not card.get_node("%Special").visible, "No special section")
	card.show_piece(_def("cannon"))
	check(card.get_node("%Special").visible, "Cannon has a special section")
	card.free()

func test_types_italic_keywords_capitals_and_explanations() -> void:
	var card: PieceCard = load("res://scenes/common/piece_card.tscn").instantiate()
	card.show_piece(_def("king"))
	_root().add_child(card)
	# Details row: "Free", "·", "King,", "Royal".
	var details := card.get_node("%Details")
	check_eq(details.get_child_count(), 4, "Cost, dot and two types")
	var king_label: Label = details.get_child(2)
	check_eq(king_label.text, "King,", "First type")
	var type_font := king_label.get_theme_font("font")
	check(type_font is FontVariation and type_font.base_font == PieceCard.ITALIC_FONT, "Types use the italic font")
	card.show_tooltip(king_label, "King")
	check(card.tooltip.visible, "Explanation shown")
	check(card.tooltip.get_child(0).text.begins_with("If a [i]King[/i] is checkmated"), "King explained (the type in italics)")
	card.show_tooltip(king_label, "King")
	check(not card.tooltip.visible, "Second tap hides it")
	card.show_piece(_def("paladin"))
	var shield_box: PanelContainer = card.get_node("%Keywords").get_child(0)
	check_eq(shield_box.get_child(0).text, "SHIELD", "Keywords in capitals")
	card.free()

# --- Pop-up in a game -------------------------------------------------------------------

func _view(state: GameState) -> BoardView:
	var view := BoardView.new()
	view.size = Vector2(800, 800)
	view.show_game(state)
	view.info_requested.connect(func(piece: Piece) -> void: infos.append(piece))
	return view

func test_popup_opens_and_closes() -> void:
	var holder := Control.new()
	_root().add_child(holder)
	var info := PieceInfo.open(holder, _def("pawn"))
	check_eq(info.get_node("%Card").get_node("%Name").text, "Pawn", "Shows the pawn")
	info.close()
	check(info.is_queued_for_deletion(), "Closing removes it")
	holder.free()

func test_holding_a_piece_asks_for_its_card() -> void:
	var view := _view(StandardSetup.create_game())
	var moves := []
	view.move_chosen.connect(func(m: Move) -> void: moves.append(m))
	var g1 := view.square_center(Board.parse_square("g1"))
	view.pointer_down(g1)
	view.check_long_press(Time.get_ticks_msec() + BoardView.LONG_PRESS_MS + 10)
	check_eq(infos.size(), 1, "Card requested")
	if infos.size() == 1:
		check_eq(infos[0].def.id, "knight", "For the knight")
	view.pointer_up(g1)
	view.tap(Board.parse_square("f3"))
	check_eq(moves.size(), 0, "The hold didn't leave the knight selected")
	view.free()

func test_short_press_is_just_a_tap() -> void:
	var view := _view(StandardSetup.create_game())
	view.pointer_down(view.square_center(Board.parse_square("g1")))
	view.check_long_press(Time.get_ticks_msec() + 100)
	check_eq(infos.size(), 0, "No card for a quick tap")
	view.free()

func test_holding_an_opponents_piece_works_too() -> void:
	var view := _view(StandardSetup.create_game())
	view.pointer_down(view.square_center(Board.parse_square("d8")))
	view.check_long_press(Time.get_ticks_msec() + BoardView.LONG_PRESS_MS + 10)
	check(infos.size() == 1 and infos[0].team == Piece.Team.BLACK, "Black queen's card")
	view.free()

func test_moving_away_cancels_the_hold() -> void:
	var view := _view(StandardSetup.create_game())
	var a7 := view.square_center(Board.parse_square("a7"))
	view.pointer_down(a7)
	view.pointer_move(a7 + Vector2(60, 0))
	view.check_long_press(Time.get_ticks_msec() + BoardView.LONG_PRESS_MS + 10)
	check_eq(infos.size(), 0, "Wandered off: no card")
	view.free()

func test_pressing_a_move_square_does_not_open_a_card() -> void:
	var view := _view(StandardSetup.create_game())
	view.tap(Board.parse_square("g1"))
	view.pointer_down(view.square_center(Board.parse_square("f3")))
	view.check_long_press(Time.get_ticks_msec() + BoardView.LONG_PRESS_MS + 10)
	check_eq(infos.size(), 0, "No card after a move")
	view.free()

# --- Army builder ------------------------------------------------------------------------

func _builder() -> Node:
	var builder: Node = load("res://scenes/armies/army_builder.tscn").instantiate()
	builder.setup(ArmyLibrary.new("user://test_armies/"), null)
	_root().add_child(builder)
	return builder

func test_builder_card_follows_the_tray() -> void:
	var builder := _builder()
	check_eq(builder.card.def.id, "king", "Starts on the king")
	builder.select(_def("cannon"))
	check_eq(builder.card.def.id, "cannon", "Switches to the cannon")
	builder.select(null)
	check_eq(builder.card.def.id, "cannon", "Deselecting keeps the last card")
	builder.free()

func test_builder_colour_switch() -> void:
	var builder := _builder()
	builder.select(_def("knight"))
	builder.toggle_team()
	check_eq(builder.team, Piece.Team.BLACK, "Now black")
	check_eq(builder.team_button.text, "Black", "Button says Black")
	check_eq(builder.card.team, Piece.Team.BLACK, "Card in black")
	check_eq(builder.army_board.team, Piece.Team.BLACK, "Board pieces in black")
	check_eq(builder._tray_buttons[_def("knight")].icon, PieceArt.texture_for(_def("knight"), Piece.Team.BLACK), "Tray in black")
	builder.toggle_team()
	check_eq(builder.team_button.text, "White", "And back")
	builder.free()

func test_mouse_hold_does_not_open_a_card() -> void:
	var view := _view(StandardSetup.create_game())
	view.pointer_down(view.square_center(Board.parse_square("g1")), false)
	view.check_long_press(Time.get_ticks_msec() + BoardView.LONG_PRESS_MS + 10)
	check_eq(infos.size(), 0, "Holding the mouse button opens nothing")
	view.free()

func test_middle_click_opens_the_card() -> void:
	var view := _view(StandardSetup.create_game())
	view.tap(Board.parse_square("g1"))
	view.middle_click(view.square_center(Board.parse_square("d8")))
	check(infos.size() == 1 and infos[0].def.id == "queen", "Middle-clicking a piece opens its card (Mac)")
	check(view.highlights.is_empty(), "...and marks nothing")
	view.middle_click(view.square_center(Board.parse_square("e4")))
	check_eq(infos.size(), 1, "Empty square: nothing")
	view.right_click(view.square_center(Board.parse_square("d8")))
	check_eq(infos.size(), 1, "A right-click opens nothing (it marks the square)")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	press.position = view.square_center(Board.parse_square("e1"))
	view._gui_input(press)
	check(infos.size() == 2 and infos[1].def.id == "king", "The real middle button works too")
	view.free()

func _motion(pos: Vector2) -> InputEventMouseMotion:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	return motion

func test_tip_matches_the_device() -> void:
	check(load("res://scenes/game/game.gd").tip_text(true).contains("hold"), "Phones: hold")
	check(load("res://scenes/game/game.gd").tip_text(false).contains("middle-click"), "PC: middle-click")

func test_move_note_in_italics() -> void:
	var card: PieceCard = load("res://scenes/common/piece_card.tscn").instantiate()
	card.show_piece(_def("knight"))
	_root().add_child(card)
	var note: RichTextLabel = card.get_node("%MoveNote")
	check(note.visible and note.text.begins_with("[i]When it moves to a square an L shape away"), "The Knight's note (Mac): " + note.text)
	check(note.get_theme_font("italics_font") is FontVariation, "...in italics")
	card.show_piece(_def("cavalry"))
	check(note.visible, "The Cavalry has it too")
	card.show_piece(_def("berserker"))
	check(note.visible, "And the Barbarian (Mac, Oct 2026)")
	card.show_piece(_def("bishop"))
	check(not note.visible, "Other pieces don't")
	card.free()

func test_special_ability_heading_explains_itself() -> void:
	check_eq(PieceCard.EXPLANATIONS["Special Ability"], "Once per game, after the piece has moved at least once (a capture or a shield break counts). Uses your turn.", "Mac's rule (Oct 2026)")
	var card: PieceCard = load("res://scenes/common/piece_card.tscn").instantiate()
	card.show_piece(_def("archer"))
	_root().add_child(card)
	var title: Label = card.get_node("Ability/AbilityHeader/AbilityTitle")
	title.gui_input.emit(_click())
	check(card.tooltip.visible and card.tooltip_owner == title, "Tapping the heading explains it")
	card.free()

func _click() -> InputEventMouseButton:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	return press

## Mac (Oct 2026): every card shows its piece moving up the screen, whatever
## its colour and whichever way round the board is.
func test_mini_board_always_shows_moving_up() -> void:
	var card: PieceCard = load("res://scenes/common/piece_card.tscn").instantiate()
	card.show_piece(_def("pawn"), Piece.Team.BLACK)
	_root().add_child(card)
	var guide := PieceGuide.guide(_def("pawn"))
	check(guide.squares.has(Vector2i(0, 1)), "A pawn's step is (0, 1): forward")
	check_eq(card.get_node("%GuideBoard").team, Piece.Team.BLACK, "Drawn as a Black pawn...")
	check(not ("upside_down" in card.get_node("%GuideBoard")), "...with no way to turn it upside down")
	card.free()
