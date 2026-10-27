class_name OldSaves
extends RefCounted

## The game was called ChessPlus until 26 Oct 2026 (Mac renamed it Overchess).
## On PC, Godot keeps a game's saves in a folder named after the project
## (%APPDATA%\Godot\app_userdata\<name>\), so the renamed game would start with
## no saved armies, settings or game in progress. The first time it starts,
## this copies them over from the old folder. (The web version keeps its saves
## in the same place whatever the name, so it needs nothing.)

const OLD_NAME := "ChessPlus"
## The game's own saves. Godot's own files (logs, shader cache) stay behind.
const SAVES: Array[String] = ["settings.cfg", "current_game.json", "armies"]

## Copy the old saves when the new folder has none yet. Returns how many files
## were copied (0 if there was nothing to copy, or saves were already there).
static func bring_over(old_dir: String, new_dir: String) -> int:
	if not DirAccess.dir_exists_absolute(old_dir):
		return 0
	for name in SAVES:
		if _has_save(new_dir.path_join(name)):
			return 0
	var copied := 0
	for name in SAVES:
		copied += _copy(old_dir.path_join(name), new_dir.path_join(name))
	return copied

## On PC at start-up: from the ChessPlus folder next to this game's own.
static func bring_over_on_start() -> int:
	if OS.has_feature("web"):
		return 0
	var new_dir := OS.get_user_data_dir()
	return bring_over(new_dir.get_base_dir().path_join(OLD_NAME), new_dir)

## A file, or a folder with something in it (the game makes an empty armies
## folder as it starts, before this runs).
static func _has_save(path: String) -> bool:
	if FileAccess.file_exists(path):
		return true
	if not DirAccess.dir_exists_absolute(path):
		return false
	if not DirAccess.get_files_at(path).is_empty():
		return true
	for folder in DirAccess.get_directories_at(path):
		if _has_save(path.path_join(folder)):
			return true
	return false

static func _copy(from: String, to: String) -> int:
	if FileAccess.file_exists(from):
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		return 1 if DirAccess.copy_absolute(from, to) == OK else 0
	if not DirAccess.dir_exists_absolute(from):
		return 0
	DirAccess.make_dir_recursive_absolute(to)
	var copied := 0
	for file in DirAccess.get_files_at(from):
		copied += _copy(from.path_join(file), to.path_join(file))
	for folder in DirAccess.get_directories_at(from):
		copied += _copy(from.path_join(folder), to.path_join(folder))
	return copied
