class_name MemoryBackend
extends OnlineBackend

## A pretend server that keeps games in memory, for tests: OnlineSessions with
## their own MemoryBackends play each other instantly, with no internet. It
## follows the same rules as the real server's functions
## (server/supabase_update_3.sql): who may do what, server clocks, limits.
## Each MemoryBackend is one device: `user` is who it's signed in as.

## code -> game (with the players' IDs). Shared by every MemoryBackend, like one server.
static var games := {}
## code -> army data.
static var shared_armies := {}
## Quick match queue: user -> {white_army, black_army, time_ms, rules, game_code, seen, entered}.
static var queue := {}
## Reports: {code, reporter, reported, reason, chat, moves}.
static var reports: Array = []
## Added to the server's clock (tests use it to pretend time has passed).
static var clock_offset_ms := 0
## Set to true to make every call fail, as if the internet were down.
var offline := false
## Who this device is signed in as.
var user := ""

## Players seen online: user -> time (ms), for the live counts.
static var presence := {}
const LAG_ALLOWANCE_MS := 2500

func _init(p_user := "") -> void:
	user = p_user if p_user != "" else "device-%d" % randi()

func user_id() -> String:
	return user

static func now_ms() -> int:
	return Time.get_ticks_msec() + clock_offset_ms

## Forget every game and shared army (tests start fresh).
static func clear() -> void:
	games.clear()
	shared_armies.clear()
	queue.clear()
	reports.clear()
	presence.clear()
	clock_offset_ms = 0

func call_function(name: String, args: Dictionary) -> Dictionary:
	if offline:
		return failed("offline")
	match name:
		"get_game": return _get_game(args)
		"resign_game": return _resign(args)
		"offer_draw": return _offer_draw(args)
		"answer_draw": return _answer_draw(args)
		"cancel_game": return _cancel(args)
		"claim_timeout": return _claim_timeout(args)
		"send_chat": return _send_chat(args)
		"claim_rematch": return _claim_rematch(args)
		"share_army": return _share_army(args)
		"get_shared_army": return _get_shared_army(args)
		"quick_match_status": return _quick_status()
		"leave_quick_match": return _leave_quick()
		"report_player": return _report(args)
		"online_counts": return _online_counts()
	return failed("no such function: " + name)

## The referee (server/supabase/functions/referee), with the game's own rules
## engine in place of Plusfish: armies must keep the army rules, moves must be
## legal, and the rules engine says when the game ends.
func referee(action: String, args: Dictionary) -> Dictionary:
	if offline:
		return failed("offline")
	match action:
		"create": return _referee_create(args)
		"join": return _referee_join(args)
		"move": return _referee_move(args)
		"quick": return _referee_quick(args)
	return failed("unknown action")

const UPDATE_NEEDED := "This copy of Overchess is out of date for online play: it updates itself at the main menu."

func _referee_create(args: Dictionary) -> Dictionary:
	if args.get("rules", "") != RuleSet.version():
		return failed(UPDATE_NEEDED)
	var seat := str(args.seat)
	if seat == "random":
		seat = "white" if randi() % 2 == 0 else "black"
	var problem := _army_problem(args.white_army if seat == "white" else args.black_army)
	if problem != "":
		return failed(problem)
	return _create({"p_seat": seat, "p_white_army": args.white_army, "p_black_army": args.black_army,
			"p_time_ms": args.time_ms, "p_increment_ms": args.get("increment_ms", 0), "p_eval_bar": args.get("eval_bar", false),
			"p_rules": args.rules})

func _referee_join(args: Dictionary) -> Dictionary:
	var code := str(args.code).strip_edges().to_upper()
	if not games.has(code):
		return failed("There's no game with the code %s." % code)
	var g: Dictionary = games[code]
	if args.get("rules", "") != g.rules:
		return failed("You and your opponent have different versions of Overchess: both update themselves at the main menu.")
	if g.status != OnlineSession.WAITING:
		return failed("That game was cancelled." if g.status == OnlineSession.CANCELLED else "That game has already started.")
	var seat := "white" if g.white_id == "" else "black"
	var mine: Variant = args.white_army if seat == "white" else args.black_army
	var problem := _army_problem(mine)
	if problem != "":
		return failed(problem)
	var start := _game_state(mine if seat == "white" else g.white_army, mine if seat == "black" else g.black_army, [])
	return _join({"p_code": code, "p_white_army": args.white_army, "p_black_army": args.black_army,
			"p_finished": start.outcome() != GameState.Outcome.NONE, "p_refereed": PlusfishLink.supports(start)})

func _referee_move(args: Dictionary) -> Dictionary:
	var code := str(args.code).strip_edges().to_upper()
	if not games.has(code):
		return failed("There's no game with the code %s." % code)
	var g: Dictionary = games[code]
	var text := str(args.move)
	var refereed: bool = g.refereed
	var finished := bool(args.get("finished", false))
	if refereed and g.status == OnlineSession.PLAYING and int(g.move_count) == int(args.expected) and args.seat == _mover(g):
		if "/" in text:
			refereed = false
		else:
			var state := _game_state(g.white_army, g.black_army, g.moves)
			var move: Move = state.find_move(text) if state else null
			if move == null:
				return failed("That move isn't allowed.")
			state.make_move(move)
			finished = state.outcome() != GameState.Outcome.NONE
	return _play({"p_code": code, "p_seat": args.seat, "p_move": text, "p_expected": args.expected,
			"p_think_ms": args.think_ms, "p_finished": finished, "p_refereed": refereed})

func _referee_quick(args: Dictionary) -> Dictionary:
	if args.get("rules", "") != RuleSet.version():
		return failed(UPDATE_NEEDED)
	for side in ["white_army", "black_army"]:
		var problem := _army_problem(args[side])
		if problem != "":
			return failed(problem)
	var time := int(args.time_ms)
	var bonus := 0 if time == OnlineSession.QUICK_ANY else int(args.get("increment_ms", 0))
	if time != OnlineSession.QUICK_ANY and not time_ok(time, bonus):
		return failed("That time limit isn't one of the choices.")
	presence[user] = now_ms()
	var mine: Dictionary = queue.get(user, {})
	if mine.get("game_code", "") != "":
		queue.erase(user)
		return succeeded([{"paired": mine.game_code}])
	queue[user] = {"white_army": args.white_army, "black_army": args.black_army, "time_ms": time, "increment_ms": bonus,
			"rules": args.rules, "game_code": "", "seen": now_ms(), "entered": mine.get("entered", now_ms())}
	for other: String in _quick_candidates(user):
		var theirs: Dictionary = queue[other]
		var i_am_white := randi() % 2 == 0
		var white: Variant = args.white_army if i_am_white else theirs.white_army
		var black: Variant = theirs.black_army if i_am_white else args.black_army
		var start := _game_state(white, black, [])
		var t: int = time if time >= 0 else (int(theirs.time_ms) if int(theirs.time_ms) >= 0 else 600000)
		var b: int = bonus if time >= 0 else (int(theirs.increment_ms) if int(theirs.time_ms) >= 0 else 0)
		var code := _new_code(games)
		var g := {
			"code": code, "status": OnlineSession.PLAYING, "result": "", "version": 0,
			"time_ms": t, "increment_ms": b, "white_ms": t, "black_ms": t, "moves": [], "move_count": 0, "eval_bar": false,
			"white_id": user if i_am_white else other, "black_id": other if i_am_white else user,
			"white_army": white, "black_army": black, "chat": [], "draw_offer": "", "rematch": "",
			"created_by": user, "turn_started": now_ms(), "rules": args.rules,
			"refereed": PlusfishLink.supports(start),
		}
		if start.outcome() != GameState.Outcome.NONE:
			g.status = OnlineSession.FINISHED
			g.result = "board"
		games[code] = g
		theirs.game_code = code
		queue.erase(user)
		var view := _view(g)
		view["seat"] = "white" if i_am_white else "black"
		return succeeded([view])
	return succeeded([])

## The server's list of time controls (time_ok in the SQL).
static func time_ok(base: int, bonus: int) -> bool:
	for control: Array in OnlineSession.TIME_CONTROLS:
		if control[1] == base and control[2] == bonus:
			return true
	return false

func _online_counts() -> Dictionary:
	presence[user] = now_ms()
	var online := presence.values().filter(func(t: int) -> bool: return now_ms() - t < 60000).size()
	var looking := queue.values().filter(func(q: Dictionary) -> bool: return q.game_code == "" and now_ms() - int(q.seen) < 20000).size()
	return succeeded([{"online": online, "looking": looking}])

## Waiting players whose time fits this player's, seen in the last 20 s, oldest first.
func _quick_candidates(who: String) -> Array:
	var mine: Dictionary = queue[who]
	var found := []
	for other: String in queue:
		var q: Dictionary = queue[other]
		if other == who or q.game_code != "" or q.rules != mine.rules or now_ms() - int(q.seen) > 20000:
			continue
		var same: bool = q.time_ms == mine.time_ms and q.increment_ms == mine.increment_ms
		if same or q.time_ms == OnlineSession.QUICK_ANY or mine.time_ms == OnlineSession.QUICK_ANY:
			found.append(other)
	found.sort_custom(func(a: String, b: String) -> bool: return queue[a].entered < queue[b].entered)
	return found

func _quick_status() -> Dictionary:
	if not queue.has(user):
		return succeeded([{"gone": true}])
	var mine: Dictionary = queue[user]
	if mine.game_code != "":
		queue.erase(user)
		return succeeded([{"code": mine.game_code}])
	mine.seen = now_ms()
	return succeeded([{"waiting": true, "others": _quick_candidates(user).size()}])

func _leave_quick() -> Dictionary:
	var mine: Dictionary = queue.get(user, {})
	queue.erase(user)
	if mine.get("game_code", "") != "":
		return succeeded([{"code": mine.game_code}])
	return succeeded([{"left": true}])

func _report(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	var other: String = g.black_id if args.p_seat == "white" else g.white_id
	if other == "" or other == user:
		return failed("There's no opponent to report.")
	for r: Dictionary in reports:
		if r.code == g.code and r.reporter == user:
			return failed("You've already reported this game.")
	reports.append({"code": g.code, "reporter": user, "reported": other, "reason": str(args.get("p_reason", "")),
			"chat": g.chat.duplicate(true), "moves": g.moves.duplicate()})
	return succeeded([{"reported": true}])

## The referee's refusal for an army breaking the rules, or "".
static func _army_problem(data: Variant) -> String:
	var army := SavedGame.army_from_dict(data) if army_ok(data) else null
	if army == null:
		return "Your army breaks the army rules: That isn't an army."
	var problems := RuleText.plain_lines(army.problems(StandardSetup.create_rules(), 8))
	return "" if problems.is_empty() else "Your army breaks the army rules: " + " ".join(problems)

## The game from the two armies (as data) after `moves` (null if one can't be played).
static func _game_state(white: Variant, black: Variant, moves: Array) -> GameState:
	var state := ArmySetup.create_game(SavedGame.army_from_dict(white), SavedGame.army_from_dict(black), StandardSetup.create_rules())
	for text: Variant in moves:
		var move := state.find_move(str(text))
		if move == null:
			return null
		state.make_move(move)
	return state

# --- The server's functions (the referee's create/join/play, and the rest) ---------------

func _create(args: Dictionary) -> Dictionary:
	var seat := str(args.p_seat)
	if seat == "random":
		seat = "white" if randi() % 2 == 0 else "black"
	if seat not in ["white", "black"]:
		return failed("Choose White, Black or Random.")
	if not time_ok(int(args.p_time_ms), int(args.get("p_increment_ms", 0))):
		return failed("That time limit isn't one of the choices.")
	var army: Variant = args.p_white_army if seat == "white" else args.p_black_army
	if not army_ok(army):
		return failed("That army can't be used online.")
	if games.values().filter(func(g: Dictionary) -> bool: return g.created_by == user and g.status == OnlineSession.WAITING).size() >= 5:
		return failed("You already have 5 games waiting for an opponent.")
	var code := _new_code(games)
	var g := {
		"code": code, "status": OnlineSession.WAITING, "result": "", "version": 0,
		"time_ms": int(args.p_time_ms), "increment_ms": int(args.get("p_increment_ms", 0)),
		"white_ms": int(args.p_time_ms), "black_ms": int(args.p_time_ms),
		"moves": [], "move_count": 0, "eval_bar": bool(args.get("p_eval_bar", false)),
		"white_id": user if seat == "white" else "", "black_id": user if seat == "black" else "",
		"white_army": army if seat == "white" else null, "black_army": army if seat == "black" else null,
		"chat": [], "draw_offer": "", "rematch": "", "created_by": user, "turn_started": 0,
		"rules": str(args.get("p_rules", "")), "refereed": true,
	}
	games[code] = g
	return succeeded([_view(g)])

func _join(args: Dictionary) -> Dictionary:
	var code := str(args.p_code).strip_edges().to_upper()
	if not games.has(code):
		return failed("There's no game with the code %s." % code)
	var g: Dictionary = games[code]
	if g.status == OnlineSession.CANCELLED:
		return failed("That game was cancelled.")
	if g.status != OnlineSession.WAITING:
		return failed("That game has already started.")
	var seat := "white" if g.white_id == "" else "black"
	var army: Variant = args.p_white_army if seat == "white" else args.p_black_army
	if not army_ok(army):
		return failed("That army can't be used online.")
	g[seat + "_id"] = user
	g[seat + "_army"] = army
	g.refereed = bool(args.get("p_refereed", true))
	g.status = OnlineSession.PLAYING
	if bool(args.get("p_finished", false)):
		g.status = OnlineSession.FINISHED
		g.result = "board"
	g.turn_started = now_ms()
	_touch(g)
	var view := _view(g)
	view["seat"] = seat
	return succeeded([view])

func _get_game(args: Dictionary) -> Dictionary:
	presence[user] = now_ms()
	var code := str(args.p_code).strip_edges().to_upper()
	if not games.has(code):
		return succeeded([])
	var g: Dictionary = games[code]
	if int(g.version) == int(args.get("p_known_version", -1)):
		return succeeded([{"version": g.version, "unchanged": true}])
	return succeeded([_view(g)])

func _play(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	var mover := _mover(g)
	if g.status != OnlineSession.PLAYING or int(g.move_count) != int(args.p_expected) or args.p_seat != mover:
		return succeeded([])
	var text := str(args.p_move)
	if not RegEx.create_from_string("^[A-Za-z0-9!=@~x/-]{2,20}$").search(text):
		return failed("That move can't be sent.")
	var left := 0
	if int(g.time_ms) > 0:
		var elapsed := maxi(0, now_ms() - int(g.turn_started))
		var charged := mini(elapsed, maxi(maxi(int(args.p_think_ms), 0), elapsed - LAG_ALLOWANCE_MS))
		left = int(g[mover + "_ms"]) - charged
		if left <= 0:
			_finish(g, mover + "_timeout")
			g[mover + "_ms"] = 0
			return succeeded([_view(g)])
		g[mover + "_ms"] = left + int(g.get("increment_ms", 0))
	g.moves.append(text)
	g.move_count = int(g.move_count) + 1
	if g.draw_offer != mover:
		g.draw_offer = ""
	g.turn_started = now_ms()
	g.refereed = g.refereed and bool(args.get("p_refereed", false))
	if bool(args.get("p_finished", false)):
		g.status = OnlineSession.FINISHED
		g.result = "board"
	_touch(g)
	return succeeded([_view(g)])

func _resign(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	if g.status != OnlineSession.PLAYING:
		return succeeded([])
	g.draw_offer = ""
	_finish(g, str(args.p_seat) + "_resigned")
	return succeeded([_view(g)])

func _offer_draw(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	if g.status != OnlineSession.PLAYING or g.draw_offer != "":
		return succeeded([])
	g.draw_offer = args.p_seat
	_touch(g)
	return succeeded([_view(g)])

func _answer_draw(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	if g.draw_offer == "" or g.draw_offer == args.p_seat:
		return succeeded([])
	g.draw_offer = ""
	if bool(args.p_accept) and g.status == OnlineSession.PLAYING:
		_finish(g, "draw_agreed")
	else:
		_touch(g)
	return succeeded([_view(g)])

func _cancel(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	if g.status != OnlineSession.WAITING:
		return succeeded([])
	g.status = OnlineSession.CANCELLED
	_touch(g)
	return succeeded([_view(g)])

func _claim_timeout(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	var mover := _mover(g)
	var grace := 0 if args.p_seat == mover else LAG_ALLOWANCE_MS
	if g.status == OnlineSession.PLAYING and int(g.time_ms) > 0 \
			and now_ms() - int(g.turn_started) > int(g[mover + "_ms"]) + grace:
		g[mover + "_ms"] = 0
		_finish(g, mover + "_timeout")
	return succeeded([_view(g)])

func _send_chat(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	var text := str(args.p_text).strip_edges().left(200)
	if text == "":
		return failed("Empty message.")
	if g.chat.size() >= 300:
		return failed("This game's chat is full.")
	var now := now_ms()
	var recent: Array = g.chat.filter(func(m: Dictionary) -> bool: return m.from == args.p_seat and int(m.at) > now - 10000)
	if recent.size() >= 5:
		return failed("You're sending messages too fast.")
	g.chat.append({"from": args.p_seat, "text": text, "at": now})
	_touch(g)
	return succeeded([_view(g)])

func _claim_rematch(args: Dictionary) -> Dictionary:
	var found := _my_game(args)
	if found.has("error"):
		return failed(found.error)
	var g: Dictionary = found.game
	if g.status != OnlineSession.FINISHED or g.rematch != "":
		return succeeded([])
	var new_code := str(args.p_new_code).to_upper()
	var other: Dictionary = games.get(new_code, {})
	if other.is_empty() or other.created_by != user or other.status != OnlineSession.WAITING:
		return failed("That rematch game isn't yours.")
	g.rematch = new_code
	_touch(g)
	return succeeded([_view(g)])

func _share_army(args: Dictionary) -> Dictionary:
	if not army_ok(args.p_army):
		return failed("That army can't be shared.")
	var code := _new_code(shared_armies)
	shared_armies[code] = (args.p_army as Dictionary).duplicate(true)
	return succeeded([{"code": code}])

func _get_shared_army(args: Dictionary) -> Dictionary:
	var code := str(args.p_code).strip_edges().to_upper()
	if not shared_armies.has(code):
		return succeeded([])
	return succeeded([{"army": (shared_armies[code] as Dictionary).duplicate(true)}])

# --- Inside -----------------------------------------------------------------------------

## The server's checks on an army's shape and size (see army_ok in the SQL).
static func army_ok(army: Variant) -> bool:
	if not army is Dictionary or JSON.stringify(army).length() > 3000:
		return false
	var pieces: Variant = army.get("pieces")
	if not pieces is Array or pieces.size() < 1 or pieces.size() > 16 or str(army.get("name", "")).length() > 40:
		return false
	for entry: Variant in pieces:
		if not entry is Array or entry.size() != 3 or not entry[0] is String:
			return false
		if not (entry[1] is int or entry[1] is float) or not (entry[2] is int or entry[2] is float):
			return false
		if int(entry[1]) < 0 or int(entry[1]) > 7 or int(entry[2]) < 0 or int(entry[2]) > 1:
			return false
	return true

## The caller's game after checking the seat is theirs: {"game"} or {"error"}.
func _my_game(args: Dictionary) -> Dictionary:
	var code := str(args.p_code).strip_edges().to_upper()
	if not games.has(code):
		return {"error": "There's no game with the code %s." % code}
	var g: Dictionary = games[code]
	var seat := str(args.get("p_seat", ""))
	if seat not in ["white", "black"] or g[seat + "_id"] != user:
		return {"error": "You're not a player in that game."}
	return {"game": g}

static func _mover(g: Dictionary) -> String:
	return "white" if int(g.move_count) % 2 == 0 else "black"

static func _finish(g: Dictionary, result: String) -> void:
	g.status = OnlineSession.FINISHED
	g.result = result
	_touch(g)

static func _touch(g: Dictionary) -> void:
	g.version = int(g.version) + 1

func _view(g: Dictionary) -> Dictionary:
	var player: bool = user in [g.white_id, g.black_id]
	var you := []
	for seat in ["white", "black"]:
		if g[seat + "_id"] == user:
			you.append(seat)
	return {
		"code": g.code, "status": g.status, "result": g.result, "version": g.version,
		"time_ms": g.time_ms, "increment_ms": g.get("increment_ms", 0), "white_ms": g.white_ms, "black_ms": g.black_ms,
		"moves": g.moves.duplicate(), "move_count": g.move_count, "eval_bar": g.eval_bar,
		"white_army": g.white_army, "black_army": g.black_army,
		"white_taken": g.white_id != "", "black_taken": g.black_id != "",
		"turn_ms": maxi(0, now_ms() - int(g.turn_started)) if g.status == OnlineSession.PLAYING else 0,
		"you": you,
		"chat": g.chat.duplicate(true) if player else [],
		"draw_offer": g.draw_offer if player else "",
		"rematch": g.rematch if player else "",
	}

static func _new_code(taken: Dictionary) -> String:
	while true:
		var code := ""
		for i in OnlineSession.CODE_LENGTH:
			code += OnlineSession.CODE_LETTERS[randi() % OnlineSession.CODE_LETTERS.length()]
		if not taken.has(code):
			return code
	return ""
