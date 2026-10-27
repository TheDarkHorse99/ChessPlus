extends Node

## Runs every test in every *_test.gd file in this folder, then prints a summary.
## In the editor: open run_tests.tscn and press F6.
## Command line: see "Running tests" in CLAUDE.md. Words after "--" only run
## files whose names contain them, e.g. "-- movegen".
## Functions named slow_test_... only run when "--slow" is given, e.g. "-- --slow".

const TEST_DIR := "res://tests/"

## Counts every error Godot logs, including script errors. GDScript has no
## exceptions: a script error just stops the test function early. Counting errors
## lets the runner fail that test instead of wrongly reporting a pass.
class ErrorCounter extends Logger:
	var count := 0
	var _mutex := Mutex.new()  # Errors can be logged from other threads.

	func _log_error(_function: String, _file: String, _line: int, _code: String,
			_rationale: String, _editor_notify: bool, _error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		_mutex.lock()
		count += 1
		_mutex.unlock()

var _errors := ErrorCounter.new()

func _ready() -> void:
	OS.add_logger(_errors)
	# Games played in tests are saved to a test file, never the player's real one.
	SavedGame.save_path = "user://test_current_game.json"
	SavedGame.delete_saved()
	UserSettings.save_path = "user://test_settings.cfg"
	# Tests that open the main scene expect the menu, not the first-launch How to play page.
	UserSettings.set_how_to_play_seen(true)
	# Finished games in tests mustn't start Plusfish (eval_bar_test turns it on).
	PlusfishLink.enabled = false
	# Silent: sounds still left playing when the tests quit count as leaks.
	UserSettings.set_sound_on(false)
	# "Your move" notifications are only recorded, never shown.
	TurnNotifier.deliver = false
	# Wait until the scene tree has finished starting up, so tests can add
	# scenes to it.
	_run_all.call_deferred()

func _run_all() -> void:
	var filters: PackedStringArray = []
	var include_slow := false
	for arg in OS.get_cmdline_user_args():
		if arg == "--slow":
			include_slow = true
		else:
			filters.append(arg)
	var passed := 0
	var failed := 0
	for file in DirAccess.get_files_at(TEST_DIR):
		if not file.ends_with("_test.gd") or not _matches(file, filters):
			continue
		var script: GDScript = load(TEST_DIR + file)
		# A file with a mistake in it doesn't load (or has no tests): count that as
		# a failure rather than quietly skipping it.
		if script == null or not script.can_instantiate() or _test_names(script, include_slow).is_empty():
			failed += 1
			print("  FAIL  %s could not be loaded (see the errors above)" % file)
			continue
		for test_name in _test_names(script, include_slow):
			# A fresh copy per test, so one test's leftovers can't affect another.
			var suite: TestSuite = script.new()
			var start := Time.get_ticks_msec()
			var errors_before := _errors.count
			# Tests may wait (await); others just return straight away.
			await suite.call(test_name)
			var ms := Time.get_ticks_msec() - start
			var new_errors := _errors.count - errors_before
			if new_errors > 0:
				suite.failures.append("%d error(s) logged during the test (see above)" % new_errors)
			var label := "%s.%s (%d ms)" % [file.get_basename(), test_name, ms]
			if suite.failures.is_empty():
				passed += 1
				print("  PASS  ", label)
			else:
				failed += 1
				print("  FAIL  ", label)
				for failure in suite.failures:
					print("        ", failure)
	print("\n%d passed, %d failed" % [passed, failed])
	# Empty the shared caches, so what's left at exit is a real leak worth a warning.
	PieceArt.clear_cache()
	PlusfishLink.clear_cache()
	PracticeBot.clear_cache()
	GameSounds.clear_cache()
	BoardView.clear_cache()
	UiStyle.clear_cache()
	MemoryBackend.clear()
	SupabaseBackend.clear_cache()
	RuleSet.clear_cache()
	get_tree().quit(1 if failed > 0 else 0)

func _matches(file: String, filters: PackedStringArray) -> bool:
	if filters.is_empty():
		return true
	for filter in filters:
		if file.contains(filter):
			return true
	return false

## The script's test functions, in the order written.
func _test_names(script: GDScript, include_slow: bool) -> PackedStringArray:
	var names: PackedStringArray = []
	for method in script.get_script_method_list():
		var method_name: String = method.name
		var is_test := method_name.begins_with("test_") or (include_slow and method_name.begins_with("slow_test_"))
		if is_test and not names.has(method_name):
			names.append(method_name)
	return names
