class_name RuleText
extends RefCounted

## Rule texts with light markup (Mac, Oct 2026): on the piece cards and in the
## army builder every piece type (King, Royal, Pawn) is in italics and every
## keyword (Jump, Castle, Promote, Shield, Wall) sits in its coloured box, inline.
## In the source text (piece files, PieceCard.EXPLANATIONS, Army.problems):
##   *King*     -> King in italics
##   {Shield}   -> SHIELD in the Shield keyword's box
## to_bbcode() turns that into BBCode for a RichTextLabel; plain() strips the
## marks for places that show plain text (tooltips of OptionButton items, the
## import pop-ups, tests).

## Each keyword's box colour and text colour (the piece card's keyword boxes
## use these too).
const KEYWORD_COLORS := {
	"Jump": [Color("#F2A51F"), Color("#2A1A00")],
	"Castle": [Color("#8C8C8C"), Color.WHITE],
	"Promote": [Color("#7B4BC9"), Color.WHITE],
	"Shield": [Color("#8FD0F5"), Color("#0B2A3D")],
	"Wall": [Color("#9C7B5A"), Color("#2B1A0E")],
}

const ITALIC_FONT := preload("res://art/fonts/OpenSans-Italic.ttf")

static var _italic_regex: RegEx
static var _keyword_regex: RegEx

static func _regexes() -> void:
	if _italic_regex == null:
		_italic_regex = RegEx.create_from_string(r"\*([^*]+)\*")
		_keyword_regex = RegEx.create_from_string(r"\{([A-Za-z]+)\}")

## The text as BBCode: italics for *types*, a coloured box for {keywords}.
static func to_bbcode(text: String) -> String:
	_regexes()
	var out := _italic_regex.sub(text, "[i]$1[/i]", true)
	for found in _keyword_regex.search_all(out):
		var keyword: String = found.get_string(1)
		var key := keyword.capitalize()
		var colors: Array = KEYWORD_COLORS.get(key, [Color("#8C8C8C"), Color.WHITE])
		var box := "[bgcolor=#%s][color=#%s] %s [/color][/bgcolor]" % [(colors[0] as Color).to_html(false), (colors[1] as Color).to_html(false), keyword.to_upper()]
		out = out.replace(found.get_string(0), box)
	return out

## The text with the marks taken off: *King* -> King, {Shield} -> SHIELD.
static func plain(text: String) -> String:
	_regexes()
	var out := _italic_regex.sub(text, "$1", true)
	for found in _keyword_regex.search_all(out):
		out = out.replace(found.get_string(0), found.get_string(1).to_upper())
	return out

## Every line of `lines`, plain.
static func plain_lines(lines: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	for line in lines:
		out.append(plain(line))
	return out

## Open Sans Italic at the normal text's semi-bold weight (bundled, so it looks
## the same everywhere; slanting the normal font made the letters jiggle).
static func italic_font() -> Font:
	var italic := FontVariation.new()
	italic.base_font = ITALIC_FONT
	italic.variation_opentype = {"wght": 600}
	return italic

## Set up `label` (a RichTextLabel) to show rule text at `font_size`: BBCode
## on, grows with its text, no scrolling, the italic font for *types*, mouse
## events passed through (so hovering a card still works as before).
static func style(label: RichTextLabel, font_size: int, color := Color.WHITE) -> void:
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("italics_font", italic_font())
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("italics_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_color_override("default_color", color)

## Show marked-up `text` in a styled RichTextLabel.
static func show(label: RichTextLabel, text: String) -> void:
	label.text = to_bbcode(text)
