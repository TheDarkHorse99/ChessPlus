class_name PieceCard
extends VBoxContainer

## Everything about one piece type, in a compact card:
##   header: its picture(s), name, cost and type(s) (types in italics)
##   a mini board showing how it moves, with a legend
##   its keywords as coloured boxes (in capitals)
##   "Special Rule": anything the rest can't show (e.g. how the cannon captures)
##   "Special Ability": a once-per-game action, with its name
## Hovering over a type or keyword (tapping, on a phone) shows a short
## explanation in a bubble.
## Used in the army builder (always showing the chosen piece) and in games
## (inside PieceInfo, when you hold a piece).

## Each keyword's box colour and text colour (shared with RuleText, which draws
## keywords inline in rule texts).
const KEYWORD_COLORS := RuleText.KEYWORD_COLORS
const ITALIC_FONT := RuleText.ITALIC_FONT

## The short explanation shown for each type and keyword (Mac's rulings, Oct
## 2026; *type* = italics, {keyword} = its coloured box: see RuleText).
const EXPLANATIONS := {
	"King": "If a *King* is checkmated, its side loses. Every army has exactly one, starting in the middle of the back row. It can castle.",
	"Royal": "An army can have only one *Royal* piece besides its *King*.",
	"Pawn": "Any number per army. It can capture, and be captured, en passant. Moving it resets the 50-move count.",
	"Jump": "Leaps over pieces: the squares it jumps over can't block it.",
	"Castle": "Your *King* can castle with it if neither has moved and it started in a corner of your back row.",
	"Promote": "Must turn into another piece when it reaches the far end (any non-*Pawn*, non-*King* piece that started the game).",
	"Shield": "The first capture only breaks its shield, and the attacker stays where it was.",
	"Wall": "The opponent's pieces can't jump over it. Their Knights count as moving 2 squares straight, then 1. It's no screen for the opponent's Cannons. Your own pieces jump it freely.",
	"Special Ability": "Once per game, after the piece has moved at least once (a capture or a shield break counts). Uses your turn.",
}

var def: PieceDef
## Whose moves the mini board and legend show: `def`'s, or (for a piece with two
## forms, like the Werewolf) its other form's.
var moves_def: PieceDef
var team := Piece.Team.WHITE
## How big the card is drawn: 1 = normal (the pop-up in games); the army builder
## uses more. Change it with set_zoom.
var zoom := 1.0
## The explanation bubble, and the type/keyword it's showing (null if hidden).
var tooltip: PanelContainer
var tooltip_owner: Control

## Show `p_def`. Safe to call before or after the card is on screen.
func show_piece(p_def: PieceDef, p_team := Piece.Team.WHITE) -> void:
	def = p_def
	moves_def = p_def
	team = p_team
	if is_node_ready():
		_refresh()

## A piece that changes form (the Werewolf) shows both pictures, and a grey
## button switches the mini board and legend between its two forms' moves
## (Mac); the rest of the card stays. Returns [the piece it starts as, the form
## it changes into], or [] for an ordinary piece. Works from either form.
static func forms_of(p_def: PieceDef) -> Array:
	if p_def.transforms_into:
		return [p_def, p_def.transforms_into]
	for other: PieceDef in PieceCatalog.all_defs():
		if other.transforms_into == p_def:
			return [other, p_def]
	return []

## Show the other form's moves (the button under the name).
func turn_over() -> void:
	var forms := forms_of(def)
	if forms.is_empty():
		return
	moves_def = forms[1] if moves_def == forms[0] else forms[0]
	_update_form_button()
	%GuideBoard.show_piece(moves_def, team)
	_fill_move_note()

var _form_button: Button

## The grey "Wolf moves" / "Human moves" button: it names the moves it switches
## to.
func _update_form_button() -> void:
	var forms := forms_of(def)
	if forms.is_empty():
		if _form_button:
			_form_button.hide()
		return
	if _form_button == null:
		_form_button = Button.new()
		_form_button.focus_mode = Control.FOCUS_NONE
		_form_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_form_button.pressed.connect(turn_over)
		%Name.get_parent().add_child(_form_button)
	var other: PieceDef = forms[1] if moves_def == forms[0] else forms[0]
	_form_button.text = other.form_name + " moves"
	_form_button.add_theme_font_size_override("font_size", _z(20))
	var grey := Color("#6E6E6E")
	var style := GradientStyleBox.new(PackedColorArray([grey, grey]), 8, _z(12), _z(4))
	_form_button.add_theme_stylebox_override("normal", style)
	_form_button.add_theme_stylebox_override("hover", style.shaded(0.15))
	_form_button.add_theme_stylebox_override("pressed", style.shaded(-0.2))
	for color in ["font_color", "font_hover_color", "font_pressed_color"]:
		_form_button.add_theme_color_override(color, Color.WHITE)
	_form_button.show()

func _ready() -> void:
	_make_tooltip()
	# What a special ability is (Mac): on its heading and its name.
	_explain_on_hover($Ability/AbilityHeader/AbilityTitle, "Special Ability")
	_explain_on_hover(%AbilityChip, "Special Ability")
	_apply_zoom()
	if def:
		_refresh()

## Draw the card bigger (or smaller): 1.5 = everything half as big again.
func set_zoom(p_zoom: float) -> void:
	if is_equal_approx(p_zoom, zoom):
		return
	zoom = p_zoom
	if is_node_ready():
		_apply_zoom()
		if def:
			_refresh()

## How tall the card gets for the piece with the most to say, among `defs`,
## when `width` wide at `zoom`: measured on an invisible card under `host`
## (it takes a couple of frames per piece). Remembered, so asking again for the
## same size is instant. Used to keep the card one size for every piece.
static var _tallest := {}

static func tallest_height(host: Node, defs: Array, width: float, p_zoom := 1.0) -> float:
	var key := "%d|%.2f|%d" % [roundi(width), p_zoom, defs.size()]
	if _tallest.has(key):
		return _tallest[key]
	var probe: PieceCard = load("res://scenes/common/piece_card.tscn").instantiate()
	probe.zoom = p_zoom
	probe.top_level = true
	probe.modulate.a = 0.0
	probe.position = Vector2(-20000, 0)
	host.add_child(probe)
	var tallest := 0.0
	var tree := Engine.get_main_loop() as SceneTree
	for def: PieceDef in defs:
		probe.show_piece(def)
		probe.size = Vector2(width, 0)
		for i in 2:
			await tree.process_frame
		# The screen closed while measuring (the card went with it): give up.
		if not is_instance_valid(probe):
			return tallest
		tallest = maxf(tallest, probe.get_combined_minimum_size().y)
	probe.queue_free()
	_tallest[key] = tallest
	return tallest

## A size at the current zoom.
## The mini board's size and the legend's text at zoom 1 (Mac: bigger; were
## 220 and 19 while the legend had eight long entries).
const BOARD_SIZE := 280
const LEGEND_FONT_SIZE := 24

func _z(value: float) -> int:
	return roundi(value * zoom)

## Sizes of the parts that come from the scene file.
func _apply_zoom() -> void:
	%Name.add_theme_font_size_override("font_size", _z(40))
	%GuideBoard.custom_minimum_size = Vector2(_z(BOARD_SIZE), _z(BOARD_SIZE))
	$Special/SpecialTitle.add_theme_font_size_override("font_size", _z(26))
	RuleText.style(%SpecialText, _z(22))
	RuleText.style(%MoveNote, _z(22), Color(0.78, 0.78, 0.78))
	$Ability/AbilityHeader/AbilityTitle.add_theme_font_size_override("font_size", _z(26))
	%AbilityName.add_theme_font_size_override("font_size", _z(22))
	RuleText.style(%AbilityText, _z(22))
	var tip_label: RichTextLabel = tooltip.get_child(0)
	tip_label.custom_minimum_size = Vector2(_z(420), 0)
	RuleText.style(tip_label, _z(22))

## E.g. "Free", "1 point", "3 points".
static func cost_text(p_def: PieceDef) -> String:
	if p_def.value == 0:
		return "Free"
	return "%s point%s" % [Army.format_points(p_def.value), "" if is_equal_approx(p_def.value, 1.0) else "s"]

static func type_names(p_def: PieceDef) -> PackedStringArray:
	var names: PackedStringArray = []
	if p_def.is_king_type():
		names.append("King")
	if p_def.is_royal_type():
		names.append("Royal")
	if p_def.is_pawn_type():
		names.append("Pawn")
	return names

static func keyword_names(p_def: PieceDef) -> PackedStringArray:
	var names: PackedStringArray = []
	if p_def.has_jump():
		names.append("Jump")
	if p_def.has_castle():
		names.append("Castle")
	# Pawn types promote too, so they show the keyword as well.
	if p_def.can_promote():
		names.append("Promote")
	if p_def.has_shield():
		names.append("Shield")
	if p_def.has_wall():
		names.append("Wall")
	return names

## Rules that the types, keywords and picture can't show (from the piece's data).
static func special_rules(p_def: PieceDef) -> PackedStringArray:
	var rules: PackedStringArray = []
	if p_def.special_rule != "":
		rules.append(p_def.special_rule)
	return rules

## Show the explanation bubble for `tag` (a type or keyword) just below `item`.
## Showing it again for the same item hides it (so a second tap closes it).
func show_tooltip(item: Control, tag: String) -> void:
	if tooltip_owner == item and tooltip.visible:
		hide_tooltip()
		return
	tooltip_owner = item
	RuleText.show(tooltip.get_child(0), EXPLANATIONS[tag])
	tooltip.reset_size()
	tooltip.visible = true
	# Below the type/keyword, kept inside the screen; above it if there's no room.
	var screen := get_viewport_rect().size
	var pos := item.global_position + Vector2(0, item.size.y + 6)
	pos.x = clampf(pos.x, 8, screen.x - tooltip.size.x - 8)
	if pos.y + tooltip.size.y > screen.y - 8:
		pos.y = item.global_position.y - tooltip.size.y - 6
	tooltip.global_position = pos

func hide_tooltip() -> void:
	tooltip_owner = null
	if tooltip:
		tooltip.visible = false

func _make_tooltip() -> void:
	tooltip = PanelContainer.new()
	tooltip.top_level = true  # Drawn over everything, not squeezed into the card.
	tooltip.z_index = 100
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.09, 0.96)
	style.border_color = Color(0.6, 0.6, 0.6)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(12)
	tooltip.add_theme_stylebox_override("panel", style)
	var label := RichTextLabel.new()
	label.custom_minimum_size = Vector2(420, 0)
	RuleText.style(label, 22)
	tooltip.add_child(label)
	add_child(tooltip)

## Make `item` show `tag`'s explanation on hover, and on tap (for phones).
func _explain_on_hover(item: Control, tag: String) -> void:
	item.mouse_filter = Control.MOUSE_FILTER_STOP
	item.mouse_entered.connect(func() -> void:
		if tooltip_owner != item:
			show_tooltip(item, tag))
	item.mouse_exited.connect(func() -> void:
		if tooltip_owner == item:
			hide_tooltip())
	item.gui_input.connect(func(event: InputEvent) -> void:
		var press := event as InputEventMouseButton
		if press and press.pressed and press.button_index == MOUSE_BUTTON_LEFT:
			show_tooltip(item, tag))

func _refresh() -> void:
	hide_tooltip()
	for child in %Pictures.get_children():
		child.queue_free()
	var textures := PieceArt.all_textures(def, team)
	var forms := forms_of(def)
	if not forms.is_empty():
		# Both forms' pictures, like the Paladin with and without its shield.
		textures = PieceArt.all_textures(forms[0], team) + PieceArt.all_textures(forms[1], team)
	for texture in textures:
		var picture := TextureRect.new()
		picture.texture = texture
		picture.custom_minimum_size = Vector2(_z(88), _z(88))
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		%Pictures.add_child(picture)
	%Name.text = def.display_name
	_update_form_button()
	_fill_details()
	%GuideBoard.show_piece(moves_def, team)
	_fill_legend()
	_fill_move_note()
	_fill_keywords()
	var special := special_rules(def)
	%Special.visible = not special.is_empty()
	RuleText.show(%SpecialText, "\n".join(special))
	%Ability.visible = def.ability_name != ""
	# The name in a box like the keywords', filled with the piece's gradient.
	%AbilityName.text = def.ability_name.to_upper()
	%AbilityName.add_theme_color_override("font_color", def.ability_label_color())
	%AbilityChip.add_theme_stylebox_override("panel", GradientStyleBox.new(def.ability_gradient(), 8, _z(14), _z(4)))
	RuleText.show(%AbilityText, def.ability_text)

## "3 points" followed by the types in italics, e.g. "Free · King, Royal".
func _fill_details() -> void:
	for child in %Details.get_children():
		child.queue_free()
	%Details.add_child(_detail_label(cost_text(def)))
	var types := type_names(def)
	if types.is_empty():
		return
	%Details.add_child(_detail_label("·"))
	for i in types.size():
		var label := _detail_label(types[i] + ("," if i < types.size() - 1 else ""))
		label.add_theme_font_override("font", _italic_font())
		_explain_on_hover(label, types[i])
		%Details.add_child(label)

func _detail_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _z(24))
	label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78))
	return label

## Open Sans Italic at the normal text's weight (see RuleText.italic_font).
func _italic_font() -> Font:
	return RuleText.italic_font()

## The note about how the shown moves work, in italics (only some pieces).
func _fill_move_note() -> void:
	# The whole note in italics (types inside it stay italic too).
	%MoveNote.text = "[i]%s[/i]" % RuleText.to_bbcode(moves_def.move_note)
	%MoveNote.visible = moves_def.move_note != ""

## The legend, the same on every card (Mac), whichever marks this piece uses;
## the plain dot and arrow aren't in it (PieceGuideBoard.NOT_IN_LEGEND).
func _fill_legend() -> void:
	for child in %Legend.get_children():
		child.queue_free()
	%Legend.add_theme_constant_override("separation", _z(8))
	for kind in PieceGuideBoard.LEGEND:
		if kind in PieceGuideBoard.NOT_IN_LEGEND:
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", _z(10))
		var icon := LegendIcon.new()
		icon.kind = kind
		icon.custom_minimum_size = Vector2(_z(34), _z(34))
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = PieceGuideBoard.LEGEND[kind]
		label.add_theme_font_size_override("font_size", _z(LEGEND_FONT_SIZE))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(icon)
		row.add_child(label)
		%Legend.add_child(row)

func _fill_keywords() -> void:
	for child in %Keywords.get_children():
		child.queue_free()
	var names := keyword_names(def)
	%Keywords.visible = not names.is_empty()
	for keyword in names:
		var colors: Array = KEYWORD_COLORS[keyword]
		var box := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = colors[0]
		style.set_corner_radius_all(8)
		style.content_margin_left = _z(14)
		style.content_margin_right = _z(14)
		style.content_margin_top = _z(4)
		style.content_margin_bottom = _z(4)
		box.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = keyword.to_upper()
		label.add_theme_font_size_override("font_size", _z(22))
		label.add_theme_color_override("font_color", colors[1])
		box.add_child(label)
		_explain_on_hover(box, keyword)
		%Keywords.add_child(box)

## One legend icon.
class LegendIcon extends Control:
	var kind := ""

	func _draw() -> void:
		PieceGuideBoard.draw_legend_icon(self, Rect2(Vector2.ZERO, size), kind)
