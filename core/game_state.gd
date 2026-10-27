class_name GameState
extends RefCounted

## A game in progress: the board plus everything else the rules need to know.
## Moves are played with make_move and taken back with undo_move. Undo must
## happen in reverse order (last move made is the first one undone).

## How the game has ended, if it has. See outcome().
## KING_EXPOSED: the side NOT to move has its king attacked, which can only
## happen in the starting position (some army pairings leave Black's king
## attacked before White's first move). For now that side loses at once (Mac's
## temporary rule, Oct 2026; he'll design a real fix later).
enum Outcome { NONE, CHECKMATE, STALEMATE, FIFTY_MOVES, REPETITION, INSUFFICIENT_MATERIAL, KING_EXPOSED, SEVENTY_FIVE_MOVES }

var board: Board
var rules: GameRules
var side_to_move: Piece.Team = Piece.Team.WHITE
## Squares the last move's piece skipped over, where it can be captured en passant.
var en_passant_squares: Array[Vector2i] = []
## Where that piece now stands (the piece removed by an en passant capture).
var en_passant_victim: Vector2i = Board.NO_SQUARE
## Half-moves since the last capture or pawn-type move (100 = 50 moves each).
var halfmove_clock: int = 0
## True for a position set up from FEN, in testing mode or by an import: not
## a game's start, so White's quiet first move doesn't apply there.
var from_position := false
## Plies since the pieces on the board last changed: a capture (a shield
## break, a Ram's death and a Crack Shot count), a promotion, Raise Dead, a
## Ghost's Haunt return or a Werewolf's transformation. Pawn moves don't reset
## it. 150 (75 moves each) is an automatic draw (Mac's rule, Oct 2026),
## alongside the 50-move rule. FEN carries it as "unchanged=N" when it differs
## from the halfmove clock.
var change_clock: int = 0
## Starts at 1 and goes up after each Black move, as in FEN and PGN.
var fullmove_number: int = 1
## Every move made so far, oldest first. undo_move takes the last one off.
var history: Array[Move] = []
## Each team's lost pieces (indexed by Piece.Team), oldest first: captured, or
## removed by their own rules (a Ram that captured). Raise Dead brings them back.
var lost: Array = [[], []]
## Each team's attack table (see MoveGenerator.attack_table), worked out the first
## time it's needed. It covers every piece type that team has at that point plus
## every promotion choice, so it stays right for the rest of the game.
var _attack_tables: Array = [null, null]

func _init(p_board: Board, p_rules: GameRules) -> void:
	board = p_board
	rules = p_rules

## The legal moves for whoever's turn it is. Worked out once per position
## (the game screen asks again for every tap on a piece, the outcome, the move
## list...) and handed out as a fresh list each time, so changing the list
## (the practice bot reorders it) can't spoil the kept one.
func moves() -> Array[Move]:
	var key := _position_now()
	if key != _moves_key:
		_moves = MoveGenerator.legal_moves(self)
		_moves_key = key
	return _moves.duplicate()

var _moves: Array[Move] = []
var _moves_key := []

## What tells this position apart from others reached in the game, for keeping
## answers about it (see outcome() and moves()).
func _position_now() -> Array:
	return [_position_ids.back(), board.changes, side_to_move, halfmove_clock, change_clock, lost[0].size(), lost[1].size()]

## `team`'s attack table: the lines its pieces can capture along (cached).
func attack_table(team: Piece.Team) -> Array:
	if _attack_tables[team] == null:
		var defs: Array[PieceDef] = []
		for piece: Piece in board.pieces_of(team).values():
			if not defs.has(piece.def):
				defs.append(piece.def)
		for def in rules.promotion_options:
			if not defs.has(def):
				defs.append(def)
		# Lost pieces could come back (Raise Dead, Haunt), as what they started as.
		for piece: Piece in lost[team]:
			for def: PieceDef in [piece.def, piece.starting_def()]:
				if not defs.has(def):
					defs.append(def)
		# A piece that can change (Full Moon) attacks as its new form afterwards.
		for i in range(defs.size()):
			var form := defs[i].transforms_into
			if form and not defs.has(form):
				defs.append(form)
		_attack_tables[team] = MoveGenerator.attack_table(team, defs)
	return _attack_tables[team]

## The piece the opponent's Song of Slumber put to sleep: it can't move this
## turn. Null if the last move wasn't a Song of Slumber.
func frozen_piece() -> Piece:
	if history.is_empty():
		return null
	return history.back().frozen

## True if the side to move has a royal piece under attack.
func is_in_check() -> bool:
	return MoveGenerator.is_in_check(board, side_to_move)

## How the game has ended, or Outcome.NONE if it's still going. For CHECKMATE,
## the side to move is the one that lost; for KING_EXPOSED, the other side lost;
## every other outcome is a draw. Checkmate counts even if the mating move was
## also the 50th move.
func outcome() -> Outcome:
	var key := _position_now()
	if key == _outcome_key:
		return _outcome
	_outcome = _work_out_outcome()
	_outcome_key = key
	return _outcome

## outcome() is slow (it works out every legal move and looks back for
## repetitions) and the game screen asks for it many times after each move, so
## the answer is kept until the position changes: a move made or undone, a
## piece put on or taken off the board, or one added to the lost pieces.
var _outcome := Outcome.NONE
var _outcome_key := []
## A number for each position reached by make_move (the start's first): a new
## one for every move made, and undoing a move goes back to the one before, so
## trying moves (make, then undo) doesn't lose the outcome worked out for the
## position. With board.changes put back on undo too, any other change to the
## board still counts as a new position.
var _position_ids: Array[int] = [0]
var _board_changes: Array[int] = []
var _last_position_id := 0

## For stepping back through the game and playing the same moves again (to
## look at earlier positions): call this first, then same_position_again() once
## they're all made again, so the position counts as the same one it was (and
## outcome() keeps its answer).
func position_marks() -> Array:
	return [_position_ids.duplicate(), _board_changes.duplicate(), board.changes]

func same_position_again(marks: Array) -> void:
	_position_ids = marks[0]
	_board_changes = marks[1]
	board.changes = marks[2]

func _work_out_outcome() -> Outcome:
	if history.is_empty() and MoveGenerator.is_in_check(board, Piece.other_team(side_to_move)):
		return Outcome.KING_EXPOSED
	if moves().is_empty():
		return Outcome.CHECKMATE if is_in_check() else Outcome.STALEMATE
	if _checkmate_impossible():
		return Outcome.INSUFFICIENT_MATERIAL
	if halfmove_clock >= 100:
		return Outcome.FIFTY_MOVES
	if change_clock >= 150:
		return Outcome.SEVENTY_FIVE_MOVES
	if _repetition_count() >= 3:
		return Outcome.REPETITION
	return Outcome.NONE

## The result as written in PGN: "1-0", "0-1", "1/2-1/2", or "*" if not over.
func result_text() -> String:
	match outcome():
		Outcome.NONE:
			return "*"
		Outcome.CHECKMATE:
			return "0-1" if side_to_move == Piece.Team.WHITE else "1-0"
		Outcome.KING_EXPOSED:
			return "1-0" if side_to_move == Piece.Team.WHITE else "0-1"
	return "1/2-1/2"

func make_move(move: Move) -> void:
	_last_position_id += 1
	_position_ids.append(_last_position_id)
	_board_changes.append(board.changes)
	move.piece_had_moved = move.piece.has_moved
	move.prev_en_passant_squares = en_passant_squares
	move.prev_en_passant_victim = en_passant_victim
	move.prev_halfmove_clock = halfmove_clock
	if move.is_capture() or move.piece.def.is_pawn_type():
		halfmove_clock = 0
	else:
		halfmove_clock += 1
	move.prev_change_clock = change_clock
	if changes_pieces(move):
		change_clock = 0
	else:
		change_clock += 1
	history.append(move)
	if move.ability != PieceDef.Ability.NONE:
		move.piece.ability_used = true
	if move.ability == PieceDef.Ability.RAISE_DEAD:
		# The Necromancer leaves; the lost piece's fresh copy takes its square.
		move.raised_lost_index = lost[move.piece.team].find(move.raised_from_lost)
		lost[move.piece.team].remove_at(move.raised_lost_index)
		board.set_piece(move.from, move.raised)
		_clear_en_passant()
		_next_turn()
		return
	if move.ability == PieceDef.Ability.HAUNT:
		# The lost Ghost comes back onto the board.
		move.raised_lost_index = lost[move.piece.team].find(move.piece)
		lost[move.piece.team].remove_at(move.raised_lost_index)
		board.set_piece(move.to, move.piece)
		move.piece.has_moved = true
		_clear_en_passant()
		_next_turn()
		return
	if move.ability == PieceDef.Ability.FULL_MOON:
		# The Werewolf becomes the wolf, on the same square.
		move.piece.base_def = move.piece.def
		move.piece.def = move.piece.def.transforms_into
		_clear_en_passant()
		_next_turn()
		return
	if move.ability == PieceDef.Ability.SONG_OF_SLUMBER:
		# Nothing moves: frozen_piece() reads the target from this move.
		_clear_en_passant()
		_next_turn()
		return
	if move.breaks_shield():
		# Nothing moves: the shielded piece just loses its shield. (A Ram dies doing it.)
		if move.shield_target.gained_shield:
			move.shield_target.gained_shield = false
			move.broke_gained_shield = true
		else:
			move.shield_target.shield_broken = true
		if move.piece.def.dies_on_capture:
			_remove_dead_attacker(move, move.from)
		# Breaking a shield counts as a move (Mac): the piece may use its ability
		# afterwards (undo puts piece_had_moved back).
		move.piece.has_moved = true
		_clear_en_passant()
		_next_turn()
		return
	if move.decoy_piece:
		# A Jester takes the hit: the target moves to the Jester's square, and the
		# Jester (move.captured) is taken off where the target stood.
		move.decoy_piece_had_moved = move.decoy_piece.has_moved
		board.set_piece(move.decoy_square, move.decoy_piece)
		move.decoy_piece.has_moved = true
	if move.ability == PieceDef.Ability.CRACK_SHOT:
		# The Archer shoots from where it stands (a capture counts as a move).
		board.set_piece(move.capture_square, null)
		lost[move.captured.team].append(move.captured)
		move.piece.has_moved = true
		_clear_en_passant()
		_next_turn()
		return
	# A Vampire gains a shield by capturing (if it hasn't one already).
	if move.captured and move.piece.def.shield_on_capture and not move.piece.has_active_shield():
		move.piece.gained_shield = true
		move.gained_shield = true
	if move.captured:
		lost[move.captured.team].append(move.captured)
	board.set_piece(move.from, null)
	board.set_piece(move.capture_square, null)
	if move.promotion:
		if move.promoted_piece == null:
			move.promoted_piece = Piece.new(move.promotion, move.piece.team)
			move.promoted_piece.has_moved = true
		board.set_piece(move.to, move.promoted_piece)
	else:
		board.set_piece(move.to, move.piece)
	move.piece.has_moved = true
	if move.is_castling():
		move.partner_had_moved = move.partner.has_moved
		board.set_piece(move.partner_from, null)
		board.set_piece(move.partner_to, move.partner)
		move.partner.has_moved = true
	if move.captured and move.piece.def.dies_on_capture:
		_remove_dead_attacker(move, move.to)
	# En passant is only possible on the very next move.
	en_passant_squares = move.skipped_squares
	en_passant_victim = move.to if not move.skipped_squares.is_empty() else Board.NO_SQUARE
	_next_turn()

## A Ram that just captured is removed from `square` and counts as lost.
func _remove_dead_attacker(move: Move, square: Vector2i) -> void:
	board.set_piece(square, null)
	lost[move.piece.team].append(move.piece)
	move.attacker_died = true

func _clear_en_passant() -> void:
	en_passant_squares = []
	en_passant_victim = Board.NO_SQUARE

func _next_turn() -> void:
	if side_to_move == Piece.Team.BLACK:
		fullmove_number += 1
	side_to_move = Piece.other_team(side_to_move)

## True while White is about to make the game's first move and may not attack
## (`GameRules.white_quiet_first_move`): no capture, no shield break.
func white_quiet_first_move_applies() -> bool:
	return rules.white_quiet_first_move and not from_position and history.is_empty() \
			and side_to_move == Piece.Team.WHITE

## True if the move changes the pieces on the board (the 75-move rule's
## count): any capture or shield break, a promotion, Raise Dead, Haunt or Full
## Moon. A plain move, castling or Song of Slumber doesn't.
static func changes_pieces(move: Move) -> bool:
	return move.is_capture() or move.promotion != null \
			or move.ability in [PieceDef.Ability.RAISE_DEAD, PieceDef.Ability.HAUNT, PieceDef.Ability.FULL_MOON]

func undo_move(move: Move) -> void:
	assert(not history.is_empty() and history.back() == move, "Moves must be undone last-first")
	_position_ids.pop_back()
	_take_back(move)
	board.changes = _board_changes.pop_back()

func _take_back(move: Move) -> void:
	history.pop_back()
	halfmove_clock = move.prev_halfmove_clock
	change_clock = move.prev_change_clock
	side_to_move = Piece.other_team(side_to_move)
	if side_to_move == Piece.Team.BLACK:
		fullmove_number -= 1
	move.piece.has_moved = move.piece_had_moved
	en_passant_squares = move.prev_en_passant_squares
	en_passant_victim = move.prev_en_passant_victim
	if move.ability != PieceDef.Ability.NONE:
		move.piece.ability_used = false
	if move.ability == PieceDef.Ability.RAISE_DEAD:
		lost[move.piece.team].insert(move.raised_lost_index, move.raised_from_lost)
		board.set_piece(move.from, move.piece)
		return
	if move.ability == PieceDef.Ability.HAUNT:
		board.set_piece(move.to, null)
		lost[move.piece.team].insert(move.raised_lost_index, move.piece)
		return
	if move.ability == PieceDef.Ability.FULL_MOON:
		move.piece.def = move.piece.base_def
		move.piece.base_def = null
		return
	if move.ability == PieceDef.Ability.SONG_OF_SLUMBER:
		return
	if move.attacker_died:
		lost[move.piece.team].pop_back()
		move.attacker_died = false
	if move.breaks_shield():
		if move.broke_gained_shield:
			move.shield_target.gained_shield = true
			move.broke_gained_shield = false
		else:
			move.shield_target.shield_broken = false
		board.set_piece(move.from, move.piece)  # Back, if it was a Ram that died.
		return
	if move.gained_shield:
		move.piece.gained_shield = false
		move.gained_shield = false
	if move.captured:
		lost[move.captured.team].pop_back()
	if move.ability == PieceDef.Ability.CRACK_SHOT:
		board.set_piece(move.capture_square, move.captured)
		_undo_decoy(move)
		return
	if move.is_castling():
		move.partner.has_moved = move.partner_had_moved
		board.set_piece(move.partner_to, null)
		board.set_piece(move.partner_from, move.partner)
	board.set_piece(move.to, null)
	board.set_piece(move.capture_square, move.captured)  # null if nothing was captured.
	board.set_piece(move.from, move.piece)
	_undo_decoy(move)

## Undo a Jester swap: the Jester back on its square, the target back on its own.
func _undo_decoy(move: Move) -> void:
	if move.decoy_piece == null:
		return
	board.set_piece(move.decoy_square, move.captured)
	board.set_piece(move.capture_square, move.decoy_piece)
	move.decoy_piece.has_moved = move.decoy_piece_had_moved

## How many times the current position has occurred, counting now. "Same position"
## means the same pieces on the same squares, same side to move, same castling
## rights and same en passant possibilities. Only positions since the last move
## that changed the pieces (`changes_pieces`: a capture, a promotion, Raise Dead,
## Haunt, Full Moon) can match; pawn-type moves no longer end the window (Mac,
## 27 Oct 2026), because a Vassal can step sideways and an Abatis back, so their
## moves can be undone and a position can come round again. Each position's key is kept once worked out
## (outcome() is asked after every move), so usually they're all known already;
## otherwise it steps back that far (undoing moves to look, then replaying them).
func _repetition_count() -> int:
	var key := _kept_position_key()
	var steps := mini(change_clock, history.size())
	var count := 1
	# Position i (0 = the start) has id _position_ids[i], and the board had
	# _board_changes[i] changes then (see make_move).
	if _position_ids.size() == history.size() + 1:
		var all_known := true
		for i in range(history.size() - 1, history.size() - 1 - steps, -1):
			var known: Array = _position_keys.get(_position_ids[i], [])
			if known.is_empty() or known[0] != _board_changes[i]:
				all_known = false
				break
			if known[1] == key:
				count += 1
		if all_known:
			return count
		count = 1
	var marks := position_marks()
	var undone: Array[Move] = []
	for i in range(steps):
		var move: Move = history.back()
		undo_move(move)
		undone.append(move)
		if _kept_position_key() == key:
			count += 1
	for i in range(undone.size() - 1, -1, -1):
		make_move(undone[i])
	same_position_again(marks)
	return count

## Position keys worked out so far: position id -> [board.changes then, key].
var _position_keys := {}

## _position_key() for the position now, kept for next time.
func _kept_position_key() -> String:
	var id: int = _position_ids.back()
	var known: Array = _position_keys.get(id, [])
	if not known.is_empty() and known[0] == board.changes:
		return known[1]
	# Only positions still in the game can come up again: forget the rest now
	# and then, so this doesn't keep growing.
	if _position_keys.size() > 2 * _position_ids.size() + 64:
		var still := {}
		for kept_id in _position_ids:
			if _position_keys.has(kept_id):
				still[kept_id] = _position_keys[kept_id]
		_position_keys = still
	var key := _position_key()
	_position_keys[id] = [board.changes, key]
	return key

## Text that is identical for two positions exactly when they count as the same
## position for repetition.
func _position_key() -> String:
	var fields := Fen.write(self).split(" ")
	var key := " ".join([fields[0], fields[1], fields[2]])
	# A piece that hasn't moved yet can have moves it loses once it moves (a
	# first-move double step, an ability, a promotion), so an unmoved piece and
	# the same piece back on its square aren't the same position. (Castling
	# rights already cover Kings and castle partners; other pieces' first move
	# changes nothing, so a Knight out and back still repeats, as in chess.)
	var unmoved := PackedStringArray()
	for rank in range(board.height):
		for file in range(board.width):
			var piece := board.get_piece(Vector2i(file, rank))
			if piece and not piece.has_moved and _first_move_matters(piece.def):
				unmoved.append(Board.square_name(Vector2i(file, rank)))
	if not unmoved.is_empty():
		key += " unmoved:" + ",".join(unmoved)
	# The en passant square only matters if an en passant capture can really be made.
	if not en_passant_squares.is_empty():
		for move in moves():
			if move.capture_square != move.to:
				key += " " + Board.square_name(move.to)
	return key

## Whether a piece of this type loses something by moving for the first time.
static func _first_move_matters(def: PieceDef) -> bool:
	if def.ability != PieceDef.Ability.NONE or def.can_promote():
		return true
	for rule in def.move_rules:
		if rule.first_move_max_steps > 0:
			return true
	return false

## True if neither side could ever checkmate. Worked out from the pieces' move data,
## not their names. Recognises: only royal pieces left; royals plus a single
## knight-style leaper (it can't attack the squares next to itself); royals plus
## pieces that stay on one square color (like bishops), all on the same color.
## Custom pieces will need more thought here later.
func _checkmate_impossible() -> bool:
	# A Necromancer that can still bring a piece back, or a Ghost that can still
	# come back, changes everything.
	for team in [Piece.Team.WHITE, Piece.Team.BLACK]:
		if not MoveGenerator.haunting_ghosts(self, team).is_empty():
			return false
		if not MoveGenerator.raisable_defs(self, team).is_empty():
			for piece: Piece in board.pieces_of(team).values():
				if piece.can_use_ability() and piece.def.ability == PieceDef.Ability.RAISE_DEAD:
					return false
	var others: Array[Piece] = []
	var square_colors := {}
	var non_capturers := 0
	for rank in range(board.height):
		for file in range(board.width):
			var piece := board.get_piece(Vector2i(file, rank))
			if piece == null or piece.def.is_king_type():
				continue
			if piece.def.is_pawn_type():
				return false
			# A piece that can never capture (a Necromancer with nothing to raise)
			# can never give check.
			if not _can_capture(piece.def):
				non_capturers += 1
				continue
			others.append(piece)
			square_colors[(file + rank) % 2] = true
	if others.is_empty():
		return true
	# With pieces that can attack about, pieces that can't might still help trap
	# a king: don't call it a draw.
	if non_capturers > 0:
		return false
	if others.size() == 1 and _is_distant_leaper(others[0].def):
		return true
	for piece in others:
		if not _stays_on_one_color(piece.def):
			return false
	return square_colors.size() == 1

static func _can_capture(def: PieceDef) -> bool:
	return def.move_rules.any(func(rule: MoveRule) -> bool: return rule.mode != MoveRule.Mode.MOVE_ONLY)

## A piece whose every move is a single jump of 3+ squares' distance (|x| + |y|),
## like a knight. Such a piece can't guard the squares around itself.
static func _is_distant_leaper(def: PieceDef) -> bool:
	for rule in def.move_rules:
		if rule.is_unusual() or rule.max_steps != 1 or rule.first_move_max_steps > 1:
			return false
		for dir in rule.directions:
			if absi(dir.x) + absi(dir.y) < 3:
				return false
	return true

## True if every move keeps the piece on the same square color, like a bishop.
static func _stays_on_one_color(def: PieceDef) -> bool:
	for rule in def.move_rules:
		if not rule.path.is_empty():
			for steps: Array in rule.path_variants():
				var offset := MoveRule.path_offset(steps)
				if (offset.x + offset.y) % 2 != 0:
					return false
			continue
		for dir in rule.directions:
			if (dir.x + dir.y) % 2 != 0:
				return false
	return true

## The same as find_move, for a move already known to be legal here (it was
## played in this position before: replaying a game or a side line). Much
## quicker: it doesn't check every move for leaving the king attacked (each a
## make, attack test and undo), which made looking back through a long game
## take a quarter of a second per step. If two moves have the text, it asks
## find_move to be sure.
func find_played_move(text: String) -> Move:
	var found: Move = null
	for move in MoveGenerator.pseudo_legal_moves(self):
		if move.to_text() == text:
			if found:
				return find_move(text)
			found = move
	return found

## The available move whose to_text() matches, e.g. "e2-e4" or "e7-e8=Q", or null.
## For tests.
func find_move(text: String) -> Move:
	var all := moves()
	for move in all:
		if move.to_text() == text:
			return move
	# Saved before the attacker chose which Jester takes a hit (Oct 2026), a move
	# doesn't name the Jester: it was the first one, as the game picked then.
	if not text.contains("/"):
		for move in all:
			if move.decoy_choice and move.to_text().get_slice("/", 0) == text:
				return move
	return null
