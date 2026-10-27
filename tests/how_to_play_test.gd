extends TestSuite

## The How to play page (Mac, 26 Oct 2026): from the main menu below Play
## local, once on the first launch, and its words.

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

func test_the_page_has_the_rules_and_closes() -> void:
	var page := HowToPlay.new()
	_root().add_child(page)
	var text := HowToPlay.plain_text()
	for phrase in ["40 points", "two rows", "one King", "two of any piece", "Pawn-type", "card",
			"White's first move", "special ability or promote", "75 moves"]:
		check(text.contains(phrase), "The page says: " + phrase)
	check(text.split(" ").size() < 150, "Under 150 words (%d)" % text.split(" ").size())
	var labels := page.find_children("*", "Label", true, false)
	check(labels.size() > 10, "Drawn as labels")
	var closed := [false]
	page.closed.connect(func() -> void: closed[0] = true)
	var buttons := page.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Got it")
	check_eq(buttons.size(), 1, "A Got it button")
	buttons[0].pressed.emit()
	check(closed[0], "Got it closes the page")
	page.free()

func test_the_menu_offers_it_below_play_local() -> void:
	var menu: Node = load("res://scenes/menu/main_menu.tscn").instantiate()
	_root().add_child(menu)
	var play: Button = menu.get_node("%Play")
	var how: Button = menu.get_node("%HowToPlay")
	check(how.text == "How to play" and how.get_index() == play.get_index() + 1, "How to play sits right below Play local")
	var pressed := [false]
	menu.how_to_play_pressed.connect(func() -> void: pressed[0] = true)
	how.pressed.emit()
	check(pressed[0], "Pressing it asks the main scene for the page")
	menu.free()

func test_shown_once_on_the_first_launch() -> void:
	UserSettings.set_how_to_play_seen(false)
	check(not UserSettings.how_to_play_seen(), "Not seen yet")
	UserSettings.set_how_to_play_seen(true)
	check(UserSettings.how_to_play_seen(), "Remembered as seen")
	# Leave it seen: other tests open the main scene and expect the menu.
