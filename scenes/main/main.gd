extends Control

## The whole app. Shows one screen at a time and moves between them:
## main menu -> my armies -> army builder, and main menu -> choose armies -> game.

const MAIN_MENU := preload("res://scenes/menu/main_menu.tscn")
const ARMY_LIST := preload("res://scenes/armies/army_list.tscn")
const ARMY_BUILDER := preload("res://scenes/armies/army_builder.tscn")
const MATCH_SETUP := preload("res://scenes/menu/match_setup.tscn")
const GAME := preload("res://scenes/game/game.tscn")
const ONLINE_LOBBY := preload("res://scenes/online/online_lobby.tscn")
const POSITION_SETUP := preload("res://scenes/testing/position_setup.tscn")

var library := ArmyLibrary.new()
## The screen currently showing.
var screen: Node
## The volume button in the top-right corner, over every screen.
var volume_control: VolumeControl

func _ready() -> void:
	# Before anything reads a save: on PC, the saves from when the game was
	# called ChessPlus (26 Oct 2026) come over to Overchess's folder once.
	OldSaves.bring_over_on_start()
	UiStyle.apply_font_smoothing()
	SystemFonts.install()
	KeyBinds.install()
	fit_window_to_screen()
	volume_control = VolumeControl.new()
	add_child(volume_control)
	# A local game left 2 days without a move ends; say so once (Mac).
	var note := SavedGame.end_if_abandoned()
	show_main_menu()
	show_how_to_play_once()
	if note != "":
		show_note("Game ended", note)
	_watch_for_updates()
	if OS.has_feature("web") and "selftest=1" in str(JavaScriptBridge.eval("location.search")):
		_online_self_test()

## A pop-up message with an OK button, over whatever is showing.
func show_note(title: String, text: String) -> ModalPanel:
	var panel := ModalPanel.new(title)
	panel.add_text(text)
	panel.add_button("OK", panel.close, &"AccentButton")
	add_child(panel)
	return panel

## Opened with ?selftest=1 (web only): check this browser can sign in to the
## online server and call it, and print the answers to the browser's console.
func _online_self_test() -> void:
	var backend := SupabaseBackend.new()
	add_child(backend)
	var signed := await backend.sign_in()
	print("ONLINE SELF-TEST sign in: ok=%s error=%s user=%s" % [signed.ok, signed.error, backend.user_id()])
	var result := await backend.call_function("get_game", {"p_code": "SELFT"})
	print("ONLINE SELF-TEST read: ok=%s error=%s rows=%d" % [result.ok, result.error, result.rows.size()])
	backend.queue_free()

## On a computer (not a phone), draw the game at the screen's own pixel size
## instead of shrinking the phone-sized layout to fit: text and pictures come
## out sharp. The PC app's window also opens as big as the screen comfortably
## allows. Skipped when the window was opened at some other size on purpose (the
## screenshot tools ask for one to see the phone layout).
func fit_window_to_screen() -> void:
	var window := get_window()
	var normal_size := Vector2i(ProjectSettings.get_setting("display/window/size/window_width_override"),
			ProjectSettings.get_setting("display/window/size/window_height_override"))
	var pc_app := OS.has_feature("pc") and DisplayServer.get_name() != "headless"
	var pc_browser := OS.has_feature("web") and not OS.has_feature("web_android") \
			and not OS.has_feature("web_ios") and not DisplayServer.is_touchscreen_available()
	if not (pc_app or pc_browser) or (pc_app and window.size != normal_size):
		return
	if pc_app and window.mode == Window.MODE_WINDOWED:
		var area := DisplayServer.screen_get_usable_rect(window.current_screen)
		# 90% of the screen's height (leaving room for the title bar), 16:10 shaped.
		var height := int(area.size.y * 0.9)
		var width := mini(int(height * 1.6), int(area.size.x * 0.95))
		window.size = Vector2i(width, height)
		window.position = area.position + (area.size - window.size) / 2
		# Smaller than this, the screens don't fit.
		window.min_size = Vector2i(900, 640)
	# One game pixel per screen pixel (times the screen's own scale setting, e.g.
	# 1.5 on a laptop set to 150%), rather than stretching a 720x1280 layout.
	window.content_scale_size = Vector2i.ZERO
	_fit_content_scale()
	_fitting_scale = true

## True once the window should keep being fitted (see _process).
var _fitting_scale := false
var _fitted_size := Vector2i.ZERO

## Refit whenever the window changes size. Checked every frame rather than
## trusting a resize signal: a browser's canvas can start at zero size and grow
## without one.
func _process(_delta: float) -> void:
	if _fitting_scale and get_window().size != _fitted_size:
		_fit_content_scale()

## The smallest space (in game units) the screens need. A smaller window (a
## small browser window, say) is drawn scaled down just enough to fit.
const MIN_GAME_SIZE := Vector2(720, 900)

func _fit_content_scale() -> void:
	var window := get_window()
	_fitted_size = window.size
	if window.size.x <= 0 or window.size.y <= 0:
		return
	var size := Vector2(window.size)
	var scale := DisplayServer.screen_get_scale(window.current_screen)
	scale = minf(scale, minf(size.x / MIN_GAME_SIZE.x, size.y / MIN_GAME_SIZE.y))
	window.content_scale_factor = maxf(scale, 0.25)

func show_main_menu() -> void:
	var menu := MAIN_MENU.instantiate()
	menu.continue_pressed.connect(continue_game)
	menu.play_pressed.connect(show_match_setup)
	menu.how_to_play_pressed.connect(show_how_to_play)
	menu.online_pressed.connect(show_online_lobby)
	menu.continue_online_pressed.connect(continue_online_game)
	menu.armies_pressed.connect(show_army_list)
	menu.testing_pressed.connect(show_testing_setup)
	menu.settings_pressed.connect(show_settings)
	_show(menu)
	_update_if_ready()

## The web version keeps a copy of the game on the phone (so it starts fast and
## works offline) and only notices a new version in the background. Without
## this, the home-screen app and Safari could each keep running an old copy.
## Ask the browser to look for a new version now; when one has downloaded, it
## is switched to (the page reloads) the next time the main menu is showing,
## so nobody is thrown out of a game.
func _watch_for_updates() -> void:
	if not OS.has_feature("web"):
		return
	# The page asks the browser for a new version now, then keeps a flag saying
	# whether one has finished downloading (Godot's own signal can miss one that
	# started downloading before the game had loaded).
	JavaScriptBridge.eval(UPDATE_JS, true)
	var timer := Timer.new()
	timer.wait_time = 2.0
	timer.timeout.connect(_update_if_ready)
	add_child(timer)
	timer.start()

const UPDATE_JS := """
(function () {
	if (!('serviceWorker' in navigator) || window.cpUpdate) return;
	window.cpUpdate = { ready: false };
	navigator.serviceWorker.getRegistration().then(function (r) {
		if (!r) return;
		r.update().catch(function () {});
		setInterval(function () { window.cpUpdate.ready = !!(r.waiting && r.active); }, 1000);
	});
	window.cpUpdate.apply = function () {
		navigator.serviceWorker.getRegistration().then(function (r) { if (r && r.waiting) r.waiting.postMessage('update'); });
	};
})();
"""

func _update_if_ready() -> void:
	if not OS.has_feature("web") or screen == null or screen.scene_file_path != MAIN_MENU.resource_path:
		return
	if JavaScriptBridge.eval("!!(window.cpUpdate && window.cpUpdate.ready)", true):
		JavaScriptBridge.eval("window.cpUpdate.ready = false; window.cpUpdate.apply();", true)

## The Settings screen (Back returns to the main menu).
## The How to play page (Mac, 26 Oct 2026): from the menu, and once on the
## first launch (`UserSettings.how_to_play_seen`).
func show_how_to_play() -> void:
	var page := HowToPlay.new()
	page.closed.connect(show_main_menu)
	_show(page)

func show_how_to_play_once() -> void:
	if UserSettings.how_to_play_seen():
		return
	UserSettings.set_how_to_play_seen(true)
	show_how_to_play()

func show_settings() -> void:
	var settings := SettingsMenu.new()
	settings.closed.connect(show_main_menu)
	_show(settings)

func show_army_list() -> void:
	var army_list := ARMY_LIST.instantiate()
	army_list.library = library
	army_list.closed.connect(show_main_menu)
	army_list.edit_requested.connect(show_army_builder)
	_show(army_list)

## `army` is null to start a new one.
func show_army_builder(army: Army) -> void:
	var builder := ARMY_BUILDER.instantiate()
	builder.setup(library, army)
	builder.closed.connect(show_army_list)
	builder.saved.connect(func(_army: Army) -> void: show_army_list())
	_show(builder)

func show_match_setup() -> void:
	var setup := MATCH_SETUP.instantiate()
	setup.library = library
	setup.closed.connect(show_main_menu)
	setup.start_requested.connect(func(white: Army, black: Army, bot_team: int, bot_level: int) -> void:
		start_game(white, black, bot_team, bot_level, setup.eval_bar_wanted()))
	_show(setup)

## `bot_team` is the practice bot's side (Piece.Team), or -1 for two players.
func start_game(white: Army, black: Army, bot_team := -1, bot_level := PracticeBot.Level.MEDIUM, eval_bar := false) -> void:
	var game := GAME.instantiate()
	game.eval_bar_on = eval_bar
	game.white_army = white
	game.black_army = black
	game.bot_team = bot_team
	game.bot_level = bot_level
	game.menu_requested.connect(show_main_menu)
	game.armies_requested.connect(show_match_setup)
	_show(game)

## Testing mode: set up a position (`position` to carry on editing one, or
## null for the standard start).
func show_testing_setup(position: TestingPosition = null) -> void:
	var setup := POSITION_SETUP.instantiate()
	setup.library = library
	if position:
		setup.setup = position
	setup.back_pressed.connect(show_main_menu)
	setup.start_pressed.connect(start_testing_game)
	setup.game_imported.connect(start_testing_game)
	_show(setup)

## A two-player game from a Testing mode position (with `moves` already played,
## for an imported game). Its Setup button goes back to editing that position.
func start_testing_game(position: TestingPosition, moves := PackedStringArray()) -> void:
	var game := GAME.instantiate()
	game.testing_position = position
	game.testing_moves = moves
	game.menu_requested.connect(func() -> void: show_testing_setup(position.copy()))
	_show(game)

## Pick up the saved game, if there is one.
func continue_game() -> void:
	var saved := SavedGame.load_saved()
	if saved == null:
		show_main_menu()
		return
	var game := GAME.instantiate()
	game.white_army = saved.white_army
	game.black_army = saved.black_army
	game.bot_team = saved.bot_team
	game.bot_level = saved.bot_level
	game.eval_bar_on = saved.eval_bar
	game.best_move_on = saved.best_move
	game.eval_bar_hidden = saved.eval_bar_hidden
	game.resume = saved
	game.menu_requested.connect(show_main_menu)
	_show(game)

## The online lobby: create a game (and wait for a friend) or join one by code.
## `backend` is for tests (null = the real server).
func show_online_lobby(backend: OnlineBackend = null) -> void:
	var lobby := ONLINE_LOBBY.instantiate()
	lobby.library = library
	lobby.backend = backend
	lobby.closed.connect(show_main_menu)
	lobby.game_ready.connect(start_online_game)
	_show(lobby)

## Both players are in: open the game. The session moves from the lobby into
## the game screen.
func start_online_game(session: OnlineSession) -> void:
	if session.get_parent():
		session.get_parent().remove_child(session)
	var game := GAME.instantiate()
	game.online = session
	game.library = library
	game.menu_requested.connect(show_main_menu)
	game.rematch_ready.connect(start_online_game)
	_show(game)

## Pick up the online game this device was playing.
func continue_online_game(backend: OnlineBackend = null) -> void:
	var session := OnlineSession.new(backend)
	add_child(session)
	var result := await session.resume(UserSettings.online_game(), UserSettings.online_team())
	if not result.ok or session.status() != OnlineSession.PLAYING:
		# It has ended (or gone) since: stop offering it.
		UserSettings.set_online_game("")
		session.queue_free()
		show_main_menu()
		return
	start_online_game(session)

## Replace the current screen with `new_screen`.
func _show(new_screen: Node) -> void:
	if screen:
		# queue_free: the old screen may still be in the middle of handling the
		# button press that brought us here, so free it once that's finished.
		screen.queue_free()
	screen = new_screen
	add_child(new_screen)
