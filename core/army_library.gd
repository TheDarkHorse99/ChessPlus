class_name ArmyLibrary
extends RefCounted

## The player's saved armies: one file per army in a folder on the device.
## "user://" is the game's own private folder (on Windows it's inside
## %APPDATA%\Godot\app_userdata\Overchess\).

const DEFAULT_DIR := "user://armies/"
const MAX_ARMIES := 10

var dir: String

## Tests pass a different folder so they never touch the player's real armies.
func _init(p_dir := DEFAULT_DIR) -> void:
	dir = p_dir
	DirAccess.make_dir_recursive_absolute(dir)

## Every saved army, sorted by name.
func armies() -> Array[Army]:
	var result: Array[Army] = []
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".tres"):
			continue
		# CACHE_MODE_IGNORE: always read the file fresh, never an old copy in memory.
		var army := ResourceLoader.load(dir + file, "", ResourceLoader.CACHE_MODE_IGNORE) as Army
		if army:
			army.library_path = dir + file
			result.append(army)
	result.sort_custom(func(a: Army, b: Army) -> bool: return a.army_name.naturalnocasecmp_to(b.army_name) < 0)
	return result

func count() -> int:
	return armies().size()

func is_full() -> bool:
	return count() >= MAX_ARMIES

## Save an army. A new army gets its own file (if there's room); an army that
## came from this library overwrites its old file.
func save(army: Army) -> Error:
	var path := army.library_path
	if path.is_empty() or not path.begins_with(dir):
		if is_full():
			return ERR_CANT_CREATE
		path = _new_path()
	var error := ResourceSaver.save(army, path)
	if error == OK:
		army.library_path = path
	return error

func delete(army: Army) -> void:
	if army.library_path.begins_with(dir):
		DirAccess.remove_absolute(army.library_path)
		army.library_path = ""

## A file name that isn't taken yet: army_1.tres, army_2.tres, ...
func _new_path() -> String:
	var n := 1
	while FileAccess.file_exists(dir + "army_%d.tres" % n):
		n += 1
	return dir + "army_%d.tres" % n
