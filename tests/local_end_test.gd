extends TestSuite

## Ending local games (Mac, Oct 2026): Resign, and games left 2 days without a
## move ending on their own.

func _open(bot_team := -1) -> Node:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	game.white_army = StandardSetup.army()
	game.black_army = StandardSetup.army()
	game.bot_team = bot_team
	game.bot_level = PracticeBot.Level.EASY
	game.bot_delay_frames = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(game)
	return game

func _play(game: Node, san: String) -> void:
	var move := Notation.find_move(game.state, san)
	check(move != null, "Should be legal: " + san)
	if move:
		game.play(move)

func test_two_players_resign_on_the_second_tap() -> void:
	var game := _open()
	check(game.resign_button.visible, "Local games have Resign")
	_play(game, "e4")
	game.resign_local()
	check(not game.is_over(), "One tap only asks")
	check_eq(game.resign_button.text, "Tap again", "...for a second tap")
	game.resign_local()
	check(game.is_over(), "Second tap resigns")
	check_eq(game.result_texts(), ["Black resigned", "White wins"], "Whoever's turn it was resigns")
	check_eq(game.status_label.text, "Black resigned - White wins", "Status says so")
	game.choose(Notation.find_move(game.board_view.state, "e5"))
	check_eq(game.state.history.size(), 1, "No more moves in the game: a move on the board...")
	check_eq(game.side_lines.size(), 1, "...goes into a side line")
	check(game.game_over_panel.visible, "Result screen")
	check(SavedGame.load_saved() == null, "The saved game is gone")
	game.undo()
	check(not game.is_over(), "Undo takes the resignation back")
	check_eq(game.state.history.size(), 1, "...without undoing a move")
	check(game.board_view.input_enabled, "Play on")
	check(game.side_lines.is_empty() and game.viewing < 0, "...back in the game, its side line gone (two players: only after the game)")
	check(SavedGame.load_saved() != null, "Saved again")
	game.free()
	SavedGame.delete_saved()

func test_resigning_against_the_bot() -> void:
	var game := _open(Piece.Team.BLACK)
	_play(game, "e4")
	game.resign_local()
	game.resign_local()
	check_eq(game.result_texts(), ["You resigned", "The bot wins"], "You lose")
	check_eq(game._resigned_result(), "0-1", "Written 0-1")
	game.new_game()
	check(not game.is_over(), "New game starts fresh")
	game.free()
	SavedGame.delete_saved()

func test_online_games_keep_their_own_resign() -> void:
	var game := _open()
	check(game.resign_button.visible, "Shown in local games")
	game.free()
	SavedGame.delete_saved()

func test_games_left_two_days_end() -> void:
	var saved := SavedGame.from_state(StandardSetup.create_game(), StandardSetup.army(), StandardSetup.army(), -1, 0)
	var now := 1_800_000_000.0
	saved.started_time = now - 5 * 86400
	saved.save(now - 86400)
	check_eq(SavedGame.end_if_abandoned(now), "", "A day without a move: still going")
	check(SavedGame.load_saved() != null, "...and still saved")
	saved.save(now - 2 * 86400 - 1)
	var note := SavedGame.end_if_abandoned(now)
	check(note.begins_with("Your game from ") and note.ends_with("was ended because no move was made for 2 days."), "Over 2 days: ended with a note: " + note)
	check(SavedGame.load_saved() == null, "The saved game is gone")
	check_eq(SavedGame.end_if_abandoned(now), "", "Nothing more to say next time")

func test_old_saves_start_their_clock() -> void:
	var saved := SavedGame.from_state(StandardSetup.create_game(), StandardSetup.army(), StandardSetup.army(), -1, 0)
	saved.save(0.0)
	var file := FileAccess.open(SavedGame.save_path, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	data.erase("saved")
	file = FileAccess.open(SavedGame.save_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	check_eq(SavedGame.end_if_abandoned(1_800_000_000.0), "", "A save with no time isn't ended")
	check_eq(SavedGame.load_saved().saved_time, 1_800_000_000.0, "Its clock starts now")
	SavedGame.delete_saved()

func test_date_text() -> void:
	var text := SavedGame.date_text(1_800_000_000.0)
	check(text.length() >= 5 and text.split(" ").size() == 2, "Like 'Jan 15': " + text)

func test_bot_reply_notifies_in_the_background() -> void:
	var game := _open(Piece.Team.BLACK)
	TurnNotifier.sent.clear()
	TurnNotifier.force_background = true
	_play(game, "e4")
	TurnNotifier.force_background = false
	check_eq(TurnNotifier.sent.size(), 1, "Told when the bot has replied")
	check(TurnNotifier.sent[0].begins_with("Overchess: your move: The bot played "), TurnNotifier.sent[0] if not TurnNotifier.sent.is_empty() else "")
	TurnNotifier.sent.clear()
	game.free()
	SavedGame.delete_saved()
