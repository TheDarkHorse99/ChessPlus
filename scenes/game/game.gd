extends Control

## The game screen: connects the board view, the text around it and the buttons
## to a GameState. Either two players share the device (pass and play), or one
## player plays the practice bot.

## Pressed "Menu". Only shown if something is listening (the main scene).
signal menu_requested
## Online: both players are in the rematch; the main scene opens it.
signal rematch_ready(session: OnlineSession)
## Pressed "Choose armies" on the result screen of a game that ended before its
## first move (e.g. King exposed). Only offered if something is listening.
signal armies_requested

## If set, games start from this FEN position instead of the standard one. Any
## piece in res://data/pieces/ can appear in it (e.g. "E"/"e" for elephants).
@export var start_fen := ""

## If both are set (by the main scene, before the screen opens), games are
## played with these armies, and "New game" replays them.
var white_army: Army
var black_army: Army

## The bot's side (Piece.Team), or -1 when two people are playing. Set by the
## main scene, with the bot's level, before the screen opens.
var bot_team := -1
var bot_level := PracticeBot.Level.MEDIUM
## Frames to wait before the bot thinks, so the screen can show the player's move
## and "Bot is thinking..." first. Tests use 0.
var bot_delay_frames := 2
var bot: PracticeBot
## The bot always takes at least this long (seconds) over a move, so its replies
## don't land instantly. Not in tests (bot_delay_frames = 0).
var bot_min_seconds := 2.0
## Counts down the rest of that time. A child of this screen, so if the screen
## closes while it runs, the bot's turn is simply dropped.
var _bot_timer: Timer
## True from the moment it's the bot's turn until it has moved.
var bot_thinking := false
## Counts bot turns, so a turn that was overtaken (New game, Menu) is dropped.
var _bot_turn_id := 0
## The Plusfish level's own link to the engine (separate from the eval bar's,
## so neither stops the other's job). Made only for that level.
var bot_engine: PlusfishLink
## How hard Plusfish searches for each move: about 1.7 s on a PC; the web
## version is slower (more so on phones), so it searches less.
const PLUSFISH_BOT_NODES := 400000
const PLUSFISH_BOT_WEB_NODES := 100000
## If Plusfish hasn't answered after this long, the Hard bot moves instead.
var plusfish_bot_max_seconds := 30.0
## A saved game to continue instead of starting a new one (set by the main scene).
var resume: SavedGame
## An online game (set by the main scene before the screen opens): the session
## that talks to the server. Null for games on this device.
var online: OnlineSession
## Both players' clocks, in a timed online game.
var clock_label: Label
## Resigning needs a second tap: when the first tap was (or -1).
var _resign_tapped_ms := -1
## True while this player's move is on its way to the server.
var _sending := false
var _claiming_timeout := false
## When a refused timeout claim may be tried again (Time.get_ticks_msec()).
var _next_timeout_claim_ms := 0
## The result screen shown when a game ends.
var game_over_panel: GameOverPanel
## Saved armies, for choosing one for a rematch.
var library: ArmyLibrary
## Online extras: chat, draw offers, rematches.
var chat_panel: ChatPanel
var chat_button: Button
var draw_button: Button
## "Your opponent offers a draw" with Accept / Decline.
var offer_bar: HBoxContainer
## Was the game over at the last update (so the result shows once)?
var _was_over := false
## The last move played here was checkmate: the result screen waits for the
## checkmate effect (see CheckmateEffect).
var _mate_just_played := false
var _mate_effect: CheckmateEffect
## Counts checkmate effects started, so one waiting for the move's animation
## knows if it has been cancelled meanwhile.
var _mate_count := 0
var _result_fade: Tween
## Chat messages already read.
var _chat_seen := 0
## The rematch this player set up (its code), if any.
var _my_rematch_code := ""
var sounds: GameSounds

@onready var board_view: BoardView = %BoardView
@onready var status_label: Label = %Status
@onready var move_list: MoveList = %Moves
@onready var play_from_here_button: Button = %PlayFromHere
## Shown while looking back: Back / Forward a move (and Play from here, against the bot).
@onready var view_nav: HBoxContainer = %ViewNav
@onready var step_back_button: Button = %StepBack
@onready var step_forward_button: Button = %StepForward
## Shown while a piece with an unused special ability is selected.
@onready var ability_button: Button = %Ability
@onready var new_game_button: Button = %NewGame
@onready var undo_button: Button = %Undo
@onready var redo_button: Button = %Redo
@onready var menu_button: Button = %Menu
## Resign, in local games (online games use the New game button's place).
@onready var resign_button: Button = %Resign
@onready var promotion_overlay: ColorRect = %PromotionOverlay
@onready var promotion_choices: GridContainer = %PromotionChoices
## The shimmering purple behind Raise Dead's choices.
@onready var picker_shimmer: ColorRect = %Shimmer
@onready var _layout: VBoxContainer = $Margin/Layout
@onready var _board_area: Control = $Margin/Layout/BoardArea
@onready var _moves_scroll: ScrollContainer = $Margin/Layout/MovesScroll
@onready var _buttons: Control = $Margin/Layout/Buttons
## On wide screens: the board on the left, `_side` (status, moves, buttons) on the right.
var _wide_box: HBoxContainer
var _side: VBoxContainer
var wide := false

## Plusfish's evaluations of a finished game (PlusfishLink), shown in the bar
## beside the board (EvalBar) and as a blue best-move arrow, when looking over
## the board after the game.
var plusfish: PlusfishLink
var eval_bar: EvalBar
## After the game: the whole game's evaluation as a graph (under the board, or
## beside it on wide screens), and the moves it judges mistakes or blunders
## (moves played -> MoveQuality.Mark), also marked in the move list.
var eval_graph: EvalGraph
var move_marks := {}
## The board and the eval bar side by side, inside the board area.
var _board_row: HBoxContainer
## The status line before the eval part was added to it.
var _status_base := ""
## The eval bar's width as a share of the board's.
const EVAL_BAR_SHARE := 0.05
## Picks the squares out of a move's text ("e2-e4", "a1xb2", "a1!c3", ...).
var _move_squares := RegEx.create_from_string("^([a-z][0-9]+)[-x!~]([a-z][0-9]+)")

## Looking back: the number of moves played in the position being shown, or -1
## when showing the game as it is now. Looking back never changes the game.
var viewing := -1
## The position being looked at (a separate copy of the game).
var _view_state: GameState

var state: GameState

## Shown where the move list goes, until the first move.
var TIP := tip_text(DisplayServer.is_touchscreen_available())

## Phones: hold a piece. PC: the mouse button Settings gives the piece card
## (middle click unless changed).
static func tip_text(touchscreen: bool) -> String:
	return "Tip: %s any piece to see how it moves." % ("hold" if touchscreen else MouseBinds.verb(MouseBinds.button("piece_card")))

func _ready() -> void:
	KeyBinds.install()
	sounds = GameSounds.new()
	add_child(sounds)
	# The moves sit in a box of their own.
	_moves_scroll.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.CARD, UiStyle.RADIUS, 14, 8))
	_build_status_row()
	clock_label = Label.new()
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clock_label.add_theme_font_size_override("font_size", 32)
	clock_label.hide()
	_layout.add_child(clock_label)
	_layout.move_child(clock_label, _status_row.get_index() + 1)
	_build_offer_bar()
	PieceInfo.prepare(self)
	game_over_panel = GameOverPanel.new()
	game_over_panel.chosen.connect(_on_game_over_action)
	add_child(game_over_panel)
	if library == null:
		library = ArmyLibrary.new()
	_bot_timer = Timer.new()
	_bot_timer.one_shot = true
	add_child(_bot_timer)
	_build_capture_rows()
	_build_eval_bar()
	_build_hint_toggles()
	_build_top_moves()
	_build_eval_graph()
	_build_wide_layout()
	resized.connect(fit_layout)
	fit_layout()
	board_view.move_chosen.connect(choose)
	board_view.choice_needed.connect(_ask_which_move)
	board_view.info_requested.connect(func(piece: Piece) -> void:
		PieceInfo.open(self, piece.def, piece.team))
	new_game_button.pressed.connect(ask_new_game)
	resign_button.pressed.connect(resign_local)
	undo_button.pressed.connect(undo)
	redo_button.pressed.connect(redo)
	play_from_here_button.pressed.connect(play_from_here)
	step_back_button.pressed.connect(step_back)
	step_forward_button.pressed.connect(step_forward)
	ability_button.pressed.connect(use_ability)
	# The ability button floats just above the bottom row of buttons instead of
	# taking up room in the layout: showing or hiding it mustn't resize the board.
	ability_button.top_level = true
	_buttons.item_rect_changed.connect(_place_ability_button)
	resized.connect(_place_ability_button.call_deferred)
	board_view.selection_changed.connect(_on_selection_changed)
	board_view.sound_cue.connect(func(sound: int) -> void: sounds.play(sound))
	move_list.move_tapped.connect(view_move)
	move_list.line_tapped.connect(view_side_line)
	move_list.line_removed.connect(remove_side_line)
	menu_button.pressed.connect(func() -> void: menu_requested.emit())
	menu_button.visible = not menu_requested.get_connections().is_empty()
	if testing_position:
		menu_button.text = "Setup"
	promotion_overlay.gui_input.connect(_on_overlay_input)
	if is_bot_game():
		bot = PracticeBot.new(bot_level)
		if bot_level == PracticeBot.Level.PLUSFISH:
			bot_engine = PlusfishLink.new()
			bot_engine.desktop_nodes = PLUSFISH_BOT_NODES
			bot_engine.web_nodes = PLUSFISH_BOT_WEB_NODES
			# One store of answers for both: the eval bar shows the bot's own
			# (bigger) searches instead of working those positions out again.
			bot_engine.cache = plusfish.cache
			add_child(bot_engine)
	if online:
		_start_online()
		return
	if resume:
		_continue_saved_game(resume)
	elif not testing_moves.is_empty():
		_play_testing_moves()
	else:
		new_game()

func new_game() -> void:
	state = _create_start_state()
	resigned = -1
	_started_time = Time.get_unix_time_from_system()
	_show_new_state()

## Testing mode (Mac's design): the game starts from this position, set up by
## hand; two players, the eval bar always on, and Menu goes back to the setup.
var testing_position: TestingPosition
## Testing mode: moves already played from testing_position when the screen
## opens (an imported game, GameExport), as Move.to_text(). New game starts
## without them.
var testing_moves: PackedStringArray = []

## Open on an imported game: its start, then its moves.
func _play_testing_moves() -> void:
	state = _create_start_state()
	for text in testing_moves:
		var move := state.find_move(text)
		if move == null:
			break
		state.make_move(move)
	_show_new_state()

## When this game started (seconds since 1970), kept with the saved game.
var _started_time := Time.get_unix_time_from_system()

## In a local game, the side that resigned (Piece.Team), or -1. Against the bot
## that's you; with two players on one device, whoever's turn it was.
var resigned := -1

## The Resign button (local games): the first tap asks for a second one. After
## resigning, Undo takes the resignation back.
func resign_local() -> void:
	if online:
		return
	# After the game, this button shows the result screen again.
	if is_over():
		show_game_over()
		return
	if bot_thinking or viewing >= 0:
		return
	var now := Time.get_ticks_msec()
	if _resign_tapped_ms < 0 or now - _resign_tapped_ms > 3000:
		_resign_tapped_ms = now
		resign_button.text = "Tap again"
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if is_instance_valid(resign_button) and not is_over():
				resign_button.text = "Resign")
		return
	_resign_tapped_ms = -1
	resigned = _my_team() if is_bot_game() else state.side_to_move
	board_view.refresh()
	_update_input()
	_update_text()
	_save_progress()

## "1-0" / "0-1" after a local resignation, else "*".
func _resigned_result() -> String:
	if resigned < 0:
		return "*"
	return "0-1" if resigned == Piece.Team.WHITE else "1-0"

## The New game button: once moves have been played, check first (Mac's request).
func ask_new_game() -> void:
	if state.history.is_empty():
		new_game()
		return
	if new_game_confirm == null:
		new_game_confirm = ConfirmationDialog.new()
		new_game_confirm.title = "New game"
		new_game_confirm.dialog_text = "Are you sure you want to start a new game?\nThis game will be lost."
		new_game_confirm.ok_button_text = "New game"
		new_game_confirm.confirmed.connect(new_game)
		# Big enough to tap easily.
		for button: Button in [new_game_confirm.get_ok_button(), new_game_confirm.get_cancel_button()]:
			button.custom_minimum_size = Vector2(200, 72)
		add_child(new_game_confirm)
	new_game_confirm.popup_centered()

## The "are you sure?" box for New game (made the first time it's needed).
var new_game_confirm: ConfirmationDialog

## The game's starting position: from the armies, start_fen, or standard chess.
func _create_start_state() -> GameState:
	if testing_position:
		return testing_position.create_state()
	if white_army and black_army:
		return ArmySetup.create_game(white_army, black_army, StandardSetup.create_rules())
	if start_fen.is_empty():
		return StandardSetup.create_game()
	return Fen.parse(start_fen, PieceCatalog.all_defs(), StandardSetup.create_rules())

## Show the position after the first `moves_played` moves, without changing the
## game. The latest position (or anything past it) goes back to the game itself.
func view_move(moves_played: int) -> void:
	if moves_played < 0 or moves_played >= state.history.size():
		back_to_game()
		return
	var copy := _game_copy_at(moves_played)
	if copy == null:
		back_to_game()
		return
	viewing = moves_played
	line_index = -1
	line_ply = 0
	_view_state = copy
	board_view.show_game(copy)
	_update_input()
	_update_text()

## A fresh copy of the game's start with its first `main_moves` moves played,
## then `extra` (Move.to_text(), a side line's); null if one isn't legal.
func _replay(main_moves: int, extra: Array) -> GameState:
	var copy := _create_start_state()
	var texts: Array = []
	for i in main_moves:
		texts.append(state.history[i].to_text())
	texts.append_array(extra)
	for text: String in texts:
		var move := copy.find_played_move(text)
		if move == null:
			return null
		copy.make_move(move)
	return copy

## A copy of the game after its first `moves_played` moves, for looking back.
## The copy already on the board is moved there if it's on the game's own
## moves (stepping back or forward is then one move, not the whole game again).
func _game_copy_at(moves_played: int) -> GameState:
	var copy := _view_state
	if copy == null and _spare_copy_of == state:
		copy = _spare_copy
	_keep_copy(null)
	return _step_copy(copy, moves_played)

## `copy` (a copy of this game, or null) moved to the position after the game's
## first `moves_played` moves; a fresh copy if it isn't on the game's moves.
func _step_copy(copy: GameState, moves_played: int) -> GameState:
	if copy == null or copy == state or not _on_game_moves(copy):
		return _replay(moves_played, [])
	while copy.history.size() > moves_played:
		copy.undo_move(copy.history.back())
	while copy.history.size() < moves_played:
		var move := copy.find_played_move(state.history[copy.history.size()].to_text())
		if move == null:
			return _replay(moves_played, [])
		copy.make_move(move)
	return copy

## The last copy looked at, kept after going back to the game so looking back
## again starts from it, and the game it's a copy of.
var _spare_copy: GameState
var _spare_copy_of: GameState

func _keep_copy(copy: GameState) -> void:
	_spare_copy = copy
	_spare_copy_of = state if copy else null

## Whether every move played in `copy` is the game's move at that point.
func _on_game_moves(copy: GameState) -> bool:
	if copy.history.size() > state.history.size():
		return false
	for i in copy.history.size():
		if copy.history[i].to_text() != state.history[i].to_text():
			return false
	return true

## Stop looking back and show the game as it is now.
func back_to_game() -> void:
	if viewing < 0:
		return
	viewing = -1
	line_index = -1
	line_ply = 0
	_keep_copy(_view_state)
	_view_state = null
	board_view.show_game(state)
	_update_input()
	_update_text()

## The status line's row: the gear that opens Settings on the left (Mac), the
## status in the middle, and a gap on the right as wide as the volume button,
## which sits over that corner (so the status stays centred).
var _status_row: HBoxContainer
var gear_button: Button
## Settings, while it's open over the game.
var settings_menu: SettingsMenu

func _build_status_row() -> void:
	_status_row = HBoxContainer.new()
	_status_row.add_theme_constant_override("separation", 8)
	var parent := status_label.get_parent()
	var index := status_label.get_index()
	parent.remove_child(status_label)
	gear_button = SettingsMenu.gear_button()
	gear_button.pressed.connect(open_settings)
	_status_row.add_child(gear_button)
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_row.add_child(status_label)
	_status_row.add_child(VolumeControl.make_room())
	parent.add_child(_status_row)
	parent.move_child(_status_row, index)

## Open Settings over the game (the gear). The game carries on underneath;
## changes show straight away.
func open_settings() -> void:
	if settings_menu:
		return
	settings_menu = SettingsMenu.new()
	settings_menu.settings_changed.connect(board_view.apply_settings)
	settings_menu.closed.connect(close_settings)
	settings_open = true
	# Over everything in the game, pop-ups included.
	settings_menu.z_index = 30
	add_child(settings_menu)

func close_settings() -> void:
	if settings_menu:
		settings_menu.queue_free()
		settings_menu = null
	settings_open = false
	board_view.apply_settings()

## Keyboard shortcuts (KeyBinds; Mac's Settings, PC). Taken before the buttons
## see the key, so Space can't also press a button clicked earlier; not while
## typing (chat) or while a pop-up such as Settings is open.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or not is_visible_in_tree() or settings_open:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	var action := KeyBinds.action_for(key)
	# Holding Left or Right keeps stepping; other keys act once per press.
	if action == "" or (key.echo and action not in ["step_back", "step_forward"]):
		return
	if run_shortcut(action):
		get_viewport().set_input_as_handled()

## True while the Settings pop-up is open over the game (no shortcuts then).
var settings_open := false

## Do what shortcut `action` stands for, if it can be done now (the same rules
## as its button). Returns whether it did anything.
func run_shortcut(action: String) -> bool:
	match action:
		"step_back":
			if viewing >= 0 or line_index >= 0:
				step_back()
			elif not state.history.is_empty():
				view_move(state.history.size() - 1)
			else:
				return false
		"step_forward":
			if viewing < 0:
				return false
			step_forward()
		"step_start":
			if state.history.is_empty():
				return false
			view_move(0)
		"step_end":
			if viewing < 0:
				return false
			back_to_game()
		"undo":
			if not undo_button.is_visible_in_tree() or undo_button.disabled:
				return false
			undo()
		"redo":
			if not redo_button.is_visible_in_tree() or redo_button.disabled:
				return false
			redo()
		"flip_board":
			flip_board()
		"use_ability":
			if not ability_button.visible:
				return false
			use_ability()
		"cancel":
			if board_view.selected_square() == Board.NO_SQUARE and not board_view.aiming:
				return false
			board_view.cancel_selection()
		"piece_card":
			var square := board_view.selected_square()
			var piece: Piece = board_view.state.board.get_piece(square) if square != Board.NO_SQUARE else null
			if piece == null:
				return false
			PieceInfo.open(self, piece.def, piece.team)
		_:
			return false
	return true

## Turn the board round to see it from the other side (the Flip the board
## shortcut). Only the view changes; the captures rows, eval bar and graph
## follow it. A new game puts it back the usual way.
func flip_board() -> void:
	board_view.flipped = not board_view.flipped
	board_view.queue_redraw()
	_update_captures()
	_update_eval_bar()

## While looking back: show the position one move earlier (down to the start;
## in a side line, back to where it left the game).
func step_back() -> void:
	if line_index >= 0:
		view_side_line(line_index, line_ply - 1)
	elif viewing > 0:
		view_move(viewing - 1)

## While looking back: show the position one move later (in a side line, up to
## its last move); past the second-to-last move that's the game as it is now.
func step_forward() -> void:
	if line_index >= 0:
		if line_ply < side_lines[line_index]["moves"].size():
			view_side_line(line_index, line_ply + 1)
	elif viewing >= 0:
		view_move(viewing + 1)

## Against the bot (and in testing mode): take the game back to the position
## being looked at, and carry on from there (from a side line: with its moves
## as the game's).
func play_from_here() -> void:
	if viewing < 0 or bot_thinking:
		return
	var target := viewing
	var extra: Array = side_lines[line_index]["moves"].slice(0, line_ply) if line_index >= 0 else []
	var adopted := line_index
	back_to_game()
	while state.history.size() > target:
		state.undo_move(state.history.back())
	for text: String in extra:
		var move := state.find_move(text)
		if move == null:
			break
		state.make_move(move)
	if adopted >= 0:
		side_lines.remove_at(adopted)
		redo_moves.clear()
	_drop_side_lines_after(target)
	board_view.refresh()
	sounds.play(GameSounds.Sound.MOVE)
	_update_text()
	_save_progress()
	_start_bot_turn_if_needed()

## The board takes moves for the game only when showing the game now, it's not
## the bot's turn, and (online) it's this player's turn; while looking back (and
## after the game), moves on the board go into a side line (can_branch()).
func _update_input() -> void:
	var playing := viewing < 0 and not is_over() and not bot_thinking and _my_online_turn()
	board_view.input_enabled = playing or can_branch()
	_refresh_ability_button()

# --- Side lines: trying other moves from a position looked back at ------------------

## Moves tried from an earlier position (or from the end of a finished game),
## kept beside the game without changing it, so other paths can be tried
## (Nicholas's fork, Oct 2026). Each: {"from": the game's moves before it,
## "moves": its moves (Move.to_text()), "entries": the same for the move list
## (Notation.numbered_moves)}. Not saved with the game.
var side_lines: Array = []
## The side line on the board (its index), or -1 for the game itself; and how
## many of its moves have been played in the position shown (1 or more).
## While in a side line, `viewing` is where it leaves the game.
var line_index := -1
var line_ply := 0

## Moves on the board make side lines while looking back, and after the game
## from its last position. While a game is on, only against the bot and in
## testing mode: two players (on one device, Mac, or online) only once the game
## has ended.
func can_branch() -> bool:
	if not is_over() and not (bot_team >= 0 or testing_position != null or side_lines_mid_game):
		return false
	return viewing >= 0 or is_over()

## Tests: allow side lines while a two-player game is on.
var side_lines_mid_game := false

## A move chosen on the board (or in the promotion / Raise Dead picker): played
## in the game, or, while looking back or after the game, in a side line.
func choose(move: Move) -> void:
	if viewing >= 0 or is_over():
		play_side_move(move)
	else:
		play(move)

## Play a move in the position on the board without changing the game: the
## game's own next move just steps forward along it, a side line's next move
## steps along that line; any other move starts a new side line (or carries on
## the one shown, from its last move).
func play_side_move(move: Move) -> void:
	if not can_branch():
		return
	var text := move.to_text()
	var shown := board_view.state
	if shown == state:
		# After the game, from its last position: on a copy.
		shown = _replay(state.history.size(), [])
		move = shown.find_move(text) if shown else null
		if move == null:
			return
	var from := viewing if viewing >= 0 else state.history.size()
	if line_index < 0 and from < state.history.size() and state.history[from].to_text() == text:
		_step_along_game(shown, move, from + 1)
		return
	var path: Array = side_lines[line_index]["moves"].slice(0, line_ply) if line_index >= 0 else []
	path.append(text)
	var index := _side_line_with(from, path)
	shown.make_move(move)
	if index < 0:
		if line_index >= 0 and line_ply == side_lines[line_index]["moves"].size():
			index = line_index
		else:
			side_lines.append({"from": from})
			index = side_lines.size() - 1
		side_lines[index]["moves"] = path
		side_lines[index]["entries"] = Notation.numbered_moves(shown, from)
	viewing = from
	line_index = index
	line_ply = path.size()
	_view_state = shown
	board_view.state = shown
	board_view.show_move(move)
	_update_input()
	_update_text()

## The game's own next move was played while looking back: show the position
## after it (with the move's animation), or the game now if that's where it is.
func _step_along_game(shown: GameState, move: Move, moves_played: int) -> void:
	line_index = -1
	line_ply = 0
	if moves_played >= state.history.size():
		viewing = -1
		_view_state = null
		board_view.state = state
		board_view.show_move(state.history.back())
	else:
		shown.make_move(move)
		viewing = moves_played
		_view_state = shown
		board_view.state = shown
		board_view.show_move(move)
	_update_input()
	_update_text()

## The side line leaving the game after `from` moves whose moves start with
## `path`, or -1.
func _side_line_with(from: int, path: Array) -> int:
	for index in side_lines.size():
		var line: Dictionary = side_lines[index]
		if line["from"] == from and line["moves"].size() >= path.size() and line["moves"].slice(0, path.size()) == path:
			return index
	return -1

## Show the position after the first `moves_played` moves of side line `index`
## (0 = where it leaves the game).
func view_side_line(index: int, moves_played: int) -> void:
	if index < 0 or index >= side_lines.size():
		return
	var line: Dictionary = side_lines[index]
	moves_played = clampi(moves_played, 0, line["moves"].size())
	if moves_played == 0:
		view_move(line["from"])
		return
	var copy := _replay(line["from"], line["moves"].slice(0, moves_played))
	if copy == null:
		return
	viewing = line["from"]
	line_index = index
	line_ply = moves_played
	_view_state = copy
	board_view.show_game(copy)
	_update_input()
	_update_text()

## Remove a side line (its x in the move list). If it was on the board, the
## board goes back to where it left the game.
func remove_side_line(index: int) -> void:
	if index < 0 or index >= side_lines.size():
		return
	var from: int = side_lines[index]["from"]
	var was_shown := line_index == index
	side_lines.remove_at(index)
	if was_shown:
		line_index = -1
		view_move(from)
		return
	if line_index > index:
		line_index -= 1
	_update_text()

## Forget side lines that leave the game after more than `moves` moves (the
## game was taken back past them).
func _drop_side_lines_after(moves: int) -> void:
	side_lines = side_lines.filter(func(line: Dictionary) -> bool: return line["from"] <= moves)

## The side-by-side layout for wide screens, unused (hidden) until needed.
func _build_wide_layout() -> void:
	_wide_box = HBoxContainer.new()
	_wide_box.add_theme_constant_override("separation", 24)
	_wide_box.hide()
	_layout.get_parent().add_child(_wide_box)
	_side = VBoxContainer.new()
	_side.custom_minimum_size.x = 620
	_side.add_theme_constant_override("separation", 12)
	_wide_box.add_child(_side)
	_board_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL

## What each player has captured, above and below the board (see CapturedRow).
var captured_top: CapturedRow
var captured_bottom: CapturedRow
## The board area with a captures row above and below it.
var _board_column: VBoxContainer

func _build_capture_rows() -> void:
	_board_column = VBoxContainer.new()
	_board_column.add_theme_constant_override("separation", 4)
	_board_column.size_flags_vertical = _board_area.size_flags_vertical
	_board_column.size_flags_stretch_ratio = _board_area.size_flags_stretch_ratio
	_board_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parent := _board_area.get_parent()
	var index := _board_area.get_index()
	parent.add_child(_board_column)
	parent.move_child(_board_column, index)
	captured_top = CapturedRow.new()
	_board_column.add_child(captured_top)
	_board_area.reparent(_board_column, false)
	_board_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	captured_bottom = CapturedRow.new()
	_board_column.add_child(captured_bottom)
	board_view.resized.connect(_line_up_captures)
	board_view.item_rect_changed.connect(_line_up_captures)

## Start the captures rows at the board's left edge (the board is centred).
func _line_up_captures() -> void:
	var left := board_view.get_global_rect().position.x + board_view.board_origin().x
	captured_top.inset = maxf(0.0, left - captured_top.get_global_rect().position.x)
	captured_bottom.inset = maxf(0.0, left - captured_bottom.get_global_rect().position.x)

## Fill the captures rows for the position on the board: the row nearest each
## player's side of the board shows what that player has captured.
func _update_captures() -> void:
	var shown := board_view.state
	if shown == null:
		return
	var bottom_team := Piece.Team.BLACK if board_view.flipped else Piece.Team.WHITE
	captured_bottom.show_for(shown, bottom_team)
	captured_top.show_for(shown, Piece.other_team(bottom_team))
	_line_up_captures()

## Put the board beside the rest on a wide screen, above it on a tall one.
func fit_layout() -> void:
	var now_wide := ScreenShape.is_wide(size)
	if now_wide == wide:
		return
	wide = now_wide
	if wide:
		ScreenShape.move_to([_board_column], _wide_box)
		_wide_box.move_child(_board_column, 0)
		ScreenShape.move_to([_status_row, clock_label, _top_row, hint_toggles, eval_graph, _moves_scroll, offer_bar, ability_button, view_nav, _buttons], _side)
	else:
		ScreenShape.move_to([_status_row, clock_label, _top_row, _board_column, hint_toggles, eval_graph, _moves_scroll, offer_bar, ability_button, view_nav, _buttons], _layout)
	_layout.visible = not wide
	_wide_box.visible = wide

func is_bot_game() -> bool:
	return bot_team >= 0

## Make a move (it must be legal) and update everything on screen. Online, this
## player's moves are sent to the server (`from_server` = it came from there).
func play(move: Move, from_server := false) -> void:
	state.make_move(move)
	# A new move means the taken-back moves can't be redone any more.
	if not _redoing:
		redo_moves.clear()
	# While looking back, the board keeps showing the old position.
	if viewing < 0:
		# The board's animation plays each sound at the right moment.
		board_view.show_move(move)
		_mate_just_played = state.outcome() == GameState.Outcome.CHECKMATE
	else:
		sounds.play_for_move(state, move)
	_update_text()
	_save_progress()
	_start_bot_turn_if_needed()
	if online and not from_server:
		_send_online_moves()

## Take back the last move (also after the game has ended). Against the bot it
## takes back the bot's reply too, so it's your turn again.
func undo() -> void:
	if not _can_undo():
		return
	# After resigning, Undo takes the resignation back first.
	if resigned >= 0:
		resigned = -1
		# Back in play: two players can't keep side lines while it's on (Mac).
		if not can_branch():
			side_lines.clear()
			back_to_game()
		_update_input()
		_update_text()
		_save_progress()
		return
	back_to_game()
	var undone: Array[Move] = [state.history.back()]
	state.undo_move(undone[0])
	if is_bot_game() and state.side_to_move == bot_team and not state.history.is_empty():
		undone.append(state.history.back())
		state.undo_move(undone[1])
	promotion_overlay.hide()
	# Remember them for Redo: the move to play next goes last.
	for move in undone:
		redo_moves.append(move)
	_drop_side_lines_after(state.history.size())
	board_view.show_undo(undone)
	_update_text()
	_save_progress()
	_start_bot_turn_if_needed()

## Moves taken back with Undo that Redo can play again: the next one is last.
var redo_moves: Array[Move] = []
## True while Redo is playing moves (so they don't clear redo_moves, and the
## bot doesn't start thinking between the two).
var _redoing := false

## Play again the move that Undo took back (against the bot: your move and the
## bot's reply, as Undo took back both).
func redo() -> void:
	if not _can_redo():
		return
	back_to_game()
	_redoing = true
	var replay := func() -> void:
		var move: Move = state.find_move(redo_moves.pop_back().to_text())
		if move:
			play(move)
	replay.call()
	if is_bot_game() and state.side_to_move == bot_team and not redo_moves.is_empty() and state.outcome() == GameState.Outcome.NONE:
		replay.call()
	_redoing = false
	_update_text()
	_start_bot_turn_if_needed()

func _can_redo() -> bool:
	return not redo_moves.is_empty() and not bot_thinking and online == null and resigned < 0

## The bot plays its move now. Normally called by _start_bot_turn_if_needed
## (after a short wait); tests call it directly.
func make_bot_move() -> void:
	_play_bot_move(bot.choose_move(state))

func _play_bot_move(move: Move) -> void:
	bot_thinking = false
	_update_input()
	if move:
		var san := Notation.san(state, move)
		play(move)
		if not is_over():
			TurnNotifier.your_turn("The bot played %s." % san)
	else:
		_update_text()

## Pick up a saved game where it left off. If it can't be rebuilt (for example
## the rules changed since), start a new game with the same armies instead.
func _continue_saved_game(saved: SavedGame) -> void:
	if saved.started_time > 0:
		_started_time = saved.started_time
	var rebuilt := saved.create_state(StandardSetup.create_rules())
	if rebuilt == null:
		new_game()
		return
	state = rebuilt
	_show_new_state()

## Show `state` from scratch (after a new game or continuing a saved one).
func _show_new_state() -> void:
	# Your own army at the bottom: online, or against the bot. (Two players
	# sharing a device keep White at the bottom.)
	var black_player := online.my_team == Piece.Team.BLACK if online else bot_team == Piece.Team.WHITE
	board_view.flipped = black_player
	promotion_overlay.hide()
	bot_thinking = false
	viewing = -1
	_view_state = null
	side_lines.clear()
	line_index = -1
	line_ply = 0
	redo_moves.clear()
	eval_bar.reset()
	board_view.show_game(state)
	_update_text()
	_save_progress()
	_start_bot_turn_if_needed()

## Save the game so it can be continued after the app closes; once it's over,
## remove the save so the menu stops offering to continue it. Only games started
## from armies (from the menu) are saved.
func _save_progress() -> void:
	# Online games are kept on the server instead.
	if online or white_army == null or black_army == null:
		return
	if state.outcome() != GameState.Outcome.NONE or resigned >= 0:
		SavedGame.delete_saved()
	else:
		var saved := SavedGame.from_state(state, white_army, black_army, bot_team, bot_level)
		saved.started_time = _started_time
		saved.eval_bar = eval_bar_on
		saved.best_move = best_move_on
		saved.eval_bar_hidden = eval_bar_hidden
		saved.save()

## If it's the bot's turn: block the board, say it's thinking, then let it move.
func _start_bot_turn_if_needed() -> void:
	if _redoing:
		return
	if not is_bot_game() or state.side_to_move != bot_team or state.outcome() != GameState.Outcome.NONE or resigned >= 0:
		_update_input()
		return
	bot_thinking = true
	_update_input()
	_update_text()
	_bot_turn_id += 1
	var turn_id := _bot_turn_id
	for i in bot_delay_frames:
		await get_tree().process_frame
	# Let the player's move finish sliding first: thinking freezes the screen.
	while bot_delay_frames > 0 and board_view.is_animating() and turn_id == _bot_turn_id:
		await get_tree().process_frame
	# Dropped if a new game (or another turn) started while we waited.
	if turn_id != _bot_turn_id or not bot_thinking:
		return
	var started := Time.get_ticks_msec()
	var move: Move
	if _plusfish_bot_can_play():
		move = await _plusfish_bot_move(turn_id)
	else:
		move = await _practice_bot_move(turn_id)
	# Fast answers wait until the bot has "thought" for bot_min_seconds.
	var wait := bot_min_seconds - (Time.get_ticks_msec() - started) / 1000.0
	if bot_delay_frames > 0 and wait > 0:
		_bot_timer.start(wait)
		await _bot_timer.timeout
	if turn_id == _bot_turn_id and bot_thinking:
		_play_bot_move(move)

## The practice bot's move. It searches a copy of the game, so the screen
## keeps going while it thinks (searching here froze it for 0.6-1.5 s every move
## in army games): on PC on its own thread; on the web, which has no threads, in
## steps of BOT_STEP_MS with a frame drawn between them (bot_in_steps). In tests
## (bot_delay_frames = 0) it searches the game itself, all at once. Null if the
## turn was dropped meanwhile.
func _practice_bot_move(turn_id: int) -> Move:
	if bot_delay_frames == 0:
		return bot.choose_move(state)
	_stop_bot_thread()
	# The bot's copy from its last turn, two moves on (or a new one).
	var copy := _step_copy(_bot_copy if _bot_copy_of == state else null, state.history.size())
	_bot_copy = copy
	_bot_copy_of = state if copy else null
	if copy == null:
		return bot.choose_move(state)
	if bot_in_steps:
		var best: Move = await _search_in_steps(copy)
		if best == null or turn_id != _bot_turn_id:
			return null
		return state.find_played_move(best.to_text())
	var thread := Thread.new()
	_bot_thread = thread
	thread.start(bot.choose_move.bind(copy))
	# Checked with the screen's own timer: if the screen closes, the wait just ends.
	while thread.is_alive() and thread == _bot_thread:
		_bot_timer.start(0.02)
		await _bot_timer.timeout
	# Another turn started meanwhile and has already stopped this search.
	if thread != _bot_thread:
		return null
	var found: Move = thread.wait_to_finish()
	_bot_thread = null
	if found == null or turn_id != _bot_turn_id:
		return null
	return state.find_played_move(found.to_text())

## The practice bot's search on its own thread, while it runs; the copy of
## the game it searches (kept for its next turn), and the game it's a copy of.
var _bot_thread: Thread
var _bot_copy: GameState
var _bot_copy_of: GameState

## The web's way (see _practice_bot_move): search `copy` a step at a time,
## letting the screen draw a frame between steps. Null if it was stopped.
func _search_in_steps(copy: GameState) -> Move:
	_bot_steps_id += 1
	var id := _bot_steps_id
	var search := bot.begin_search(copy)
	while not bot.continue_search(copy, search, BOT_STEP_MS):
		# The screen's own timer: if the screen closes, the wait just ends.
		_bot_timer.start(0.001)
		await _bot_timer.timeout
		if id != _bot_steps_id:
			return null
	return search.best

## Search in steps instead of on a thread (the web has none; tests set it too).
var bot_in_steps := OS.has_feature("web")
## About how long each step of the search lasts, in milliseconds.
const BOT_STEP_MS := 40
## Goes up when a search in steps starts or is stopped, so an old one knows to end.
var _bot_steps_id := 0

## Stop the practice bot's search (if one is running) and wait for its thread.
func _stop_bot_thread() -> void:
	_bot_steps_id += 1
	if _bot_thread == null:
		return
	bot.stop()
	_bot_thread.wait_to_finish()
	_bot_thread = null

func _exit_tree() -> void:
	_stop_bot_thread()

## True if this is a Plusfish game and Plusfish can play it. If it can't (the
## program isn't on this computer, or a piece has a rule it doesn't know yet),
## the Hard bot plays instead, and a note says so once.
func _plusfish_bot_can_play() -> bool:
	if bot_engine == null:
		return false
	if PlusfishLink.available() and _plusfish_knows_pieces():
		return true
	if not _told_plusfish_missing:
		_told_plusfish_missing = true
		show_notice("Plusfish can't play here, so the Hard bot is playing instead.")
	return false

var _told_plusfish_missing := false

## Ask Plusfish for its best move in the position now and wait for the answer
## (it searches on a background thread on PC, in a Web Worker on the web, so
## the screen keeps running meanwhile). Null if the turn was dropped.
func _plusfish_bot_move(turn_id: int) -> Move:
	var moves := []
	for move in state.history:
		moves.append(move.to_text())
	var ply := moves.size()
	bot_engine.analyse_live(_create_start_state(), moves)
	var give_up := Time.get_ticks_msec() + int(plusfish_bot_max_seconds * 1000.0)
	# Checked with the screen's own timer: if the screen closes, the wait just ends.
	while bot_engine.is_running() and turn_id == _bot_turn_id and Time.get_ticks_msec() < give_up:
		_bot_timer.start(0.05)
		await _bot_timer.timeout
	if turn_id != _bot_turn_id:
		return null
	bot_engine.stop()
	return engine_move_or_fallback(bot_engine.results.get(ply, {}).get("best", ""))

## The move Plusfish chose (Move.to_text()), or the Hard bot's move if Plusfish
## gave none or one that isn't legal here (it failed, or ran out of time).
func engine_move_or_fallback(best: String) -> Move:
	var move := state.find_move(best) if best != "" else null
	if move == null:
		move = bot.choose_move(state)
	return move

## Undo is possible if there's a move to take back that you made (against the
## bot) or any move at all (two players), and the bot isn't thinking.
func _can_undo() -> bool:
	if bot_thinking:
		return false
	if resigned >= 0:
		return true
	if is_bot_game():
		return state.history.any(func(m: Move) -> bool: return m.piece.team != bot_team)
	return not state.history.is_empty()

## Behind Raise Dead's choices: purples with bands of light sweeping across.
const SHIMMER_SHADER := """
shader_type canvas_item;
void fragment() {
	vec3 dark = vec3(0.16, 0.04, 0.28);
	vec3 light = vec3(0.58, 0.28, 0.82);
	float wave = 0.5 + 0.5 * sin((UV.x * 2.0 + UV.y * 1.2 - TIME * 0.7) * 3.14159);
	float band = smoothstep(0.8, 1.0, sin((UV.x * 1.4 - UV.y * 0.7 - TIME * 0.45) * 6.28318));
	vec3 color = mix(dark, light, 0.3 + 0.35 * wave) + vec3(0.35, 0.25, 0.4) * band;
	COLOR = vec4(color, 1.0);
}
"""

## Several moves go between the same two squares: the promotion choices, or the
## pieces Raise Dead can bring back. Show a button with each piece's picture, in
## a grid (up to 4 across, so a long list doesn't run off a phone's screen);
## Raise Dead's has a shimmering purple background.
func _ask_which_move(moves: Array[Move]) -> void:
	for child in promotion_choices.get_children():
		child.queue_free()
	promotion_choices.columns = clampi(moves.size(), 1, 4)
	var raising := not moves.is_empty() and moves[0].ability == PieceDef.Ability.RAISE_DEAD
	picker_shimmer.visible = raising
	if raising and picker_shimmer.material == null:
		var shader := Shader.new()
		shader.code = SHIMMER_SHADER
		picker_shimmer.material = ShaderMaterial.new()
		picker_shimmer.material.shader = shader
	for move in moves:
		var button := Button.new()
		# The piece it would become (promotion) or bring back (Raise Dead).
		if move.promotion:
			button.icon = board_view.texture_for(move.promotion, move.piece.team)
		elif move.raised:
			button.icon = board_view.texture_for(move.raised.def, move.piece.team)
			if button.icon == null:
				button.text = move.raised.def.display_name
		if button.icon == null and button.text == "":
			button.text = Notation.san(board_view.state, move)
		button.expand_icon = true
		button.custom_minimum_size = Vector2(120, 120)
		button.pressed.connect(func() -> void:
			promotion_overlay.hide()
			choose(move))
		promotion_choices.add_child(button)
	promotion_overlay.show()

## A piece was selected (or the selection cleared): a piece with a special
## ability shows its button (Mac's design): in its colours when it can be used
## now, darkened when it can't be used in this position, grey once used up.
func _on_selection_changed(_square: Vector2i) -> void:
	_update_text()

## Shows or hides the ability button for what's selected now. With nothing
## selected, it shows HAUNT while one of the player's captured Ghosts can come
## back (it isn't on the board to be selected).
func _refresh_ability_button() -> void:
	# The whirr of an ability being aimed stops once a target is chosen (or not).
	if not board_view.aiming and sounds.is_looping():
		sounds.stop_loop()
	var square := board_view.selected_square()
	var shown := board_view.state
	var piece: Piece = shown.board.get_piece(square) if shown and square != Board.NO_SQUARE else null
	# The captured Ghost glows in the row of captures while its square is chosen.
	var choosing_haunt := piece == null and board_view.aiming
	for row: CapturedRow in [captured_top, captured_bottom]:
		if row:
			row.haunting = null
	if piece == null:
		var haunts := _haunt_moves()
		if choosing_haunt and not haunts.is_empty():
			for row: CapturedRow in [captured_top, captured_bottom]:
				if row and row.pieces.has(haunts[0].piece):
					row.haunting = haunts[0].piece
		ability_button.visible = not haunts.is_empty()
		_place_ability_button()
		if ability_button.visible:
			var ghost := haunts[0].piece
			ability_button.text = ghost.def.ability_name.to_upper()
			_style_ability_button(ghost.def.ability_gradient(), ghost.def.ability_label_color(), true)
		return
	ability_button.visible = piece.def.ability != PieceDef.Ability.NONE
	_place_ability_button()
	if not ability_button.visible:
		return
	ability_button.text = piece.def.ability_name.to_upper()
	if piece.ability_used:
		_style_ability_button(PackedColorArray([Color("#555555"), Color("#555555")]), Color("#a0a0a0"), false)
	elif board_view.selected_ability_moves().is_empty():
		var dark := GradientStyleBox.new(piece.def.ability_gradient()).shaded(-0.55).colors
		_style_ability_button(dark, Color("#9a9a9a"), false)
	else:
		_style_ability_button(piece.def.ability_gradient(), piece.def.ability_label_color(), true)

## The ways a captured Ghost of the side to move can come back (Haunt), when the
## player can move now; empty otherwise.
func _haunt_moves() -> Array[Move]:
	var found: Array[Move] = []
	var shown := board_view.state
	if shown == null or not board_view.input_enabled:
		return found
	# (The quick check first: there's rarely a Ghost to bring back.)
	if MoveGenerator.haunting_ghosts(shown, shown.side_to_move).is_empty():
		return found
	if shown.outcome() != GameState.Outcome.NONE or (shown == state and is_over()):
		return found
	found.assign(shown.moves().filter(func(m: Move) -> bool: return m.ability == PieceDef.Ability.HAUNT))
	return found

## The ability button gets the piece's gradient (lighter under the mouse,
## darker while pressed when it can be used).
## Put the ability button just above the bottom row of buttons, centred on it.
func _place_ability_button() -> void:
	if not is_inside_tree() or not ability_button.visible:
		return
	var row := _buttons.get_global_rect()
	var button_size := ability_button.get_combined_minimum_size()
	ability_button.size = button_size
	ability_button.global_position = Vector2(row.get_center().x - button_size.x / 2, row.position.y - button_size.y - 14)

func _style_ability_button(colors: PackedColorArray, text_color: Color, usable: bool) -> void:
	var style := GradientStyleBox.new(colors, 12, 16, 8)
	ability_button.add_theme_stylebox_override("normal", style)
	ability_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	ability_button.add_theme_stylebox_override("hover", style.shaded(0.15) if usable else style)
	ability_button.add_theme_stylebox_override("pressed", style.shaded(-0.2) if usable else style)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		ability_button.add_theme_color_override(color, text_color)

## The ability button: Crack Shot and Song of Slumber ask which piece to target
## (on the board); Raise Dead asks which lost piece to bring back (a picker, like
## promotion); Full Moon happens at once; Haunt (nothing selected) asks which
## square the Ghost comes back on. If it can't be used, a short message says why.
func use_ability() -> void:
	if board_view.selected_square() == Board.NO_SQUARE:
		var haunts := _haunt_moves()
		if not haunts.is_empty():
			board_view.aim_moves(haunts, false)
			sounds.start_loop(GameSounds.Sound.AIMING)
			_refresh_ability_button()
			status_label.text = "%s: tap any empty square" % haunts[0].piece.def.ability_name
		return
	var moves := board_view.selected_ability_moves()
	if moves.is_empty():
		var piece: Piece = board_view.state.board.get_piece(board_view.selected_square())
		if piece and piece.ability_used:
			show_notice("%s has already been used." % piece.def.ability_name)
		elif piece and piece.def.ability == PieceDef.Ability.HAUNT:
			show_notice("The Ghost can use Haunt after it has moved and been captured.")
		elif piece and not piece.has_moved:
			# Mac's rule (Oct 2026): an ability needs a move first.
			show_notice("%s can be used once this piece has moved." % piece.def.ability_name)
		else:
			show_notice("This ability can't be used right now.")
		return
	var piece := moves[0].piece
	if piece.def.ability == PieceDef.Ability.RAISE_DEAD:
		_ask_which_move(moves)
	elif piece.def.ability == PieceDef.Ability.FULL_MOON:
		choose(moves[0])
	else:
		board_view.aim_ability()
		# A magical whirr while the target is chosen (Mac).
		sounds.start_loop(GameSounds.Sound.AIMING)
		status_label.text = "%s: choose a target" % piece.def.ability_name

## The last message shown by show_notice (for tests).
var last_notice := ""

## A short message that pops up just above the ability button, then fades away.
func show_notice(text: String) -> void:
	last_notice = text
	var notice := PanelContainer.new()
	var style := UiStyle.dialog_box(14)
	style.set_corner_radius_all(12)
	style.shadow_size = 12
	notice.add_theme_stylebox_override("panel", style)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	notice.add_child(label)
	notice.top_level = true
	notice.modulate.a = 0.0
	add_child(notice)
	# Placed a frame later, once the button (maybe just shown) has its place.
	await get_tree().process_frame
	if not is_instance_valid(notice):
		return
	notice.reset_size()
	notice.modulate.a = 1.0
	var anchor := ability_button.get_global_rect()
	notice.global_position = Vector2(anchor.get_center().x - notice.size.x / 2, anchor.position.y - notice.size.y - 10)
	notice.global_position.x = clampf(notice.global_position.x, 8, maxf(8, size.x - notice.size.x - 8))
	var tween := notice.create_tween()
	tween.tween_interval(1.6)
	tween.tween_property(notice, "modulate:a", 0.0, 0.4)
	tween.tween_callback(notice.queue_free)

## Tapping outside the choices cancels.
func _on_overlay_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click and click.pressed:
		promotion_overlay.hide()

func _update_text() -> void:
	_refresh_ability_button()
	var mover := "White" if state.side_to_move == Piece.Team.WHITE else "Black"
	var other := "Black" if state.side_to_move == Piece.Team.WHITE else "White"
	if online:
		var my_turn := state.side_to_move == online.my_team
		mover = "You" if my_turn else "Your opponent"
		other = "Your opponent" if my_turn else "You"
	elif is_bot_game():
		var bots_turn := state.side_to_move == bot_team
		mover = "Bot" if bots_turn else "You"
		other = "You" if bots_turn else "The bot"
	match state.outcome():
		GameState.Outcome.NONE:
			if online:
				var mine := state.side_to_move == online.my_team
				status_label.text = ("Your move" if mine else "Your opponent's move") + (" - check!" if state.is_in_check() else "")
			elif is_bot_game():
				status_label.text = "Bot is thinking..." if bot_thinking else "Your move" + (" - check!" if state.is_in_check() else "")
			else:
				status_label.text = mover + " to move" + (" - check!" if state.is_in_check() else "")
		GameState.Outcome.CHECKMATE:
			status_label.text = "Checkmate! %s %s" % [other, "win" if other == "You" else "wins"]
		GameState.Outcome.STALEMATE:
			status_label.text = "Draw by stalemate"
		GameState.Outcome.FIFTY_MOVES:
			status_label.text = "Draw by the 50-move rule"
		GameState.Outcome.SEVENTY_FIVE_MOVES:
			status_label.text = "Draw by the 75-move rule"
		GameState.Outcome.REPETITION:
			status_label.text = "Draw by repetition"
		GameState.Outcome.INSUFFICIENT_MATERIAL:
			status_label.text = "Draw: checkmate is impossible"
		GameState.Outcome.KING_EXPOSED:
			var exposed := "Black" if state.side_to_move == Piece.Team.WHITE else "White"
			status_label.text = "%s's king was under attack from the start: %s loses" % [exposed, exposed]
	if online and _online_ending() != "":
		status_label.text = _online_ending()
	if resigned >= 0 and state.outcome() == GameState.Outcome.NONE:
		var texts := result_texts()
		status_label.text = "%s - %s" % [texts[0], texts[1]]
	if line_index >= 0:
		status_label.text = "Side line: %s" % _move_name_in(_view_state.history, shown_ply() - 1)
	elif viewing > 0:
		status_label.text = "Viewing %s" % _move_name(viewing - 1)
	elif viewing == 0:
		status_label.text = "Viewing the start"
	_status_base = status_label.text
	var result := state.result_text()
	if online and result == "*":
		result = _online_result_text()
	if result == "*":
		result = _resigned_result()
	resign_button.visible = online == null
	if is_over():
		resign_button.text = "Results"
	elif resign_button.text == "Results":
		resign_button.text = "Resign"
	resign_button.disabled = not is_over() and (bot_thinking or viewing >= 0)
	if online == null:
		new_game_button.disabled = replay_ends_at_once()
	move_list.show_moves(_numbered_moves(), "" if result == "*" else result,
			viewing if line_index < 0 else -1, TIP, side_lines, line_index, line_ply)
	# Keep the latest move in sight (not while looking back at an older one).
	if viewing < 0:
		_scroll_moves_to_end.call_deferred()
	else:
		_scroll_to_viewed_move.call_deferred()
	undo_button.disabled = not _can_undo()
	redo_button.disabled = not _can_redo()
	view_nav.visible = viewing >= 0
	step_back_button.disabled = viewing <= 0 and line_index < 0
	step_forward_button.disabled = line_index >= 0 and line_ply >= side_lines[line_index]["moves"].size()
	play_from_here_button.visible = (is_bot_game() or testing_position != null) and viewing >= 0
	play_from_here_button.disabled = bot_thinking
	if online:
		_update_online_controls()
	_update_game_over()
	_update_eval_bar()
	_update_captures()

## The move list's entries (Notation.numbered_moves) for the game so far, and
## the moves they were written for. Writing a move is slow (it works out every
## legal move, to see whether it needs a file or rank and whether it gives
## check), and a move's entry only depends on the moves before it, so after a
## new move only that one is written. Writing them all every time froze the
## screen for up to half a second per move late in a long game.
var _list_entries: Array = []
var _list_moves: Array[Move] = []
var _list_state: GameState

func _numbered_moves() -> Array:
	if _list_state != state:
		_list_state = state
		_list_entries.clear()
		_list_moves.clear()
	# Keep the entries of the moves still the same (Undo and Redo make new ones).
	var same := 0
	var limit := mini(_list_moves.size(), state.history.size())
	while same < limit and _list_moves[same] == state.history[same]:
		same += 1
	_list_entries.resize(same)
	_list_moves.resize(same)
	if same < state.history.size():
		var added := Notation.numbered_moves(state, same)
		# Carrying on a turn: Black's move after White's has no number.
		if same > 0:
			added[0][0] = "" if added[0][0].ends_with("...") else added[0][0]
		_list_entries.append_array(added)
		_list_moves.append_array(state.history.slice(same))
	return _list_entries.duplicate()

# --- Looking over a finished game with Plusfish ----------------------------------

## The eval bar goes to the left of the board, inside the board area (which
## keeps the board square: it widens by the bar's share while the bar shows).
func _build_eval_bar() -> void:
	plusfish = PlusfishLink.new()
	plusfish.evaluated.connect(_on_evaluated)
	add_child(plusfish)
	_board_row = HBoxContainer.new()
	_board_row.add_theme_constant_override("separation", 6)
	_board_area.add_child(_board_row)
	eval_bar = EvalBar.new()
	eval_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eval_bar.size_flags_stretch_ratio = EVAL_BAR_SHARE
	eval_bar.hide()
	_board_row.add_child(eval_bar)
	board_view.reparent(_board_row)
	board_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_view.size_flags_vertical = Control.SIZE_EXPAND_FILL

## Once the game is over: evaluate all its positions (the one on screen first).
## Whether Plusfish knows the rules of every piece in this game (worked out once).
var _plusfish_checked := false
var _plusfish_ok := true

func _plusfish_knows_pieces() -> bool:
	if not _plusfish_checked:
		_plusfish_checked = true
		_plusfish_ok = PlusfishLink.supports(_create_start_state())
	return _plusfish_ok

## The position on the board, as the number of moves played to reach it (in a
## side line: the game's moves before it, then its own).
func shown_ply() -> int:
	if line_index >= 0:
		return viewing + line_ply
	return viewing if viewing >= 0 else state.history.size()

## The moves (Move.to_text()) of the line the board is on: the game, or the
## side line being looked at (all of it, from the start).
func shown_line_moves() -> Array:
	var moves := []
	var count: int = state.history.size() if line_index < 0 else side_lines[line_index]["from"]
	for i in count:
		moves.append(state.history[i].to_text())
	if line_index >= 0:
		moves.append_array(side_lines[line_index]["moves"])
	return moves

## Whether the eval bar shows while the game is on (Mac's design): always
## against the bot; chosen when setting up a game on one device or an online one
## (the creator chooses for both players). After any game it shows anyway.
var eval_bar_on := false

## Against the bot the bar is on unless the player switches it off during the
## game (the "Eval bar" switch under the board).
var eval_bar_hidden := false

func live_eval() -> bool:
	if testing_position:
		return true
	if is_bot_game():
		return not eval_bar_hidden
	if eval_bar_on:
		return true
	return online != null and bool(online.row.get("eval_bar", false))

## The line Plusfish was last given (see _follow_line), so it's given once.
var _plusfish_line := ""

## Give Plusfish the line on the board: once the game is over, the whole game,
## every position (the one on screen first); while it's on, or in a side line,
## its newest position (and any position looked at, see _update_eval_bar).
func _follow_line() -> void:
	var moves := shown_line_moves()
	var whole := is_over() and line_index < 0
	var key := ("game " if whole else "live ") + " ".join(PackedStringArray(moves))
	if key == _plusfish_line:
		return
	_plusfish_line = key
	if whole:
		plusfish.analyse(_create_start_state(), moves)
	else:
		plusfish.analyse_live(_create_start_state(), moves)

## The engine's best move is on for this game against the bot (the "Best move"
## switch under the board).
var best_move_on := false

## Whether the best-move hints (blue arrow, "best: ..." in the status line) show
## while the game is on: in testing mode, which is for studying positions, and
## against the bot if best_move_on was chosen (only on your turn, or when looking
## back at an earlier position, so the arrow is always a move for you to
## consider). Otherwise they show only after the game, so the engine never tells
## anyone what to play.
func live_best_move() -> bool:
	if testing_position != null:
		return true
	if not (is_bot_game() and best_move_on):
		return false
	return viewing >= 0 or state.side_to_move != bot_team

## Show (or hide) the bar, the best-move arrow and the eval in the status line
## for the position on the board. The bar shows after the game, and during it
## if live_eval(); the best-move hints after the game, and during it if
## live_best_move() (with or without the bar).
func _update_eval_bar() -> void:
	var usable := PlusfishLink.available() and _plusfish_knows_pieces()
	var bar_on := usable and (is_over() or live_eval())
	var hints_on := usable and (is_over() or live_best_move())
	_update_hint_toggles(usable)
	_top_row.visible = usable and top_moves_shown()
	if bar_on or hints_on:
		_follow_line()
	# (After _follow_line: Plusfish's results are for the line on the board.)
	_update_eval_graph(usable)
	eval_bar.visible = bar_on
	_board_area.ratio = 1.0 + EVAL_BAR_SHARE + 0.01 if bar_on else 1.0
	# Looking at a mistake or blunder: say so.
	var base := _status_base
	if viewing > 0 and line_index < 0 and move_marks.has(viewing):
		base = "%s  ·  %s" % [_status_base, MoveQuality.name_of(move_marks[viewing])]
	status_label.text = base
	if not (bar_on or hints_on):
		_show_hint("")
		_fill_top_moves({}, false)
		return
	eval_bar.flipped = board_view.flipped
	var ply := shown_ply()
	plusfish.prioritise(ply, hints_on and _top_row.visible)
	var found: Dictionary = plusfish.results.get(ply, {})
	var position_key := "%d %d %d" % [line_index, viewing, ply]
	if position_key != _top_moves_for:
		_top_moves_for = position_key
		_top_choice = 0
	_fill_top_moves(found, hints_on)
	if found.is_empty():
		eval_bar.set_unknown()
		_show_hint("")
		return
	# The final position shows the game's result (it may have been a resignation).
	var result := ""
	if ply == state.history.size() and state.result_text() != "*":
		result = state.result_text()
	elif ply == state.history.size() and resigned >= 0:
		result = _resigned_result()
	elif found.get("outcome", "none") in ["checkmate", "king_exposed"]:
		result = "1-0" if int(found["cp"]) > 0 else "0-1"
	elif found.get("outcome", "none") != "none":
		result = "1/2-1/2"
	eval_bar.set_score(int(found["cp"]), found.get("mate"), result)
	var best: String = found.get("best", "") if hints_on else ""
	var lines: Array = found.get("lines", [])
	if best != "" and _top_choice < lines.size():
		best = lines[_top_choice]["move"]
	_show_hint(best)
	# With the Top moves list showing, it names the move instead.
	if best != "" and result == "" and not _top_row.visible:
		status_label.text = "%s  ·  best: %s" % [base, found.get("best_san", best)]

## Show Plusfish's suggestion on the board ("" = none): the arrow, and for a
## promotion or Raise Dead the piece it turns into or brings back.
func _show_hint(move_text: String) -> void:
	board_view.hint_arrow = _arrow_for(move_text)
	board_view.hint_piece = _hint_piece_for(move_text)

## Promotions ("e7-e8=Q": the piece on the square moved to) and Raise Dead
## ("d1!=Q": the piece on the Necromancer's square, which gets a ring).
var _promotion_text := RegEx.create_from_string("^[a-z][0-9]+[-x]([a-z][0-9]+)=([A-Z]+)$")
var _raise_text := RegEx.create_from_string("^([a-z][0-9]+)!=([A-Z]+)$")
## Piece types by symbol, for reading the moves (made when first needed).
var _defs_by_symbol := {}

## For a promotion or Raise Dead: BoardView.hint_piece (the piece belongs to
## the side to move in the position shown); {} for any other move.
func _hint_piece_for(move_text: String) -> Dictionary:
	var ring := false
	var found := _promotion_text.search(move_text)
	if found == null:
		found = _raise_text.search(move_text)
		ring = true
	if found == null:
		return {}
	if _defs_by_symbol.is_empty():
		for def in PieceCatalog.all_defs():
			_defs_by_symbol[def.symbol.to_upper()] = def
	var def: PieceDef = _defs_by_symbol.get(found.get_string(2))
	if def == null:
		return {}
	return {"square": Board.parse_square(found.get_string(1)), "def": def, "team": board_view.state.side_to_move, "ring": ring}

## A move's text ("e2-e4", "a1!c3") as [from, to] squares; [] if it has none.
func _arrow_for(move_text: String) -> Array:
	var found := _move_squares.search(move_text)
	if found == null:
		return []
	return [Board.parse_square(found.get_string(1)), Board.parse_square(found.get_string(2))]

func _on_evaluated(ply: int, _result: Dictionary) -> void:
	if (is_over() or live_eval() or live_best_move()) and ply == shown_ply():
		_update_eval_bar()
	elif is_over():
		# Another position for the graph (and maybe a mark for the move list).
		_update_eval_graph(true)
		if viewing > 0 and line_index < 0 and move_marks.has(viewing):
			_update_eval_bar()

## The graph sits where the bot game's switches were (they're gone once it ends).
func _build_eval_graph() -> void:
	eval_graph = EvalGraph.new()
	eval_graph.hide()
	eval_graph.ply_chosen.connect(view_move)
	_layout.add_child(eval_graph)
	_layout.move_child(eval_graph, hint_toggles.get_index() + 1)

## Once the game is over: show the graph of every position evaluated so far and
## mark the mistakes and blunders found (in the graph and the move list).
func _update_eval_graph(usable: bool) -> void:
	var on := usable and is_over() and not state.history.is_empty()
	eval_graph.visible = on
	var marks := {}
	if on and line_index >= 0:
		# On a side line Plusfish's results are the line's, not the game's: the
		# graph and marks stay as they were, marking where the line leaves the game.
		eval_graph.show_game(state.history.size(), eval_graph.chances, move_marks, viewing, board_view.flipped)
		return
	if on:
		var moves := []
		var movers := []
		for move in state.history:
			moves.append(move.to_text())
			movers.append(move.piece.team)
		marks = MoveQuality.marks(plusfish.results, moves, movers)
		var chances := {}
		for ply: int in plusfish.results:
			if ply <= moves.size():
				chances[ply] = MoveQuality.white_chances(plusfish.results[ply])
		eval_graph.show_game(moves.size(), chances, marks, shown_ply(), board_view.flipped)
	if marks != move_marks:
		move_marks = marks
		move_list.set_marks(marks)

## The Top moves list (Nicholas's fork, Oct 2026): a dropdown under the status
## line naming Plusfish's best moves for the position on the board with their
## scores ("Best: Nf3 (+0.4)", "2nd: ...", "3rd: ..."); choosing one shows its
## arrow. Shown wherever the best move may be shown: after the game, in testing
## mode, and against the bot with Best move on (greyed out on the bot's turn).
var top_moves_button: OptionButton
var _top_row: HBoxContainer
## The chosen line (0 = the best), and the position it was chosen for.
var _top_choice := 0
var _top_moves_for := ""
const TOP_MOVE_NAMES := ["Best", "2nd", "3rd", "4th", "5th"]

func _build_top_moves() -> void:
	_top_row = HBoxContainer.new()
	_top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_top_row.hide()
	top_moves_button = OptionButton.new()
	top_moves_button.focus_mode = Control.FOCUS_NONE
	top_moves_button.fit_to_longest_item = false
	top_moves_button.custom_minimum_size.x = 320
	top_moves_button.add_theme_font_size_override("font_size", 26)
	top_moves_button.get_popup().add_theme_font_size_override("font_size", 28)
	top_moves_button.item_selected.connect(choose_top_move)
	_top_row.add_child(top_moves_button)
	_layout.add_child(_top_row)
	_layout.move_child(_top_row, clock_label.get_index() + 1)

## Whether the Top moves list has a place on the screen in this game (it stays
## while the game is on, so the board doesn't jump as it comes and goes).
func top_moves_shown() -> bool:
	if is_over() or testing_position != null:
		return true
	return is_bot_game() and online == null and best_move_on

## Show the line chosen in the Top moves list (0 = the best move).
func choose_top_move(index: int) -> void:
	_top_choice = index
	_update_eval_bar()

## Fill the Top moves list from Plusfish's answer for the position on the board
## (`usable` = the best move may be shown now). Only rebuilt when it changes,
## so an open list isn't closed by an update.
func _fill_top_moves(found: Dictionary, usable: bool) -> void:
	var items: Array[String] = []
	var lines: Array = found.get("lines", []) if usable else []
	for i in mini(lines.size(), TOP_MOVE_NAMES.size()):
		items.append("%s: %s  (%s)" % [TOP_MOVE_NAMES[i], lines[i]["san"], score_text(int(lines[i]["cp"]), lines[i].get("mate"))])
	var enabled := not items.is_empty()
	if items.is_empty():
		var best: String = found.get("best_san", "") if usable else ""
		if best != "":
			items.append("Best: %s  (%s)" % [best, score_text(int(found["cp"]), found.get("mate"))])
		elif usable and found.is_empty():
			items.append("Top moves: thinking...")
		else:
			items.append("Top moves")
	var choice := clampi(_top_choice, 0, items.size() - 1)
	var signature := "%s|%d|%s" % [enabled, choice, "|".join(PackedStringArray(items))]
	if top_moves_button.get_meta("signature", "") == signature:
		return
	top_moves_button.set_meta("signature", signature)
	top_moves_button.clear()
	for item in items:
		top_moves_button.add_item(item)
	top_moves_button.select(choice)
	top_moves_button.disabled = not enabled

## A score as the eval bar writes it, with the side: "+0.4", "-1.2", "0.0",
## "M3" (White mates in 3), "-M2" (Black mates in 2).
static func score_text(cp: int, mate: Variant) -> String:
	if mate != null:
		return ("M%d" if int(mate) > 0 else "-M%d") % absi(int(mate))
	if absi(cp) < 5:
		return "0.0"
	return "%+.1f" % (cp / 100.0)

## The "Eval bar" and "Best move" switches under the board (beside the moves on
## wide screens): against the bot, while the game is on. Each takes effect at
## once and is saved with the game.
var hint_toggles: HBoxContainer
var eval_toggle: CheckButton
var best_move_toggle: CheckButton

func _build_hint_toggles() -> void:
	hint_toggles = HBoxContainer.new()
	hint_toggles.add_theme_constant_override("separation", 24)
	hint_toggles.alignment = BoxContainer.ALIGNMENT_CENTER
	hint_toggles.hide()
	eval_toggle = CheckButton.new()
	eval_toggle.text = "Eval bar"
	eval_toggle.toggled.connect(func(on: bool) -> void:
		eval_bar_hidden = not on
		_hint_toggled())
	best_move_toggle = CheckButton.new()
	best_move_toggle.text = "Best move"
	best_move_toggle.toggled.connect(func(on: bool) -> void:
		best_move_on = on
		_hint_toggled())
	for toggle in [eval_toggle, best_move_toggle]:
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.add_theme_font_size_override("font_size", 26)
		hint_toggles.add_child(toggle)
	_layout.add_child(hint_toggles)
	_layout.move_child(hint_toggles, _board_column.get_index() + 1)

func _hint_toggled() -> void:
	_update_eval_bar()
	_save_progress()

func _update_hint_toggles(usable: bool) -> void:
	hint_toggles.visible = usable and is_bot_game() and online == null and not is_over()
	eval_toggle.set_pressed_no_signal(not eval_bar_hidden)
	best_move_toggle.set_pressed_no_signal(best_move_on)

# --- The result screen ----------------------------------------------------------

func is_over() -> bool:
	if state.outcome() != GameState.Outcome.NONE or resigned >= 0:
		return true
	return online != null and online.status() in [OnlineSession.FINISHED, OnlineSession.CANCELLED]

## The game ended before its first move (e.g. King exposed), so a new game from
## the same start would end the same way at once: "Play again" would do nothing.
func replay_ends_at_once() -> bool:
	return state.history.is_empty() and state.outcome() != GameState.Outcome.NONE

## Show the result once, when the game ends; hide it if the game is back on
## (e.g. the last move was undone).
func _update_game_over() -> void:
	var over := is_over()
	if over and not _was_over and viewing < 0:
		_show_game_over_when_still()
	elif not over:
		game_over_panel.hide()
		_stop_checkmate_effect()
	if not over and _was_over:
		plusfish.stop()
		_plusfish_line = ""
	_was_over = over

## The result screen, once the last move's animation has finished (a draw
## found automatically used to cover the move as it played).
var _game_over_wait := 0

func _show_game_over_when_still() -> void:
	_game_over_wait += 1
	var this_one := _game_over_wait
	if board_view.is_animating():
		await board_view.animation_finished
	if this_one != _game_over_wait or not is_over() or viewing >= 0:
		return
	show_game_over()

func show_game_over() -> void:
	var texts := result_texts()
	var buttons := []
	if online:
		buttons.append(["rematch", "Rematch"])
	elif replay_ends_at_once():
		# The same armies again would end the same way straight away.
		if not armies_requested.get_connections().is_empty():
			buttons.append(["armies", "Choose armies"])
	elif is_bot_game():
		buttons.append(["again", "Play again"])
	else:
		buttons.append(["again", "New game"])
	buttons.append(["board", "View board"])
	buttons.append(["export", "Export game"])
	if menu_button.visible:
		buttons.append(["menu", menu_button.text])
	game_over_panel.show_result(texts[0], texts[1], buttons)
	if _mate_just_played:
		_mate_just_played = false
		_play_checkmate_effect()
	if online and _opponent_wants_rematch():
		_show_rematch_offer()

## Checkmate was just played: once the move's animation ends, the beaten king
## rises off the board and crumbles to dust as "CHECKMATE" appears; a tap then
## brings up the result screen (see CheckmateEffect).
func _play_checkmate_effect() -> void:
	_stop_checkmate_effect()
	var squares := MoveAnimation.royal_squares(state, state.side_to_move)
	if squares.is_empty():
		return
	var king := state.board.get_piece(squares[0])
	var texture := board_view.texture_for(king.def, king.team)
	if texture == null:
		return
	game_over_panel.modulate.a = 0.0
	_mate_count += 1
	var this_one := _mate_count
	if board_view.is_animating():
		await board_view.animation_finished
	if this_one != _mate_count or not is_over():
		return  # Undone or a new game meanwhile.
	var effect := CheckmateEffect.new()
	_mate_effect = effect
	board_view.hidden_squares.append(squares[0])
	board_view.queue_redraw()
	var square_rect := board_view.square_screen_rect(squares[0])
	effect.setup(texture, Rect2(square_rect.position - get_global_rect().position, square_rect.size))
	effect.crumbling.connect(func() -> void:
		sounds.play(GameSounds.Sound.DUST))
	# A tap anywhere: on to the usual result screen, and the king is back on the board.
	effect.dismissed.connect(func() -> void:
		board_view.hidden_squares.erase(squares[0])
		board_view.queue_redraw()
		_mate_effect = null
		_result_fade = create_tween()
		_result_fade.tween_property(game_over_panel, "modulate:a", 1.0, 0.4))
	add_child(effect)
	sounds.play(GameSounds.Sound.CHECKMATE)

## Remove the checkmate effect (the mate was undone, or a new game started).
func _stop_checkmate_effect() -> void:
	_mate_count += 1
	if _result_fade:
		_result_fade.kill()
		_result_fade = null
	game_over_panel.modulate.a = 1.0
	if is_instance_valid(_mate_effect) and _mate_effect.is_inside_tree():
		_mate_effect.queue_free()
	_mate_effect = null

## The headline and the line under it, e.g. ["Checkmate!", "You win!"].
func result_texts() -> Array:
	var me := _my_team()
	if resigned >= 0 and state.outcome() == GameState.Outcome.NONE:
		if is_bot_game():
			return ["You resigned", "The bot wins"]
		var loser := "White" if resigned == Piece.Team.WHITE else "Black"
		var winner := "Black" if resigned == Piece.Team.WHITE else "White"
		return ["%s resigned" % loser, "%s wins" % winner]
	if online:
		var code := online.result_code()
		if online.status() == OnlineSession.CANCELLED:
			return ["Game cancelled", ""]
		if code == "draw_agreed":
			return ["Draw", "Agreed by both players"]
		if code.ends_with("_resigned") or code.ends_with("_timeout"):
			var loser := Piece.Team.WHITE if code.begins_with("white") else Piece.Team.BLACK
			var you_lost := loser == me
			if code.ends_with("_resigned"):
				return ["You resigned" if you_lost else "Your opponent resigned", "You lose" if you_lost else "You win!"]
			return ["Out of time", "You ran out of time" if you_lost else "Your opponent ran out of time - you win!"]
	match state.outcome():
		GameState.Outcome.CHECKMATE:
			# The side to move has been checkmated.
			var winner := Piece.other_team(state.side_to_move)
			if me == -1:
				return ["Checkmate!", "%s wins" % ("White" if winner == Piece.Team.WHITE else "Black")]
			if winner == me:
				return ["Checkmate!", "You win!"]
			return ["Checkmate!", "The bot wins" if is_bot_game() else "You lose"]
		GameState.Outcome.STALEMATE:
			return ["Draw", "Stalemate: no legal moves, but not in check"]
		GameState.Outcome.FIFTY_MOVES:
			return ["Draw", "50 moves each without a capture or pawn move"]
		GameState.Outcome.SEVENTY_FIVE_MOVES:
			return ["Draw", "75 moves each without a change to the pieces"]
		GameState.Outcome.REPETITION:
			return ["Draw", "The same position three times"]
		GameState.Outcome.INSUFFICIENT_MATERIAL:
			return ["Draw", "Checkmate is impossible"]
		GameState.Outcome.KING_EXPOSED:
			# The armies left the other side's king attacked before the first move.
			var winner := state.side_to_move
			var how := "%s's king was under attack from the start" % ("Black" if winner == Piece.Team.WHITE else "White")
			if me == -1:
				return ["King exposed", "%s. %s wins" % [how, "White" if winner == Piece.Team.WHITE else "Black"]]
			return ["King exposed", how + (". You win!" if winner == me else ". You lose")]
	return ["Game over", ""]

## This player's side: online or against the bot. -1 for two players on one device.
func _my_team() -> int:
	if online:
		return online.my_team
	if is_bot_game():
		return Piece.other_team(bot_team)
	return -1

func _on_game_over_action(action: String) -> void:
	match action:
		"again":
			new_game()
		"board":
			game_over_panel.hide()
		"menu":
			menu_requested.emit()
		"armies":
			armies_requested.emit()
		"rematch":
			start_rematch()
		"export":
			show_export()

## The game as a line of text (GameExport), with a Copy button, to keep or send
## to someone; Testing mode's Import game reads it back.
func show_export() -> void:
	var text := GameExport.to_text(_create_start_state(), state.history)
	export_panel = ModalPanel.new("Export game")
	export_panel.add_text("Copy this text and keep it or send it to someone. To look over the game again, paste it into Import game in Testing mode.")
	# A long game is a lot of text: it scrolls instead of filling the screen.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	export_panel.column.add_child(scroll)
	var shown := export_panel.add_text(text, 20)
	shown.name = "GameText"
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	shown.reparent(scroll)
	var copy_button := export_panel.add_button("Copy text", func() -> void: DisplayServer.clipboard_set(text), &"AccentButton")
	copy_button.pressed.connect(func() -> void: copy_button.text = "Copied!")
	export_panel.add_button("Done", export_panel.close, &"GhostButton")
	add_child(export_panel)
	# A scroll box doesn't grow with what's in it: as tall as the wrapped text
	# (known once it's laid out), up to EXPORT_TEXT_MAX_HEIGHT.
	scroll.custom_minimum_size.y = EXPORT_TEXT_MAX_HEIGHT
	await get_tree().process_frame
	if is_instance_valid(shown):
		scroll.custom_minimum_size.y = minf(shown.size.y, EXPORT_TEXT_MAX_HEIGHT)

const EXPORT_TEXT_MAX_HEIGHT := 360.0

## The Export game pop-up (null until first shown).
var export_panel: ModalPanel

# --- Online extras: draw offers, chat, rematch ------------------------------------

func _build_offer_bar() -> void:
	offer_bar = HBoxContainer.new()
	offer_bar.add_theme_constant_override("separation", 10)
	offer_bar.hide()
	var label := Label.new()
	label.name = "Text"
	label.text = "Your opponent offers a draw"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	offer_bar.add_child(label)
	for entry in [["Accept", true], ["Decline", false]]:
		var button := Button.new()
		button.name = entry[0]
		button.text = entry[0]
		button.theme_type_variation = &"AccentButton" if entry[1] else &"CompactButton"
		button.custom_minimum_size = Vector2(150, 70)
		var accept: bool = entry[1]
		button.pressed.connect(func() -> void: answer_draw(accept))
		offer_bar.add_child(button)
	_layout.add_child(offer_bar)
	_layout.move_child(offer_bar, _buttons.get_index())

## The extra buttons and chat window, for online games.
func _build_online_extras() -> void:
	chat_button = Button.new()
	chat_button.text = "Chat"
	chat_button.theme_type_variation = &"CompactButton"
	chat_button.custom_minimum_size = Vector2(0, 78)
	chat_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chat_button.pressed.connect(open_chat)
	_buttons.add_child(chat_button)
	_buttons.move_child(chat_button, new_game_button.get_index())
	draw_button = Button.new()
	draw_button.text = "Draw"
	draw_button.theme_type_variation = &"CompactButton"
	draw_button.custom_minimum_size = Vector2(0, 78)
	draw_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	draw_button.pressed.connect(offer_draw)
	_buttons.add_child(draw_button)
	_buttons.move_child(draw_button, new_game_button.get_index())
	chat_panel = ChatPanel.new()
	chat_panel.send_requested.connect(send_chat)
	chat_panel.mute_toggled.connect(set_muted)
	chat_panel.report_requested.connect(ask_report)
	add_child(chat_panel)

func _update_online_controls() -> void:
	var playing := online.status() == OnlineSession.PLAYING
	var theirs := OnlineSession.team_key(Piece.other_team(online.my_team))
	draw_button.visible = playing
	draw_button.disabled = online.draw_offer() != "" or _sending
	draw_button.text = "Draw offered" if online.draw_offer() == OnlineSession.team_key(online.my_team) else "Draw"
	offer_bar.visible = playing and online.draw_offer() == theirs
	new_game_button.text = "Results" if is_over() else "Resign"
	var unread := _visible_chat().size() - _chat_seen
	chat_button.text = "Chat (%d)" % unread if unread > 0 else "Chat"
	if chat_panel.visible:
		_refresh_chat()

func offer_draw() -> void:
	if online == null or online.status() != OnlineSession.PLAYING or online.draw_offer() != "":
		return
	draw_button.disabled = true
	await online.offer_draw()
	_after_online_change()

func answer_draw(accept: bool) -> void:
	await online.answer_draw(accept)
	_after_online_change()

func open_chat() -> void:
	_refresh_chat()
	chat_panel.show()
	_update_online_controls()

func send_chat(text: String) -> void:
	await online.post_chat(text)
	_refresh_chat()
	_update_online_controls()

func _refresh_chat() -> void:
	_chat_seen = _visible_chat().size()
	chat_panel.show_messages(online.chat(), OnlineSession.team_key(online.my_team), online.muted)

## The chat messages this player sees (not the opponent's while muted).
func _visible_chat() -> Array:
	if not online.muted:
		return online.chat()
	var mine := OnlineSession.team_key(online.my_team)
	return online.chat().filter(func(m: Dictionary) -> bool: return m.get("from", "") == mine)

## Mute or unmute the opponent's chat (Mac's Mute; this game and its rematches).
func set_muted(muted: bool) -> void:
	online.muted = muted
	_refresh_chat()
	_update_online_controls()

## Report the opponent (Mac's Report): asks first, then the server keeps this
## game's chat and moves for review; the opponent is muted too.
func ask_report() -> void:
	var panel := ModalPanel.new("Report your opponent?")
	panel.add_text(REPORT_TEXT)
	panel.add_button("Report", func() -> void:
		panel.close()
		send_report(), &"DangerButton")
	panel.add_button("Cancel", panel.close, &"GhostButton")
	panel.z_index = 40
	add_child(panel)

## The report pop-up's text (drafted by Claude for Mac to change).
const REPORT_TEXT := "This game's chat and moves will be sent for review, and your opponent will be muted."

func send_report() -> void:
	var result := await online.report_opponent()
	set_muted(true)
	show_notice("Thanks: your report was sent." if result.ok else result.error)

func _opponent_wants_rematch() -> bool:
	return online.rematch_code() != "" and online.rematch_code() != _my_rematch_code

func _show_rematch_offer() -> void:
	if not game_over_panel.visible:
		show_game_over()
		return
	game_over_panel.set_note("Your opponent wants a rematch!")
	var button := game_over_panel.button("rematch")
	if button:
		button.text = "Accept rematch"

## Rematch: accepting the opponent's rematch means choosing an army; setting one
## up means choosing an army and a side (White, Black or Random, Mac's design),
## then waiting for them. The time limit stays the same.
func start_rematch() -> void:
	var accepting := _opponent_wants_rematch()
	var picker := ArmyPicker.new(library, "Your army for the rematch", not accepting)
	picker.chosen.connect(_rematch_with)
	add_child(picker)

## `army`: an Army, or a Callable(team) -> Army (Default / Random, see ArmyChoices).
func _rematch_with(army: Variant, side := OnlineSession.SIDE_RANDOM) -> void:
	var button := game_over_panel.button("rematch")
	if button:
		button.disabled = true
	if _opponent_wants_rematch():
		await _join_rematch(online.rematch_code(), army)
		return
	game_over_panel.set_note("Setting up the rematch...")
	var next := _new_session()
	var created := await next.create_game(army, side, int(online.row.get("time_ms", 0)), bool(online.row.get("eval_bar", false)),
			online.increment_ms())
	if not created.ok:
		_rematch_failed(next, "Couldn't set up a rematch: " + created.error)
		return
	var claimed := await online.claim_rematch(next.code)
	if claimed.ok and not claimed.rows.is_empty():
		_my_rematch_code = next.code
		game_over_panel.set_note("Waiting for your opponent to accept the rematch...")
		next.changed.connect(func(_row: Dictionary) -> void:
			if next.status() == OnlineSession.PLAYING:
				_go_to_rematch(next))
		next.start_polling()
		return
	# The opponent set one up at the same moment: join theirs instead.
	await next.cancel()
	next.queue_free()
	await online.poll()
	if online.rematch_code() != "":
		await _join_rematch(online.rematch_code(), army)
	else:
		_rematch_failed(null, "Couldn't set up a rematch.")

func _join_rematch(rematch_code: String, army: Variant) -> void:
	game_over_panel.set_note("Joining the rematch...")
	var next := _new_session()
	var joined := await next.join_game(rematch_code, army)
	if not joined.ok:
		_rematch_failed(next, joined.error)
		return
	_go_to_rematch(next)

func _new_session() -> OnlineSession:
	var next := OnlineSession.new(online.backend.duplicate(), online.player_id)
	next.poll_seconds = online.poll_seconds
	# A muted opponent stays muted in the rematch.
	next.muted = online.muted
	add_child(next)
	return next

func _rematch_failed(next: OnlineSession, message: String) -> void:
	if next:
		next.queue_free()
	game_over_panel.set_note(message)
	var button := game_over_panel.button("rematch")
	if button:
		button.disabled = false

func _go_to_rematch(next: OnlineSession) -> void:
	next.stop_polling()
	rematch_ready.emit(next)

# --- Online games ---------------------------------------------------------------

## Set the screen up for an online game: the position from the server, this
## player's side, the clocks, and Resign instead of Undo / New game.
func _start_online() -> void:
	if online.get_parent() != self:
		add_child(online)
	resign_button.hide()
	# So "your move" notifications can be shown (web: asked on the next tap).
	TurnNotifier.ask_permission_on_next_tap()
	white_army = online.army(Piece.Team.WHITE)
	black_army = online.army(Piece.Team.BLACK)
	state = online.create_state(StandardSetup.create_rules())
	if state == null:
		state = _create_start_state()
	undo_button.hide()
	redo_button.hide()
	new_game_button.text = "Resign"
	new_game_button.pressed.disconnect(ask_new_game)
	new_game_button.pressed.connect(resign)
	clock_label.visible = online.timed()
	_build_online_extras()
	online.changed.connect(_on_online_changed)
	online.start_polling()
	if online.status() == OnlineSession.PLAYING:
		UserSettings.set_online_game(online.code, online.my_team)
	else:
		UserSettings.set_online_game("")
	_show_new_state()

func _my_online_turn() -> bool:
	if online == null:
		return true
	return online.status() == OnlineSession.PLAYING and state.side_to_move == online.my_team and not _sending

## Send this player's move. If the connection fails, keep trying until the
## server has it. If the server didn't take it (the opponent resigned first,
## the clock ran out, ...), the board goes back to the server's game.
func _send_online_moves() -> void:
	_sending = true
	_update_input()
	var move_text: String = state.history.back().to_text()
	var finished := state.outcome() != GameState.Outcome.NONE
	var result := await online.send_move(move_text, finished)
	while not result.ok and result.error.begins_with("no connection") and is_inside_tree():
		status_label.text = "Connection problem - trying again..."
		await get_tree().create_timer(3.0).timeout
		result = await online.send_move(move_text, finished)
	_sending = false
	if not is_inside_tree():
		return
	if not result.ok:
		show_notice("The server didn't take that move: " + result.error)
	# The server had something newer (e.g. the opponent resigned): catch up.
	if result.rows.is_empty():
		await online.poll()
	if online.move_count() != state.history.size():
		_resync_with_server()
	_after_online_change()

## Put the board back to the game exactly as the server has it.
func _resync_with_server() -> void:
	var server_state := online.create_state(StandardSetup.create_rules())
	if server_state == null:
		return
	state = server_state
	redo_moves.clear()
	_show_new_state()

## Something changed on the server: play any new moves from the opponent.
func _on_online_changed(_row: Dictionary) -> void:
	var server_moves := online.moves()
	var last_san := ""
	for i in range(state.history.size(), server_moves.size()):
		var move := state.find_move(str(server_moves[i]))
		if move == null:
			_resync_with_server()
			break
		last_san = Notation.san(state, move)
		play(move, true)
	_after_online_change()
	# The opponent moved: tell the player if they're not looking (Mac).
	if last_san != "" and state.side_to_move == online.my_team and not is_over():
		TurnNotifier.your_turn("Your opponent played %s." % last_san)

func _after_online_change() -> void:
	# Keep checking the server after the game ends too, for rematch offers.
	if online.status() != OnlineSession.PLAYING:
		UserSettings.set_online_game("")
	_update_text()
	_update_input()
	if is_over() and _opponent_wants_rematch():
		_show_rematch_offer()

## Resign this online game (the first tap asks for a second one).
func resign() -> void:
	if online == null:
		return
	# After the game, this button shows the result screen again.
	if is_over():
		show_game_over()
		return
	if online.status() != OnlineSession.PLAYING:
		return
	var now := Time.get_ticks_msec()
	if _resign_tapped_ms < 0 or now - _resign_tapped_ms > 3000:
		_resign_tapped_ms = now
		new_game_button.text = "Tap again to resign"
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if is_instance_valid(new_game_button):
				new_game_button.text = "Resign")
		return
	_resign_tapped_ms = -1
	new_game_button.text = "Resign"
	await online.resign()
	_after_online_change()

func _process(_delta: float) -> void:
	if online == null or not online.timed():
		return
	var now := Time.get_ticks_msec()
	var white := _clock_text(online.clock_ms(Piece.Team.WHITE, now))
	var black := _clock_text(online.clock_ms(Piece.Team.BLACK, now))
	var you := " (you)"
	clock_label.text = "White %s%s      Black %s%s" % [white, you if online.my_team == Piece.Team.WHITE else "",
			black, you if online.my_team == Piece.Team.BLACK else ""]
	# A clock that has run out ends the game (claimed by whoever notices first;
	# the server checks with its own clock, so a refused claim waits 2 s).
	if not _claiming_timeout and now >= _next_timeout_claim_ms and online.out_of_time(online.side_to_move(), now):
		_claim_timeout(online.side_to_move())

func _claim_timeout(team: Piece.Team) -> void:
	_claiming_timeout = true
	await online.claim_timeout(team)
	_claiming_timeout = false
	_next_timeout_claim_ms = Time.get_ticks_msec() + 2000
	_after_online_change()

## "4:05", never below "0:00".
static func _clock_text(ms: int) -> String:
	var seconds := maxi(0, ceili(ms / 1000.0))
	return "%d:%02d" % [seconds / 60, seconds % 60]

## How a finished online game ended, if not on the board: "" otherwise.
func _online_ending() -> String:
	if online.status() == OnlineSession.CANCELLED:
		return "This game was cancelled"
	var code := online.result_code()
	if online.status() != OnlineSession.FINISHED or code == "board" or code == "":
		return ""
	var losing_team := Piece.Team.WHITE if code.begins_with("white") else Piece.Team.BLACK
	var you_lost := losing_team == online.my_team
	if code.ends_with("resigned"):
		return "You resigned" if you_lost else "Your opponent resigned - you win!"
	return "You ran out of time" if you_lost else "Your opponent ran out of time - you win!"

## "1-0" / "0-1" for a game that ended by resigning or time, else "*".
func _online_result_text() -> String:
	var code := online.result_code()
	if online.status() != OnlineSession.FINISHED or code == "board" or code == "":
		return "*"
	return "0-1" if code.begins_with("white") else "1-0"

func _scroll_moves_to_end() -> void:
	if is_inside_tree():
		_moves_scroll.scroll_vertical = int(_moves_scroll.get_v_scroll_bar().max_value)

## Keep the move being looked at in sight while stepping through the moves.
func _scroll_to_viewed_move() -> void:
	var button := move_list.viewed_button
	if not is_inside_tree() or not is_instance_valid(button):
		return
	# A side line's box is laid out a frame later than the main list.
	if not move_list.buttons.has(button):
		await get_tree().process_frame
		if not is_instance_valid(button) or button != move_list.viewed_button:
			return
	# Where the move sits in the list (not ensure_control_visible: it goes by
	# where things are on screen, which lags behind until the next frame).
	var top := button.global_position.y - move_list.global_position.y
	var bottom := top + button.size.y
	if top < _moves_scroll.scroll_vertical:
		_moves_scroll.scroll_vertical = int(top)
	elif bottom > _moves_scroll.scroll_vertical + _moves_scroll.size.y:
		_moves_scroll.scroll_vertical = int(ceil(bottom - _moves_scroll.size.y))

## Which move `index` (0 = the first) was, e.g. "White's move 12".
func _move_name(index: int) -> String:
	return _move_name_in(state.history, index)

## The same for move `index` of `moves` (a side line's copy of the game).
static func _move_name_in(moves: Array[Move], index: int) -> String:
	var move: Move = moves[index]
	var side := "White" if move.piece.team == Piece.Team.WHITE else "Black"
	# Count White's and Black's moves up to this one.
	var number := 0
	for i in range(index + 1):
		if moves[i].piece.team == move.piece.team:
			number += 1
	return "%s's move %d" % [side, number]
