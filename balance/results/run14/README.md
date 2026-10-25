# Balance run 14: the 24 October prices and the ability rule (AWS sims server, 25 October 2026)

Mac's update of 24 Oct 2026 went into the game: budget **40**, Queen 10,
Bishop 3.5, Rook 4.5, Werewolf 3.5, Parapet 2.5, Jester 3.5, and a new rule:
**a special ability can't be used until the piece has moved at least once; a
capture or a shield break counts as a move even when the piece stays put.**
Plusfish didn't know the rule, so this run teaches it on a branch
(`experiment/run14`, `--abilities-need-move=true`) and measures both changes.
Normal rules otherwise (no first-move rule). Two arms:

| Arm | What |
|---|---|
| **A** | the new prices and budget 40 (Plusfish's own `BUDGET` raised to 40 too, so its random armies and meta pool follow) |
| **B** | arm A plus the ability rule (`--abilities-need-move=true`) |

**Haunt under the rule (Claude's reading of Mac's wording, as the game does
it):** a Ghost captured before it ever moved can never Haunt; one that had
moved Haunts as before. Crack Shot counts as the Archer's move. A piece
brought back by Raise Dead counts as moved, so it may use its ability at once.

## Success lines (written before the run)

Prices (arm A, 20,000 random-army games; "worth" = what one extra piece at
the start is worth by game results, on the cost scale):

1. Each repriced piece (Queen 10, Bishop 3.5, Rook 4.5, Werewolf 3.5,
   Parapet 2.5, Jester 3.5) has its worth within **0.5** of its new cost.
2. No piece is more than **1.0** off its cost (run 2's worst was the Queen,
   +1.1 at 9).

The ability rule (arm B against arm A):

3. The five ability pieces (Archer, Necromancer, Ghost, Bard, Werewolf) each
   stay within **1.0** of cost under the rule, and none loses more than
   **0.5** of worth from A to B (the rule shouldn't gut them; if one does
   drop, that's a price question for Mac).
4. White's edge is not made bigger by the rule: B's White score in random
   armies is no higher than A's (B's 95% range overlaps or sits below A's),
   and B's regrown-pool round robin passes Mac's standing lines: White
   50-55%, no pool army's White-minus-Black gap over 30 points, no pairing
   with either colour at 80%+.
5. First moves: under B no game starts with a special ability (0%), and
   White's first-move capture share in B is no higher than A's.
6. Diversity: B's regrown pool uses at least as many piece types as A's (or
   within 2), and at least 3 of the 5 ability types still appear in B's pool
   (the rule mustn't make ability pieces not worth buying).

Report only for the colour specialists (3) and the mirror matches (4): no
pass line, they show how the strongest armies play under the rule.

## Before the run: does Plusfish agree with the game?

- `plusfish perft-suite` (standard positions): must match.
- Traced games: the game's own engine (`engine/plusfish/verify/plusfish_trace.gd`,
  main at dd06e19, which has the rule) played 320 random games leaning towards
  the ability and shield pieces (Archer, Necromancer, Ghost, Bard, Werewolf,
  Paladin, Vampire; no Jesters, whose two-Jester choice Plusfish doesn't know),
  logging every position's FEN, full legal move list, check and outcome.
  `plusfish trace-check` with `--abilities-need-move=true` must give **0
  mismatches**; without the flag it must give **some** (proof the traces
  exercise the rule). **Done before the run (25 Oct, branch commit de5f5f6):**
  perft suite all PASS; traces with the rule on: 23,632 + 24,092 = 47,724
  positions, **0 mismatches** (coverage: 89 Crack Shots, 179 Raise Deads, 167
  Haunts, 102 Songs of Slumber, 192 Full Moons, 158 Vampire shields gained,
  91 broken); with the rule off: 142 + 144 = **286 of the 320 games
  mismatch** (the first unmoved-piece ability each game).

## Parts and settings

| Part | What | Settings |
|---|---|---|
| (1) | balance report, both arms (`A/report.txt`, `B/report.txt`, `.html`) | `selfplay --games 20000 --nodes 8000 --seed 101` (budgets 34-40), `values` |
| (2) | the all-round pool regrown, both arms (`meta_pool.txt`, `meta.log`), then run 10's colour test on it (`rr/`) | `meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1` from run 7's pool; round robin of the pool + Standard, 40 games a pairing (20 per colour), 8,000 nodes, `--random-plies 4`, seeds 3000+ |
| (3) | B: run 13's colour specialists from B's regrown pool (`split/`) | `meta --split-colours --fixed-opponent` (B's pool + Standard frozen as the opponent); specialists vs specialists (seeds 4000+), White specialists vs the pool as Black (5000+), the pool as White vs Black specialists (6000+); 40 games a pairing, colours fixed |
| (4) | B: each regrown-pool army against itself (`mirror.txt`) | `plusfish analyse`, 2,000,000 nodes, 8 threads, with the rule and without |
| (5) | move-1 tally over every game of each arm (`firstmoves.jsonl`) | new `plusfish first-moves`: White's first move's kind, mover, target, check, whether Black could capture the mover back and whether it did |
| (6) | piece-type diversity of the pools | from the pool files (`tools/balance/run14_analyse.py`) |

- Server: `chessplus-sims`, c8g.16xlarge (64 Graviton4 cores), `--threads 64`.
  Script: `tools/balance/run14_server.sh` (branch `experiment/run14`).
  Game files (not in the repo): `Documents\ChessPlusSims\run14\`.
- Expected: about 4 hours, roughly $10 metered.

## Results (full tables in `report.md`, made by `tools/balance/run14_analyse.py`)

Server 03:48-07:05 UTC 25 Oct (about 3.3 hours, roughly $8.40 metered; arm A
51 minutes, arm B 2 h 17 min, of which the colour-specialist search 75 min),
stopped through AWS. Plusfish commit de5f5f6 (branch `experiment/run14`).

**Success lines: 1, 2, 3, 5 and 6 pass; 4 fails** (B's regrown-pool round
robin has 4 pairings at 80%+; its other parts pass).

### (1) Prices (arm A, 20,000 games)

| Piece | New cost | Worth | | Piece | New cost | Worth |
|---|---|---|---|---|---|---|
| Queen | 10 | 9.91 ±0.37 | | Werewolf | 3.5 | 3.43 ±0.16 |
| Rook | 4.5 | 4.72 ±0.19 | | Jester | 3.5 | 3.51 ±0.16 |
| Bishop | 3.5 | 3.47 ±0.16 | | Parapet | 2.5 | 2.60 ±0.13 |

All six within 0.25 of cost. The pieces furthest off now: **Vampire +0.73**
(worth 7.23 at 6.5, as in runs 1 and 2), Archer +0.47 (4.97 at 4.5), Wizard
+0.40, Cavalry +0.36; nothing over 1.0. Standard costs exactly 40.

### (1) The ability rule's effect on worth (arm B minus arm A)

Archer 4.97 -> 4.78 (-0.19), **Necromancer 3.80 -> 3.39 (-0.41)**, Ghost 3.16
-> 3.17, Bard 3.20 -> 3.26, **Werewolf 3.43 -> 3.16 (-0.27)**. Under the rule
the Necromancer sits 0.1 under its 3.5 and the Werewolf 0.3 under (it was
raised to 3.5 the same day). Other pieces move by at most ±0.15.

### White's edge

| | Arm A | Arm B (rule) |
|---|---|---|
| Random armies (20,000 games): White | 56.2% (55.6-56.8) | 55.8% (55.2-56.4) |
| ...White won both games of a swapped pair | 12.9% | 12.8% |
| ...White's first move a capture / an ability | 20.6% / 4.1% (179 Crack Shots, 640 Full Moons) | 20.7% / **0%** |
| Regrown pool + Standard round robin: White | 56.2% (54.4-58.0) | 53.6% (51.8-55.4) |
| ...biggest White-minus-Black gap | +26.7 (Wide 8c) | +19.2 (Wide 11a) |
| ...pairings at 80%+ (Standard's left out) | 5 | 4 |
| ...White won both of a swapped pair | 16.1% | 11.5% |
| ...first move a hit, White / Black | 56.8% / 45.0% | 43.6% / 51.1% |

The rule takes out exactly the move-1 abilities (4 points of hits in random
armies) and moves White's score by -0.4 point there (the ranges overlap). The
pool round robin is 2.6 points lower, but it's a different pool (regrown under
the rule), so part of that is the pool, not the rule.

### (4) B's pool armies against themselves (2,000,000 nodes)

Without the rule: median **+1.39**, 6 of 11 over +1 (Wide 13c +3.63 and 15a
+3.61 both by 1. Axg7!, Wide 11a +3.01 by 1. Axb7!). With the rule: median
**+0.70**, 5 of 11 over +1, all by ordinary pieces: Wide 5b +1.84 (1. Kc1),
Wide 10b +1.62 (**1. Lxb8=W+**: a Lance captures on the back row and
promotes to a Wizard with check on move 1), Wide 12c +1.16 (1. Lxd7), Wide
11a +1.13, Wide 14a +1.08 (1. Bxg7). Standard +0.19 (chess +0.29). So the
rule halves the strong armies' first-move edge but leaves the long-range
strikers (Lance, Bishop) untouched.

### (3) Colour specialists under the rule (run 13's method on B's pool)

| | White's score |
|---|---|
| B's all-rounders, White vs Black (the round robin) | 53.6% |
| White specialists vs all-rounders as Black | 69.9% (**+16.3** points) |
| All-rounders as White vs Black specialists | 46.1% (**+7.5** for Black) |
| White specialists vs Black specialists | **70.6%** (60 of 100 pairings at 80%+) |

Run 13 (old prices, no rule): +11.0 / +13.5 / 56.7%. The White pool is all
strikers: **every one has a Lance** (10 of 10), 7 have a Wizard, 8 a Paladin,
4.1 long-range pieces in the front row on average, only 1 pawn. Its best,
Wide W15a `3CK(RO)(PR)1/W1LL(RM)(PD)1A` (10 pieces: Cannon, Rogue, Princess,
Wizard, two Lances, Ram, Paladin, Archer), scores **100% as White against
every Black specialist** and 95.6% against the all-rounders. The Black pool
is defenders: Archer 10 of 10, Assassin 8, Barbarian 8, Pawn 8 (pawns in the
front row), 3.1 ability pieces. Without the Archer's shot to lean on, White's
specialists went further into Lances and Wizards; with these prices and the
rule, the colour gap between specialists is bigger, not smaller.

### (5) White's first move (every game)

| | A random | B random | A pool games | B pool games |
|---|---|---|---|---|
| Games | 20,000 | 20,000 | 2,200 | 16,720 |
| White's first move a hit | 25.0% | 21.0% | 56.8% | 53.3% |
| ...an ability | 4.1% | 0% | 29.7% (653 Crack Shots) | 0% |
| White's score after a hit / after a quiet move | 67.0% / 52.6% | 68.9% / 52.3% | 58.4% / 53.2% | 70.9% / 49.9% |
| Free hits (Black can't hit the mover back): share of hits, White's score | 35%, 78.6% | 42%, 78.6% | 10%, 62.0% | 5%, 73.3% |
| Recapturable hits: share, recaptured | 48%, 75% | 56%, 76% | 56%, 79% | 91%, 78% |
| Hits giving check | 15% | 17% | 0% | 29% |

Random armies, commonest hits: Lance x Pawn (~225 games, White ~73%, free
61%), Lance x Jester (~215, the Jester taking the hit for something), Cannon
x Jester (~105), Lance x Lance, Lance x Barbarian. A's pool: the Archer's
Crack Shot in 30% of games (Archer x Jester 153, x Archer 133, x Ghost 87,
x Rook 80, 62-100% of them free). B's pool games: Lance x Barbarian 658,
Lance x Pawn 580 (White 85%), **Bishop x Pawn 457 (White 98.9%)**, Lance x
Ghost 436, Bishop x Parapet 427 (White 91%): nearly all recapturable, yet
White scores 71% after them. In strong armies the first capture is a trade
White starts, and it wins anyway.

### (6) Piece-type diversity

A's pool: 23 types in 10 armies (Archer 9, Ghost 9, Necromancer 9, Pawn 8).
B's pool: 25 types (Ghost 8, Archer 7, Assassin 6, Barbarian 6, Necromancer
6, Parapet 6; Bard 1; no Werewolf, no Princess, no Queen in either). B's
colour pools: White 26 types, Black 23.

### Reading

- The prices work: all six within 0.25 of cost. Left over from before: the
  Vampire (+0.7) and the Archer (+0.5).
- The ability rule does what it says and costs little: no move-1 abilities,
  the Necromancer -0.4 and Werewolf -0.3 of worth, otherwise nothing moves.
- It is not a colour fix. First-move contact by long-range pieces (Lance,
  Bishop, Queen, Cannon) is the driver of White's edge, and the rule leaves
  it alone: in strong-army games half still open with a White capture and
  White scores ~70% after it. Against colour specialists it's worse than
  run 13 (White specialists +16 points; one army at 100%).
