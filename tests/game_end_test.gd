extends TestSuite

const Outcome = GameState.Outcome

func _play(state: GameState, texts: Array) -> void:
	for text in texts:
		var move := state.find_move(text)
		check(move != null, "Move should be available: " + text)
		if move == null:
			return
		state.make_move(move)

func test_game_in_progress() -> void:
	var state := StandardSetup.create_game()
	check_eq(state.outcome(), Outcome.NONE, "Start position")
	check_eq(state.result_text(), "*", "Result")

func test_checkmate() -> void:
	var state := StandardSetup.create_game()
	_play(state, ["f2-f3", "e7-e5", "g2-g4", "d8-h4"])
	check_eq(state.outcome(), Outcome.CHECKMATE, "Fool's mate")
	check_eq(state.result_text(), "0-1", "Black wins")

func test_stalemate() -> void:
	var state := StandardSetup.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
	check_eq(state.outcome(), Outcome.STALEMATE, "Stalemate")
	check_eq(state.result_text(), "1/2-1/2", "Draw")

func test_fifty_moves() -> void:
	var state := StandardSetup.from_fen("4k3/8/8/8/8/8/8/R3K3 w - - 99 60")
	check_eq(state.outcome(), Outcome.NONE, "99 half-moves")
	_play(state, ["a1-a2"])
	check_eq(state.halfmove_clock, 100, "Clock")
	check_eq(state.outcome(), Outcome.FIFTY_MOVES, "100 half-moves")

func test_checkmate_beats_fifty_moves() -> void:
	var state := StandardSetup.from_fen("7k/8/6K1/8/8/8/8/R7 w - - 99 80")
	_play(state, ["a1-a8"])
	check_eq(state.outcome(), Outcome.CHECKMATE, "Mate on the 100th half-move")
	check_eq(state.result_text(), "1-0", "White wins")

func test_capture_and_pawn_move_reset_clock() -> void:
	var state := StandardSetup.from_fen("4k3/8/8/3p4/8/8/4P3/R3K3 w - - 30 40")
	_play(state, ["a1-a2"])
	check_eq(state.halfmove_clock, 31, "After a rook move")
	_play(state, ["e8-e7", "e2-e4"])
	check_eq(state.halfmove_clock, 0, "After a pawn move")
	_play(state, ["d5xe4"])
	check_eq(state.halfmove_clock, 0, "After a capture")
	state.undo_move(state.history.back())
	state.undo_move(state.history.back())
	check_eq(state.halfmove_clock, 32, "Undo restores the clock")

func test_threefold_repetition() -> void:
	var state := StandardSetup.create_game()
	var shuffle := ["g1-f3", "g8-f6", "f3-g1", "f6-g8"]
	_play(state, shuffle)
	check_eq(state.outcome(), Outcome.NONE, "Start position seen twice")
	_play(state, shuffle)
	check_eq(state.outcome(), Outcome.REPETITION, "Start position seen three times")
	check_eq(Fen.write(state).split(" ")[0], "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", "Checking left the board as it was")
	check_eq(state.history.size(), 8, "Checking left the history as it was")

func test_lost_castling_rights_make_a_new_position() -> void:
	# Kings step out and back: same squares, but castling rights are gone,
	# so the first position doesn't count toward the repetition.
	var state := StandardSetup.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
	_play(state, ["e1-f1", "e8-f8", "f1-e1", "f8-e8", "e1-f1", "e8-f8", "f1-e1", "f8-e8"])
	check_eq(state.outcome(), Outcome.NONE, "Only two repetitions without castling rights")
	_play(state, ["e1-f1", "e8-f8", "f1-e1", "f8-e8"])
	check_eq(state.outcome(), Outcome.REPETITION, "Third time")

func test_checkmate_impossible() -> void:
	var dead := {
		"King vs king": "4k3/8/8/8/8/8/8/4K3 w - - 0 1",
		"King and knight vs king": "4k3/8/8/8/8/8/8/1N2K3 w - - 0 1",
		"King and bishop vs king": "4k3/8/8/8/8/8/8/2B1K3 w - - 0 1",
		"Bishops on the same color": "4kb2/8/8/8/8/8/8/2B1K3 w - - 0 1",
	}
	for name in dead:
		check_eq(StandardSetup.from_fen(dead[name]).outcome(), Outcome.INSUFFICIENT_MATERIAL, name)
	var alive := {
		"Bishops on opposite colors": "2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1",
		"Two knights": "4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1",
		"Knight and bishop": "4k3/8/8/8/8/8/8/1NB1K3 w - - 0 1",
		"Rook": "4k3/8/8/8/8/8/8/R3K3 w - - 0 1",
		"Pawn": "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1",
	}
	for name in alive:
		check_eq(StandardSetup.from_fen(alive[name]).outcome(), Outcome.NONE, name)

func test_capture_into_bare_kings() -> void:
	var state := StandardSetup.from_fen("4k3/8/8/8/8/8/3q4/4K3 w - - 0 1")
	_play(state, ["e1xd2"])
	check_eq(state.outcome(), Outcome.INSUFFICIENT_MATERIAL, "Only kings left")

func test_threefold_repetition_asked_after_every_move() -> void:
	# The game screen asks after every move, so each position's key is kept and
	# the count is made from those instead of stepping back.
	var state := StandardSetup.create_game()
	var outcomes := []
	for i in 2:
		for text in ["g1-f3", "g8-f6", "f3-g1", "f6-g8"]:
			_play(state, [text])
			outcomes.append(state.outcome())
	check_eq(outcomes.count(Outcome.REPETITION), 1, "Only the last position is the third time")
	check_eq(outcomes.back(), Outcome.REPETITION, "Start position seen three times")
	# Undo and play it again: still the third time.
	var last: Move = state.history.back()
	state.undo_move(last)
	check_eq(state.outcome(), Outcome.NONE, "Taken back")
	_play(state, ["f6-g8"])
	check_eq(state.outcome(), Outcome.REPETITION, "Played again")

func test_a_board_changed_by_hand_is_a_new_position() -> void:
	var state := StandardSetup.create_game()
	_play(state, ["g1-f3", "g8-f6", "f3-g1", "f6-g8"])
	check_eq(state.outcome(), Outcome.NONE, "Seen twice")
	# Take a pawn off where nothing was captured: earlier positions had it.
	state.board.set_piece(Board.parse_square("a2"), null)
	_play(state, ["g1-f3", "g8-f6", "f3-g1", "f6-g8"])
	check_eq(state.outcome(), Outcome.NONE, "Not the same as before the pawn went")

## Mac's 75-move rule (Oct 2026): 150 plies with no change to the pieces on
## the board is a draw. Pawn moves don't reset it (they do reset the 50-move
## clock); captures, shield breaks, promotions, Raise Dead, Haunt and Full
## Moon do.
func test_seventy_five_moves() -> void:
	var state := StandardSetup.from_fen("4k3/8/8/8/8/8/4P3/R3K3 w - - 0 60 unchanged=148")
	check_eq(state.change_clock, 148, "FEN carries the count")
	_play(state, ["e2-e3"])
	check_eq(state.halfmove_clock, 0, "A pawn move resets the 50-move clock")
	check_eq(state.change_clock, 149, "...but not the 75-move count")
	check_eq(state.outcome(), Outcome.NONE, "149 plies")
	_play(state, ["e8-e7"])
	check_eq(state.outcome(), Outcome.SEVENTY_FIVE_MOVES, "150 plies without a change to the pieces")
	check_eq(state.result_text(), "1/2-1/2", "A draw")
	check_eq(Fen.write(state), "8/4k3/8/8/8/4P3/8/R3K3 w - - 1 61 unchanged=150", "FEN writes the count when it differs")
	state.undo_move(state.history.back())
	check_eq(state.change_clock, 149, "Undo restores the count")
	check_eq(state.outcome(), Outcome.NONE, "Not over after the undo")

func test_checkmate_beats_seventy_five_moves() -> void:
	var state := StandardSetup.from_fen("7k/8/6K1/8/8/8/8/R7 w - - 10 80 unchanged=149")
	_play(state, ["a1-a8"])
	check_eq(state.outcome(), Outcome.CHECKMATE, "Mate on the 150th ply")

func test_plain_fen_has_no_count() -> void:
	var state := StandardSetup.from_fen("4k3/8/8/8/8/8/8/R3K3 w - - 7 60")
	check_eq(state.change_clock, 7, "Left out, the count equals the halfmove clock")
	check_eq(Fen.write(state), "4k3/8/8/8/8/8/8/R3K3 w - - 7 60", "...and isn't written")

func _parse_all(fen: String) -> GameState:
	return Fen.parse(fen, PieceCatalog.all_defs(), StandardSetup.create_rules())

func test_what_resets_the_seventy_five_move_count() -> void:
	var state := _parse_all("4k3/6P1/8/8/8/3r4/8/R3K3 w - - 0 1 unchanged=40")
	_play(state, ["a1-a2", "d3-d4"])
	check_eq(state.change_clock, 42, "Quiet moves add one each")
	_play(state, ["g7-g8=N"])
	check_eq(state.change_clock, 0, "A promotion resets it")
	_play(state, ["d4-d2", "a2xd2"])
	check_eq(state.change_clock, 0, "A capture resets it")
	state.undo_move(state.history.back())
	check_eq(state.change_clock, 1, "Undo puts the count back")
	# A shield break (the attacker stays put).
	state = _parse_all("4k3/8/8/8/8/(pd)7/8/R3K3 w - - 0 1 unchanged=30")
	_play(state, ["a1xa3"])
	check_eq(state.change_clock, 0, "A shield break resets it")
	# Raise Dead.
	state = _parse_all("4k3/8/8/8/8/8/8/(NC)3K3 w - - 0 1 unchanged=30")
	state.lost[Piece.Team.WHITE].append(Piece.new(load("res://data/pieces/archer.tres"), Piece.Team.WHITE))
	_play(state, ["a1!=A"])
	check_eq(state.change_clock, 0, "Raise Dead resets it")
	# Haunt (a lost Ghost that had moved).
	state = _parse_all("4k3/8/8/8/8/8/8/4K3 w - - 0 1 unchanged=30")
	var ghost := Piece.new(load("res://data/pieces/ghost.tres"), Piece.Team.WHITE)
	ghost.has_moved = true
	state.lost[Piece.Team.WHITE].append(ghost)
	_play(state, ["@e4"])
	check_eq(state.change_clock, 0, "Haunt resets it")
	# Full Moon.
	state = _parse_all("4k3/8/8/8/8/8/8/(WW)3K3 w - - 0 1 unchanged=30")
	var moon: Array = state.moves().filter(func(m: Move) -> bool: return m.ability == PieceDef.Ability.FULL_MOON)
	check_eq(moon.size(), 1, "The Werewolf can transform")
	state.make_move(moon[0])
	check_eq(state.change_clock, 0, "Full Moon resets it")
	# Song of Slumber changes nothing on the board.
	state = _parse_all("4k3/8/8/8/8/2r5/8/(BD)3K3 w - - 0 1 unchanged=30")
	var song: Array = state.moves().filter(func(m: Move) -> bool: return m.ability == PieceDef.Ability.SONG_OF_SLUMBER)
	check(not song.is_empty(), "The Bard can sing to the rook")
	state.make_move(song[0])
	check_eq(state.change_clock, 31, "Song of Slumber doesn't reset it")
	# Castling doesn't either.
	state = _parse_all("4k3/8/8/8/8/8/8/R3K3 w Q - 0 1 unchanged=30")
	_play(state, ["e1-c1"])
	check_eq(state.change_clock, 31, "Castling doesn't reset it")
