extends TestSuite

## Online play: two OnlineSessions ("devices") sharing a pretend server
## (MemoryBackend), so no internet is needed. The pretend server follows the
## real server's rules (server/supabase_update_3.sql), so these tests also
## check that nobody can act for the other player.

const KNIGHT = preload("res://data/pieces/knight.tres")
const LOBBY = preload("res://scenes/online/online_lobby.gd")

func _session(player_id: String) -> OnlineSession:
	var session := OnlineSession.new(MemoryBackend.new(), player_id)
	session.poll_seconds = 0
	(Engine.get_main_loop() as SceneTree).root.add_child(session)
	return session

## Host creates a game (White, no clock); guest joins it.
func _started_game(time_ms := 0) -> Array:
	MemoryBackend.clear()
	var host := _session("host")
	var guest := _session("guest")
	await host.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, time_ms)
	await guest.join_game(host.code, StandardSetup.army())
	await host.poll()
	return [host, guest]

func _free(sessions: Array) -> void:
	for session: Node in sessions:
		session.free()

func test_create_and_join() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var guest := _session("guest")
	var created := await host.create_game(StandardSetup.army(), OnlineSession.SIDE_BLACK, 0)
	check(created.ok, "Created")
	check_eq(host.code.length(), OnlineSession.CODE_LENGTH, "A 5-character code")
	check_eq(host.status(), OnlineSession.WAITING, "Waiting for an opponent")
	check_eq(host.my_team, Piece.Team.BLACK, "Host chose Black")
	var heard := []
	host.changed.connect(func(row: Dictionary) -> void: heard.append(row.status))
	var joined := await guest.join_game(host.code.to_lower() + " ", StandardSetup.army())
	check(joined.ok, "Joined (code typed in lower case, with a space)")
	check_eq(guest.my_team, Piece.Team.WHITE, "Guest gets the other side")
	await host.poll()
	check_eq(heard, [OnlineSession.PLAYING], "Host hears that the game started")
	check(host.create_state(StandardSetup.create_rules()) != null, "Both armies are there")
	_free([host, guest])

func test_random_side() -> void:
	MemoryBackend.clear()
	var teams := {}
	for i in 20:
		var host := _session("host%d" % i)
		await host.create_game(StandardSetup.army(), OnlineSession.SIDE_RANDOM, 0)
		teams[host.my_team] = true
		host.free()
	check_eq(teams.size(), 2, "Random gives both sides")

func test_join_problems() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var guest := _session("guest")
	var third := _session("third")
	var missing := await guest.join_game("ZZZZZ", StandardSetup.army())
	check(not missing.ok and "no game" in missing.error, "No such game: " + missing.error)
	await host.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 0)
	await guest.join_game(host.code, StandardSetup.army())
	var late := await third.join_game(host.code, StandardSetup.army())
	check(not late.ok and "already started" in late.error, "Too late")
	_free([host, guest, third])

func test_moves_travel_between_devices() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	var sent := await host.send_move("e2-e4", false)
	check(sent.ok and not sent.rows.is_empty(), "Move sent")
	await guest.poll()
	check_eq(guest.moves(), ["e2-e4"], "Guest sees it")
	check_eq(guest.side_to_move(), Piece.Team.BLACK, "Black's turn")
	var state := guest.create_state(StandardSetup.create_rules())
	check_eq(state.history.size(), 1, "Replayed")
	_free(pair)

func test_moves_cannot_collide() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	await host.send_move("e2-e4", false)
	# The guest hasn't heard about e4 yet, so its idea of the move count is old.
	var clash := await guest.send_move("d2-d4", false)
	check(clash.ok and clash.rows.is_empty(), "Rejected: someone moved first")
	_free(pair)

func test_nobody_can_act_for_the_other_player() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	# The guest (Black) pretends to be White.
	guest.my_team = Piece.Team.WHITE
	var moved := await guest.send_move("e2-e4", false)
	check(not moved.ok and "not a player" in moved.error, "Can't move for White: " + moved.error)
	var resigned := await guest.resign()
	check(not resigned.ok, "Can't resign for White")
	var chatted := await guest.post_chat("I'm White, honest")
	check(not chatted.ok, "Can't chat as White")
	guest.my_team = Piece.Team.BLACK
	# Black can't move on White's turn either.
	var early := await guest.send_move("e7-e5", false)
	check(early.ok and early.rows.is_empty(), "Not Black's turn")
	# A stranger with the code sees the game but not the chat, and can't act.
	var stranger := _session("stranger")
	await host.post_chat("secret plan")
	var seen := await stranger.resume(host.code)
	check(not seen.ok and "not a player" in seen.error, "A stranger isn't a player")
	var peek: Dictionary = await stranger.backend.call_function("get_game", {"p_code": host.code})
	check_eq(peek.rows[0].chat, [], "...and doesn't see the chat")
	check(not (peek.rows[0] as Dictionary).has("white_id"), "No player IDs are ever sent")
	_free(pair + [stranger])

func test_chat_limits() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	for i in 5:
		check((await host.post_chat("hi %d" % i)).ok, "Message %d sent" % i)
	var sixth := await host.post_chat("too fast")
	check(not sixth.ok and "too fast" in sixth.error, "Six in ten seconds is too many: " + sixth.error)
	MemoryBackend.clock_offset_ms = 11000
	check((await host.post_chat("later")).ok, "Fine again later")
	_free(pair)

func test_quiet_polls_send_nothing_new() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var version := int(host.row.version)
	var quiet: Dictionary = await host.backend.call_function("get_game", {"p_code": host.code, "p_known_version": version})
	check(quiet.rows[0].get("unchanged", false), "Nothing new: only the version comes back")
	await host.send_move("e2-e4", false)
	check(int(host.row.version) > version, "A move changes the version")
	_free(pair)

func test_resign_and_finish() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	await guest.resign()
	await host.poll()
	check_eq(host.status(), OnlineSession.FINISHED, "Finished")
	check_eq(host.result_code(), "black_resigned", "Black resigned")
	_free(pair)

func test_cancel_while_waiting() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var guest := _session("guest")
	await host.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 0)
	await host.cancel()
	check_eq(host.status(), OnlineSession.CANCELLED, "Cancelled")
	check(not (await guest.join_game(host.code, StandardSetup.army())).ok, "Can't join a cancelled game")
	_free([host, guest])

func test_clocks() -> void:
	var pair: Array = await _started_game(180000)
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	var start := host.turn_started_ms
	check_eq(host.clock_ms(Piece.Team.WHITE, start + 10000), 170000, "White's clock runs on White's turn")
	check_eq(host.clock_ms(Piece.Team.BLACK, start + 10000), 180000, "Black's doesn't")
	check(host.out_of_time(Piece.Team.WHITE, start + 180000), "Out of time at zero on your own device")
	check(not guest.out_of_time(Piece.Team.WHITE, guest.turn_started_ms + 180000), "The opponent waits a little longer")
	check(guest.out_of_time(Piece.Team.WHITE, guest.turn_started_ms + 180000 + OnlineSession.TIMEOUT_GRACE_MS), "Then claims it")
	# The server decides by its own clock: too early, the game goes on.
	MemoryBackend.clock_offset_ms = 30000
	await guest.claim_timeout(Piece.Team.WHITE)
	check_eq(guest.status(), OnlineSession.PLAYING, "Claimed too early: refused")
	MemoryBackend.clock_offset_ms = 180000 + OnlineSession.TIMEOUT_GRACE_MS
	await guest.claim_timeout(Piece.Team.WHITE)
	check_eq(guest.result_code(), "white_timeout", "White lost on time")
	_free(pair)

func test_server_clock_counts_the_move() -> void:
	var pair: Array = await _started_game(180000)
	var host: OnlineSession = pair[0]
	# 10 s pass on the server; the device says it thought for 9 s (it heard
	# about the turn a little late): the server takes the device's word, as it's
	# within the allowance.
	MemoryBackend.clock_offset_ms = 10000
	host.turn_started_ms = Time.get_ticks_msec() - 9000
	await host.send_move("e2-e4", false)
	check(absi(int(host.row.white_ms) - 171000) < 200, "9 s used: %d left" % int(host.row.white_ms))
	# Claiming far less than the server saw doesn't work: at most 2.5 s off.
	MemoryBackend.clock_offset_ms = 30000
	var guest: OnlineSession = pair[1]
	await guest.poll()
	guest.turn_started_ms = Time.get_ticks_msec() - 1000
	await guest.send_move("e7-e5", false)
	check(absi(int(guest.row.black_ms) - (180000 - 17500)) < 200, "Said 1 s, but 20 s passed: 17.5 s counted (%d left)" % int(guest.row.black_ms))
	# Running out on the server ends the game instead of taking the move.
	MemoryBackend.clock_offset_ms = 30000 + 180000
	await host.poll()
	var late := await host.send_move("g1-f3", false)
	check(late.ok and host.result_code() == "white_timeout", "A move after the flag fell loses on time")
	check_eq(host.move_count(), 2, "...and isn't added")
	_free(pair)

func test_resume_after_closing() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	await host.send_move("e2-e4", false)
	var again := _session("host")
	var resumed := await again.resume(host.code)
	check(resumed.ok, "Resumed")
	check_eq(again.my_team, Piece.Team.WHITE, "Same side as before")
	check_eq(again.moves(), ["e2-e4"], "Same moves")
	var stranger := _session("stranger")
	check(not (await stranger.resume(host.code)).ok, "Someone else can't take over")
	_free(pair + [again, stranger])

func test_custom_armies_travel() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var guest := _session("guest")
	var army := Army.new()
	army.army_name = "Knights"
	army.place(load("res://data/pieces/king.tres"), Vector2i(4, 0))
	army.place(KNIGHT, Vector2i(1, 0))
	await host.create_game(army, OnlineSession.SIDE_WHITE, 0)
	await guest.join_game(host.code, StandardSetup.army())
	var white := guest.army(Piece.Team.WHITE)
	check(white != null and white.def_at(Vector2i(1, 0)) == KNIGHT, "The host's own army arrives")
	_free([host, guest])

func test_offline_errors_are_reported() -> void:
	MemoryBackend.clear()
	var backend := MemoryBackend.new()
	backend.offline = true
	var host := OnlineSession.new(backend, "host")
	(Engine.get_main_loop() as SceneTree).root.add_child(host)
	var created := await host.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 0)
	check(not created.ok and created.error != "", "Fails with a message")
	host.free()

# --- Screens -------------------------------------------------------------------------

func _root() -> Node:
	return (Engine.get_main_loop() as SceneTree).root

## An online game screen for `session`.
func _game_screen(session: OnlineSession) -> Node:
	var game: Node = load("res://scenes/game/game.tscn").instantiate()
	if session.get_parent():
		session.get_parent().remove_child(session)
	game.online = session
	_root().add_child(game)
	return game

func test_lobby_create_then_friend_joins() -> void:
	MemoryBackend.clear()
	var lobby: Node = load("res://scenes/online/online_lobby.tscn").instantiate()
	var backend := MemoryBackend.new()
	lobby.backend = backend
	lobby.player_id = "host"
	_root().add_child(lobby)
	var ready_sessions := []
	lobby.game_ready.connect(func(session: OnlineSession) -> void: ready_sessions.append(session))
	await lobby.create()
	check(lobby.waiting.visible, "Waiting screen")
	check_eq(lobby.code_label.text, lobby.session.code, "Shows the code")
	var guest := _session("guest")
	await guest.join_game(lobby.session.code, StandardSetup.army())
	await lobby.session.poll()
	check_eq(ready_sessions.size(), 1, "Host's game starts when the friend joins")
	lobby.free()
	guest.free()
	backend.free()

func test_lobby_join_problems_are_shown() -> void:
	MemoryBackend.clear()
	var lobby: Node = load("res://scenes/online/online_lobby.tscn").instantiate()
	var backend := MemoryBackend.new()
	lobby.backend = backend
	lobby.player_id = "guest"
	_root().add_child(lobby)
	lobby.code_edit.text = "ABC"
	await lobby.join()
	check(lobby.message_label.text.contains("5"), "Too short: says how long codes are")
	lobby.code_edit.text = "ZZZZZ"
	await lobby.join()
	check(lobby.message_label.text.contains("no game"), "Unknown code: " + lobby.message_label.text)
	lobby.free()
	backend.free()

func test_online_game_between_two_screens() -> void:
	var pair: Array = await _started_game()
	var host_screen := _game_screen(pair[0])
	var guest_screen := _game_screen(pair[1])
	check(host_screen.board_view.input_enabled, "White (host) can move")
	check(not guest_screen.board_view.input_enabled, "Black (guest) has to wait")
	check_eq(guest_screen.status_label.text, "Your opponent's move", "Guest is told to wait")
	check(not host_screen.undo_button.visible, "No undo online")
	check_eq(host_screen.new_game_button.text, "Resign", "Resign instead of New game")
	host_screen.play(Notation.find_move(host_screen.state, "e4"))
	await get_tree_frames(2)
	check(not host_screen.board_view.input_enabled, "Host waits after moving")
	await guest_screen.online.poll()
	check_eq(guest_screen.state.history.size(), 1, "Guest received e4")
	check(guest_screen.board_view.input_enabled, "Now the guest can move")
	check_eq(guest_screen.status_label.text, "Your move", "And is told so")
	host_screen.free()
	guest_screen.free()

func test_no_side_lines_while_the_game_is_on() -> void:
	var pair: Array = await _started_game()
	var host_screen := _game_screen(pair[0])
	var guest_screen := _game_screen(pair[1])
	host_screen.board_view.move_time = 0.0
	host_screen.play(Notation.find_move(host_screen.state, "e4"))
	await get_tree_frames(2)
	await guest_screen.online.poll()
	guest_screen.play(Notation.find_move(guest_screen.state, "e5"))
	await get_tree_frames(2)
	await host_screen.online.poll()
	host_screen.view_move(1)
	check(not host_screen.can_branch(), "No trying moves while the online game is on")
	check(not host_screen.board_view.input_enabled, "The board takes no moves while looking back")
	host_screen.choose(Notation.find_move(host_screen.board_view.state, "c5"))
	check(host_screen.side_lines.is_empty(), "No side line")
	host_screen.back_to_game()
	host_screen.resign()
	await host_screen.resign()
	host_screen.view_move(1)
	check(host_screen.can_branch(), "Once it's over, side lines can be tried")
	host_screen.choose(Notation.find_move(host_screen.board_view.state, "c5"))
	check_eq(host_screen.side_lines.size(), 1, "A side line")
	check_eq(host_screen.state.history.size(), 2, "The game unchanged")
	host_screen.free()
	guest_screen.free()

func test_your_move_notification() -> void:
	var pair: Array = await _started_game()
	var host_screen := _game_screen(pair[0])
	var guest_screen := _game_screen(pair[1])
	TurnNotifier.sent.clear()
	host_screen.play(Notation.find_move(host_screen.state, "e4"))
	await guest_screen.online.poll()
	check(TurnNotifier.sent.is_empty(), "No notification while the game is in front of you")
	guest_screen.play(Notation.find_move(guest_screen.state, "e5"))
	TurnNotifier.force_background = true
	await host_screen.online.poll()
	TurnNotifier.force_background = false
	check_eq(TurnNotifier.sent, PackedStringArray(["Overchess: your move: Your opponent played e5."]), "In the background: told it's your move")
	TurnNotifier.sent.clear()
	host_screen.free()
	guest_screen.free()

func test_resign_from_the_game_screen() -> void:
	var pair: Array = await _started_game()
	var host_screen := _game_screen(pair[0])
	var guest_screen := _game_screen(pair[1])
	host_screen.resign()
	check_eq(host_screen.new_game_button.text, "Tap again to resign", "First tap asks to confirm")
	await host_screen.resign()
	check_eq(host_screen.status_label.text, "You resigned", "Host resigned")
	await guest_screen.online.poll()
	check_eq(guest_screen.status_label.text, "Your opponent resigned - you win!", "Guest wins")
	check_eq(UserSettings.online_game(), "", "No longer offered on the menu")
	host_screen.free()
	guest_screen.free()

func test_checkmate_finishes_the_online_game() -> void:
	var pair: Array = await _started_game()
	var host_screen := _game_screen(pair[0])
	var guest_screen := _game_screen(pair[1])
	for san in ["f3", "e5", "g4", "Qh4#"]:
		var mover: Node = host_screen if host_screen.state.side_to_move == host_screen.online.my_team else guest_screen
		var other: Node = guest_screen if mover == host_screen else host_screen
		mover.play(Notation.find_move(mover.state, san))
		await get_tree_frames(2)
		await other.online.poll()
	check_eq(host_screen.online.status(), OnlineSession.FINISHED, "Finished on the server")
	check_eq(host_screen.status_label.text, "Checkmate! Your opponent wins", "Host lost")
	check_eq(guest_screen.status_label.text, "Checkmate! You win", "Guest won")
	host_screen.free()
	guest_screen.free()

func test_menu_offers_the_online_game_again() -> void:
	var pair: Array = await _started_game()
	var host_screen := _game_screen(pair[0])
	check_eq(UserSettings.online_game(), host_screen.online.code, "Remembered")
	var menu: Node = load("res://scenes/menu/main_menu.tscn").instantiate()
	_root().add_child(menu)
	check(menu.get_node("%ContinueOnline").visible, "Continue online game shown")
	menu.free()
	host_screen.free()
	(pair[1] as Node).free()
	UserSettings.set_online_game("")

func get_tree_frames(count: int) -> void:
	for i in count:
		await (Engine.get_main_loop() as SceneTree).process_frame

func test_your_army_is_at_the_bottom() -> void:
	var pair: Array = await _started_game()
	var host_screen := _game_screen(pair[0])
	var guest_screen := _game_screen(pair[1])
	check(not host_screen.board_view.flipped, "White (host): White at the bottom")
	check(guest_screen.board_view.flipped, "Black (guest): Black at the bottom")
	host_screen.free()
	guest_screen.free()

# --- Draw offers, chat, rematch ---------------------------------------------------------

func test_draw_offer_accepted() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	await host.offer_draw()
	await guest.poll()
	check_eq(guest.draw_offer(), "white", "Guest sees White's offer")
	var second := await host.offer_draw()
	check(second.rows.is_empty(), "Only one offer at a time")
	await guest.answer_draw(true)
	check_eq(guest.status(), OnlineSession.FINISHED, "Finished")
	check_eq(guest.result_code(), "draw_agreed", "Agreed draw")
	_free(pair)

func test_draw_offer_declined_or_ignored() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	await guest.offer_draw()
	await host.poll()
	await host.answer_draw(false)
	check_eq(host.draw_offer(), "", "Declined")
	await guest.poll()
	await guest.offer_draw()
	await host.poll()
	await host.send_move("e2-e4", false)
	check_eq(host.draw_offer(), "", "Moving turns the offer down")
	check_eq(host.status(), OnlineSession.PLAYING, "Game goes on")
	_free(pair)

func test_chat_messages() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	await host.post_chat("Good luck!")
	await guest.post_chat("  You too  ")
	await host.poll()
	var said := host.chat().map(func(m: Dictionary) -> Array: return [m.from, m.text])
	check_eq(said, [["white", "Good luck!"], ["black", "You too"]], "Both messages, in order")
	check(not (await host.post_chat("   ")).ok, "Empty messages are not sent")
	await host.post_chat("x".repeat(300))
	check_eq((host.chat().back().text as String).length(), 200, "Long messages are cut to 200")
	_free(pair)

func test_rematch_claim() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	await host.resign()
	await guest.poll()
	var host_next := _session("host")
	var guest_next := _session("guest")
	await host_next.create_game(StandardSetup.army(), OnlineSession.SIDE_BLACK, 0)
	await guest_next.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 0)
	var not_mine := await host.claim_rematch(guest_next.code)
	check(not not_mine.ok, "Can't point the rematch at someone else's game")
	check((await host.claim_rematch(host_next.code)).rows.size() == 1, "First claim wins")
	var late := await guest.claim_rematch(guest_next.code)
	check(late.rows.is_empty(), "Second claim loses")
	await guest.poll()
	check_eq(guest.rematch_code(), host_next.code, "Both see the same rematch")
	_free(pair + [host_next, guest_next])

func test_two_copies_on_one_phone_can_play_each_other() -> void:
	MemoryBackend.clear()
	# No IDs given: each session makes its own, as two copies of the app would.
	var first := OnlineSession.new(MemoryBackend.new())
	var second := OnlineSession.new(MemoryBackend.new())
	first.poll_seconds = 0
	second.poll_seconds = 0
	_root().add_child(first)
	_root().add_child(second)
	check(first.player_id != second.player_id, "Different IDs")
	await first.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 0)
	var joined := await second.join_game(first.code, StandardSetup.army())
	check(joined.ok, "Joined: " + joined.error)
	first.free()
	second.free()

func test_continue_uses_the_id_saved_with_the_game() -> void:
	var pair: Array = await _started_game()
	var guest_screen := _game_screen(pair[1])
	check_eq(UserSettings.online_game(), guest_screen.online.code, "Game remembered")
	check_eq(UserSettings.online_team(), Piece.Team.BLACK, "With the guest's side")
	var code: String = guest_screen.online.code
	guest_screen.free()
	(pair[0] as Node).free()
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	_root().add_child(main)
	await main.continue_online_game(MemoryBackend.new("guest"))
	check(main.screen.get("online") != null, "Back in the game")
	if main.screen.get("online") != null:
		check_eq(main.screen.online.code, code, "The same game")
		check_eq(main.screen.online.my_team, Piece.Team.BLACK, "On the same side")
	main.free()
	UserSettings.set_online_game("")

# --- The referee (MemoryBackend judges with the game's own rules, as the real
# referee does with Plusfish) --------------------------------------------------------

func test_referee_refuses_illegal_moves() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var bad := await host.send_move("e2-e5", false)
	check(not bad.ok and "isn't allowed" in bad.error, "A pawn can't jump three squares: " + bad.error)
	check_eq(host.move_count(), 0, "Nothing was played")
	var good := await host.send_move("e2-e4", false)
	check(good.ok and host.move_count() == 1, "A legal move goes through")
	_free(pair)

func test_referee_decides_how_the_game_ends() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	for text in ["f2-f3", "e7-e5", "g2-g4"]:
		await host.poll()
		await guest.poll()
		var mover: OnlineSession = host if host.side_to_move() == host.my_team else guest
		check((await mover.send_move(text, false)).ok, "Played " + text)
	await guest.poll()
	# The mating move, sent as "not finished": the referee knows better.
	await guest.send_move("d8-h4", false)
	check_eq(guest.status(), OnlineSession.FINISHED, "Checkmate ends the game on the server")
	check_eq(guest.result_code(), "board", "Ended on the board")
	_free(pair)

func test_referee_refuses_armies_that_break_the_rules() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var greedy := Army.new()
	greedy.place(load("res://data/pieces/king.tres"), Vector2i(4, 0))
	for file in [0, 1, 2, 3, 5, 6, 7]:
		greedy.place(load("res://data/pieces/queen.tres"), Vector2i(file, 0))
	var created := await host.create_game(greedy, OnlineSession.SIDE_WHITE, 0)
	check(not created.ok and "army rules" in created.error, "Seven queens are refused: " + created.error)
	host.free()

func test_referee_needs_the_same_rules() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var backend: MemoryBackend = host.backend
	var old := await backend.referee("create", {"seat": "white", "white_army": SavedGame.army_to_dict(StandardSetup.army()),
			"black_army": SavedGame.army_to_dict(StandardSetup.army()), "time_ms": 0, "rules": "old-version"})
	check(not old.ok and "out of date" in old.error, "An old copy of the game is told to update: " + old.error)
	host.free()

func test_referee_ends_king_exposed_at_once() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var guest := _session("guest")
	# White's Lance looks straight up the e-file at Black's king.
	var lance_army := StandardSetup.army()
	for file in [0, 1, 6, 4]:
		lance_army.remove_at(Vector2i(file, 1))
	lance_army.place(load("res://data/pieces/lance.tres"), Vector2i(4, 1))
	var open_army := StandardSetup.army()
	open_army.remove_at(Vector2i(4, 1))
	await host.create_game(lance_army, OnlineSession.SIDE_WHITE, 0)
	var joined := await guest.join_game(host.code, open_army)
	check(joined.ok, "Joined: " + joined.error)
	check_eq(guest.status(), OnlineSession.FINISHED, "King exposed: over before it starts, on the server too")
	_free([host, guest])

# --- Quick match and reports ---------------------------------------------------------

func _quick_session(player_id: String) -> OnlineSession:
	var session := _session(player_id)
	session.quick_poll_seconds = 0
	return session

func test_quick_match_pairs_two_players() -> void:
	MemoryBackend.clear()
	var first := _quick_session("first")
	var second := _quick_session("second")
	# The first waits (nobody else yet): one try, then they're in the queue.
	first.looking = true
	first._quick_args = first._armies(StandardSetup.army())
	first._quick_args.merge({"time_ms": 300000, "rules": RuleSet.version()})
	var waiting := await first._try_quick()
	check(waiting.ok and first.code == "", "Nobody to play yet: waiting")
	# The second arrives with the same time: paired at once.
	var found := await second.find_quick_match(StandardSetup.army(), 300000)
	check(found.ok and second.code != "", "Paired: " + found.error)
	# The first hears about it on its next check of the queue.
	await first.check_quick_match()
	check_eq(first.code, second.code, "Both are in the same game")
	check(first.my_team != second.my_team, "On opposite sides")
	check_eq(int(first.row.time_ms), 300000, "5 minutes each, as both chose")
	check_eq(first.status(), OnlineSession.PLAYING, "The game is on")
	_free([first, second])

func test_quick_match_times_must_fit() -> void:
	MemoryBackend.clear()
	var first := _quick_session("first")
	var second := _quick_session("second")
	var third := _quick_session("third")
	first._quick_args = first._armies(StandardSetup.army())
	first._quick_args.merge({"time_ms": 180000, "rules": RuleSet.version()})
	await first._try_quick()
	second._quick_args = second._armies(StandardSetup.army())
	second._quick_args.merge({"time_ms": 600000, "rules": RuleSet.version()})
	await second._try_quick()
	check(first.code == "" and second.code == "", "3 minutes and 10 minutes don't fit")
	# Any fits either: paired with whoever waited longest, at their time.
	var found := await third.find_quick_match(StandardSetup.army(), OnlineSession.QUICK_ANY)
	check(found.ok, "Any found a game")
	check_eq(int(third.row.time_ms), 180000, "With the first player, at their 3 minutes")
	_free([first, second, third])

func test_quick_match_any_with_any_is_ten_minutes() -> void:
	MemoryBackend.clear()
	var first := _quick_session("first")
	var second := _quick_session("second")
	first._quick_args = first._armies(StandardSetup.army())
	first._quick_args.merge({"time_ms": OnlineSession.QUICK_ANY, "rules": RuleSet.version()})
	await first._try_quick()
	await second.find_quick_match(StandardSetup.army(), OnlineSession.QUICK_ANY)
	check_eq(int(second.row.time_ms), 600000, "Any with Any: 10 minutes each")
	_free([first, second])

func test_quick_match_cancel() -> void:
	MemoryBackend.clear()
	var first := _quick_session("first")
	var second := _quick_session("second")
	first._quick_args = first._armies(StandardSetup.army())
	first._quick_args.merge({"time_ms": 0, "rules": RuleSet.version()})
	await first._try_quick()
	await first.cancel_quick_match()
	check(first.code == "" and not first.looking, "Stopped looking")
	second._quick_args = second._armies(StandardSetup.army())
	second._quick_args.merge({"time_ms": 0, "rules": RuleSet.version()})
	await second._try_quick()
	check_eq(second.code, "", "Nobody left in the queue to pair with")
	_free([first, second])

func test_quick_match_checks_armies() -> void:
	MemoryBackend.clear()
	var first := _quick_session("first")
	var greedy := Army.new()
	greedy.place(load("res://data/pieces/king.tres"), Vector2i(4, 0))
	for file in [0, 1, 2, 3, 5, 6, 7]:
		greedy.place(load("res://data/pieces/queen.tres"), Vector2i(file, 0))
	var found := await first.find_quick_match(greedy, 0)
	check(not found.ok and "army rules" in found.error, "A rule-breaking army can't queue: " + found.error)
	first.free()

func test_report_opponent() -> void:
	var pair: Array = await _started_game()
	var host: OnlineSession = pair[0]
	var guest: OnlineSession = pair[1]
	await guest.post_chat("something rude")
	await host.poll()
	var reported := await host.report_opponent()
	check(reported.ok, "Reported: " + reported.error)
	check_eq(MemoryBackend.reports.size(), 1, "One report kept")
	check_eq(MemoryBackend.reports[0].reported, "guest", "Against the guest")
	check_eq(MemoryBackend.reports[0].chat[0].text, "something rude", "With the chat")
	var again := await host.report_opponent()
	check(not again.ok and "already" in again.error, "Only once per game")
	_free(pair)

func test_lobby_quick_match() -> void:
	MemoryBackend.clear()
	var lobby: Node = load("res://scenes/online/online_lobby.tscn").instantiate()
	var backend := MemoryBackend.new()
	lobby.backend = backend
	lobby.player_id = "lobby"
	_root().add_child(lobby)
	var ready_sessions := []
	lobby.game_ready.connect(func(session: OnlineSession) -> void: ready_sessions.append(session))
	lobby.quick_time_pick.select(0)
	lobby.quick_match()
	await get_tree_frames(2)
	check(lobby.waiting.visible and not lobby.get_node("%CodeCard").visible, "Waiting, with no code to share")
	check_eq(lobby.get_node("%WaitLabel").text, "Looking for an opponent...", "Says it's looking")
	var other := _quick_session("other")
	var found := await other.find_quick_match(StandardSetup.army(), 300000)
	check(found.ok, "The other player is paired with the waiting one")
	# The lobby checks the queue every 2 seconds.
	var waited := 0.0
	while ready_sessions.is_empty() and waited < 5.0:
		await (Engine.get_main_loop() as SceneTree).create_timer(0.2).timeout
		waited += 0.2
	check_eq(ready_sessions.size(), 1, "The lobby's game starts")
	if not ready_sessions.is_empty():
		check_eq((ready_sessions[0] as OnlineSession).code, other.code, "The same game")
	lobby.free()
	other.free()
	backend.free()

# --- Bonus time and live counts ----------------------------------------------------

func test_time_choices_are_the_full_set() -> void:
	var names := OnlineSession.TIME_CONTROLS.map(func(c: Array) -> String: return c[0])
	check_eq(names, ["No time limit", "1+0", "1+1", "2+1", "3+0", "3+2", "5+0", "5+3", "10+0", "10+5",
			"15+10", "30+0", "30+20"], "Mac's full set, in order")
	for control: Array in OnlineSession.TIME_CONTROLS:
		if control[1] > 0:
			check_eq(control[0], "%d+%d" % [control[1] / 60000, control[2] / 1000], "Name matches the times")

func test_bonus_is_added_after_each_move() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var guest := _session("guest")
	var created := await host.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 180000, false, 2000)
	check(created.ok, "3+2 can be created: " + created.error)
	await guest.join_game(host.code, StandardSetup.army())
	await host.poll()
	check_eq(host.increment_ms(), 2000, "Both see the bonus")
	MemoryBackend.clock_offset_ms = 10000
	host.turn_started_ms = Time.get_ticks_msec() - 10000
	await host.send_move("e2-e4", false)
	check(absi(int(host.row.white_ms) - (180000 - 10000 + 2000)) < 200, "10 s used, 2 s back: %d left" % int(host.row.white_ms))
	_free([host, guest])

func test_only_listed_times_can_be_used() -> void:
	MemoryBackend.clear()
	var host := _session("host")
	var odd := await host.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 180000, false, 5000)
	check(not odd.ok, "3+5 isn't one of the choices")
	var old := await host.create_game(StandardSetup.army(), OnlineSession.SIDE_WHITE, 900000, false, 0)
	check(not old.ok, "15+0 was dropped")
	host.free()

func test_quick_match_needs_the_same_bonus() -> void:
	MemoryBackend.clear()
	var first := _quick_session("first")
	var second := _quick_session("second")
	var third := _quick_session("third")
	first._quick_args = first._armies(StandardSetup.army())
	first._quick_args.merge({"time_ms": 180000, "increment_ms": 2000, "rules": RuleSet.version()})
	await first._try_quick()
	second._quick_args = second._armies(StandardSetup.army())
	second._quick_args.merge({"time_ms": 180000, "increment_ms": 0, "rules": RuleSet.version()})
	await second._try_quick()
	check(first.code == "" and second.code == "", "3+2 and 3+0 don't fit")
	var found := await third.find_quick_match(StandardSetup.army(), 180000, 2000)
	check(found.ok and third.code != "", "3+2 meets 3+2")
	check_eq(int(third.row.increment_ms), 2000, "With the bonus")
	_free([first, second, third])

func test_quick_match_any_takes_the_bonus_too() -> void:
	MemoryBackend.clear()
	var first := _quick_session("first")
	var second := _quick_session("second")
	first._quick_args = first._armies(StandardSetup.army())
	first._quick_args.merge({"time_ms": 600000, "increment_ms": 5000, "rules": RuleSet.version()})
	await first._try_quick()
	await second.find_quick_match(StandardSetup.army(), OnlineSession.QUICK_ANY)
	check(int(second.row.time_ms) == 600000 and int(second.row.increment_ms) == 5000, "Any plays the other's 10+5")
	_free([first, second])

func test_online_counts() -> void:
	MemoryBackend.clear()
	var watcher := _session("watcher")
	var counts := await watcher.online_counts()
	check_eq(counts, {"online": 1, "looking": 0}, "Just me, on Play online")
	var waiter := _quick_session("waiter")
	waiter._quick_args = waiter._armies(StandardSetup.army())
	waiter._quick_args.merge({"time_ms": 300000, "rules": RuleSet.version()})
	await waiter._try_quick()
	counts = await watcher.online_counts()
	check_eq(counts, {"online": 2, "looking": 1}, "One more, looking for a quick match")
	MemoryBackend.clock_offset_ms = 61000
	counts = await watcher.online_counts()
	check_eq(counts, {"online": 1, "looking": 0}, "Gone quiet for a minute: not counted")
	check_eq(LOBBY.counts_text(1, 0), "1 player online · 0 looking for a quick match", "One player")
	check_eq(LOBBY.counts_text(12, 3), "12 players online · 3 looking for a quick match", "Several")
	_free([watcher, waiter])

func test_lobby_shows_the_counts() -> void:
	MemoryBackend.clear()
	var lobby: Node = load("res://scenes/online/online_lobby.tscn").instantiate()
	var backend := MemoryBackend.new()
	lobby.backend = backend
	lobby.player_id = "lobby"
	_root().add_child(lobby)
	await lobby.refresh_counts()
	check(lobby.counts_label.visible, "The counts show")
	check_eq(lobby.counts_label.text, "1 player online · 0 looking for a quick match", "Counting me")
	check_eq(lobby.quick_time_pick.get_item_text(0), "Any", "Quick match: Any first")
	check_eq(lobby.quick_time_pick.item_count, OnlineSession.TIME_CONTROLS.size() + 1, "Then every time")
	lobby.free()
	backend.free()
