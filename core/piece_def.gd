class_name PieceDef
extends Resource

## The blueprint for one type of piece. One file per type, e.g. knight.tres.

## Bit values for `types`. A piece can have several, e.g. the king is KING + ROYAL.
enum Type { KING = 1, ROYAL = 2, PAWN = 4 }
## Bit values for `keywords`.
enum Keyword { JUMP = 1, CASTLE = 2, PROMOTE = 4, SHIELD = 8, WALL = 16 }

@export var id: String = ""
@export var display_name: String = ""
## One or two capital letters for notation and saved positions, e.g. "N" for
## knight, "PD" for paladin. Must be unique across all pieces.
@export var symbol: String = ""
@export var value: float = 0.0
@export var move_rules: Array[MoveRule] = []

## King: the piece you must protect; if it's checkmated you lose. Each army has
##   exactly one, starting in the middle of its back row. It can castle.
## Royal: an army may have at most one royal piece besides its king.
## Pawn: any number allowed. Promotes on the far rank, takes part in en passant,
##   and moving it resets the 50-move count.
@export_flags("King", "Royal", "Pawn") var types := 0
## Jump: its moves are single leaps, so it can't be blocked (a label for players;
##   the leaping comes from its move rules).
## Castle: the king can castle with it.
## Promote: promotes on the far rank, with the same choices as pawns.
## Shield: must be captured twice. The first capture only breaks the shield (the
##   attacker stays where it is and uses its turn); the shield never comes back.
@export_flags("Jump", "Castle", "Promote", "Shield", "Wall") var keywords := 0

## Once-per-game special abilities (each uses a turn).
## CRACK_SHOT (Archer): capture something it could capture, without moving.
## RAISE_DEAD (Necromancer): it leaves the board and one of its side's lost
##   pieces (not a pawn type, not a Necromancer) comes back on its square, fresh.
## HAUNT (Ghost): used after it has been captured: it comes back onto any empty
##   square in its side's half of the board.
## SONG_OF_SLUMBER (Bard): one enemy piece it could capture (not a king) can't
##   move on the opponent's next turn.
## FULL_MOON (Werewolf): it turns into `transforms_into` for the rest of the game.
enum Ability { NONE, CRACK_SHOT, RAISE_DEAD, HAUNT, SONG_OF_SLUMBER, FULL_MOON }
@export var ability: Ability = Ability.NONE

## For FULL_MOON: the piece type it becomes (the Werewolf's wolf form, kept in
## res://data/pieces/forms/ so it isn't offered in the army builder).
@export var transforms_into: PieceDef

## For a piece with two forms (the Werewolf): what its piece card's button calls
## this form's moves ("Human" -> "Human moves", Mac).
@export var form_name := ""

## The Ram's rule: after capturing (or breaking a shield) it is removed from the
## board too, and counts as lost.
@export var dies_on_capture := false

## The Wall keyword's rule (the Parapet, and the Abatis from Oct 2026): the
## opponent's pieces can't jump over it (its own side's can, Mac). Their leaps
## (Knight, Elephant, Catapult) and the Wizard's and Rogue's leaps stop at it,
## and their Cannons can't use it as a screen. A Knight counts as moving two
## squares straight first, then one to the side. (It was a flag of its own,
## `blocks_jumps`, until the keyword; Plusfish's data still calls it that.)
func blocks_jumps() -> bool:
	return has_wall()

## The Vampire's rule: it starts without a shield and gains one whenever it
## captures (if it hasn't one). The shield works like the Shield keyword's.
@export var shield_on_capture := false

## The Squire's rule: these piece types (by id), on squares this piece could
## reach, can't be captured.
@export var protects: Array[String] = []

## The Jester's rule: when an enemy would capture one of its side's pieces (not a
## pawn type) on a square this piece could reach, they swap places and this piece
## is captured instead. One Jester per capture.
@export var decoy := false

## Shown on the piece card under "Special Rule": anything about how it plays that
## its types, keywords and move picture can't show. Empty for most pieces.
@export_multiline var special_rule := ""

## A note in italics under the piece card's mini board, about how it moves
## (Mac: the Knight's and Cavalry's "2 squares, then 1").
@export_multiline var move_note := ""
## Shown under "Special Ability": a once-per-game action that uses a turn. The
## name (e.g. "Crack Shot") and what it does. Empty for most pieces.
@export var ability_name := ""
@export_multiline var ability_text := ""
## The ability's colours, left to right: its name on the piece card and the
## button in a game are filled with a gradient between them (Mac's design).
@export var ability_colors := PackedColorArray()

## ability_colors, or a grey gradient if the piece has none.
func ability_gradient() -> PackedColorArray:
	if ability_colors.size() >= 2:
		return ability_colors
	return PackedColorArray([Color("#4a4a4a"), Color("#9a9a9a")])

## The colours of the faint glow round a piece whose ability is still unused,
## when they aren't its ability's colours (Mac: the Werewolf's white -> silver
## didn't show on the board, so its glow is blue while its button stays white).
@export var glow_colors := PackedColorArray()

## glow_colors, or the ability's colours.
func glow_gradient() -> PackedColorArray:
	if glow_colors.size() >= 2:
		return glow_colors
	return ability_gradient()

## The colour for writing the ability's name on its gradient: white, or dark
## grey on a pale gradient (the Ghost's and Werewolf's).
func ability_label_color() -> Color:
	var colors := ability_gradient()
	var light := 0.0
	for color in colors:
		light += color.get_luminance()
	return Color("#262626") if light / colors.size() > 0.62 else Color.WHITE

func is_king_type() -> bool:
	return types & Type.KING != 0

func is_royal_type() -> bool:
	return types & Type.ROYAL != 0

func is_pawn_type() -> bool:
	return types & Type.PAWN != 0

func has_jump() -> bool:
	return keywords & Keyword.JUMP != 0

func has_castle() -> bool:
	return keywords & Keyword.CASTLE != 0

func has_promote() -> bool:
	return keywords & Keyword.PROMOTE != 0

func has_shield() -> bool:
	return keywords & Keyword.SHIELD != 0

func has_wall() -> bool:
	return keywords & Keyword.WALL != 0

## Pawn types and pieces with the Promote keyword promote on the far rank.
func can_promote() -> bool:
	return is_pawn_type() or has_promote()
