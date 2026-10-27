# The meta pool (October 2026, fourth search: the rules of 24-25 October)

Regrown on 25 October 2026 for Mac's rules of 24 and 25 October (an ability
and a promotion need a move first, White's first move may not attack, the
75-move rule), the 40-point budget, the 24-25 Oct prices and the Grunt,
Abatis and Vassal, with Plusfish after PR #28 (it knows those rules, and its
weights were retrained on them). It replaces run 7's pool, which was grown
before any of these rules (kept in `balance/results/run7/meta_pool.txt`).

It started from Mac's run 15 D pool (`balance/results/run15/report_d.md`),
grown under almost the same rules (everything but promotion needing a move
first), all ten still legal at today's prices:

```
plusfish meta --wide 38 --pool start_pool.txt --out meta_pool.txt --game-climb --king-exposed reject --rounds 15 --stable 6 --threads 19 --seed 1
```

(Nicholas's PC, 19 threads, 2 h 24 min.) Every round changed the pool, as in
every earlier search: it doesn't settle, so it stopped at 15 rounds. Only one
starting army (Wide 5b) is still in it.

**Is it stronger?** A round robin of all 20 armies (the new ten and the
starting ten; Wide 5b is in both), 20 games a pairing at 6,000 nodes
(`plusfish tournament`, seed 7): the new pool's armies average **58.8%**, the
starting pool's 41.2%. The new armies take the top five places (Wide 11c
first at 70.9%, +155 Elo); Wide 5b shares sixth. White's first-move edge in
those 3,800 games: +28 Elo (about 54% for White, inside chess's 54-56%).

## The pool

| Army | Name | Games vs the rest | Turn-0 eval | Pieces |
|---|---|---|---|---|
| `1(VS)JK(SQ)1(VS)1/GVVL(WW)AB(AB)` | Wide 15a | 57.2% (+51) | +137 | 2 Vampire, Archer, Squire, Bishop, Jester, Ghost, Lance, Werewolf, 2 Vassal, Abatis |
| `(VS)R(VS)K1(GR)(CT)1/JVV(RM)(RM)(WW)B(AB)` | Wide 11a | 54.4% (+31) | +13 | 2 Vampire, Rook, Bishop, Jester, Catapult, 2 Ram, Werewolf, Grunt, 2 Vassal, Abatis |
| `(GR)(GR)J1KW1R/(PD)VV(BR)(AB)(PD)(CV)1` | Wide 11c | 54.4% (+31) | +71 | Wizard, 2 Vampire, Rook, Jester, Cavalry, Barbarian, 2 Paladin, 2 Grunt, Abatis |
| `1A(CH)(CT)K(GR)(VS)1/(AB)B1(BR)(BR)VVR` | Wide 14b | 54.2% (+29) | +94 | 2 Vampire, Archer, Rook, Chariot, Bishop, Catapult, 2 Barbarian, Grunt, Vassal, Abatis |
| `(GA)2KC2N/B(GA)VJA(RM)(PD)A` | Wide 5b | 52.6% (+18) | -63 | Vampire, 2 Archer, Cannon, Bishop, Jester, 2 Galleon, Knight, Ram, Paladin |
| `(VS)W(VS)JK2(PA)/R1BV(NC)(BR)G(AB)` | Wide 13a | 51.0% (+7) | -34 | Wizard, Vampire, Rook, Bishop, Jester, Necromancer, Ghost, Barbarian, Parapet, 2 Vassal, Abatis |
| `1ANNK1G(VS)/1VV(CT)(NC)(BR)G(AB)` | Wide 14c | 48.9% (-8) | +88 | 2 Vampire, Archer, Necromancer, Catapult, 2 Ghost, 2 Knight, Barbarian, Vassal, Abatis |
| `(NC)1PNK(BR)(GR)G/(AB)JV(PA)(BR)BV(AB)` | Wide 4b | 46.8% (-22) | +111 | 2 Vampire, Bishop, Jester, Necromancer, Ghost, Knight, 2 Barbarian, Parapet, Grunt, Pawn, 2 Abatis |
| `(VS)(GR)(GR)1K(GR)1(GR)/(CH)(CV)VJQA1J` | Wide 1c | 43.5% (-46) | -70 | Queen, Vampire, Archer, Chariot, 2 Jester, Cavalry, 4 Grunt, Vassal |
| `(NC)(VS)NK(SQ)1R(AS)/(CV)(PD)(RM)LV1(RO)N` | Wide 2a | 36.9% (-93) | -347 | Vampire, Rook, Squire, Necromancer, Rogue, Cavalry, 2 Knight, Lance, Ram, Paladin, Vassal, Assassin |

All cost 40. Games = average score against the other nine (40 games a pair,
6,000 nodes); eval = average turn-0 advantage over them at 20,000 nodes (cp).

## What it shows

* **The Vampire is in all ten armies, and twice in seven** (16 in all). No
  other piece is in more than seven. At 6.5 it looks underpriced under the
  new rules (run 14 already measured it about +0.7 over its cost).
  Mac's call.
* **Cheap pawn types fill the armies:** Vassal in seven (10 in all), Abatis in
  seven (8), Grunt in five (9). The Abatis is a Wall at 0.5 points.
* **Abilities matter less now that they need a move first:** Archer in five
  armies, Ghost and Necromancer in four, Werewolf in two, the Bard in none.
* **The Queen is in only one army** at 10 points, the Wizard in two.
* Jester in seven, Bishop in six; Rook, Barbarian and Archer in five.
* Never picked: Bard, Elephant, Man, Princess.

# Earlier: the third search (Mac's new prices, 21 October)

Regrown on 21 October 2026 after Mac's price changes (Vampire 6.5, Princess
8.5, Squire 4, Galleon 3, Elephant 1, Paladin 1.5, Assassin 0.5; Queen 9).
Every army in the previous pool was over the 39 budget at the new prices, so
the search started from Standard alone:

```
plusfish meta --wide 64 --pool engine/plusfish/reports/meta_pool.txt --out meta_pool.txt --game-climb --king-exposed reject --rounds 15 --threads 64 --seed 1
```

(game version 1c9f93f, on the AWS sims server: c8g.16xlarge, 64 cores; 27
minutes). The full log and both balance reports from the same day are in
`balance/results/run2/`.

What it shows: no Vampire, Squire or Princess in any army now (they were in
nearly every strong army before the price rise). Cheap pieces fill the
armies instead: Assassin in all ten, Paladin in nine, Queen, Knight and
Barbarian in eight, Elephant, Bishop and Pawn in seven. The top army (Wide
15b) scores 58.9% against the rest; the pool still hadn't settled after 15
rounds (members kept changing), as with the earlier searches.

# Earlier: the second search

Ten armies that hold up best **in games** against each other, played by the
stronger Plusfish of PR #19 (its search work). File: `reports/meta_pool.txt`
(readable by `enginematch --pool`, `start-check --pool` and `meta --pool`).
Every army costs 39 under the current costs (Lance 3.5, Necromancer 3.5,
Ram 3, Archer 4.5), is legal, and none leaves a king attacked at the start
against another member or Standard.

The previous pool (PR #13) was found and judged with the engine from before
PR #18 and PR #19. Five of its armies stay; five new ones replace the rest.

## Step 1: the old pool, replayed with the new engine

The same ten armies plus Standard played a full round robin twice on the same
openings: once with the old engine (the one that chose them) and once with the
new one. 40 games per pair (20 with each colour), 6,000 nodes per move, as
before. Eval = the army's average turn-0 advantage over the other nine at
20,000 nodes, as the eval bar sees it (the old engine reproduced the old
pool's eval column exactly, so the method matches).

| Army | Old engine | New engine | Change | Rank old -> new | Eval old -> new |
|---|---|---|---|---|---|
| Wide 6a | 53.1% | 68.8% | +15.7 | 5 -> 1 | +60 -> +104 |
| Meta C 19 | 64.2% | 65.8% | +1.7 | 3 -> 2 | +123 -> +91 |
| Wide 8b | 70.1% | 58.5% | -11.7 | 1 -> 3 | +255 -> +190 |
| Wide 7a | 64.9% | 56.7% | -8.2 | 2 -> 4 | +138 -> +116 |
| Wide 6c | 54.6% | 54.9% | +0.3 | 4 -> 5 | +19 -> +10 |
| Meta C 63 | 51.1% | 52.2% | +1.1 | 6 -> 6 | -50 -> -74 |
| Wide 3b | 37.9% | 46.1% | +8.2 | 8 -> 7 | -20 -> -52 |
| Wide 1a | 39.4% | 36.4% | -3.1 | 7 -> 8 | -214 -> -164 |
| Meta C 71 | 37.1% | 33.5% | -3.6 | 9 -> 9 | -163 -> -128 |
| Wide 3c | 27.6% | 27.2% | -0.4 | 10 -> 10 | -149 -> -92 |

What changed: the top four swapped places (each army's score is over 360
games, so swings of 10-16 points are real, not luck), the bottom stayed the
bottom, and Wide 3c was clearly weak with both engines. The eval's opinion
of the armies hardly moved (old and new evals correlate 0.97), but it now
agrees a little less with the games (0.82, was 0.90). Every army still beat
Standard 97.5-100%.

## Step 2: searching again

`meta --wide` from the old pool with the new engine, same settings as the
PR #13 run (38 climbers a round, game climb, starts with a king attacked
rejected, 19 threads), 17 rounds in two runs (the first stopped during round
10 at a 2-hour limit and the second carried on from its round-9 pool):

```
plusfish meta --wide 38 --pool reports/meta_pool.txt --out wide_search.txt --game-climb --king-exposed reject --rounds 12 --threads 19 --seed 21
plusfish meta --wide 38 --pool leg2_start.txt --out leg2.txt --game-climb --king-exposed reject --rounds 8 --threads 19 --seed 22 --name Leg2
```

About 3.5 hours. New armies are called "Search" + the round they were found
in (the second run's rounds count on from 10).

**It never settled.** 16 of the 17 rounds changed the pool, and armies rose
and fell as the others changed around them: one army (Search 11a) joined at
72% against the pool and was down to 38.5% six rounds later; Search 9a went
from 59% to 31.5%. The armies beat each other in circles, like
rock-paper-scissors, so "best against the current pool" keeps moving. By the
end, none of the old armies was left.

## Step 3: was the new pool better? Only a little

Each of the run's ten armies played each of the old ten (and Standard), 4,000
games: **the new pool scored 54.0% (+28 Elo)** against the old one. Three old
armies (Meta C 19, Wide 6a, Wide 6c) actually scored over 50% against the new
pool. So the run's last pool wasn't clearly the ten best armies available.

So the final ten were picked from all **20** (old ten + run's ten) by games,
with every pair played on the same openings: near-copies (fewer than 3 pieces
apart) keep only the better one (Search 16b beat Wide 8b, Search 16c beat
Wide 3c), then the army with the lowest score against the others still in is
dropped, one at a time, until ten remain (the same drop rule `meta --wide`
uses). Dropped in order: Search 16c, Search 14a, Wide 1a, Search 16a, Wide
3b, Search 9a, Search 11a, Wide 7a (the closest call: 39.6% against the
others still in at that point).

## The pool

Games = mean score against the other nine over 40 games per pair (20 per
colour, 6,000 nodes per move). As White / as Black = the same split by
colour. Eval = mean turn-0 advantage over the other nine at 20,000 nodes
(centipawns). vs Standard = 40 games, 6,000 nodes per move.

| Army | Text | Games (Elo) | As White / as Black | Eval | vs Standard |
|---|---|---|---|---|---|
| Wide 6a (old): Queen, 2 Archer, Vampire, Bishop, 2 Knight, 2 Squire, 2 Pawn | `Q2KNVPA/1A(SQ)(SQ)NP1B` | 56.7% (+47) | 73.6% / 39.7% | +72 | 100% |
| Search 17c: Queen, 2 Vampire, Bard, Necromancer, Bishop, 2 Knight, 2 Squire | `1(SQ)VK1NQ1/1N(BD)(SQ)VB1(NC)` | 56.7% (+47) | 66.7% / 46.7% | +82 | 98.8% |
| Meta C 19 (old): 2 Archer, Cannon, 2 Vampire, Necromancer, 2 Ram, 2 Squire, Berserker | `1V(SQ)CKV(SQ)1/2AA(RM)(BR)(RM)(NC)` | 53.6% (+25) | 65.8% / 41.4% | -12 | 100% |
| Wide 6c (old): Wizard, Rook, Archer, 2 Vampire, Necromancer, Ram, 2 Squire, Pawn | `(NC)VPKW2R/1(SQ)A(RM)V1(SQ)1` | 53.2% (+22) | 58.9% / 47.5% | -1 | 98.8% |
| Search 15a: Queen, 2 Vampire, Lance, Necromancer, 2 Bishop, Ram, 2 Squire | `3K1(RM)QB/B(SQ)1(SQ)VLV(NC)` | 52.9% (+20) | 60.8% / 45.0% | -10 | 100% |
| Search 15c: Queen, Princess, 2 Vampire, Necromancer, 2 Bishop, Cavalry, Berserker | `1(BR)1K(PR)2Q/BB(CV)VV1(NC)1` | 51.7% (+12) | 52.5% / 50.8% | +141 | 100% |
| Search 16b: Rook, 2 Archer, Vampire, 2 Bishop, Man, 2 Ram, 2 Squire | `1B(SQ)KV1R1/AMB(RM)(RM)(SQ)1A` | 48.6% (-10) | 68.9% / 28.3% | -4 | 100% |
| Search 17a: Queen, 2 Archer, 2 Vampire, Lance, Necromancer, Parapet, Squire | `1(NC)(SQ)K4/LVAVQ1(PA)A` | 47.8% (-15) | 59.2% / 36.4% | +52 | 100% |
| Meta C 71 (old): Queen, Vampire, Bard, Necromancer, Bishop, Knight, Ram, 2 Squire, 4 Pawn | `PP(SQ)NK(NC)P1/Q(RM)(SQ)V(BD)B1P` | 42.2% (-54) | 50.0% / 34.5% | -97 | 100% |
| Meta C 63 (old): Wizard, 2 Archer, Vampire, Lance, Necromancer, Bishop, Ram, Squire, 2 Pawn | `1P(NC)K1PW1/B1(SQ)(RM)VALA` | 36.7% (-95) | 52.5% / 20.8% | -224 | 97.5% |

Search 16b is Wide 8b (the old pool's top army) with its Knight swapped for a
Man and rearranged.

## What it shows

* **The pool is a circle, not a ladder.** The scores are much closer together
  than before (36.7-56.7%, was 25.8-69.6%), and many pairs are lopsided
  either way (Search 15a beat Search 11a 40-0; Wide 6c lost to Search 17a
  11.5-28.5 but beat Search 16b 22.5-17.5). With a stronger engine there's no
  single best army, which is good for the game: every strong army has a
  counter.
* **The core is the same**: a Vampire in all ten (six with two) and a
  Necromancer in eight. Compared with the old pool, there are more Queens
  (6 of 10, was 4) and Lances (3, was 1), fewer Squires (9, was 10) and Rams
  (6, was 8), and fewer Pawns (9 in all, was 18).
* **The eval is a weaker guide than before**: the eval and games columns
  correlate 0.82 by value but only 0.54 by rank (Search 15c is first by eval
  and sixth in games). Games, not the eval, should keep deciding.
* **White's edge is big**: White scored 60-61% in every set of games here
  (59.6% with the old engine). Some pairs are almost all White (Wide 8b won
  all 20 games as White against Wide 6a and lost all 20 as Black).
* **Standard is far behind**: every army beats it 97.5-100%.
* **This is still the pool for once the temporary "king exposed" rule is
  replaced.** Like the PR #13 run, this search threw out any army that leaves
  the other king attacked at the start. Under the game's current rule (that
  side loses at once), the PR #13 write-up found Cannon armies that win
  instantly as White (a Cannon on e1 with nothing on e2,
  `V1(SQ)KC2(SQ)/ABNC1(BR)BA`); that hasn't changed.
* **Pricing hints for Mac (nothing changed)**: the Lance (3.5 since its
  rise from 2.5) turned up in 6 of the run's last 10 armies, more than any
  piece except Vampire, Necromancer, Queen and Bishop, so it may still be
  cheap. The Queen is back in most armies. Squires and Rams, everywhere
  before, are now in fewer armies.

## Files

Run inputs, logs and the scripts for the checks (`rr.py` round robins,
`cross.py` new-vs-old, `select.py` the final pick from 20, `compare.py` old
vs new engine) are outside the repo, in Nicholas's `work/meta-search/`.
