class_name UserSettings
extends RefCounted

## The player's own preferences (sound, volume, default armies, ...), saved on the device.
## Everything is static: there's only one set of settings.

const DEFAULT_PATH := "user://settings.cfg"

## Where the settings are saved. Tests point this somewhere else.
static var save_path := DEFAULT_PATH

static func sound_on() -> bool:
	return _settings().get_value("audio", "sound_on", true)

static func set_sound_on(on: bool) -> void:
	var file := _settings()
	file.set_value("audio", "sound_on", on)
	file.save(save_path)

## How loud the game is, from 0 (silent) to 1 (full), set with VolumeControl.
static func volume() -> float:
	return clampf(_settings().get_value("audio", "volume", 1.0), 0.0, 1.0)

static func set_volume(value: float) -> void:
	var file := _settings()
	file.set_value("audio", "volume", clampf(value, 0.0, 1.0))
	file.save(save_path)

## The sound groups with a volume of their own (Mac's Settings, Oct 2026):
## ordinary moves and captures, special effects (abilities, promotion,
## checkmate, ...) and warnings (check, the buzz of a move that isn't allowed).
const SOUND_GROUPS: Array[String] = ["moves", "effects", "warnings"]

## A sound group's volume, from 0 (silent) to 1 (full), on top of the main volume.
static func group_volume(group: String) -> float:
	return clampf(_settings().get_value("audio", "volume_" + group, 1.0), 0.0, 1.0)

static func set_group_volume(group: String, value: float) -> void:
	_store("audio", "volume_" + group, clampf(value, 0.0, 1.0))

## "Your move" notifications (TurnNotifier), on unless switched off in Settings.
## Whether the How to play page has been shown once at start-up (Mac, Oct 2026).
static func how_to_play_seen() -> bool:
	return _settings().get_value("help", "how_to_play_seen", false)

static func set_how_to_play_seen(seen: bool) -> void:
	_store("help", "how_to_play_seen", seen)

static func notifications_on() -> bool:
	return _settings().get_value("notify", "your_move", true)

static func set_notifications_on(on: bool) -> void:
	_store("notify", "your_move", on)

## How fast move and ability animations play (Mac's Settings): each choice
## and what it multiplies their length by ("off" = no animation, moves appear
## at once). In the order shown.
const ANIMATION_SPEEDS := {"off": 0.0, "fast": 0.6, "normal": 1.0, "slow": 1.5}

static func animation_speed() -> String:
	var speed: String = _settings().get_value("visual", "animation_speed", "normal")
	return speed if ANIMATION_SPEEDS.has(speed) else "normal"

static func set_animation_speed(speed: String) -> void:
	_store("visual", "animation_speed", speed)

## The board helpers that can be switched off (Mac's Settings), all on to
## start with: "coordinates", "move_dots" (where the chosen piece can go),
## "last_move" (the last move's squares tinted) and "ability_glow" (the glow
## round a piece whose ability is unused).
const BOARD_HELPERS: Array[String] = ["coordinates", "move_dots", "last_move", "ability_glow"]

static func board_helper(helper: String) -> bool:
	return _settings().get_value("visual", helper, true)

static func set_board_helper(helper: String, on: bool) -> void:
	_store("visual", helper, on)

## Tone down flashes and shaking (Mac's Settings): no white impact frames, no
## flickering lightning, no trembling king or flaring border in check.
static func reduce_effects() -> bool:
	return _settings().get_value("visual", "reduce_effects", false)

static func set_reduce_effects(on: bool) -> void:
	_store("visual", "reduce_effects", on)

## The key a keyboard shortcut is on (see KeyBinds), or `default`.
static func key_bind(action: String, default: int) -> int:
	return _settings().get_value("keys", action, default)

static func set_key_bind(action: String, code: int) -> void:
	_store("keys", action, code)

## The mouse button a board action is on (see MouseBinds), or `default`.
static func mouse_bind(action: String, default: int) -> int:
	return _settings().get_value("mouse", action, default)

static func set_mouse_bind(action: String, index: int) -> void:
	_store("mouse", action, index)

## Settings' "Reset to defaults": every setting back to how it started (sound,
## notifications, visual, keys, mouse buttons). The online game in progress and
## the default armies (set in My armies) are kept.
static func reset_to_defaults() -> void:
	var file := _settings()
	for section in ["audio", "notify", "visual", "keys", "mouse"]:
		if file.has_section(section):
			file.erase_section(section)
	file.save(save_path)

## Save one value.
static func _store(section: String, key: String, value: Variant) -> void:
	var file := _settings()
	file.set_value(section, key, value)
	file.save(save_path)

## The online game this copy of the game is playing ("" if none), so it can be
## picked up again from the main menu after the app closes.
static func online_game() -> String:
	return _settings().get_value("online", "game", "")

## Which side this device plays in that game (Piece.Team). The same device can
## hold both sides (two copies of the game on one phone playing each other).
static func online_team() -> int:
	return int(_settings().get_value("online", "game_team", Piece.Team.WHITE))

static func set_online_game(code: String, team := Piece.Team.WHITE) -> void:
	var file := _settings()
	file.set_value("online", "game", code)
	file.set_value("online", "game_team", team)
	if file.has_section_key("online", "game_player_id"):
		file.erase_section_key("online", "game_player_id")
	file.save(save_path)

## This device's sign-in on the online server ({} if none yet), kept so it
## stays the same player between visits. `slot` "" is the device's own; tests
## and the live server check use other slots for extra pretend devices.
static func online_sign_in(slot := "") -> Dictionary:
	var data: Variant = _settings().get_value("online_sign_in", slot if slot != "" else "device", {})
	return data if data is Dictionary else {}

static func set_online_sign_in(data: Dictionary, slot := "") -> void:
	_store("online_sign_in", slot if slot != "" else "device", data)

## The saved army (its file, Army.library_path) the player chose as their
## default for `team`, or "" for none (then Standard is used). See ArmyChoices.
static func default_army(team: Piece.Team) -> String:
	return _settings().get_value("armies", _default_key(team), "")

static func set_default_army(team: Piece.Team, path: String) -> void:
	var file := _settings()
	file.set_value("armies", _default_key(team), path)
	file.save(save_path)

static func _default_key(team: Piece.Team) -> String:
	return "default_white" if team == Piece.Team.WHITE else "default_black"

## The settings file, read fresh each time (it's tiny).
static func _settings() -> ConfigFile:
	var file := ConfigFile.new()
	file.load(save_path)  # A missing file just means "all defaults".
	return file
