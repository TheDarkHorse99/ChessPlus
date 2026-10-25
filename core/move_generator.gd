class_name MoveGenerator
extends RefCounted

## Works out which moves are possible in a position.
## Driven entirely by each piece's MoveRule data; no piece is special-cased by name.

## The moves the side to move can actually play: pseudo-legal moves that don't
## leave any of its royal pieces attacked.
static func legal_moves(state: GameState) -> Array[Move]:
	var enemy := Piece.other_team(state.side_to_move)
	var table := state.attack_table(enemy)
	var royals := _royal_squares(state.board, state.side_to_move)
	var legal: Array[Move] = []
	for move in pseudo_legal_moves(state):
		if _keeps_royals_safe(state, move, royals, enemy, table):
			legal.append(move)
	return legal

## True if `move`, one of the side to move's pseudo-legal moves, is legal (it
## doesn't leave a royal piece attacked). Quicker than looking for it among
## legal_moves when only a few moves need checking.
static func is_legal(state: GameState, move: Move) -> bool:
	var enemy := Piece.other_team(state.side_to_move)
	return _keeps_royals_safe(state, move, _royal_squares(state.board, state.side_to_move), enemy, state.attack_table(enemy))

## Try `move`: true if none of the mover's royal pieces (on `royals` before it)
## is attacked afterwards.
static func _keeps_royals_safe(state: GameState, move: Move, royals: Array[Vector2i], enemy: Piece.Team, table: Array) -> bool:
	var board := state.board
	state.make_move(move)
	# A piece put to sleep can't capture next turn, so its attacks don't count
	# (Mac): it's lifted off the board while looking.
	if move.frozen:
		board.set_piece(move.to, null)
	var safe := true
	for square in royals:
		var now_at := move.lands_on() if square == move.from else square
		if attacked_with(board, now_at, enemy, table):
			safe = false
			break
	if move.frozen:
		board.set_piece(move.to, move.frozen)
	state.undo_move(move)
	return safe

## Every move the side to move's pieces can make by their movement rules,
## without checking whether it leaves their royal piece attacked. With
## `captures_only`, just the captures (and shield breaks): the practice bot uses
## that to look at captures without paying for every quiet move too.
static func pseudo_legal_moves(state: GameState, captures_only := false) -> Array[Move]:
	var board := state.board
	var moves: Array[Move] = []
	var pieces := board.pieces_of(state.side_to_move)
	# A piece put to sleep by the opponent's Song of Slumber can't move this turn.
	var frozen := state.frozen_piece()
	for from: Vector2i in pieces:
		var piece: Piece = pieces[from]
		if piece == frozen:
			continue
		var first_new := moves.size()
		for rule in piece.def.move_rules:
			_add_rule_moves(state, from, piece, rule, moves, captures_only)
		if not captures_only and piece.def.is_king_type() and not piece.has_moved:
			_add_castling_moves(board, state.rules, from, piece, moves)
		if piece.can_use_ability():
			_add_ability_moves(state, from, piece, moves, first_new, captures_only)
	if not captures_only:
		_add_haunt_moves(state, moves)
	return _apply_guards(state, moves)

## Haunt: a lost Ghost whose ability is unused can come back onto any empty
## square of the board (Mac). One Ghost's moves if there are several: they'd all
## be the same.
static func _add_haunt_moves(state: GameState, moves: Array[Move]) -> void:
	var ghosts := haunting_ghosts(state, state.side_to_move)
	if ghosts.is_empty():
		return
	var ghost: Piece = ghosts[0]
	var board := state.board
	for rank in range(board.height):
		for file in range(board.width):
			var square := Vector2i(file, rank)
			if board.is_empty(square):
				var haunt := Move.new(square, square, ghost)
				haunt.ability = PieceDef.Ability.HAUNT
				moves.append(haunt)

## `team`'s lost pieces that can still use Haunt to come back: a Ghost that
## moved at least once before it was captured (Mac's rule for every ability).
static func haunting_ghosts(state: GameState, team: Piece.Team) -> Array[Piece]:
	var ghosts: Array[Piece] = []
	for piece: Piece in state.lost[team]:
		if piece.def.ability == PieceDef.Ability.HAUNT and piece.can_use_ability():
			ghosts.append(piece)
	return ghosts

## The enemy's Squires and Jesters change the side to move's captures: a
## protected piece (a Knight on a square a Squire could reach) can't be
## captured, and a capture of a piece a Jester could reach becomes a swap in
## which the Jester is captured instead. Pawn types and kings are never swapped.
## If more than one Jester could take the hit, the attacking player chooses
## which (Mac): the capture becomes one move per Jester.
static func _apply_guards(state: GameState, moves: Array[Move]) -> Array[Move]:
	var board := state.board
	var defenders := board.pieces_of(Piece.other_team(state.side_to_move))
	var protected := {}
	var jesters := []
	for square: Vector2i in defenders:
		var guard: Piece = defenders[square]
		if not guard.def.protects.is_empty():
			for reached: Vector2i in pattern_squares(board, square, guard):
				var other := board.get_piece(reached)
				if other and other.team == guard.team and other.def.id in guard.def.protects:
					protected[reached] = true
		if guard.def.decoy:
			jesters.append([square, guard, reach_squares(board, square, guard)])
	if protected.is_empty() and jesters.is_empty():
		return moves
	var kept: Array[Move] = []
	for move in moves:
		if move.captured == null:
			kept.append(move)
			continue
		if protected.has(move.capture_square):
			continue
		var target := move.captured
		var reaching := []
		if not target.def.is_pawn_type() and not target.def.is_king_type() and not target.def.decoy:
			for jester: Array in jesters:
				if (jester[2] as Dictionary).has(move.capture_square):
					reaching.append(jester)
		if reaching.is_empty():
			kept.append(move)
			continue
		# Copies first, while `move` still aims at the target.
		var options: Array[Move] = [move]
		for i in range(1, reaching.size()):
			options.append(move.copy())
		for i in reaching.size():
			var option := options[i]
			option.decoy_piece = target
			option.decoy_square = reaching[i][0]
			option.captured = reaching[i][1]
			option.decoy_choice = reaching.size() > 1
			kept.append(option)
	return kept

## The squares `piece` (on `from`) could move or capture to by its rules, as the
## board stands: each line up to and including the first piece it meets. Used
## for the Squire's and Jester's ranges. Returns {square: true}.
static func reach_squares(board: Board, from: Vector2i, piece: Piece) -> Dictionary:
	var squares := {}
	for rule in piece.def.move_rules:
		if not rule.path.is_empty():
			for steps: Array in rule.path_variants():
				var end := _path_end(board, from, steps, piece.team)
				if end != Board.NO_SQUARE:
					squares[end] = true
			continue
		var limit := _step_limit(rule, piece, board)
		for dir in rule.directions:
			var step := _orient(dir, piece.team)
			var to := from
			for i in range(limit):
				if _leap_blocked(board, to, step, piece.team):
					break
				to += step
				if not board.in_bounds(to):
					break
				if i >= rule.leap_steps:
					squares[to] = true
				if not board.is_empty(to) and (i >= rule.leap_steps or stops_jumps(board.get_piece(to), piece.team)):
					break
	return squares

## Every square in the piece's move pattern from `from`, as if nothing stood in
## the way (on the board, though). The Squire protects Knights anywhere in its
## pattern, even with pieces in between (Mac, Oct 2026).
static func pattern_squares(board: Board, from: Vector2i, piece: Piece) -> Dictionary:
	var squares := {}
	for rule in piece.def.move_rules:
		if not rule.path.is_empty():
			for steps: Array in rule.path_variants():
				var to := from
				for step: Vector2i in steps:
					to += _orient(step, piece.team)
				if board.in_bounds(to):
					squares[to] = true
			continue
		var limit := _step_limit(rule, piece, board)
		for dir in rule.directions:
			var step := _orient(dir, piece.team)
			var to := from
			for i in range(limit):
				to += step
				if not board.in_bounds(to):
					break
				if i >= rule.leap_steps:
					squares[to] = true
	return squares

## Why the piece on `from` can't move or capture onto `to`, if it's down to a
## Parapet or a Squire (Mac: they react when that's tried): the square of the
## Squire protecting a Knight on `to`, or of a Parapet in the way (without it,
## the piece could go there). NO_SQUARE otherwise.
static func blocker(state: GameState, from: Vector2i, to: Vector2i) -> Vector2i:
	var board := state.board
	var piece := board.get_piece(from)
	if piece == null:
		return Board.NO_SQUARE
	var target := board.get_piece(to)
	if target and target.team != piece.team:
		var guards := board.pieces_of(target.team)
		for square: Vector2i in guards.keys():
			var guard: Piece = guards[square]
			if target.def.id in guard.def.protects and pattern_squares(board, square, guard).has(to):
				return square
	# The opponent's Parapets, each tried two ways: taken away (it was in the
	# way of a slide), and turned into an ordinary piece (it stopped a leap, or
	# a Cannon firing over it).
	var parapets: Array[Vector2i] = []
	var enemy_pieces := board.pieces_of(Piece.other_team(piece.team))
	for square: Vector2i in enemy_pieces.keys():
		if enemy_pieces[square].def.blocks_jumps() and square != to:
			parapets.append(square)
	for square in parapets:
		var parapet := board.get_piece(square)
		var real_def := parapet.def
		var plain: PieceDef = real_def.duplicate()
		plain.keywords &= ~PieceDef.Keyword.WALL
		for variant in [null, plain]:
			if variant == null:
				board.set_piece(square, null)
			else:
				parapet.def = variant
			var moves: Array[Move] = []
			for rule in piece.def.move_rules:
				_add_rule_moves(state, from, piece, rule, moves)
			parapet.def = real_def
			board.set_piece(square, parapet)
			if moves.any(func(m: Move) -> bool: return m.to == to):
				return square
	return Board.NO_SQUARE

## The squares a leap of `step` passes over on its way (not where it lands), as
## offsets from where it starts: none for a one-square step; for a straight or
## diagonal leap, the squares in between; for a Knight-like leap (Mac's rule),
## the long leg first, then the short one: (1, 2) passes (0, 1) and (0, 2).
## Worked out for every step up to 16 squares when the script loads (not as
## needed: the practice bot searches on another thread at the same time).
static var _passed_cache := _all_passed_offsets()

static func passed_offsets(step: Vector2i) -> Array:
	if _passed_cache.has(step):
		return _passed_cache[step]
	return _work_out_passed(step)

static func _all_passed_offsets() -> Dictionary:
	var all := {}
	for x in range(-16, 17):
		for y in range(-16, 17):
			all[Vector2i(x, y)] = _work_out_passed(Vector2i(x, y))
	return all

static func _work_out_passed(step: Vector2i) -> Array:
	var passed := []
	var ax := absi(step.x)
	var ay := absi(step.y)
	var sx := signi(step.x)
	var sy := signi(step.y)
	if ax == ay or ax == 0 or ay == 0:
		for k in range(1, maxi(ax, ay)):
			passed.append(Vector2i(sx * k, sy * k))
	elif ay > ax:
		for k in range(1, ay + 1):
			passed.append(Vector2i(0, sy * k))
		for k in range(1, ax):
			passed.append(Vector2i(sx * k, step.y))
	else:
		for k in range(1, ax + 1):
			passed.append(Vector2i(sx * k, 0))
		for k in range(1, ay):
			passed.append(Vector2i(step.x, sy * k))
	return passed

## True if a leap of `step` from `from`, by a piece of `team`, would pass over
## one of the other side's Parapets (Mac: a Parapet only stops its opponents'
## jumps, never its own side's).
static func _leap_blocked(board: Board, from: Vector2i, step: Vector2i, team: Piece.Team) -> bool:
	if absi(step.x) <= 1 and absi(step.y) <= 1:
		return false
	for offset: Vector2i in passed_offsets(step):
		if stops_jumps(board.get_piece(from + offset), team):
			return true
	return false

## True if `piece` is a Parapet that stops `team`'s pieces jumping over it (it's
## on the other side).
static func stops_jumps(piece: Piece, team: Piece.Team) -> bool:
	return piece != null and piece.def.blocks_jumps() and piece.team != team

## A piece's special-ability moves. Crack Shot: a copy of each of its captures
## (from `first_new` on in `moves`) in which it doesn't move. Raise Dead: one move
## per type of lost piece that can come back. Song of Slumber: one per enemy
## piece (not a king) it could reach. Full Moon: one (it changes where it stands).
## (Haunt is used from the lost pieces: see _add_haunt_moves.)
static func _add_ability_moves(state: GameState, from: Vector2i, piece: Piece, moves: Array[Move], first_new: int, captures_only: bool) -> void:
	match piece.def.ability:
		PieceDef.Ability.CRACK_SHOT:
			for i in range(first_new, moves.size()):
				var capture: Move = moves[i]
				if not capture.is_capture() or capture.promotion:
					continue
				var shot := Move.new(capture.from, capture.to, piece, capture.captured)
				shot.capture_square = capture.capture_square
				shot.shield_target = capture.shield_target
				shot.ability = PieceDef.Ability.CRACK_SHOT
				moves.append(shot)
		PieceDef.Ability.SONG_OF_SLUMBER:
			if captures_only:
				return
			for square: Vector2i in reach_squares(state.board, from, piece):
				var target := state.board.get_piece(square)
				if target and target.team != piece.team and not target.def.is_king_type():
					var song := Move.new(from, square, piece)
					song.ability = PieceDef.Ability.SONG_OF_SLUMBER
					song.frozen = target
					moves.append(song)
		PieceDef.Ability.FULL_MOON:
			if captures_only or piece.def.transforms_into == null:
				return
			var change := Move.new(from, from, piece)
			change.ability = PieceDef.Ability.FULL_MOON
			moves.append(change)
		PieceDef.Ability.RAISE_DEAD:
			if captures_only:
				return
			for def in raisable_defs(state, piece.team):
				var raise := Move.new(from, from, piece)
				raise.ability = PieceDef.Ability.RAISE_DEAD
				for lost_piece: Piece in state.lost[piece.team]:
					if lost_piece.starting_def() == def:
						raise.raised_from_lost = lost_piece
						break
				# Comes back as if the game had just started (shield, ability and all),
				# but it has "moved": it can't castle.
				raise.raised = Piece.new(def, piece.team)
				raise.raised.has_moved = true
				moves.append(raise)

## The kinds of `team`'s lost pieces that Raise Dead could bring back: not pawn
## types and not Necromancers (Raise Dead pieces). Each listed once, as the type
## it started the game as (a wolf comes back as a Werewolf).
static func raisable_defs(state: GameState, team: Piece.Team) -> Array[PieceDef]:
	var defs: Array[PieceDef] = []
	for piece: Piece in state.lost[team]:
		var def := piece.starting_def()
		if def.is_pawn_type() or def.ability == PieceDef.Ability.RAISE_DEAD or defs.has(def):
			continue
		defs.append(def)
	return defs

## True if any of `team`'s royal pieces is attacked, using the game's saved
## attack table (faster than is_in_check, which works it out from the board).
static func in_check(state: GameState, team: Piece.Team) -> bool:
	var enemy := Piece.other_team(team)
	var table := state.attack_table(enemy)
	for square in _royal_squares(state.board, team):
		if attacked_with(state.board, square, enemy, table):
			return true
	return false

## True if any of `team`'s royal pieces is attacked.
static func is_in_check(board: Board, team: Piece.Team) -> bool:
	var enemy := Piece.other_team(team)
	var enemy_defs := _defs_on_board(board, enemy)
	for square in _royal_squares(board, team):
		if _is_attacked_by(board, square, enemy, enemy_defs):
			return true
	return false

## True if a piece of `by_team` could capture on `square`.
static func is_attacked(board: Board, square: Vector2i, by_team: Piece.Team) -> bool:
	return _is_attacked_by(board, square, by_team, _defs_on_board(board, by_team))

static func _is_attacked_by(board: Board, square: Vector2i, by_team: Piece.Team, defs: Array[PieceDef]) -> bool:
	return attacked_with(board, square, by_team, attack_table(by_team, defs))

## How `by_team`'s piece types (`defs`) can capture, as [lines, unusual]:
##   lines: the straight lines they capture along, grouped by direction so each
##     line only has to be walked once. Each entry is
##     [step, farthest reach, [[piece type, rule], ...], any hopping rule?].
##   unusual: [piece type, rule] pairs for leaping and bent-path rules, which are
##     checked from each such piece instead (see MoveRule.is_unusual).
## Build it once and reuse it (GameState.attack_table does).
static func attack_table(by_team: Piece.Team, defs: Array[PieceDef]) -> Array:
	var by_step := {}
	var unusual := []
	for def in defs:
		for rule in def.move_rules:
			if rule.mode == MoveRule.Mode.MOVE_ONLY:
				continue
			if rule.is_unusual():
				unusual.append([def, rule])
				continue
			var reach := UNLIMITED if rule.max_steps == 0 else maxi(rule.max_steps, rule.first_move_max_steps)
			for dir in rule.directions:
				var step := _orient(dir, by_team)
				if not by_step.has(step):
					by_step[step] = [step, 0, [], false]
				var entry: Array = by_step[step]
				entry[1] = maxi(entry[1], reach)
				entry[2].append([def, rule])
				if rule.captures_by_hopping:
					entry[3] = true
	return [by_step.values(), unusual]

## Further than any board is wide: "slides until blocked".
const UNLIMITED := 1000

## True if a piece of `by_team` could capture on `square`. Works backwards from
## the square: walk each line in `table` (from attack_table) and look at the
## first piece met. If it's an attacking piece type for that line, on the right
## team and close enough for its step limit, the square is attacked. For a
## hopping rule the first piece met is the screen, so look one piece further.
static func attacked_with(board: Board, square: Vector2i, by_team: Piece.Team, table: Array) -> bool:
	for entry: Array in table[0]:
		var step: Vector2i = entry[0]
		var reach: int = entry[1]
		var attackers: Array = entry[2]
		var has_hop: bool = entry[3]
		var pos := square
		var screens := 0
		for distance in range(1, reach + 1):
			pos -= step
			if not board.in_bounds(pos):
				break
			# A leap from here onwards would pass over a Parapet: nothing further
			# along this line can attack.
			if _leap_blocked(board, pos, step, by_team):
				break
			var piece := board.get_piece(pos)
			if piece == null:
				continue
			if piece.team == by_team:
				for attacker: Array in attackers:
					var rule: MoveRule = attacker[1]
					if piece.def == attacker[0] and rule.captures_by_hopping == (screens == 1) \
							and distance <= _step_limit(rule, piece, board):
						return true
			screens += 1
			# An opponent's Parapet can't be a Cannon's screen.
			if screens > 1 or not has_hop or stops_jumps(piece, by_team):
				break
	# Leaping and bent-path pieces: check each one directly.
	var unusual: Array = table[1]
	if unusual.is_empty():
		return false
	var pieces := board.pieces_of(by_team)
	for pair: Array in unusual:
		for from: Vector2i in pieces:
			var piece: Piece = pieces[from]
			if piece.def == pair[0] and _rule_reaches(board, from, piece, pair[1], square):
				return true
	return false

## True if `piece` (on `from`) could capture on `square` with `rule`, a leaping
## or bent-path rule, as things stand on the board.
static func _rule_reaches(board: Board, from: Vector2i, piece: Piece, rule: MoveRule, square: Vector2i) -> bool:
	if not rule.path.is_empty():
		for steps: Array in rule.path_variants():
			if from + _orient(MoveRule.path_offset(steps), piece.team) == square 					and _path_end(board, from, steps, piece.team) == square:
				return true
		return false
	var delta := square - from
	var limit := _step_limit(rule, piece, board)
	for dir in rule.directions:
		var step := _orient(dir, piece.team)
		# How many steps along this line `square` is (0 if it isn't on it).
		var count := delta.x / step.x if step.x != 0 else delta.y / step.y
		if count <= rule.leap_steps or count > limit or step * count != delta:
			continue
		for i in range(1, count + 1):
			if _leap_blocked(board, from + step * (i - 1), step, piece.team):
				return false
		for i in range(1, count):
			var between := board.get_piece(from + step * i)
			if stops_jumps(between, piece.team) and i <= rule.leap_steps:
				return false
			if i <= rule.leap_steps:
				if rule.leap_over == MoveRule.LeapOver.OWN_PIECE and (between == null or between.team != piece.team):
					return false
			elif between != null:
				return false
		return true
	return false

## Follow a bent path from `from`. Returns where it ends, or NO_SQUARE if it
## leaves the board or a square on the way (before the last) isn't empty.
static func _path_end(board: Board, from: Vector2i, steps: Array, team: Piece.Team) -> Vector2i:
	var pos := from
	for i in steps.size():
		pos += _orient(steps[i], team)
		if not board.in_bounds(pos):
			return Board.NO_SQUARE
		if i < steps.size() - 1 and not board.is_empty(pos):
			return Board.NO_SQUARE
	return pos

## Walks each direction of one rule, one step at a time, adding moves as it goes.
static func _add_rule_moves(state: GameState, from: Vector2i, piece: Piece, rule: MoveRule, moves: Array[Move], captures_only := false) -> void:
	var board := state.board
	if not rule.path.is_empty():
		_add_path_moves(state, from, piece, rule, moves, captures_only)
		return
	var limit := _step_limit(rule, piece, board)
	# Worked out once per rule rather than on every square.
	var pawn_like := piece.def.is_pawn_type()
	var can_en_passant := pawn_like and rule.mode != MoveRule.Mode.MOVE_ONLY and not state.en_passant_squares.is_empty()
	var quiet_moves := rule.mode != MoveRule.Mode.CAPTURE_ONLY and not captures_only
	for dir in rule.directions:
		var step := _orient(dir, piece.team)
		var to := from
		# Empty squares walked over so far (only pawn-like pieces need them, for
		# en passant).
		var passed: Array[Vector2i] = Move.NO_SQUARES
		if pawn_like:
			passed = []
		for i in range(limit):
			if _leap_blocked(board, to, step, piece.team):
				break
			to += step
			if not board.in_bounds(to):
				break
			# Leapt squares: can't stop there, and they don't block (but the Rogue
			# can only leap one of its own pieces, and nothing leaps a Parapet).
			if i < rule.leap_steps:
				var leapt := board.get_piece(to)
				if stops_jumps(leapt, piece.team):
					break
				if rule.leap_over == MoveRule.LeapOver.OWN_PIECE:
					var over := board.get_piece(to)
					if over == null or over.team != piece.team:
						break
				continue
			var target := board.get_piece(to)
			if target == null:
				var en_passant: Move = _en_passant_capture(state, from, to, piece, rule) if can_en_passant else null
				if en_passant:
					_append(state, en_passant, moves)
				elif quiet_moves:
					var move := Move.new(from, to, piece)
					if not passed.is_empty():
						move.skipped_squares = passed.duplicate()
					_append(state, move, moves)
				if pawn_like:
					passed.append(to)
				continue
			# Something is in the way. A hopping rule jumps it to look for a capture;
			# otherwise capture it if it's an enemy and the rule allows. Stop either way.
			if rule.captures_by_hopping:
				# An opponent's Parapet can't be a Cannon's screen.
				if rule.mode != MoveRule.Mode.MOVE_ONLY and not stops_jumps(target, piece.team):
					_add_hop_capture(state, from, to, step, limit - i - 1, piece, moves)
			elif target.team != piece.team and rule.mode != MoveRule.Mode.MOVE_ONLY:
				_append(state, _capture(from, to, piece, target), moves)
			break

## A bent-path rule's moves: each version of the path whose squares on the way
## are empty ends in a move (empty square) or a capture (enemy piece).
static func _add_path_moves(state: GameState, from: Vector2i, piece: Piece, rule: MoveRule, moves: Array[Move], captures_only: bool) -> void:
	for steps: Array in rule.path_variants():
		var to := _path_end(state.board, from, steps, piece.team)
		if to == Board.NO_SQUARE:
			continue
		var target := state.board.get_piece(to)
		if target == null:
			if rule.mode != MoveRule.Mode.CAPTURE_ONLY and not captures_only:
				_append(state, Move.new(from, to, piece), moves)
		elif target.team != piece.team and rule.mode != MoveRule.Mode.MOVE_ONLY:
			_append(state, _capture(from, to, piece, target), moves)

## A capture of `target`, or just a shield break if it still has a Shield.
static func _capture(from: Vector2i, to: Vector2i, piece: Piece, target: Piece) -> Move:
	if target.has_active_shield():
		var hit := Move.new(from, to, piece)
		hit.shield_target = target
		return hit
	return Move.new(from, to, piece, target)

## Having reached a screen at `screen`, keep going (up to `steps_left` more squares)
## and capture the first piece beyond it, if it's an enemy.
static func _add_hop_capture(state: GameState, from: Vector2i, screen: Vector2i, step: Vector2i, steps_left: int, piece: Piece, moves: Array[Move]) -> void:
	var to := screen
	for i in range(steps_left):
		to += step
		if not state.board.in_bounds(to):
			return
		var target := state.board.get_piece(to)
		if target == null:
			continue
		if target.team != piece.team:
			_append(state, _capture(from, to, piece, target), moves)
		return

## Adds a move to the list. A promoting piece reaching the far rank must promote,
## so instead of the plain move this adds one move per promotion option.
static func _append(state: GameState, move: Move, moves: Array[Move]) -> void:
	var options := state.rules.promotion_options
	# A shield break doesn't move the piece, so it can't promote.
	if not move.piece.def.can_promote() or move.breaks_shield() or options.is_empty() \
			or move.to.y != _far_rank(state.board, move.piece.team):
		moves.append(move)
		return
	for option in options:
		var promotion := Move.new(move.from, move.to, move.piece, move.captured)
		promotion.capture_square = move.capture_square
		promotion.promotion = option
		moves.append(promotion)

## The rank farthest from the team's side of the board.
static func _far_rank(board: Board, team: Piece.Team) -> int:
	return board.height - 1 if team == Piece.Team.WHITE else 0

## Castling: the king moves two squares toward an unmoved partner on the same rank,
## with only empty squares between them, and the partner lands on the square the
## king crossed. Not allowed out of check or across an attacked square. (Landing
## in check is ruled out by the normal legality filter.)
static func _add_castling_moves(board: Board, rules: GameRules, king_pos: Vector2i, king: Piece, moves: Array[Move]) -> void:
	var enemy := Piece.other_team(king.team)
	var enemy_defs: Array[PieceDef] = []
	var checked_for_check := false
	for dir in [-1, 1]:
		var partner_pos := _first_piece_along(board, king_pos, Vector2i(dir, 0))
		if partner_pos == Board.NO_SQUARE or absi(partner_pos.x - king_pos.x) < 3:
			continue
		var partner := board.get_piece(partner_pos)
		if partner.team != king.team or not partner.def.has_castle() or partner.has_moved:
			continue
		if rules.castling_partner_in_corner and not _is_back_corner(board, partner_pos, king.team):
			continue
		# Only look for attacks once castling is actually possible: it's slow-ish.
		if not checked_for_check:
			enemy_defs = _defs_on_board(board, enemy)
			if _is_attacked_by(board, king_pos, enemy, enemy_defs):
				return
			checked_for_check = true
		var crossed := king_pos + Vector2i(dir, 0)
		if _is_attacked_by(board, crossed, enemy, enemy_defs):
			continue
		var move := Move.new(king_pos, king_pos + Vector2i(dir * 2, 0), king)
		move.partner = partner
		move.partner_from = partner_pos
		move.partner_to = crossed
		moves.append(move)

## True if `square` is a corner of `team`'s back rank.
static func _is_back_corner(board: Board, square: Vector2i, team: Piece.Team) -> bool:
	var back_rank := 0 if team == Piece.Team.WHITE else board.height - 1
	return square.y == back_rank and (square.x == 0 or square.x == board.width - 1)

## The first occupied square from `from` (not counting it) in direction `step`,
## or NO_SQUARE if there's nothing before the edge of the board.
static func _first_piece_along(board: Board, from: Vector2i, step: Vector2i) -> Vector2i:
	var pos := from + step
	while board.in_bounds(pos):
		if not board.is_empty(pos):
			return pos
		pos += step
	return Board.NO_SQUARE

## If moving to the empty square `to` would capture en passant, returns that
## capture, otherwise null. Both pieces must be pawn types.
static func _en_passant_capture(state: GameState, from: Vector2i, to: Vector2i, piece: Piece, rule: MoveRule) -> Move:
	if rule.mode == MoveRule.Mode.MOVE_ONLY or not piece.def.is_pawn_type():
		return null
	if not state.en_passant_squares.has(to):
		return null
	var victim := state.board.get_piece(state.en_passant_victim)
	if victim == null or victim.team == piece.team or not victim.def.is_pawn_type():
		return null
	var move := Move.new(from, to, piece, victim)
	move.capture_square = state.en_passant_victim
	return move

## How many steps this rule allows right now. 0 in the data means "unlimited",
## which on a finite board is never more than the board's longest side.
static func _step_limit(rule: MoveRule, piece: Piece, board: Board) -> int:
	var steps := rule.max_steps
	if rule.first_move_max_steps > 0 and not piece.has_moved:
		steps = rule.first_move_max_steps
	if steps == 0:
		steps = maxi(board.width, board.height)
	return steps

## Directions are written from the owner's point of view. Black faces the other way,
## so its rank direction is flipped.
static func _orient(dir: Vector2i, team: Piece.Team) -> Vector2i:
	if team == Piece.Team.BLACK:
		return Vector2i(dir.x, -dir.y)
	return dir

## Each kind of piece the team has on the board, listed once.
static func _defs_on_board(board: Board, team: Piece.Team) -> Array[PieceDef]:
	var defs: Array[PieceDef] = []
	for piece: Piece in board.pieces_of(team).values():
		if not defs.has(piece.def):
			defs.append(piece.def)
	return defs

static func _royal_squares(board: Board, team: Piece.Team) -> Array[Vector2i]:
	var squares: Array[Vector2i] = []
	var pieces := board.pieces_of(team)
	for square: Vector2i in pieces:
		if pieces[square].def.is_king_type():
			squares.append(square)
	return squares
