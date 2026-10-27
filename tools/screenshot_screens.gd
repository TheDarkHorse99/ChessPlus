extends SceneTree

## Opens the whole app (the main scene) and saves a picture of every screen, to
## check something that shows on all of them (e.g. the look, or the volume button).
## Run (needs a window, so not --headless):
##   "<godot console exe>" --path . --resolution 720x1280 -s res://tools/screenshot_screens.gd -- <out folder> [open]
## "open" also opens the volume slider before each picture.
## Saves <out folder>/<screen>.png for: menu, settings, armies, builder, setup,
## setup_bot, game, game_over, card, online, testing, dialog.
## Uses its own saved armies (two examples, deleted afterwards), never yours.

const ARMIES_DIR := "user://screenshot_armies/"

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "user://screens"
	var open := args.has("open")
	SavedGame.save_path = "user://screenshot_screens_game.json"
	# Its own settings file, so the real one is left alone (the first-launch
	# How to play page is shown on purpose below).
	UserSettings.save_path = "user://screenshot_settings.cfg"
	UserSettings.set_how_to_play_seen(true)
	PlusfishLink.enabled = false
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.library = _example_library()
	root.add_child(main)
	await process_frame
	var shows := {
		"menu": main.show_main_menu,
		"settings": main.show_settings,
		"howto": main.show_how_to_play,
		"armies": main.show_army_list,
		"builder": func() -> void: main.show_army_builder(main.library.armies()[0]),
		"setup": main.show_match_setup,
		"setup_bot": func() -> void:
			main.show_match_setup()
			main.screen.opponent_pick.select(1)
			main.screen.opponent_pick.item_selected.emit(1),
		"game": func() -> void:
			main.start_game(StandardSetup.army(), StandardSetup.army())
			main.screen.board_view.move_time = 0.0
			for san in ["e4", "e5", "Nf3", "Nc6", "Bc4"]:
				main.screen.play(Notation.find_move(main.screen.state, san)),
		"game_over": func() -> void:
			main.start_game(StandardSetup.army(), StandardSetup.army())
			main.screen.board_view.move_time = 0.0
			for san in ["f3", "e5", "g4", "Qh4"]:
				main.screen.play(Notation.find_move(main.screen.state, san))
			main.screen._stop_checkmate_effect(),
		"card": func() -> void:
			main.start_game(StandardSetup.army(), StandardSetup.army())
			PieceInfo.open(main.screen, load("res://data/pieces/knight.tres"), Piece.Team.WHITE),
		"online": main.show_online_lobby.bind(MemoryBackend.new()),
		"testing": main.show_testing_setup,
		"dialog": func() -> void:
			main.show_army_list()
			main.screen.ask_import(),
	}
	for screen_name: String in shows:
		(shows[screen_name] as Callable).call()
		for i in 20:
			await process_frame
		main.volume_control.set_open(open)
		for i in 5:
			await process_frame
		var path := out_dir.path_join(screen_name + ".png")
		root.get_texture().get_image().save_png(path)
		print("Saved ", path)
	DirAccess.remove_absolute(SavedGame.save_path)
	DirAccess.remove_absolute(UserSettings.save_path)
	for army in main.library.armies():
		main.library.delete(army)
	DirAccess.remove_absolute(ARMIES_DIR)
	main.free()
	MemoryBackend.clear()
	quit()

## Two saved armies to show in the lists: the standard set, and a small one.
func _example_library() -> ArmyLibrary:
	var library := ArmyLibrary.new(ARMIES_DIR)
	for army in library.armies():
		library.delete(army)
	var standard := StandardSetup.army()
	standard.army_name = "Classic"
	library.save(standard)
	var small := Army.new()
	small.army_name = "Wizards and wolves"
	small.place(load("res://data/pieces/king.tres"), Vector2i(4, 0))
	small.place(load("res://data/pieces/wizard.tres"), Vector2i(3, 0))
	small.place(load("res://data/pieces/werewolf.tres"), Vector2i(2, 1))
	small.place(load("res://data/pieces/pawn.tres"), Vector2i(4, 1))
	library.save(small)
	return library
