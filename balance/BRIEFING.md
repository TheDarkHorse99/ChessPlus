# Overchess balancing: briefing (for a chat that can't see the repo)

Last updated 26 October 2026 (after run 17). The full data is in the repo
(github.com/thedarkhorse99/ChessPlus): `balance/results/run1` to `run13` (a
README and report each) and `CLAUDE.md`. All numbers below come from
Plusfish, the game's own engine, playing itself: strong hints, not human play.
Balancing is now discussed in Claude Code; Mac makes the decisions.

## The game in one paragraph

Each player builds an army on a budget of 40 points (pawns count) on their
own first two rows of an 8x8 board: exactly one King (middle of the back row),
at most one extra Royal piece, at most 2 copies of any non-pawn type. White
moves first. 30 piece types.

## Current prices

Pawn 1, Knight 3, Bishop 3.5, Rook 4.5, Queen 10, King 0. Archer 4.5, Assassin
0.5, Barbarian 2.5, Bard 3.5, Cannon 4, Catapult 3, Cavalry 3, Chariot 4,
Elephant 1, Galleon 3, Ghost 3, Jester 3.5, Lance 3 (3.5 until 25 Oct), Man 3, Necromancer 3.5,
Paladin 1.5, Parapet 2.5, Princess 8.5, Ram 3, Rogue 3.5, Squire 4, Vampire 7.5 (6.5 until 26 Oct, run 17),
Werewolf 3 (3.5 for a day), Wizard 8.5 (8 until 26 Oct); the pawn types added 25 Oct 2026 after run 15: Grunt 1 (pawn type with a shield; started 1.5), Abatis 0.5 (pawn type that is a Wall; started 1), Vassal 1 (pawn type moving forward or sideways, takes en passant sideways). **Rules adopted 25 Oct 2026 after run 15D:** White may not attack (capture or break a shield) on its first move; a piece must have moved once before it can promote; special abilities need a move first (24 Oct); the 75-move rule. **Budget 40** (was 39) since 24 Oct 2026, when Mac set
Queen 10, Bishop 3.5, Rook 4.5, Werewolf 3.5, Parapet 2.5 and Jester 3.5, and
made special abilities usable only once the piece has moved (a capture or
shield break counts). Runs 1-13 were at the old prices and rules; run 14
measured the new ones.

Changed in October from run 1's data: Vampire 4 -> 6.5, Princess 7 -> 8.5,
Squire 3 -> 4, Galleon 4.5 -> 3, Elephant 1.5 -> 1, Paladin 2 -> 1.5,
Assassin 2 -> 0.5 (earlier: Lance 2.5 -> 3.5, Necromancer 3 -> 3.5,
Ram 3.5 -> 3, Archer 4 -> 4.5). Queen kept at 9 on purpose (measured ~10).

## Piece values (run 14, at the current prices and budget 40)

"Worth" = what one extra piece is worth at the start, judged from 20,000
games. The six repriced pieces all land within 0.25 of cost (Queen 9.91,
Rook 4.72, Bishop 3.47, Werewolf 3.43, Jester 3.51, Parapet 2.60). Still off:
Vampire worth 7.2 (costs 6.5), Archer 5.0 (4.5), Wizard +0.4, Cavalry +0.4;
nothing over 1.0. With the ability rule on (run 14's arm B) the Necromancer
drops to 3.39 (-0.4) and the Werewolf to 3.16 (-0.3); the Archer, Ghost and
Bard hardly move.

## Colour balance (Mac's goal: White's edge close to chess's)

Target: top engines rate the chess start +0.20 to +0.35 pawns for White;
strong players score 54-56% with White. Plusfish rates the chess start +0.29.

- **Random armies:** White scores about 56%.
- **The strongest armies (meta pool):** White scores about 63%, and some
  pairings are 80-100% White (run 3).
- **The cause (found 22 Oct):** armies have no pawn wall, so long-range
  front-row pieces (Bishop, Lance, Queen) and the Archer's Crack Shot can
  capture before anyone moves, and White goes first. When White's first move
  is a capture, White scores 67-71%; otherwise about 53%, already chess-like.
  Some strong armies played against themselves start +3 to +4.6 pawns for
  White (e.g. 1. Axb7! with Crack Shot).
- **Run 4, "Quiet first move"** (no captures or abilities on either side's
  first move): made it worse (White 58.4%), because a first-move check that
  could only be answered by a capture became mate, and White just captured on
  move 2 instead. Rejected.
- **Run 5, the "Front-row rule"** (Mac's name; no piece may start able to
  capture anything on the opponent's two starting rows): random armies White
  52.0% (from 56.1%); an army against itself median +0.26 (chess +0.29), none
  over +1 pawn (was 6 of 18). It would also make the temporary "King exposed"
  rule unnecessary. Status: tested, **not adopted yet** (Mac's choice).
- **Run 6, the Front-row rule with strong armies** (a meta pool grown under
  it): White 51.0% overall, every army's White-minus-Black gap under 15
  points; Mac's success test failed by a single pairing at 82.5% (33 of 40
  games). At deeper search (32k nodes) random armies under the rule: White
  51.4%. The one strong army still well ahead against itself opens with a
  check on move 1 (the rule only stops captures).
- **Run 7, the normal rules with the improved Plusfish:** the problem is
  still there (White 59.4%, 3 pairings at 80%+, half the strong armies +3 to
  +4 against themselves via first-move captures). Its pool is the official
  meta pool now.
- **Run 8, cheaper pawns (0.75 and 0.5):** no walls. Strong armies take more
  pawns at 0.5 (4.5 each) but put them on the back row, behind the pieces, so
  first-move captures stay; White's edge grows slightly (random armies 56.1%
  and 56.5%, round robins 64.2% and 62.3%, 8-9 pairings at 80%+). The Pawn's
  measured worth stays about 0.72 whatever its price. On this data it
  doesn't help.
- **Run 9, White-only quiet first move** (White may not capture, break a
  shield or use an ability on its first move unless in check; Black
  unrestricted): the best result yet. Random armies White 52.7% (control on
  today's engine 55.7%); round robin of the strong pool 50.5%, every army's
  gap under 8 points, no pairing at 80%+; an army against itself median +0.20
  (chess +0.29), none with Black more than a pawn ahead. Mac's success test
  missed on one line: the round robin's White score 50.5% is under the 52%
  floor (95% range 48.9-52.2%).
- **Run 10, the White-only quiet first move with strong armies** (a meta
  pool grown under it): round robin White 51.1% (95% 49.5-52.7%), biggest
  army gap +11.3, one pairing at exactly 80.0% (32 of 40); armies against
  themselves median +0.14, none over +1, none with Black more than a pawn
  ahead. Success test missed on two lines, both at the edge (round robin
  under 52%, one pairing on the 80% line).
- **Run 11, separate White and Black armies** (players can set a default
  army per colour; Plusfish grew a White pool and a Black pool side by side,
  each judged only as its colour; report only): under the normal rules a
  Black-only army gains about 8 points against the all-round pool, a
  White-only army about 1; specialists against specialists White 57.6% (all-
  rounders 59.4%). Black's armies keep long-range pieces out of the front row
  and take Paladins; White's take pawns, Rams, Cannons and strikers. Under the
  White-only quiet first move, specialists against specialists gave White
  48.0% (Black ahead), with White dropping the Queen and Black becoming the
  striker, but both colour pools came out weaker than the all-rounders (the
  split search never settled), so that half is a first look only.
- **Run 12, the split search in phases** (one colour grown for 5 rounds
  against the other pool frozen, then the other, 30 rounds): it cycles
  instead of settling. Each pool shoots up against the frozen opponent and
  collapses when the opponent's phase begins; both colour pools lose to the
  all-rounders (normal rules: White specialists 51.5% against the ordinary
  pool, which scores 59.4% against itself), and "specialists vs specialists"
  (White 36.8% normal, 43.3% rule) only measures which colour had the last
  phase. The one steady army is run 7's all-rounder Wide 14a. Conclusion:
  colour specialists found against a small searched pool are counters to
  those ten opponents, not generally strong; a fairer test would judge each
  colour against a fixed, broad opponent set (the all-round pool itself).
- **Run 13, each colour judged against the all-round pool frozen** (the fair
  version; it settled, and supersedes 11 and 12 for this question). Normal
  rules: a White-only army (strikers: long-range pieces in the front row,
  Archers, Lances) gains +11 points against the all-rounders, a Black-only
  army (defenders: few exposed pieces, Ghosts, Paladins) +13.5; specialists
  against specialists White 56.7% (all-rounders 59.4%), so colour defaults
  narrow White's edge a little but it stays. Under the White-only quiet first
  move: gains +6.8 / +5.2, the two pools look alike, and specialists against
  specialists is level at 50.0%, the most even setting measured so far.
- **Run 14, the 24 Oct prices and the ability rule** (abilities only after
  the piece has moved; Plusfish taught the rule on a branch and checked
  against the game, 0 mismatches). The rule removes every move-1 ability
  (they were 4% of random-army games, 30% of strong-army games through the
  Archer's Crack Shot) but White's edge barely moves: random armies 56.2% ->
  55.8%, the regrown strong pool's round robin 53.6% with 4 pairings at 80%+,
  armies against themselves median +1.39 -> +0.70 with Lances and Bishops
  still striking on move 1 (a Lance can even capture on the back row and
  promote with check on move 1). Colour specialists under the rule are more
  lopsided than run 13's: White specialists +16 points against all-rounders,
  Black +7.5, specialists against specialists 70.6% for White, and one White
  army (two Lances, Princess, Wizard, Cannon) won 100% of its games. So the
  rule is fine as a design choice but not a colour fix: first-move contact by
  long-range pieces is the driver, and only the Front-row rule or the
  White-only quiet first move have moved it.
- **Runs 15 and 15D, the three pawn types** (Grunt 1.5, Abatis 1, Vassal 1,
  added 25 Oct): measured worth Grunt ~0.9, Abatis ~0.6, Vassal 1.0. With
  the pieces alone (run 15) White's edge was a little bigger in random
  armies (56.4%) and the strong pool (57.6%), though the strongest armies'
  first-move edge halved and colour specialists fought level-ish (54.9%):
  a front-row Grunt is a tempo trap for strikers. With the White-only quiet
  first move on top (run 15D) the numbers are the closest to chess of any
  run: random armies 53.6%, the strong pool 52.1%, mirror matches +0.22,
  specialists 47.5% (Black slightly ahead), and White and Black stop needing
  different armies. Under that rule the Lance is worth only 2.8-3.1 (priced
  3.5) and the Rook and Queen gain about half a point.
- **Run 16, the meta by share** (26 Oct, today's rules and prices): 40
  all-round armies grown from scratch and 40 White-only + 40 Black-only
  specialists, grouped into archetypes. It's a Vampire meta: a Vampire in
  88-100% of armies (1.7 each), with Wizards, Archers, Jesters and the new
  1-point Vassal as the filler; the family "2 Vampires + Jester + Vassals"
  is 50% of all-rounders, 65% of White and 88% of Black specialists. White's
  and Black's specialist pools look the same. The Vampire (6.5, measured
  worth 7.0-7.3 in every run) is the obvious next price question.
- **Run 17, the Vampire and Wizard repriced** (26 Oct): with Nicholas's
  retrained engine the Vampire measures 7.73 at 6.5 and the Wizard 8.66 at
  8. At Vampire 7.5 / Wizard 8.5 (tested on the server only) the Vampire
  reads 7.88 and the Wizard 8.75, and the meta changes: the Vampire falls
  from 88% to 52% of all-round armies, the Wizard disappears from the
  specialist pools, and the Queen (10, worth 10.4) plus the Ghost take over
  ("Queen + Ghost + Vassals" is 50-58% of specialists). Pawn 0.5, Grunt 0.65
  and Assassin 0.2 keep measuring under their prices. Decision open.

## Other open questions

- Whether to adopt the Front-row rule or the White-only quiet first move
  (run 9), and the wording for whichever is chosen.
- Vampire still ~0.7 under its worth (7.2 at 6.5); Archer ~0.5 under.
- Under the ability rule the Necromancer and Werewolf lost 0.3-0.4 of worth.
- The Berserker/Barbarian card note; Nicholas's Plusfish retrain.

## Running sims

On Mac's AWS server (64 cores, ~$2.54/hour, ~$0.50-2 a run).
