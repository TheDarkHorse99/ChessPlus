class_name HowToPlay
extends Control

## "How to play" (Mac's design, 26 Oct 2026): one scrolling page opened from
## the main menu (below Play local), and shown once on the first launch
## (`UserSettings.how_to_play_seen`). The army-building rules, the three rules
## that differ from chess, and where to find a piece's card. Wording: Mac's.

signal closed

const TITLE := "How to play"
## The page: [heading or "", [lines]]. A line starting with "- " is a bullet.
const SECTIONS: Array = [
	["", ["Overchess is chess with an army you build yourself."]],
	["Build your army", [
		"- You have 40 points to spend on pieces.",
		"- Your pieces start on your side's two rows.",
		"- Exactly one King, in the middle of the back row.",
		"- At most two of any piece type.",
		"- Pawn-type pieces: as many as you like.",
		"Tap a piece in the army builder to see its card: how it moves, what it costs and any special rule.",
	]],
	["What's different from chess", [
		"- White's first move can't capture or break a shield.",
		"- A piece must have moved once before it can use its special ability or promote.",
		"- 75 moves without a capture or any other change to the pieces is a draw (the 50-move rule still applies too).",
		"Everything else, from check and castling to en passant, works as in chess.",
	]],
]
const BODY_FONT_SIZE := 26

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
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 10)
	limit.add_child(page)
	for section: Array in SECTIONS:
		if section[0] != "":
			var heading := Label.new()
			heading.text = section[0]
			heading.theme_type_variation = &"StrongLabel"
			heading.add_theme_color_override("font_color", UiStyle.ACCENT)
			var gap := Control.new()
			gap.custom_minimum_size.y = 10
			page.add_child(gap)
			page.add_child(heading)
		for line: String in section[1]:
			page.add_child(_line(line))
	var done := Button.new()
	done.text = "Got it"
	done.theme_type_variation = &"AccentButton"
	done.custom_minimum_size.y = 80
	done.pressed.connect(close)
	layout.add_child(done)

func _top_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	var back := BackButton.new()
	back.pressed.connect(close)
	bar.add_child(back)
	var title := Label.new()
	title.text = TITLE
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title)
	# Room for the volume button in the corner.
	var spacer := Control.new()
	spacer.custom_minimum_size.x = 72
	bar.add_child(spacer)
	return bar

## A paragraph, or a bullet (a hanging "•" with the text beside it).
func _line(text: String) -> Control:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not text.begins_with("- "):
		label.text = text
		return label
	label.text = text.trim_prefix("- ")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var dot := Label.new()
	dot.text = "•"
	dot.add_theme_font_size_override("font_size", BODY_FONT_SIZE)
	dot.add_theme_color_override("font_color", UiStyle.ACCENT)
	dot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(dot)
	row.add_child(label)
	return row

## The whole page as plain text (tests, and anywhere the words are needed).
static func plain_text() -> String:
	var lines: PackedStringArray = []
	for section: Array in SECTIONS:
		if section[0] != "":
			lines.append(section[0])
		for line: String in section[1]:
			lines.append(line.trim_prefix("- "))
	return "\n".join(lines)

func close() -> void:
	closed.emit()
