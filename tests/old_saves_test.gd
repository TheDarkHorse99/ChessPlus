extends TestSuite

## Saves from before the rename to Overchess (26 Oct 2026) are copied over once.

const ROOT := "user://test_old_saves"

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	for folder in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(folder))
	DirAccess.remove_absolute(dir)

func test_old_saves_come_over_once() -> void:
	var root := ProjectSettings.globalize_path(ROOT)
	_remove(root)
	var old := root.path_join("ChessPlus")
	var new := root.path_join("Overchess")
	_write(old.path_join("settings.cfg"), "[audio]\nvolume=0.5\n")
	_write(old.path_join("current_game.json"), "{}")
	_write(old.path_join("armies/army_1.tres"), "army one")
	_write(old.path_join("armies/army_2.tres"), "army two")
	_write(old.path_join("logs/godot.log"), "not a save")
	# The game makes an empty armies folder as it starts: that isn't a save.
	DirAccess.make_dir_recursive_absolute(new.path_join("armies"))
	check_eq(OldSaves.bring_over(old, new), 4, "Settings, the game in progress and two armies")
	check_eq(_read(new.path_join("armies/army_2.tres")), "army two", "Copied as they were")
	check(not DirAccess.dir_exists_absolute(new.path_join("logs")), "Godot's own logs stay behind")
	check(FileAccess.file_exists(old.path_join("settings.cfg")), "The old folder is left alone")
	_write(old.path_join("armies/army_3.tres"), "army three")
	check_eq(OldSaves.bring_over(old, new), 0, "Only once: the new folder has saves now")
	check(not FileAccess.file_exists(new.path_join("armies/army_3.tres")), "Nothing more copied")
	check_eq(OldSaves.bring_over(root.path_join("Nowhere"), root.path_join("Other")), 0, "No old folder, nothing to do")
	_remove(root)
