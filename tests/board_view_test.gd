extends TestSuite

## Checks the board view's tap handling (which piece is selected, which move is
## sent) without drawing anything.

var chosen: Array[Move] = []
var choices: Array = []

func _view_for(state: GameState) -> BoardView:
	var view := BoardView.new()
	view.show_game(state)
	view.move_chosen.connect(func(move: Move) -> void: chosen.append(move))
	view.choice_needed.connect(func(moves: Array[Move]) -> void: choices.append(moves))
	return view

func _square(name: String) -> Vector2i:
	return Board.parse_square(name)

func test_tap_piece_then_square_sends_the_move() -> void:
	var view := _view_for(StandardSetup.create_game())
	view.tap(_square("e2"))
	view.tap(_square("e4"))
	check_eq(chosen.size(), 1, "Moves sent")
	if chosen.size() == 1:
		check_eq(chosen[0].to_text(), "e2-e4", "Move sent")
	view.free()

func test_illegal_square_just_deselects() -> void:
	var view := _view_for(StandardSetup.create_game())
	view.tap(_square("e2"))
	view.tap(_square("e5"))
	view.tap(_square("e4"))
	check_eq(chosen.size(), 0, "No move: e5 was illegal, so e4 was a fresh tap on an empty square")
	view.free()

func test_tapping_another_own_piece_switches_selection() -> void:
	var view := _view_for(StandardSetup.create_game())
	view.tap(_square("e2"))
	view.tap(_square("g1"))
	view.tap(_square("f3"))
	check_eq(chosen.size(), 1, "Moves sent")
	if chosen.size() == 1:
		check_eq(chosen[0].to_text(), "g1-f3", "Move sent")
	view.free()

func test_cannot_select_opponents_piece() -> void:
	var view := _view_for(StandardSetup.create_game())
	view.tap(_square("e7"))
	view.tap(_square("e5"))
	check_eq(chosen.size(), 0, "Black can't move on White's turn")
	view.free()

func test_promotion_asks_for_a_choice() -> void:
	var view := _view_for(StandardSetup.from_fen("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"))
	view.tap(_square("b7"))
	view.tap(_square("b8"))
	check_eq(chosen.size(), 0, "No move sent yet")
	check_eq(choices.size(), 1, "Asked once")
	if choices.size() == 1:
		check_eq(choices[0].size(), 4, "Four promotion choices")
	view.free()

func test_no_taps_after_game_over() -> void:
	var state := StandardSetup.from_fen("rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3")
	var view := _view_for(state)
	view.tap(_square("a2"))
	view.tap(_square("a3"))
	check_eq(chosen.size(), 0, "Checkmated side can't move")
	view.free()

## Pieces whose art hasn't been drawn yet (they show their letters meanwhile).
## Take each one off this list when its pictures are added.
const ART_TO_COME: Array[String] = ["grunt", "abatis", "vassal"]

func test_every_piece_has_a_picture() -> void:
	var view := BoardView.new()
	for def in PieceCatalog.all_defs():
		for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
			var has_picture := view.texture_for(def, team) != null
			if def.id in ART_TO_COME:
				check(not has_picture, "%s %s has art now: take it off ART_TO_COME" % [team, def.id])
			else:
				check(has_picture, "%s %s" % [team, def.id])
	view.free()

func test_shield_pieces_have_a_wounded_picture() -> void:
	for def in PieceCatalog.all_defs():
		if def.has_shield() and def.id not in ART_TO_COME:
			for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
				check(PieceArt.texture_for(def, team, PieceArt.DEFAULT_STYLE, "wounded") != null, "%s %s wounded" % [team, def.id])

# --- Dragging. The view is given a size so squares have screen positions. ------

func _sized_view(state: GameState) -> BoardView:
	var view := _view_for(state)
	view.size = Vector2(800, 800)
	return view

func _drag(view: BoardView, from: String, to: String) -> void:
	var start := view.square_center(_square(from))
	var end := view.square_center(_square(to))
	view.pointer_down(start)
	view.pointer_move(start.lerp(end, 0.5))
	view.pointer_move(end)
	view.pointer_up(end)

func test_drag_makes_the_move() -> void:
	var view := _sized_view(StandardSetup.create_game())
	_drag(view, "g1", "f3")
	check_eq(chosen.size(), 1, "Moves sent")
	if chosen.size() == 1:
		check_eq(chosen[0].to_text(), "g1-f3", "Move sent")
	view.free()

func test_drag_to_illegal_square_keeps_selection() -> void:
	var view := _sized_view(StandardSetup.create_game())
	_drag(view, "g1", "g3")
	check_eq(chosen.size(), 0, "No move for an illegal drop")
	# The knight is still selected, so tapping a legal square now moves it.
	view.tap(_square("h3"))
	check_eq(chosen.size(), 1, "Tap after a failed drag")
	view.free()

func test_drag_promotion_asks_for_a_choice() -> void:
	var view := _sized_view(StandardSetup.from_fen("4k3/1P6/8/8/8/8/8/4K3 w - - 0 1"))
	_drag(view, "b7", "b8")
	check_eq(choices.size(), 1, "Asked which piece")
	view.free()

func test_press_and_release_on_selected_piece_deselects() -> void:
	var view := _sized_view(StandardSetup.create_game())
	var e2 := view.square_center(_square("e2"))
	view.pointer_down(e2)
	view.pointer_up(e2)
	view.pointer_down(e2)
	view.pointer_up(e2)
	view.tap(_square("e4"))
	check_eq(chosen.size(), 0, "Second click deselected, so e4 doesn't move anything")
	view.free()

func test_small_wobble_is_still_a_tap() -> void:
	var view := _sized_view(StandardSetup.create_game())
	var e2 := view.square_center(_square("e2"))
	view.pointer_down(e2)
	view.pointer_move(e2 + Vector2(3, 2))
	view.pointer_up(e2 + Vector2(3, 2))
	view.pointer_down(view.square_center(_square("e4")))
	check_eq(chosen.size(), 1, "Tap, tap still moves")
	view.free()

# --- Animation -------------------------------------------------------------------

func _played(view: BoardView, text: String) -> Move:
	var move := view.state.find_move(text)
	view.state.make_move(move)
	view.show_move(move)
	return move

func test_tapped_move_slides_then_stops() -> void:
	var view := _view_for(StandardSetup.create_game())
	_played(view, "e2-e4")
	check(view.is_animating(), "Sliding after a tapped move")
	view.advance_animation(view.move_time / 2)
	check(view.is_animating(), "Still sliding halfway")
	view.advance_animation(view.move_time)
	check(not view.is_animating(), "Finished")
	view.free()

func test_dragged_move_slams_instead_of_sliding() -> void:
	var view := _sized_view(StandardSetup.create_game())
	# Make the move the way the game screen does.
	view.move_chosen.connect(func(move: Move) -> void:
		view.state.make_move(move)
		view.show_move(move))
	_drag(view, "e2", "e4")
	check_eq(chosen.size(), 1, "Moved")
	var piece := view.state.board.get_piece(_square("e4"))
	check(view.current_animation() != null and view.current_animation().has_segment(piece, "slam"), "Dropped: it slams down")
	check(not view.current_animation().has_segment(piece, "slide"), "No slide: the piece is already there")
	view.free()

func test_capture_fades_and_undo_slides_back() -> void:
	var view := _view_for(StandardSetup.from_fen("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1"))
	_played(view, "e4xd5")
	check(view.is_animating(), "Capture animates")
	view.advance_animation(1.0)
	var move: Move = view.state.history.back()
	view.state.undo_move(move)
	var undone: Array[Move] = [move]
	view.show_undo(undone)
	check(view.is_animating(), "Undo animates")
	view.advance_animation(1.0)
	check(not view.is_animating(), "Finished")
	view.free()

func test_no_animation_when_turned_off() -> void:
	var view := _view_for(StandardSetup.create_game())
	view.move_time = 0
	_played(view, "e2-e4")
	check(not view.is_animating(), "Nothing slides")
	view.free()

func test_illegal_tap_shakes_the_piece() -> void:
	var view := _view_for(StandardSetup.create_game())
	view.tap(_square("e2"))
	view.tap(_square("e5"))
	check(view.is_shaking(_square("e2")), "e2 shakes")
	view.advance_animation(1.0)
	check(not view.is_shaking(_square("e2")), "Then stops")
	view.free()

# --- Arrows (right mouse button) ---------------------------------------------------

func _right_drag(view: BoardView, from: String, to: String) -> void:
	view.right_down(view.square_center(_square(from)))
	view.right_up(view.square_center(_square(to)))

func test_right_drag_draws_arrows() -> void:
	var view := _sized_view(StandardSetup.create_game())
	_right_drag(view, "e2", "e4")
	_right_drag(view, "g1", "f3")
	check_eq(view.arrows.size(), 2, "Two arrows")
	_right_drag(view, "e2", "e4")
	check_eq(view.arrows.size(), 1, "Drawing the same arrow again removes it")
	view.pointer_down(view.square_center(_square("d5")), false)
	view.pointer_up(view.square_center(_square("d5")))
	check_eq(view.arrows.size(), 0, "A left click clears them")
	view.free()

func test_right_click_rings_a_square() -> void:
	var view := _sized_view(StandardSetup.create_game())
	view.right_click(view.square_center(_square("d5")))
	check_eq(view.highlights, [_square("d5")] as Array[Vector2i], "d5 ringed")
	view.right_click(view.square_center(_square("e2")))
	check_eq(view.highlights.size(), 2, "A square with a piece can be ringed too")
	view.right_click(view.square_center(_square("d5")))
	check_eq(view.highlights, [_square("e2")] as Array[Vector2i], "Right-clicking it again takes the ring off")
	_right_drag(view, "g1", "f3")
	check_eq(view.highlights.size(), 1, "Drawing an arrow leaves the rings")
	view.pointer_down(view.square_center(_square("a4")), false)
	view.pointer_up(view.square_center(_square("a4")))
	check(view.highlights.is_empty() and view.arrows.is_empty(), "A left click clears rings and arrows")
	view.free()

func test_a_move_clears_the_rings() -> void:
	var view := _sized_view(StandardSetup.create_game())
	view.right_click(view.square_center(_square("d5")))
	var move := view.state.find_move("e2-e4")
	view.state.make_move(move)
	view.show_move(move)
	check(view.highlights.is_empty(), "Cleared by the move")
	view.free()

func test_a_move_clears_the_arrows() -> void:
	var view := _sized_view(StandardSetup.create_game())
	_right_drag(view, "e2", "e4")
	var move := view.state.find_move("e2-e4")
	view.state.make_move(move)
	view.show_move(move)
	check_eq(view.arrows.size(), 0, "Cleared by the move")
	view.free()

# --- Flipped board (Black at the bottom) -------------------------------------------

func test_flipped_board_puts_black_at_the_bottom() -> void:
	var view := _sized_view(StandardSetup.create_game())
	var a1 := view.square_center(_square("a1"))
	var h8 := view.square_center(_square("h8"))
	check(a1.y > h8.y and a1.x < h8.x, "Normally a1 is bottom-left")
	view.flipped = true
	a1 = view.square_center(_square("a1"))
	h8 = view.square_center(_square("h8"))
	check(a1.y < h8.y and a1.x > h8.x, "Flipped: a1 is top-right, h8 bottom-left")
	view.free()

func test_taps_and_drags_follow_the_flip() -> void:
	var game := StandardSetup.create_game()
	game.make_move(game.find_move("e2-e4"))
	var view := _sized_view(game)
	view.flipped = true
	# Drag Black's e-pawn as it appears on the flipped board.
	_drag(view, "e7", "e5")
	check_eq(chosen.size(), 1, "Moved")
	if chosen.size() == 1:
		check_eq(chosen[0].to_text(), "e7-e5", "The right squares")
	view.free()

func test_coordinates_follow_the_flip() -> void:
	var view := _sized_view(StandardSetup.create_game())
	var letters := view.edge_labels().filter(func(l: Array) -> bool: return not (l[1] as String).is_valid_int())
	check_eq(letters.map(func(l: Array) -> String: return l[1]), ["a", "b", "c", "d", "e", "f", "g", "h"], "Files a to h")
	check(letters.all(func(l: Array) -> bool: return l[0].y == 0), "Along White's back rank")
	view.flipped = true
	letters = view.edge_labels().filter(func(l: Array) -> bool: return not (l[1] as String).is_valid_int())
	check(letters.all(func(l: Array) -> bool: return l[0].y == 7), "Flipped: along Black's back rank")
	var numbers := view.edge_labels().filter(func(l: Array) -> bool: return (l[1] as String).is_valid_int())
	check(numbers.all(func(l: Array) -> bool: return l[0].x == 7), "Flipped: numbers down the h-file side")
	view.free()

func test_pieces_with_an_unused_ability_glow() -> void:
	var defs := PieceCatalog.all_defs()
	var archer := Piece.new(defs.filter(func(d: PieceDef) -> bool: return d.id == "archer")[0], Piece.Team.WHITE)
	check(BoardView.has_ability_ready(archer), "An Archer with Crack Shot ready glows")
	archer.ability_used = true
	check(not BoardView.has_ability_ready(archer), "Not once it's used")
	var knight := Piece.new(load("res://data/pieces/knight.tres"), Piece.Team.WHITE)
	check(not BoardView.has_ability_ready(knight), "Pieces without abilities don't")

func test_silhouette_is_the_picture_in_white() -> void:
	for def: PieceDef in [load("res://data/pieces/knight.tres"), load("res://data/pieces/vampire.tres")]:
		for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
			var picture := PieceArt.texture_for(def, team, "standard").get_image()
			picture.decompress()
			picture.convert(Image.FORMAT_RGBA8)
			var white := BoardView.silhouette(PieceArt.texture_for(def, team, "standard")).get_image()
			check_eq(white.get_size(), picture.get_size(), "Same size")
			var wrong := 0
			for y in range(0, picture.get_height(), 7):
				for x in range(0, picture.get_width(), 7):
					var c := white.get_pixel(x, y)
					if c.r8 != 255 or c.g8 != 255 or c.b8 != 255 or c.a8 != picture.get_pixel(x, y).a8:
						wrong += 1
			check_eq(wrong, 0, "Every pixel white, as see-through as the picture: %s" % def.id)
	BoardView.clear_cache()
