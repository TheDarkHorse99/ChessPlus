extends TestSuite

## The Settings screen (Mac's design, Oct 2026): sound groups with their own
## volumes, notifications, credits and Reset to defaults.

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

func _open() -> SettingsMenu:
	var settings := SettingsMenu.new()
	_root().add_child(settings)
	return settings

func _finish() -> void:
	UserSettings.reset_to_defaults()
	UserSettings.set_sound_on(false)  # Tests run silently (see run_tests.gd).
	GameSounds.apply_volume()

func test_each_sound_group_has_its_own_volume() -> void:
	var settings := _open()
	settings.group_sliders["warnings"].value = 25
	check_eq(UserSettings.group_volume("warnings"), 0.25, "Saved")
	check_eq(UserSettings.group_volume("moves"), 1.0, "The others unchanged")
	var bus := GameSounds.bus_index("warnings")
	check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.25 * 0.25)), "Its sound bus follows")
	settings.group_sliders["effects"].value = 0
	check(AudioServer.is_bus_mute(GameSounds.bus_index("effects")), "0% mutes that group")
	settings.free()
	_finish()

func test_sounds_are_sorted_into_groups() -> void:
	check_eq(GameSounds.group_of(GameSounds.Sound.CHECK), "warnings", "Check is a warning")
	check_eq(GameSounds.group_of(GameSounds.Sound.ILLEGAL), "warnings", "So is the buzz")
	check_eq(GameSounds.group_of(GameSounds.Sound.CAPTURE), "moves", "A capture is a move sound")
	check_eq(GameSounds.group_of(GameSounds.Sound.CHOIR), "effects", "Promotion's choir is an effect")
	check_eq(GameSounds.group_of(GameSounds.Sound.THUNDER), "effects", "So is Raise Dead's thunder")
	check_eq(AudioServer.get_bus_send(GameSounds.bus_index("moves")), &"Master", "Group buses feed the main volume")

func test_notifications_can_be_switched_off() -> void:
	var settings := _open()
	TurnNotifier.force_background = true
	TurnNotifier.sent.clear()
	settings.notifications_toggle.button_pressed = false
	check(not UserSettings.notifications_on(), "Saved")
	TurnNotifier.your_turn("Your opponent played e5.")
	check(TurnNotifier.sent.is_empty(), "No notification while switched off")
	settings.notifications_toggle.button_pressed = true
	TurnNotifier.your_turn("Your opponent played e5.")
	check_eq(TurnNotifier.sent.size(), 1, "Back on: notified")
	TurnNotifier.force_background = false
	TurnNotifier.sent.clear()
	settings.free()
	_finish()

func test_credits_and_reset() -> void:
	var settings := _open()
	settings.show_credits()
	var text := ""
	for child in settings.popup.column.get_children():
		if child is Label:
			text += (child as Label).text + "\n"
	check(text.contains("Cburnett (CC BY-SA 3.0)"), "The pieces' credit")
	check(text.contains("Coro Santa Pazienza"), "The choir's credit")
	settings.popup.close()
	settings.volume_slider.value = 40
	settings.group_sliders["moves"].value = 10
	settings.notifications_toggle.button_pressed = false
	settings.reset_to_defaults()
	check_eq(UserSettings.volume(), 1.0, "Volume back to full")
	check_eq(UserSettings.group_volume("moves"), 1.0, "Group volumes back")
	check(UserSettings.notifications_on(), "Notifications back on")
	check_eq(settings.volume_slider.value, 100.0, "The screen shows it")
	settings.free()
	_finish()

func test_privacy_notice() -> void:
	var settings := _open()
	var labels := []
	for child in settings.sections.get_children():
		if child is Button:
			labels.append((child as Button).text)
	check(labels.has("Privacy"), "A Privacy button beside Credits")
	settings.show_privacy()
	var text := ""
	for child in settings.popup.paragraphs.get_children():
		if child is Label:
			text += (child as Label).text + "
"
	check(text.contains("no accounts"), "Says there are no accounts")
	check(text.contains("30 days"), "Says how long games are kept")
	check(text.contains("not the chat"), "Says strangers can't read the chat")
	check(text.contains("90 days"), "Says how long reports are kept")
	settings.popup.close()
	settings.free()
	_finish()

func test_main_menu_opens_settings_and_back() -> void:
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.library = ArmyLibrary.new("user://test_armies/")
	_root().add_child(main)
	main.screen.get_node("%Settings").pressed.emit()
	check(main.screen is SettingsMenu, "Settings opens from the main menu")
	(main.screen as SettingsMenu).close()
	check(main.screen.scene_file_path == "res://scenes/menu/main_menu.tscn", "Back returns to the main menu")
	main.free()

func _board() -> BoardView:
	var view := BoardView.new()
	view.size = Vector2(640, 640)
	_root().add_child(view)
	view.show_game(StandardSetup.create_game())
	return view

func test_animation_speed() -> void:
	var settings := _open()
	settings.speed_buttons["slow"].pressed.emit()
	check_eq(UserSettings.animation_speed(), "slow", "Saved")
	var view := _board()
	check(is_equal_approx(view.move_time, BoardView.BASE_MOVE_TIME * 1.5), "The board plays animations 1.5x as long")
	settings.speed_buttons["off"].pressed.emit()
	view.apply_settings()
	check_eq(view.move_time, 0.0, "Off: no animation")
	settings.reset_to_defaults()
	view.apply_settings()
	check(is_equal_approx(view.move_time, BoardView.BASE_MOVE_TIME), "Reset: normal again")
	check(settings.speed_buttons["normal"].button_pressed, "...and the screen shows Normal")
	view.free()
	settings.free()
	_finish()

func test_board_helpers_and_reduced_effects() -> void:
	var settings := _open()
	settings.helper_toggles["coordinates"].button_pressed = false
	settings.helper_toggles["move_dots"].button_pressed = false
	settings.reduce_toggle.button_pressed = true
	var view := _board()
	check(not view.helpers.coordinates and not view.helpers.move_dots, "The board takes the switches")
	check(view.helpers.last_move and view.helpers.ability_glow, "...and leaves the others on")
	check(view.reduce_effects, "Reduce flashing and shaking")
	check(UserSettings.board_helper("last_move"), "Saved per helper")
	view.free()
	settings.free()
	_finish()

func _key(code: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code & KEY_CODE_MASK
	event.ctrl_pressed = code & KEY_MASK_CTRL != 0
	event.pressed = true
	return event

func test_keys_can_be_changed_and_swap() -> void:
	var settings := _open()
	check_eq(settings.key_buttons["flip_board"].text, "F", "Flip starts on F")
	settings.key_buttons["flip_board"].pressed.emit()
	check_eq(settings.key_buttons["flip_board"].text, "Press a key...", "Waiting for a key")
	settings._input(_key(KEY_B))
	check_eq(KeyBinds.key("flip_board"), KEY_B, "Now on B")
	check_eq(KeyBinds.action_for(_key(KEY_B)), "flip_board", "The InputMap follows")
	check_eq(KeyBinds.action_for(_key(KEY_F)), "", "F does nothing now")
	settings.listen_for_key("piece_card")
	settings._input(_key(KEY_B))
	check_eq(KeyBinds.key("piece_card"), KEY_B, "The piece card takes B...")
	check_eq(KeyBinds.key("flip_board"), KEY_I, "...and flip gets its old key (I): no key does two things")
	check_eq(KeyBinds.text(KeyBinds.key("undo")), "Ctrl+Z", "Undo shows Ctrl+Z")
	settings.reset_to_defaults()
	check_eq(KeyBinds.key("flip_board"), KEY_F, "Reset: back to F")
	check_eq(KeyBinds.action_for(_key(KEY_F)), "flip_board", "...in the InputMap too")
	settings.free()
	_finish()

func _click(index: int, pressed := true, pos := Vector2.ZERO) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = pos
	return event

func test_mouse_buttons_can_be_changed_and_swap() -> void:
	var settings := _open()
	check_eq(settings.mouse_buttons["move"].text, "Left click", "Moving starts on the left button")
	check_eq(settings.mouse_buttons["mark"].text, "Right click", "Marking on the right")
	check_eq(settings.mouse_buttons["piece_card"].text, "Middle click", "The piece card on the middle")
	settings.mouse_buttons["piece_card"].pressed.emit()
	check_eq(settings.mouse_buttons["piece_card"].text, "Click...", "Waiting for a click")
	settings._input(_click(MOUSE_BUTTON_WHEEL_UP))
	check_eq(settings.listening_mouse, "piece_card", "The scroll wheel doesn't count")
	settings._input(_click(MOUSE_BUTTON_XBUTTON1))
	check_eq(MouseBinds.button("piece_card"), MOUSE_BUTTON_XBUTTON1, "Piece card on a side button")
	check_eq(settings.mouse_buttons["piece_card"].text, "Side button 1", "...and it says so")
	settings.listen_for_mouse("move")
	settings._input(_click(MOUSE_BUTTON_RIGHT))
	check_eq(MouseBinds.button("move"), MOUSE_BUTTON_RIGHT, "Moving takes the right button...")
	check_eq(MouseBinds.button("mark"), MOUSE_BUTTON_LEFT, "...and marking gets the left: no button does two things")
	settings.listen_for_mouse("mark")
	settings._input(_key(KEY_ESCAPE))
	check_eq(settings.listening_mouse, "", "Esc stops waiting")
	check_eq(MouseBinds.button("mark"), MOUSE_BUTTON_LEFT, "...and changes nothing")
	settings.listen_for_key("flip_board")
	settings.listen_for_mouse("mark")
	check_eq(settings.listening, "", "Waiting for a click stops waiting for a key")
	settings.listening_mouse = ""
	settings.reset_to_defaults()
	check_eq(MouseBinds.button("move"), MOUSE_BUTTON_LEFT, "Reset: moving back on the left")
	check_eq(MouseBinds.button("piece_card"), MOUSE_BUTTON_MIDDLE, "...the piece card on the middle")
	settings.free()
	_finish()

func test_the_board_follows_the_mouse_settings() -> void:
	var view := BoardView.new()
	view.show_game(StandardSetup.create_game())
	view.size = Vector2(800, 800)
	var cards: Array[Piece] = []
	view.info_requested.connect(func(piece: Piece) -> void: cards.append(piece))
	var e2 := view.square_center(Board.parse_square("e2"))
	var e5 := view.square_center(Board.parse_square("e5"))
	MouseBinds.set_button("move", MOUSE_BUTTON_RIGHT)
	MouseBinds.set_button("piece_card", MOUSE_BUTTON_XBUTTON1)
	check_eq(MouseBinds.button("mark"), MOUSE_BUTTON_LEFT, "Marking moved to the left button")
	view._gui_input(_click(MOUSE_BUTTON_RIGHT, true, e2))
	view._gui_input(_click(MOUSE_BUTTON_RIGHT, false, e2))
	check_eq(view.selected_square(), Board.parse_square("e2"), "Right click picks up the pawn")
	view._gui_input(_click(MOUSE_BUTTON_LEFT, true, e5))
	view._gui_input(_click(MOUSE_BUTTON_LEFT, false, e5))
	check(view.highlights.has(Board.parse_square("e5")), "Left click marks a square")
	view.clear_drawings()
	view._gui_input(_click(MOUSE_BUTTON_MIDDLE, true, e2))
	check_eq(cards.size(), 0, "Middle click does nothing now")
	view._gui_input(_click(MOUSE_BUTTON_XBUTTON1, true, e2))
	check_eq(cards.size(), 1, "The side button asks for the piece card")
	var game_script: GDScript = load("res://scenes/game/game.gd")
	check(game_script.tip_text(false).contains("click side button 1 on"), "The tip names the side button")
	check(game_script.tip_text(true).contains("hold"), "Phones: still hold")
	# A finger on a touch screen arrives as a pretend left click: it still moves.
	var touch := _click(MOUSE_BUTTON_LEFT, true, e2)
	touch.device = InputEvent.DEVICE_ID_EMULATION
	view._gui_input(touch)
	check_eq(view.selected_square(), Board.parse_square("e2"), "A touch picks up the pawn")
	check(view.highlights.is_empty(), "...and marks nothing")
	view.free()
	_finish()

func test_shortcuts_in_a_game() -> void:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	_root().add_child(game)
	game.board_view.move_time = 0.0
	for san in ["e4", "e5", "Nf3"]:
		game.play(Notation.find_move(game.state, san))
	check(game.run_shortcut("step_back"), "Left: look back a move")
	check_eq(game.viewing, 2, "...at the position after 1. e4 e5")
	game.run_shortcut("step_start")
	check_eq(game.viewing, 0, "Home: the start")
	game.run_shortcut("step_forward")
	check_eq(game.viewing, 1, "Right: a move on")
	game.run_shortcut("step_end")
	check_eq(game.viewing, -1, "End: back to the game")
	game.run_shortcut("undo")
	check_eq(game.state.history.size(), 2, "Ctrl+Z: undo")
	game.run_shortcut("redo")
	check_eq(game.state.history.size(), 3, "Ctrl+Y: redo")
	game.run_shortcut("flip_board")
	check(game.board_view.flipped, "F: the board turns round")
	game.run_shortcut("flip_board")
	check(not game.board_view.flipped, "...and back")
	check(not game.run_shortcut("cancel"), "Esc with nothing selected does nothing")
	game.board_view.tap(Board.parse_square("e5"))
	check(game.board_view.selected_square() != Board.NO_SQUARE, "Black's pawn chosen")
	check(game.run_shortcut("cancel"), "Esc...")
	check_eq(game.board_view.selected_square(), Board.NO_SQUARE, "...lets go of it")
	game.board_view.tap(Board.parse_square("e5"))
	check(game.run_shortcut("piece_card"), "I opens the chosen piece's card")
	var cards := game.find_children("*", "PieceInfo", false, false)
	check_eq(cards.size(), 1, "One card")
	for card in cards:
		card.free()
	game.settings_open = true
	var key := _key(KEY_F)
	game._input(key)
	check(not game.board_view.flipped, "No shortcuts while Settings is open")
	game.free()
	_finish()

func test_gear_opens_settings_over_a_game() -> void:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	_root().add_child(game)
	check(game.gear_button.is_visible_in_tree(), "A gear beside the status line")
	check_eq(game.gear_button.get_parent(), game.status_label.get_parent(), "...in the status line's row")
	game.gear_button.pressed.emit()
	check(game.settings_menu != null and game.settings_open, "Settings opens over the game")
	game.settings_menu.speed_buttons["off"].pressed.emit()
	check_eq(game.board_view.move_time, 0.0, "A change shows straight away (animations off)")
	game.settings_menu.helper_toggles["coordinates"].button_pressed = false
	check(not game.board_view.helpers.coordinates, "...coordinates off")
	game.settings_menu.close()
	check(game.settings_menu == null and not game.settings_open, "Back closes it, the game is as it was")
	game.free()
	_finish()

func test_gear_row_moves_with_the_wide_layout() -> void:
	var game: Control = load("res://scenes/game/game.tscn").instantiate()
	_root().add_child(game)
	# Unpinned from the window so the test can pick the size (as layout_test does).
	game.set_anchors_preset(Control.PRESET_TOP_LEFT)
	game.size = Vector2(2048, 1280)
	check(game.wide, "Wide layout")
	check(game.gear_button.is_visible_in_tree(), "The gear is still there on a wide screen")
	game.size = Vector2(720, 1280)
	check(game.gear_button.is_visible_in_tree(), "...and back on a tall one")
	game.free()

func test_report_a_bug_and_discord_buttons() -> void:
	var settings := SettingsMenu.new()
	_root().add_child(settings)
	var buttons := {}
	for button: Button in settings.find_children("*", "Button", true, false):
		buttons[button.text] = button
	check(buttons.has("Report a bug") and buttons.has("Discord"), "Both buttons are there: %s" % [buttons.keys()])
	var opened: Array[String] = []
	SettingsMenu.link_opener = func(url: String) -> void: opened.append(url)
	buttons["Report a bug"].pressed.emit()
	check_eq(opened, ["https://github.com/thedarkhorse99/ChessPlus/issues"] as Array[String], "Report a bug opens the issues page")
	check_eq(buttons["Discord"].disabled, SettingsMenu.DISCORD_URL.is_empty(), "Discord is greyed out until its link is set")
	SettingsMenu.link_opener = Callable()
	settings.free()
