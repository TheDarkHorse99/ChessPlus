class_name SettingsMenu
extends Control

## The Settings screen (Mac's design, Oct 2026): sound, visual, keyboard and
## mouse settings, the credits, and a button that puts every setting back to how it
## started. Opened from the main menu (as its own screen) and from games (the
## gear button, on top of the game). Every change is saved straight away.

## Back was pressed.
signal closed
## A sound setting changed (the volume button in the corner follows it).
signal sound_changed
## Any setting changed (an open game redraws with it).
signal settings_changed

const ROW_LABEL_WIDTH := 300
## The credits the pictures, font and some of the sounds need (their licences).
const CREDITS: Array[String] = [
	"Chess pieces by Cburnett (CC BY-SA 3.0)",
	"Inter and Open Sans Italic fonts (SIL OFL 1.1)",
	"Sounds: giggle by Lomond (CC BY 3.0), thunder by Jud McCranie (CC BY-SA 4.0), church bell by Pete w. View (CC BY-SA 4.0), choir: Coro Santa Pazienza (CC BY 3.0)",
]

## The privacy notice (drafted by Claude for Mac to change, Oct 2026): what the
## game keeps and who sees it. Keep it true when online play changes (the
## server's rules are in server/supabase_update_*.sql).
## Where "Report a bug" goes (Mac, 26 Oct 2026): the game's GitHub issues.
const BUG_REPORT_URL := "https://github.com/thedarkhorse99/ChessPlus/issues"
## The Discord invite (Mac: link to follow). While it's empty the button is greyed out.
const DISCORD_URL := ""
## Tests put a Callable here to see which link a button would open.
static var link_opener: Callable = Callable()

## Opens a web page: the browser on PC, a new tab on the web (JavaScriptBridge,
## so the game isn't left; it runs inside the tap, so the browser allows it).
static func open_link(url: String) -> void:
	if url.is_empty():
		return
	if link_opener.is_valid():
		link_opener.call(url)
	elif OS.has_feature("web"):
		JavaScriptBridge.eval("window.open(%s, '_blank')" % JSON.stringify(url))
	else:
		OS.shell_open(url)

const PRIVACY: Array[String] = [
	"Overchess has no accounts and never asks for your name, email or password.",
	"Local games, your armies and your settings stay on this device.",
	"For online play, this device signs in to the game's server (run by Supabase) with a random ID. The server keeps your online games (moves, armies and their names, and chat) and deletes them 30 days after they end, or after a day if nobody joined. It also notes when you were last online, for the player count, and forgets that after a day.",
	"Your opponent sees your army, its name and your chat messages. Anyone with a game's code can see its moves and armies, but not the chat.",
	"If a game is reported, its chat and moves are kept for 90 days so the report can be looked at.",
	"Armies you share by code stay on the server so others can import them.",
	"Like any website, the server and the game's web host (GitHub) record connection details such as IP addresses.",
]

## The scrolling list of settings.
var sections: VBoxContainer
var sound_toggle: Button
var volume_slider: HSlider
## One slider per sound group (UserSettings.SOUND_GROUPS).
var group_sliders := {}
var notifications_toggle: Button
## Animation speed choices, by UserSettings.ANIMATION_SPEEDS key.
var speed_buttons := {}
## One switch per board helper (UserSettings.BOARD_HELPERS).
var helper_toggles := {}
var reduce_toggle: Button
## The key button of each keyboard shortcut (KeyBinds.ACTIONS), PC only.
var key_buttons := {}
## The shortcut waiting for its new key ("" when none).
var listening := ""
## The button of each mouse action (MouseBinds.ACTIONS), PC only.
var mouse_buttons := {}
## The mouse action waiting for its new button ("" when none).
var listening_mouse := ""
## The Credits, Privacy or Reset pop-up while it's showing.
var popup: ModalPanel

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := Backdrop.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	layout.add_child(_top_bar())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var limit := WidthLimit.new()
	limit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(limit)
	sections = VBoxContainer.new()
	sections.add_theme_constant_override("separation", 16)
	limit.add_child(sections)
	_build_sound()
	_build_visual()
	if KeyBinds.has_keyboard():
		_build_keys()
		_build_mouse()
	_build_other()
	refresh()
	# The volume button in the corner and this screen show each other's changes.
	for control in get_tree().get_nodes_in_group("volume_control"):
		(control as VolumeControl).changed.connect(refresh)

func _top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	var back := BackButton.new()
	back.pressed.connect(close)
	bar.add_child(back)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.theme_type_variation = &"TitleLabel"
	bar.add_child(title)
	# As wide as Back, so the title stays centred; then room for the volume button.
	var balance := Control.new()
	balance.custom_minimum_size.x = back.custom_minimum_size.x
	bar.add_child(balance)
	bar.add_child(VolumeControl.make_room())
	return bar

func close() -> void:
	closed.emit()

# --- Sound -------------------------------------------------------------------------

func _build_sound() -> void:
	_heading("Sound")
	sound_toggle = _toggle_row("Sound", func(on: bool) -> void:
		UserSettings.set_sound_on(on)
		_sound_changed())
	volume_slider = _slider_row("Volume", func(value: float) -> void:
		UserSettings.set_volume(value)
		# Turning the volume up is asking to hear it, even if sound was off.
		if value > 0 and not UserSettings.sound_on():
			UserSettings.set_sound_on(true)
		_sound_changed())
	var names := {"moves": "Moves and captures", "effects": "Special effects", "warnings": "Warnings"}
	for group in UserSettings.SOUND_GROUPS:
		group_sliders[group] = _slider_row(names[group], func(value: float) -> void:
			UserSettings.set_group_volume(group, value)
			_sound_changed())
	notifications_toggle = _toggle_row("\"Your move\" notifications", func(on: bool) -> void:
		UserSettings.set_notifications_on(on)
		settings_changed.emit())

func _sound_changed() -> void:
	GameSounds.apply_volume()
	refresh()
	get_tree().call_group("volume_control", "refresh")
	sound_changed.emit()
	settings_changed.emit()

# --- Visual -------------------------------------------------------------------------

func _build_visual() -> void:
	_heading("Visual")
	var names := {"off": "Off", "fast": "Fast", "normal": "Normal", "slow": "Slow"}
	speed_buttons = _choice_row("Animation speed", names, func(speed: String) -> void:
		UserSettings.set_animation_speed(speed)
		settings_changed.emit())
	var helper_names := {"coordinates": "Board coordinates", "move_dots": "Legal-move dots",
		"last_move": "Last-move highlight", "ability_glow": "Glow round unused abilities"}
	for helper in UserSettings.BOARD_HELPERS:
		helper_toggles[helper] = _toggle_row(helper_names[helper], func(on: bool) -> void:
			UserSettings.set_board_helper(helper, on)
			settings_changed.emit())
	reduce_toggle = _toggle_row("Reduce flashing and shaking", func(on: bool) -> void:
		UserSettings.set_reduce_effects(on)
		settings_changed.emit())

# --- Keyboard -----------------------------------------------------------------------

func _build_keys() -> void:
	_heading("Keyboard")
	var hint := Label.new()
	hint.text = "Press a key's button, then the new key."
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sections.add_child(hint)
	for action: String in KeyBinds.ACTIONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 60)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: listen_for_key(action))
		_row(KeyBinds.ACTIONS[action][0], button)
		key_buttons[action] = button

## Wait for the next key, for shortcut `action`.
func listen_for_key(action: String) -> void:
	listening = action
	listening_mouse = ""
	refresh()

## While waiting for a key: that key becomes the shortcut (any key, with Ctrl,
## Shift or Alt if held; pressing only one of those waits on). While waiting for
## a mouse button: the next click (any button but the wheel) sets it.
func _input(event: InputEvent) -> void:
	if listening_mouse != "":
		_listen_mouse_input(event)
		return
	var key := event as InputEventKey
	if listening == "" or key == null or not key.pressed or key.echo:
		return
	if key.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return
	get_viewport().set_input_as_handled()
	set_key(listening, key.get_keycode_with_modifiers())

## Put shortcut `action` on `code` (two shortcuts on one key swap).
func set_key(action: String, code: int) -> void:
	KeyBinds.set_key(action, code)
	listening = ""
	refresh()
	settings_changed.emit()

# --- Mouse --------------------------------------------------------------------------

func _build_mouse() -> void:
	_heading("Mouse")
	var hint := Label.new()
	hint.text = "Press a button here, then click with the mouse button you want."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 22)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	sections.add_child(hint)
	for action: String in MouseBinds.ACTIONS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(220, 60)
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(func() -> void: listen_for_mouse(action))
		_row(MouseBinds.ACTIONS[action][0], button)
		mouse_buttons[action] = button

## Wait for the next mouse click, for mouse action `action`.
func listen_for_mouse(action: String) -> void:
	listening_mouse = action
	listening = ""
	refresh()

## The click that sets the waiting mouse action; Esc stops waiting. Nothing else
## gets the click (so clicking another setting doesn't also press it).
func _listen_mouse_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and key.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		listening_mouse = ""
		refresh()
		return
	var click := event as InputEventMouseButton
	if click == null or not MouseBinds.can_use(click.button_index):
		return
	get_viewport().set_input_as_handled()
	if click.pressed:
		set_mouse(listening_mouse, click.button_index)

## Put mouse action `action` on button `index` (two actions on one button swap).
func set_mouse(action: String, index: int) -> void:
	MouseBinds.set_button(action, index)
	listening_mouse = ""
	refresh()
	settings_changed.emit()

# --- Credits and reset ---------------------------------------------------------------

## Credits, Privacy and Reset with no title over them (Mac: "More" looked like a button).
func _build_other() -> void:
	var gap := Control.new()
	gap.custom_minimum_size.y = 12
	sections.add_child(gap)
	# Report a bug and Discord side by side, above Credits (Mac, 26 Oct 2026).
	var links := HBoxContainer.new()
	links.add_theme_constant_override("separation", 12)
	sections.add_child(links)
	for entry: Array in [["Report a bug", BUG_REPORT_URL], ["Discord", DISCORD_URL]]:
		var button := Button.new()
		button.text = entry[0]
		button.custom_minimum_size.y = 80
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = (entry[1] as String).is_empty()
		if button.disabled:
			button.tooltip_text = "Link to follow"
		button.pressed.connect(open_link.bind(entry[1]))
		links.add_child(button)
	_wide_button("Credits", show_credits)
	_wide_button("Privacy", show_privacy)
	_wide_button("Reset to defaults", ask_reset)

func show_credits() -> void:
	popup = ModalPanel.new("Credits")
	for line in CREDITS:
		popup.add_text(line, 24)
	popup.add_button("Close", popup.close, &"GhostButton")
	add_child(popup)

func show_privacy() -> void:
	popup = ModalPanel.new("Privacy")
	popup.add_paragraphs(PRIVACY)
	popup.add_button("Close", popup.close, &"GhostButton")
	add_child(popup)

func ask_reset() -> void:
	popup = ModalPanel.new("Reset to defaults?")
	popup.add_text("Every setting and key goes back to how it started.")
	popup.add_button("Reset", func() -> void:
		reset_to_defaults()
		popup.close(), &"DangerButton")
	popup.add_button("Cancel", popup.close, &"GhostButton")
	add_child(popup)

func reset_to_defaults() -> void:
	UserSettings.reset_to_defaults()
	KeyBinds.install()
	listening = ""
	listening_mouse = ""
	_sound_changed()

## Show the saved settings (after a change here, or elsewhere such as the volume
## button in the corner).
func refresh() -> void:
	if sound_toggle == null:
		return
	_show_toggle(sound_toggle, UserSettings.sound_on())
	_show_slider(volume_slider, UserSettings.volume())
	for group in group_sliders:
		_show_slider(group_sliders[group], UserSettings.group_volume(group))
	_show_toggle(notifications_toggle, UserSettings.notifications_on())
	for speed in speed_buttons:
		(speed_buttons[speed] as Button).set_pressed_no_signal(speed == UserSettings.animation_speed())
	for helper in helper_toggles:
		_show_toggle(helper_toggles[helper], UserSettings.board_helper(helper))
	_show_toggle(reduce_toggle, UserSettings.reduce_effects())
	for action in key_buttons:
		(key_buttons[action] as Button).text = "Press a key..." if action == listening else KeyBinds.text(KeyBinds.key(action))
	for action in mouse_buttons:
		(mouse_buttons[action] as Button).text = "Click..." if action == listening_mouse else MouseBinds.text(MouseBinds.button(action))

# --- Building blocks ---------------------------------------------------------------

func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_font_override("font", UiStyle.bold())
	label.add_theme_color_override("font_color", UiStyle.ACCENT_TEXT)
	sections.add_child(label)

## A row: the setting's name on the left, its control on the right.
func _row(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = ROW_LABEL_WIDTH
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	row.add_child(label)
	row.add_child(control)
	sections.add_child(row)
	return row

## An On/Off switch (gold when on, like the default-army buttons).
func _toggle_row(text: String, on_toggled: Callable) -> Button:
	var button := _gold_toggle()
	button.toggled.connect(func(on: bool) -> void:
		button.text = "On" if on else "Off"
		on_toggled.call(on))
	_row(text, button)
	return button

## A choice of several (only one on at a time), on its own line under its
## name so it fits a phone; `choices` maps each value to its button text, and
## `on_chosen` gets the value. Returns value -> button.
func _choice_row(text: String, choices: Dictionary, on_chosen: Callable) -> Dictionary:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	sections.add_child(label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	sections.add_child(row)
	var group := ButtonGroup.new()
	var buttons := {}
	for value: String in choices:
		var button := _gold_toggle()
		button.text = choices[value]
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func() -> void: on_chosen.call(value))
		row.add_child(button)
		buttons[value] = button
	return buttons

## A toggle button that goes gold when on.
func _gold_toggle() -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.theme_type_variation = &"ChoiceButton"
	button.custom_minimum_size = Vector2(150, 64)
	button.focus_mode = Control.FOCUS_NONE
	return button

func _show_toggle(button: Button, on: bool) -> void:
	button.set_pressed_no_signal(on)
	button.text = "On" if on else "Off"

## A 0-100% slider with its value beside it; `on_changed` gets 0..1.
func _slider_row(text: String, on_changed: Callable) -> HSlider:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.custom_minimum_size.x = 360
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	VolumeControl.style_slider(slider)
	box.add_child(slider)
	var percent := Label.new()
	percent.custom_minimum_size.x = 90
	percent.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	percent.add_theme_font_size_override("font_size", 26)
	box.add_child(percent)
	slider.set_meta("percent", percent)
	slider.value_changed.connect(func(value: float) -> void:
		percent.text = "%d%%" % int(value)
		on_changed.call(value / 100.0))
	_row(text, box)
	return slider

func _show_slider(slider: HSlider, value: float) -> void:
	slider.set_value_no_signal(roundf(value * 100))
	(slider.get_meta("percent") as Label).text = "%d%%" % int(slider.value)

func _wide_button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 80
	button.pressed.connect(on_pressed)
	sections.add_child(button)
	return button

# --- The gear button that opens Settings from a game -----------------------------------

## A square button with a gear on it, the size of the volume button.
static func gear_button() -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(VolumeControl.BUTTON_SIZE, VolumeControl.BUTTON_SIZE)
	button.focus_mode = Control.FOCUS_NONE
	button.tooltip_text = "Settings"
	var icon := GearIcon.new()
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)
	return button

## A gear, drawn (the font has no gear symbol), in the volume button's white.
class GearIcon extends Control:
	func _draw() -> void:
		var c := size / 2
		var u := minf(size.x, size.y) / 64.0  # Drawn on a 64 x 64 grid.
		var white := Color(0.95, 0.95, 0.95)
		for i in 8:
			var angle := TAU * i / 8.0
			var along := Vector2.from_angle(angle)
			var side := Vector2(-along.y, along.x)
			draw_colored_polygon(PackedVector2Array([
				c + along * 13 * u + side * 5 * u, c + along * 21 * u + side * 4 * u,
				c + along * 21 * u - side * 4 * u, c + along * 13 * u - side * 5 * u,
			]), white)
		draw_arc(c, 10.5 * u, 0, TAU, 32, white, 9 * u, true)
