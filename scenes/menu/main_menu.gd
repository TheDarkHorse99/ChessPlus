extends Control

## The title screen.

signal continue_pressed
signal play_pressed
signal how_to_play_pressed
signal online_pressed
signal continue_online_pressed
signal armies_pressed
signal testing_pressed
signal settings_pressed

func _ready() -> void:
	# Only offer to continue when there's an unfinished game saved.
	%Continue.visible = SavedGame.load_saved() != null
	%Continue.pressed.connect(func() -> void: continue_pressed.emit())
	%Play.pressed.connect(func() -> void: play_pressed.emit())
	%HowToPlay.pressed.connect(func() -> void: how_to_play_pressed.emit())
	%Online.pressed.connect(func() -> void: online_pressed.emit())
	# An online game in progress can be picked up again.
	var online_code := UserSettings.online_game()
	%ContinueOnline.visible = online_code != ""
	%ContinueOnline.text = "Continue online game (%s)" % online_code
	%ContinueOnline.pressed.connect(func() -> void: continue_online_pressed.emit())
	%Armies.pressed.connect(func() -> void: armies_pressed.emit())
	%Testing.pressed.connect(func() -> void: testing_pressed.emit())
	%Settings.pressed.connect(func() -> void: settings_pressed.emit())
	_highlight_first()

## The top button (Continue game if there's one, else Play local) is the gold
## main button; the rest are plain.
func _highlight_first() -> void:
	var first := true
	for button: Button in [%Continue, %Play, %ContinueOnline, %Online]:
		button.theme_type_variation = &"AccentButton" if first and button.visible else &""
		if button.visible:
			first = false
