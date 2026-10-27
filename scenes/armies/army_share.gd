class_name ArmyShare
extends RefCounted

## Sharing armies (Mac's design): "Share" in the army builder uploads the army
## to the game's server and gives a short code, like an online game's; a friend
## types the code into "Import army" in My armies and gets a copy in their own
## saved armies. (The server table is set up by server/supabase_update_2.sql.)
##
## Armies can also be shared as a line of text, with no server: "Copy as text"
## in Share, "Import text" in Import army. The text is one line (a phone's text
## box can't hold more), the rows as seen in the army builder, top row first:
##   Overchess army "Wall": P P P P P P P P / R N B Q K B N R
## Each square is a piece's letters (PieceDef.symbol) or - for an empty one,
## files a to h from left to right.

## What the text starts with.
const TEXT_START := "Overchess army"
## What it started with before the game was renamed (Mac, 26 Oct 2026):
## still read, so texts sent before then import as before.
const OLD_TEXT_STARTS: Array[String] = ["Chess Plus army"]
const EMPTY_SQUARE := "-"
## Imported names are cut to the army builder's limit.
const NAME_MAX_LENGTH := 20

## Upload `army`. Returns {"ok", "code", "error"}. The server makes the code.
static func share(backend: OnlineBackend, army: Army) -> Dictionary:
	var result: Dictionary = await backend.call_function("share_army", {"p_army": SavedGame.army_to_dict(army)})
	if result.ok and not result.rows.is_empty():
		return {"ok": true, "code": str(result.rows[0].get("code", "")), "error": ""}
	return {"ok": false, "code": "", "error": result.error if result.error != "" else "couldn't share the army"}

## Download the army shared under `code` and save a copy in `library`.
## Returns "" if it worked, otherwise what went wrong (in plain words).
static func import_army(backend: OnlineBackend, library: ArmyLibrary, code: String) -> String:
	var wanted := code.strip_edges().to_upper()
	if wanted.length() != OnlineSession.CODE_LENGTH:
		return "Army codes are %d letters and numbers long." % OnlineSession.CODE_LENGTH
	if library.is_full():
		return "You already have %d saved armies; delete one first." % ArmyLibrary.MAX_ARMIES
	var found: Dictionary = await backend.call_function("get_shared_army", {"p_code": wanted})
	if not found.ok:
		return "Couldn't reach the server: " + found.error
	if found.rows.is_empty():
		return "There's no army with the code %s." % wanted
	var data: Variant = found.rows[0].get("army")
	var army := SavedGame.army_from_dict(data) if data is Dictionary else null
	if army == null:
		return "That army uses a piece this version of the game doesn't have yet."
	# Shared armies are always built ones (turned round when played as Black).
	army.mirror_for_black = bool((data as Dictionary).get("mirror", true))
	return _add_to_library(library, army)

## `army` as one line of text (see the top of this file), to send to a friend.
static func to_text(army: Army, rules := StandardSetup.create_rules(), width := 8) -> String:
	var rows := PackedStringArray()
	for row in range(rules.army_start_rows - 1, -1, -1):
		var squares := PackedStringArray()
		for file in width:
			var def := army.def_at(Vector2i(file, row))
			squares.append(def.symbol if def else EMPTY_SQUARE)
		rows.append(" ".join(squares))
	return '%s "%s": %s' % [TEXT_START, army.army_name.strip_edges(), " / ".join(rows)]

## The army written in `text` by to_text(). Returns {"army": Army, "error": ""},
## or {"army": null, "error": what's wrong, in plain words}. Doesn't check the
## army rules (import_text does).
static func from_text(text: String, width := 8) -> Dictionary:
	var line := text.strip_edges()
	var name_start := line.find('"')
	var name_end := line.rfind('"')
	var colon := line.find(":", name_end)
	if not _starts_right(line) or name_start < 0 or name_end <= name_start or colon < 0:
		return _text_error("That isn't army text. It should look like: %s \"Name\": P P P ..." % TEXT_START)
	var by_symbol := {}
	for def in PieceCatalog.all_defs():
		by_symbol[def.symbol] = def
	var army := Army.new()
	army.army_name = line.substr(name_start + 1, name_end - name_start - 1).strip_edges().left(NAME_MAX_LENGTH).strip_edges()
	if army.army_name.is_empty():
		army.army_name = "Imported army"
	var rows := line.substr(colon + 1).split("/")
	for i in rows.size():
		# The top row (furthest from you) comes first.
		var row := rows.size() - 1 - i
		var squares := rows[i].split(" ", false)
		if squares.size() != width:
			return _text_error("Each row needs %d squares (- for an empty one), but row %d has %d." % [width, row + 1, squares.size()])
		for file in width:
			var symbol := squares[file].to_upper()
			if symbol == EMPTY_SQUARE:
				continue
			if not by_symbol.has(symbol):
				return _text_error("There's no piece with the letters %s (it may be from a newer version of the game)." % symbol)
			army.place(by_symbol[symbol], Vector2i(file, row))
	return {"army": army, "error": ""}

## Read army text (from to_text) and save a copy in `library`.
## Returns "" if it worked, otherwise what went wrong (in plain words).
static func import_text(library: ArmyLibrary, text: String) -> String:
	if text.strip_edges().is_empty():
		return "Paste the army text your friend sent first."
	var found := from_text(text)
	if found.army == null:
		return found.error
	return _add_to_library(library, found.army)

## Save an imported army under a name no other saved army has. Returns "" if
## it worked, otherwise what went wrong.
static func _add_to_library(library: ArmyLibrary, army: Army) -> String:
	if library.is_full():
		return "You already have %d saved armies; delete one first." % ArmyLibrary.MAX_ARMIES
	if not army.is_valid(StandardSetup.create_rules(), 8):
		return "That army doesn't follow the army rules any more."
	army.army_name = unique_name(library, army.army_name)
	if library.save(army) != OK:
		return "Couldn't save the army."
	return ""

static func _text_error(error: String) -> Dictionary:
	return {"army": null, "error": error}

## `wanted`, or "wanted (2)", "wanted (3)"... if a saved army already has that name.
static func unique_name(library: ArmyLibrary, wanted: String) -> String:
	var taken := library.armies().map(func(a: Army) -> String: return a.army_name)
	if not wanted in taken:
		return wanted
	var n := 2
	while "%s (%d)" % [wanted, n] in taken:
		n += 1
	return "%s (%d)" % [wanted, n]

## Whether `line` starts like army text (today's start or an old one).
static func _starts_right(line: String) -> bool:
	for start: String in [TEXT_START] + OLD_TEXT_STARTS:
		if line.to_lower().begins_with(start.to_lower()):
			return true
	return false
