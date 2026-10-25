class_name PlusfishLink
extends Node

## Talks to Plusfish, the analysis engine in res://engine/plusfish/, to get an
## evaluation of every position in a finished game (for the eval bar), or of
## the newest one (the eval bar during a game, and the Plusfish bot's moves).
##
## Plusfish never holds up the game: it works out one position at a time in the
## background, and the screen only checks each frame whether an answer has
## come. On PC the Plusfish program (built with cargo, see
## res://engine/plusfish/README.md) is started once and kept running, and
## everything to do with it (starting it, sending requests, reading answers)
## happens on a background thread. In the web version Plusfish runs compiled to
## WebAssembly in a Web Worker (res://web/plusfish.js).
##
## Answers are kept for every position asked about (`cache`, by the moves that
## led there), so taking moves back, redoing them or looking back through the
## game never asks Plusfish about the same position twice.
##
## Either way the game sends Plusfish everything it needs: the piece types (as
## the game has them loaded), the exact starting position and the moves played,
## so Plusfish never has to repeat how armies are set up.

## One position has been evaluated. `ply` = how many moves had been played.
## `result`: "cp" (White's point of view, in hundredths of a point), "mate"
## (null, or moves to mate: + White, - Black), "best" (Move.to_text()),
## "best_san", "outcome", "depth"; for a position asked about with
## prioritise(ply, true) also "lines": the top moves, best first, each
## {"move" (Move.to_text()), "san", "cp", "mate"}.
signal evaluated(ply: int, result: Dictionary)

## Search size per position. The web version is slower, so it searches less.
@export var desktop_nodes := 150000
@export var web_nodes := 20000
## Seconds between positions in the web version, so the game stays responsive.
@export var web_gap := 0.1
## How many top moves to find for a position whose "lines" are wanted (the
## game screen's Top moves list). The search shares its nodes between them, so
## it gets TOP_MOVES_NODES times as many (it's only the position on screen).
@export var top_moves := 3
const TOP_MOVES_NODES := 2

## Off turns Plusfish off everywhere. The test runner turns it off, so tests
## that finish games don't start the program; the eval bar tests turn it on.
static var enabled := true
## Tests of the screen can claim Plusfish is there and hand in results themselves.
static var pretend_available := false

## Results for the current game line: ply -> result dictionary.
var results := {}
## Every answer so far, by position (a key made from the start and the moves
## that led there) -> result, with "asked" = the search size it was asked for.
## Two links can share one (the game screen gives the Plusfish bot the eval
## bar's): an answer from a bigger search serves a smaller one too.
var cache := {}

## The current line: the moves played (Move.to_text()), the start's key, the
## request's text up to the moves, the moves as JSON, and each position's key
## (ply -> key).
var _moves_so_far: Array = []
var _start_key := ""
var _request_start := ""
var _moves_json := "[]"
var _line_keys: Array[String] = []
var _queue: Array[int] = []
var _web_wait := 0.0
## Positions on the current line (ply -> true) whose answer must list the top
## moves, not just the best one.
var _need_lines := {}

## The position being worked out (_task = -1: none): its task number, ply, key
## and search size, and whether it's still wanted (false once the job stopped).
var _task := -1
var _task_ply := -1
var _task_key := ""
var _task_nodes := 0
var _task_wanted := false
var _task_lines := false

## Where the Plusfish program is on this computer, or "" if it isn't there.
## Running from the project: a fresh cargo build if there is one, otherwise the
## copy committed in res://engine/plusfish/bin/ (made by build.sh, so it works
## without Rust); an exported PC game: next to the game's own program.
static func program_path() -> String:
	var exe := "plusfish.exe" if OS.get_name() == "Windows" else "plusfish"
	var candidates := [
		ProjectSettings.globalize_path("res://engine/plusfish/target/release/" + exe),
		ProjectSettings.globalize_path("res://engine/plusfish/bin/" + exe),
		OS.get_executable_path().get_base_dir().path_join(exe),
	]
	for path: String in candidates:
		if FileAccess.file_exists(path):
			return path
	return ""

## The last special ability Plusfish knows (it knows every piece rule up to
## the Ghost, Bard and Werewolf, Oct 2026).
const KNOWN_ABILITIES := PieceDef.Ability.FULL_MOON

## True if Plusfish knows every rule of the pieces in `state`. A piece with a
## newer special ability gets no eval bar until Plusfish is updated for it.
## (Plusfish knows Mac's Oct 2026 changes too: a Parapet stops only the
## opponent's pieces, a Squire protects Knights anywhere in its move pattern
## even through pieces, and the Berserker's L-moves go 2 then 1.)
## Plusfish doesn't know yet that the attacker chooses which Jester takes a hit
## when more than one could (Mac, Oct 2026), so it's off when a side starts with
## two Jesters. (A second one made by promotion later is rare: Plusfish can't
## read that game's choice moves, so the eval bar stops there and the Plusfish
## bot hands over to Hard.)
## Tests of the screen can pretend Plusfish knows the ability rule below.
static var pretend_knows_abilities := false

## The last special ability Plusfish may judge today. Plusfish doesn't know
## Mac's Oct 2026 rule that an ability needs a move first (a capture or shield
## break counts), so that's none: it's off for any game with a special ability
## in it, on the board or already lost, until Plusfish is updated (then this
## goes back to KNOWN_ABILITIES). The online referee follows it through the
## rule set (RuleSet.data), so it refuses to judge the same games.
static func known_abilities() -> PieceDef.Ability:
	return KNOWN_ABILITIES if pretend_knows_abilities else PieceDef.Ability.NONE

static func supports(state: GameState) -> bool:
	for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
		var jesters := 0
		for piece: Piece in state.board.pieces_of(team).values() + state.lost[team]:
			if piece.def.ability > known_abilities():
				return false
			if piece.def.decoy:
				jesters += 1
		if jesters > 1:
			return false
	return true

## True if Plusfish can run here.
static func available() -> bool:
	if not enabled:
		return false
	if pretend_available:
		return true
	if OS.has_feature("web"):
		var pf: Variant = JavaScriptBridge.get_interface("plusfish")
		return pf != null and bool(pf.ready)
	return program_path() != ""

## Evaluate every position of a game: `start` is its starting position and
## `moves` the moves played since (Move.to_text()). Replaces any earlier job.
## The last position goes first, then the rest from the end backwards.
func analyse(start: GameState, moves: Array) -> void:
	_set_line(start, moves)
	_queue.clear()
	for ply in range(moves.size(), -1, -1):
		if not results.has(ply):
			_queue.append(ply)

## During a game (the eval bar while playing): evaluate only the newest
## position, keeping what's known about earlier ones.
func analyse_live(start: GameState, moves: Array) -> void:
	_set_line(start, moves)
	_queue.clear()
	if not results.has(moves.size()):
		_queue.append(moves.size())

## Switch to this game line: its results come from what's already known about
## its positions, and work on a position that isn't on it any more is dropped.
func _set_line(start: GameState, moves: Array) -> void:
	# Keep what's known about the old line (results handed in too).
	for ply: int in results:
		if ply < _line_keys.size():
			cache[_line_keys[ply]] = results[ply]
	var position := position_for(start)
	var key := JSON.stringify(position)
	if key != _start_key:
		_start_key = key
		position["pieces"] = pieces_for(start)
		var text := JSON.stringify(position)
		_request_start = text.substr(0, text.length() - 1)
	_moves_so_far = moves.duplicate()
	_moves_json = JSON.stringify(moves)
	_line_keys = [_start_key.md5_text()]
	for move: String in moves:
		_line_keys.append(_line_keys.back() + " " + move)
	results.clear()
	_need_lines.clear()
	for ply in _line_keys.size():
		var known: Variant = cache.get(_line_keys[ply])
		if known != null and int(known.get("asked", _nodes())) >= _nodes():
			results[ply] = known
	if _task >= 0 and not _on_line(_task_ply, _task_key):
		_task_wanted = false
		_cancel_task()

## True if the position with this key is the one `ply` moves into the current line.
func _on_line(ply: int, key: String) -> bool:
	return ply >= 0 and ply < _line_keys.size() and _line_keys[ply] == key

func _nodes() -> int:
	return web_nodes if OS.has_feature("web") else desktop_nodes

## Look at this position next (the one on the screen). With `lines`, its
## answer must list the top moves too (an answer without them, e.g. one the
## Plusfish bot found, is shown meanwhile and then searched again).
func prioritise(ply: int, lines := false) -> void:
	if lines and top_moves > 1:
		_need_lines[ply] = true
	if _answered(ply) or _line_keys.is_empty() or ply > _moves_so_far.size():
		return
	if _task >= 0 and _task_ply == ply and _on_line(_task_ply, _task_key):
		_task_wanted = true
		if _task_lines or not _need_lines.has(ply):
			return
	if not _queue.is_empty() and _queue.front() == ply:
		return
	_queue.erase(ply)
	_queue.push_front(ply)

## Forget the current job (what's already known is kept).
func stop() -> void:
	_queue.clear()
	if _task >= 0:
		_task_wanted = false
		_cancel_task()

## True if the position has an answer that's enough: with the top moves if
## they're wanted.
func _answered(ply: int) -> bool:
	if not results.has(ply):
		return false
	return not _need_lines.has(ply) or results[ply].has("lines")

## True until every position asked for has a result (or the job failed).
func is_running() -> bool:
	return not _queue.is_empty() or (_task >= 0 and _task_wanted)

func _exit_tree() -> void:
	stop()
	if _worker:
		_worker.shut_down()
		_worker = null

## The request for one position: the start, the moves, the search size and
## how many top moves to find.
func _request_text(ply: int, nodes: int, multipv := 1) -> String:
	return '%s,"moves":%s,"plies":[%d],"nodes":%d,"multipv":%d}' % [_request_start, _moves_json, ply, nodes, multipv]

## Each frame: take the answer if it has come, then start on the next position.
func _process(delta: float) -> void:
	_web_wait -= delta
	if _task >= 0:
		var out: Variant = _take(_task)
		if out == null:
			return  # Still working.
		_task = -1
		_on_answer(str(out), _task_ply, _task_key, _task_nodes)
	while not _queue.is_empty() and _answered(_queue.front()):
		_queue.pop_front()
	if _queue.is_empty() or not available():
		return
	if OS.has_feature("web"):
		if _web_wait > 0.0:
			return
		_web_wait = web_gap
	_task_ply = _queue.pop_front()
	_task_key = _line_keys[_task_ply]
	_task_lines = _need_lines.has(_task_ply)
	_task_nodes = _nodes() * (TOP_MOVES_NODES if _task_lines else 1)
	_task_wanted = true
	_task = _submit(_request_text(_task_ply, _task_nodes, top_moves if _task_lines else 1))
	if _task < 0:
		_queue.clear()

## Plusfish's reply lines for one position (`key` = the position asked about).
func _on_answer(out: String, ply: int, key: String, nodes: int) -> void:
	if out.is_empty():
		_queue.clear()  # Plusfish isn't working (it stopped, or wouldn't start).
		return
	for line in out.split("\n", false):
		var reply: Variant = JSON.parse_string(line)
		if not reply is Dictionary:
			continue
		if reply.has("error"):
			push_warning("Plusfish: " + str(reply["error"]))
			_queue.clear()
			return
		if not reply.has("ply") or int(reply["ply"]) != ply:
			continue
		reply["asked"] = nodes
		# A kept answer listing the top moves isn't replaced by one without them
		# (the Plusfish bot's searches, which share the store).
		var known: Variant = cache.get(key)
		if known == null or not known.has("lines") or reply.has("lines"):
			cache[key] = reply
		if _on_line(ply, key):
			results[ply] = reply
			if _answered(ply):
				_queue.erase(ply)
			evaluated.emit(ply, reply)

## The request Plusfish expects (see res://engine/plusfish/src/api.rs).
static func request_for(start: GameState, moves: Array) -> Dictionary:
	var request := position_for(start)
	request["pieces"] = pieces_for(start)
	request["moves"] = moves
	return request

## The starting position part of the request (everything but the piece types
## and the moves). Quick to make: it's also what tells two games' starts apart.
static func position_for(start: GameState) -> Dictionary:
	var board := []
	for rank in range(start.board.height):
		for file in range(start.board.width):
			var piece := start.board.get_piece(Vector2i(file, rank))
			if piece == null:
				continue
			board.append([piece.def.id, piece.team, file, rank, piece.has_moved, piece.shield_broken,
					piece.ability_used, piece.gained_shield])
	var promo := []
	for def in start.rules.promotion_options:
		promo.append(def.id)
	# Lost pieces in the order they were lost (a lost Ghost's Haunt may be used).
	var lost := []
	for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
		for piece: Piece in start.lost[team]:
			lost.append([piece.def.id, team, piece.ability_used])
	var ep := []
	for square in start.en_passant_squares:
		ep.append([square.x, square.y])
	var victim: Variant = null
	if start.en_passant_victim != Board.NO_SQUARE:
		victim = [start.en_passant_victim.x, start.en_passant_victim.y]
	return {
		"width": start.board.width, "height": start.board.height, "board": board,
		"side": start.side_to_move, "halfmove": start.halfmove_clock, "fullmove": start.fullmove_number,
		"ep": ep, "ep_victim": victim, "lost": lost, "promo": promo,
		"castling_corner": start.rules.castling_partner_in_corner,
	}

## Every piece type the game might need: the whole catalog, anything on the
## board, promoted to or lost that isn't in it, and the forms pieces change into
## (the Werewolf's wolf). Each type's dictionary is made once and kept.
static func pieces_for(start: GameState) -> Array:
	if _catalog.is_empty():
		_catalog = PieceCatalog.all_defs()
	var defs := {}
	for def in _catalog:
		defs[def.id] = def
	for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
		for piece: Piece in start.board.pieces_of(team).values():
			defs[piece.def.id] = piece.def
		for piece: Piece in start.lost[team]:
			defs[piece.def.id] = piece.def
	for def in start.rules.promotion_options:
		defs[def.id] = def
	for def: PieceDef in defs.values():
		if def.transforms_into:
			defs[def.transforms_into.id] = def.transforms_into
	var pieces := []
	for id: String in defs:
		var def: PieceDef = defs[id]
		if not _def_dicts.has(def):
			_def_dicts[def] = _def_to_dict(def)
		pieces.append(_def_dicts[def])
	return pieces

## Kept between requests: every piece type in the catalog, and each type's
## dictionary for the request (making them took ~20 ms, a stutter on every move).
static var _catalog: Array[PieceDef] = []
static var _def_dicts := {}

## Empties the kept piece types (the test runner, before quitting).
static func clear_cache() -> void:
	_catalog = []
	_def_dicts = {}

static func _def_to_dict(def: PieceDef) -> Dictionary:
	var rules := []
	for rule in def.move_rules:
		rules.append({
			"directions": rule.directions.map(func(v: Vector2i) -> Array: return [v.x, v.y]),
			"max_steps": rule.max_steps, "first_move_max_steps": rule.first_move_max_steps,
			"mode": rule.mode, "captures_by_hopping": rule.captures_by_hopping,
			"leap_steps": rule.leap_steps, "leap_over": rule.leap_over,
			"path": rule.path.map(func(v: Vector2i) -> Array: return [v.x, v.y]),
			"mirror_files": rule.mirror_files, "mirror_ranks": rule.mirror_ranks,
		})
	return {
		"id": def.id, "name": def.display_name, "symbol": def.symbol, "value": def.value,
		"types": def.types, "keywords": def.keywords, "ability": def.ability,
		"dies_on_capture": def.dies_on_capture, "blocks_jumps": def.blocks_jumps(),
		"shield_on_capture": def.shield_on_capture, "protects": def.protects, "decoy": def.decoy,
		"transforms_into": def.transforms_into.id if def.transforms_into else null, "rules": rules,
	}

# --- Where Plusfish runs -----------------------------------------------------------------

## Start working out a request (JSON text); returns its task number (-1 if
## Plusfish can't run). _take(task) gives the reply lines once they're ready.
func _submit(input: String) -> int:
	if OS.has_feature("web"):
		var pf: JavaScriptObject = JavaScriptBridge.get_interface("plusfish")
		return int(pf.submit(input))
	if _worker == null:
		var path := program_path()
		if path == "":
			return -1
		_worker = Worker.new(path)
	return _worker.submit(input)

## The reply lines for a task (all of them at once), or null while it's working.
func _take(task: int) -> Variant:
	if OS.has_feature("web"):
		var pf: JavaScriptObject = JavaScriptBridge.get_interface("plusfish")
		return pf.take(task)
	return _worker.take(task) if _worker else ""

## Drop the position being worked out. On PC the program is stopped mid-search
## (it's started again for the next position); the web version can't stop its
## Web Worker, so there the answer is still taken (and kept) when it comes.
func _cancel_task() -> void:
	if OS.has_feature("web"):
		return
	if _worker:
		_worker.cancel(_task)
	_task = -1

## PC: the Plusfish program and the background thread that talks to it.
var _worker: Worker

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _worker:
		_worker.shut_down()
		_worker = null

## Starting and stopping programs from two threads at once isn't safe in
## Godot, so every PlusfishLink's worker does both under this lock.
static var _process_lock := Mutex.new()

## PC: runs the Plusfish program (`plusfish evalgame`, kept running between
## requests) on a background thread, so starting it, sending it requests and
## waiting for its answers never holds up the game. The screen hands in
## requests (submit) and picks up answers (take); both only touch the lists
## below, under the lock, for a moment.
class Worker extends RefCounted:
	var _program: String
	var _thread := Thread.new()
	var _lock := Mutex.new()
	var _wake := Semaphore.new()
	## Shared with the screen (under _lock): requests waiting ([task, text]),
	## answers ready (task -> reply lines, "" if Plusfish failed), the task being
	## worked on, the last one cancelled, the program's process ID.
	var _waiting: Array = []
	var _answers := {}
	var _tasks_made := 0
	var _working_on := -1
	var _cancelled := -1
	var _pid := -1
	var _quit := false

	func _init(program: String) -> void:
		_program = program
		_thread.start(_run)

	func submit(input: String) -> int:
		_lock.lock()
		_tasks_made += 1
		var task := _tasks_made
		_waiting.append([task, input])
		_lock.unlock()
		_wake.post()
		return task

	func take(task: int) -> Variant:
		_lock.lock()
		var out: Variant = _answers.get(task)
		_answers.erase(task)
		_lock.unlock()
		return out

	## Forget a task; if Plusfish is searching it, stop the program.
	func cancel(task: int) -> void:
		_lock.lock()
		_cancelled = task
		_waiting = _waiting.filter(func(next: Array) -> bool: return next[0] != task)
		if _working_on == task and _pid > 0:
			PlusfishLink._kill(_pid)
			_pid = -1
		_answers.erase(task)
		_lock.unlock()

	## Stop the program and the thread (when the screen closes).
	func shut_down() -> void:
		_lock.lock()
		_quit = true
		if _pid > 0:
			PlusfishLink._kill(_pid)
			_pid = -1
		_lock.unlock()
		_wake.post()
		_thread.wait_to_finish()

	## On the background thread: take each request, send it to the program
	## (starting it if it isn't running) and keep its answer for take().
	func _run() -> void:
		var stdio: FileAccess = null
		var pid := -1
		while true:
			_wake.wait()
			_lock.lock()
			if _quit:
				_lock.unlock()
				break
			if _waiting.is_empty():
				_lock.unlock()
				continue
			var next: Array = _waiting.pop_front()
			var task: int = next[0]
			_working_on = task
			_lock.unlock()
			var out := ""
			# Twice: if the program stopped (or was stopped) since the last
			# request, it's started again.
			for attempt in 2:
				if stdio == null:
					PlusfishLink._process_lock.lock()
					var pipe := OS.execute_with_pipe(_program, ["evalgame"])
					PlusfishLink._process_lock.unlock()
					if pipe.is_empty():
						break
					stdio = pipe["stdio"]
					pid = pipe["pid"]
					_lock.lock()
					_pid = pid
					var stopped := _quit or _cancelled == task
					_lock.unlock()
					if stopped:
						PlusfishLink._kill(pid)
						stdio = null
						break
				out = PlusfishLink._ask(stdio, next[1])
				if out != "":
					break
				stdio = null
				_lock.lock()
				var stopped := _quit or _cancelled == task
				_lock.unlock()
				if stopped:
					break
			_lock.lock()
			_working_on = -1
			if _cancelled != task:
				_answers[task] = out
			_lock.unlock()
		if stdio != null:
			PlusfishLink._kill(pid)

static func _kill(pid: int) -> void:
	_process_lock.lock()
	OS.kill(pid)
	_process_lock.unlock()

## Send one request and read the reply lines up to "done" ("" if the program
## stopped first).
static func _ask(stdio: FileAccess, input: String) -> String:
	stdio.store_line(input)
	stdio.flush()
	var lines := PackedStringArray()
	while stdio.is_open() and stdio.get_error() == OK:
		var line := stdio.get_line()
		if line.is_empty():
			if stdio.eof_reached():
				break
			continue
		if line.contains("\"done\""):
			return "\n".join(lines) if not lines.is_empty() else "{}"
		lines.append(line)
	return ""
