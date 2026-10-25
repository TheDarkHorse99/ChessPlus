class_name Move
extends RefCounted

## One move: which piece goes from where to where, and what (if anything) it takes.

var from: Vector2i
var to: Vector2i
var piece: Piece
## The piece being taken, or null if the move doesn't capture.
var captured: Piece
## Where the captured piece stands. The same as `to`, except for en passant.
var capture_square: Vector2i
## An empty list that moves share until they need a list of their own (making a
## new empty list for every move is surprisingly slow). Never add to it.
const NO_SQUARES: Array[Vector2i] = []

## Squares this move skips over that the opponent may capture onto en passant
## next turn. Only set for multi-step moves by pawn-type pieces.
var skipped_squares: Array[Vector2i] = NO_SQUARES
## For a move that breaks a Shield: the shielded piece. The attacker stays on
## `from` and the shielded piece stays on `to`; only the shield is lost.
var shield_target: Piece
## What the piece turns into, or null if this move doesn't promote.
var promotion: PieceDef
## For castling: the partner piece (rook) that moves too, and where it goes.
var partner: Piece
var partner_from: Vector2i
var partner_to: Vector2i

# Filled in by GameState.make_move so undo_move can put things back exactly.
var piece_had_moved: bool
var prev_halfmove_clock: int
var prev_change_clock: int
## The new piece created by a promotion. Made once and reused if the move is
## replayed, so later moves that refer to it still find the same piece.
var promoted_piece: Piece
var partner_had_moved: bool
var prev_en_passant_squares: Array[Vector2i] = NO_SQUARES
var prev_en_passant_victim: Vector2i

func _init(p_from: Vector2i, p_to: Vector2i, p_piece: Piece, p_captured: Piece = null) -> void:
	from = p_from
	to = p_to
	piece = p_piece
	captured = p_captured
	capture_square = p_to

## The special ability this move uses (PieceDef.Ability), NONE for ordinary moves.
## A Crack Shot is a capture (or shield break) where the Archer stays put; a Raise
## Dead has from == to (the Necromancer's square) and `raised` set; a Haunt has
## from == to (where the Ghost comes back; `piece` is the lost Ghost); Song of
## Slumber goes from the Bard to the piece it puts to sleep (`frozen`), and
## nothing moves; Full Moon has from == to (the Werewolf's square).
var ability: PieceDef.Ability = PieceDef.Ability.NONE
## Raise Dead: the piece that comes back (a fresh piece of a lost piece's type),
## and the lost piece it stands for (taken off the lost list while it's back).
var raised: Piece
var raised_from_lost: Piece
## Song of Slumber: the enemy piece that can't move on its side's next turn.
var frozen: Piece
## Filled in by make_move: where raised_from_lost (or a haunting Ghost) was in
## the lost list, and whether the moving piece died (a Ram capturing).
var raised_lost_index := -1
var attacker_died := false

## A Jester swap: the piece the capture was aimed at (it moves to the Jester's
## square, `decoy_square`, and `captured` is the Jester instead).
var decoy_piece: Piece
var decoy_square: Vector2i
var decoy_piece_had_moved := false
## True when more than one Jester could take this hit: the attacking player
## chooses which (Mac, Oct 2026), so there's one move per Jester, and its text
## names the Jester's square ("e4xd5/c6").
var decoy_choice := false
## Filled in by make_move: the shield the capture broke was one the target gained
## (Vampire), and the capturing piece gained a shield by this capture.
var broke_gained_shield := false
var gained_shield := false

## True for captures and for shield breaks (both are written with "x").
func is_capture() -> bool:
	return captured != null or breaks_shield()

func breaks_shield() -> bool:
	return shield_target != null

## Where the moving piece ends up: `to`, or `from` if it only broke a shield or
## used Crack Shot (it shoots from where it stands) or Song of Slumber.
func lands_on() -> Vector2i:
	if breaks_shield() or ability == PieceDef.Ability.CRACK_SHOT or ability == PieceDef.Ability.SONG_OF_SLUMBER:
		return from
	return to

func is_castling() -> bool:
	return partner != null

## A new move just like this one, before it's played (what's chosen: squares,
## pieces, promotion, ability), for making several versions of one move.
func copy() -> Move:
	var other := Move.new(from, to, piece, captured)
	other.capture_square = capture_square
	other.skipped_squares = skipped_squares
	other.shield_target = shield_target
	other.promotion = promotion
	other.partner = partner
	other.partner_from = partner_from
	other.partner_to = partner_to
	other.ability = ability
	other.raised = raised
	other.raised_from_lost = raised_from_lost
	other.frozen = frozen
	return other

## "/c6" (the Jester's square) when the attacker chose which Jester takes the
## hit, otherwise "". Goes on the end of the move's text and SAN.
func decoy_text() -> String:
	return "/" + Board.square_name(decoy_square) if decoy_choice else ""

## Simple text like "e2-e4", "e4xd5" or "e7-e8=Q". Used for testing, not real notation.
func to_text() -> String:
	# Abilities: "c1!g5" (Crack Shot on g5), "d1!=Q" (Raise Dead bringing back a
	# queen), "@e3" (a Ghost haunting e3), "c1~g5" (Song of Slumber on g5),
	# "e4!" (Full Moon).
	if ability == PieceDef.Ability.HAUNT:
		return "@" + Board.square_name(to)
	if ability == PieceDef.Ability.SONG_OF_SLUMBER:
		return Board.square_name(from) + "~" + Board.square_name(to)
	if ability == PieceDef.Ability.FULL_MOON:
		return Board.square_name(from) + "!"
	if ability == PieceDef.Ability.RAISE_DEAD:
		return Board.square_name(from) + "!=" + raised.def.symbol.to_upper()
	if ability == PieceDef.Ability.CRACK_SHOT:
		return Board.square_name(from) + "!" + Board.square_name(to) + decoy_text()
	var joiner := "x" if is_capture() else "-"
	var text := Board.square_name(from) + joiner + Board.square_name(to)
	if promotion:
		text += "=" + promotion.symbol.to_upper()
	return text + decoy_text()
