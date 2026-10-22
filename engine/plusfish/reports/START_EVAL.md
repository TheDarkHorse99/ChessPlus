# How well Plusfish judges the start of a game (October 2026)

The question: when Plusfish scores a starting position (the eval bar at move
0, and every turn-0 score the meta pool is built on), how close is it to how
the game actually goes? And where it's wrong, why?

## How it was measured

`plusfish drift` played 12,000 games with Plusfish's top move every turn
(40,000 nodes a move), logging its score at every ply: 8,000 between random
full-budget armies, and 4,000 where about half the armies came from the meta
pool. Each start was also scored the way the eval bar does it: a fresh
search of 20,000 nodes (the web) and 150,000 (the PC).

"The truth" for a start is how the game went: its result, and the average
win chance Plusfish gave over plies 16 to 40 (once the armies have met; much
less noisy than one game's result). Scores become win chances with
1 / (1 + 10^(-score / 720)), the curve that fits these games.

Every 4th game was kept back for testing (3,000 games); everything below is
measured on those.

## What was wrong

The biggest disagreements were armies Plusfish thought were 4 to 6 pawns
ahead that went on to lose. Splitting each start score into its parts
(material, mobility, where pieces stand, abilities, king safety, ...) and
checking which parts the later scores disagreed with:

* **Where pieces stand** (`reach`, how many squares a piece could reach from
  its square on an empty board) counted 60% too much at the start, and
  mobility 30% too much. These weights were learned from middlegame
  positions, where a piece still on its back row is usually stuck and the
  game going badly. At move 0 *every* piece is on its first two rows, and
  that means nothing yet.
* **The Vampire** was the worst case. It can't move straight forward, so
  from its back row it reaches few squares, and its learned reach weight is
  large: every Vampire lost about 2 pawns of start score just for standing
  where armies put it. With Vampires in random armies that alone swung start
  scores by about a pawn either way.
* **Unused abilities** counted about 20% too little at the start (there's a
  whole game left to use them).

Smaller versions of the same mistake hit the Catapult, Cavalry and Knight.

## The fix: opening terms

Each piece type got opening versions of its terms (material, mobility,
reach, being on the second row, unused ability, plus one for whose turn it
is). Each is multiplied by the share of pieces that haven't moved yet, so it
counts fully at move 0 and fades as the armies develop. They were fitted to
the later scores in the first 40 plies of the 9,000 training games; nothing
else in the evaluation changed.

What they say each piece is really worth *at the start*, compared with
before (centipawns, about 100 = a pawn; middlegame weights):

| More than Plusfish thought | | Less than Plusfish thought | |
|---|---|---|---|
| Vampire | +154 | Rook | -43 |
| Princess | +70 | Queen | -37 |
| Lance | +68 | Man, Wizard | -24 |
| Werewolf | +55 | Knight | -18 |
| Necromancer | +51 | Assassin | -17 |
| Ghost | +50 | Chariot | -16 |
| Cannon | +33 | Ram | -15 |

These are Plusfish's own judgement of the start, not costs: the balance
report is still the place for those.

## Results

Brier score = average squared gap between the predicted win chance and the
result (lower is better; always saying 58% scores 0.166). "Skill" = how much
of that it removes.

2,000 test games between random armies:

| Start score | Brier vs result | Skill | Error vs later scores | Correlation with later scores |
|---|---|---|---|---|
| Before, 20,000 nodes (web) | 0.1395 | 0.16 | 0.0179 | 0.83 |
| Before, 150,000 nodes (PC) | 0.1371 | 0.18 | 0.0161 | 0.85 |
| Before, 1,000,000 nodes | 0.1346 | 0.19 | 0.0147 | 0.86 |
| **After, 20,000 nodes (web)** | **0.1194** | **0.28** | **0.0126** | **0.88** |
| **After, 150,000 nodes (PC)** | **0.1180** | **0.29** | **0.0116** | **0.89** |
| After, 1,000,000 nodes | 0.1175 | 0.29 | 0.0109 | 0.89 |

1,000 test games with meta pool armies on one or both sides: Brier 0.1181 →
0.1039 at 20,000 nodes, 0.1167 → 0.1019 at 150,000.

At the web's budget Plusfish now judges the start better than it used to
with 50 times the search. Searching deeper helps little either way, so what's
left is mostly not search depth: some games are decided by a tactic a few
moves in, and one game's result is noisy.

A second check with `start-check` (each army pairing played 40 times, 20
with each colour; correlation of the start score with the real score):

| Start score | 150 random pairings, 20k / 150k | Meta pool + Standard (55), 20k / 150k |
|---|---|---|
| Before | 0.63 / 0.65 (picks the right side in 76% / 78% of clear cases) | 0.73 / 0.77 |
| After | 0.73 / 0.75 (85% / 89%) | 0.73 / 0.77 |

The meta pool was judged as well as before: its armies have no Vampires
and few pawns, where the biggest corrections are.

Examples (score in pawns, White's view; "later" = average over plies 16-40):

| Game | Before (20k) | After (20k) | Later | Result |
|---|---|---|---|---|
| #999 | -4.6 | -1.3 | +5.5 | White won |
| #778 | -5.1 | -1.7 | +6.8 | White won |
| #58 | +6.1 | +3.0 | -0.2 | Black won |

It also plays better, since the opening is where every game starts:
+35 ±10 Elo at 6,000 nodes a move and +43 ±13 at 20,000 (the web eval
bar's budget) with random armies. With the meta pool's ten armies it plays
about the same as before (+7 ±12). See ELO_LOG #35.

## Still open

* A shielded Vampire walking through the enemy camp is misjudged in the
  middlegame too (one game: Plusfish thought it was 14 points up and lost).
  That's the middlegame evaluation, not the start.
* Vampires are worth a little more against armies with many pawns (about
  half a pawn against eight pawns); too small to add a term for.
* The later scores and the results disagree a little: Plusfish's middlegame
  scores give White less than White actually scores (56% vs 58%).
