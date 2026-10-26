# Balance run 17: the Vampire and Wizard repriced (AWS sims server, 26 October 2026)

Mac's question after run 16's Vampire meta (26 Oct 2026): what the pieces are
worth at today's prices, and what happens to the values and to the meta when
the Vampire goes to 7 or 7.5 and the Wizard to 8.5. Plusfish is main's engine
(Nicholas's PR #28, every rule the game has) with run 16's split-colours meta
search (branch `experiment/meta-share`). Report only, with one success line.

## Parts

| Part | What | Settings |
|---|---|---|
| (1) | balance report at today's prices (`A/report.txt`), reporting the Vampire, Wizard, Queen, Jester, Vassal, Grunt and Abatis in particular | `selfplay --games 20000 --nodes 8000 --seed 101`, `values` |
| | **the Vampire's new price**: Mac said "7 or 7.5"; the script takes its worth from (1) rounded to the nearer half point, kept within 7-7.5; the Wizard goes to 8.5; a copy of the piece files with those values (`pieces_b/`, the game unchanged) | |
| (2) | the balance report again at the new prices (`B/report.txt`) | same |
| (3) | run 16's meta-share method at the new prices (`B/meta/`): 4 independent all-round searches from scratch (40 armies), 4 specialist searches against the top 3 of each (40 White, 40 Black), all-rounders against specialists; archetype shares compared with run 16's | run 16's settings, the same four seeds |

**Success line (written before the run):** at the new prices the Vampire is
in **under 60% of the all-round armies** (run 16: 88%).

- Server: `chessplus-sims`, c8g.16xlarge (64 Graviton4 cores). Script:
  `tools/balance/run17_server.sh` (the branch). Expected: about 5 hours,
  roughly $13 metered.
- Game files (not in the repo): `Documents\ChessPlusSims\run17\`.

## Results (full tables in `report.md`, `tools/balance/run17_analyse.py`)

Server 05:59-12:03 UTC 26 Oct (6.1 hours, about $15.50 metered; the meta
part took 5.7 hours, an hour longer than run 16's), stopped through AWS.
Branch commit 74345f8. **The script picked Vampire 7.5** (measured worth 7.73
at today's prices rounds to 7.5), Wizard 8.5. **Success line: passed** (the
Vampire is in 52.5% of the all-rounders; run 16: 87.5%).

### (1) Today's prices, Nicholas's retrained Plusfish (20,000 games)

| Piece | Cost | Worth | |
|---|---|---|---|
| **Vampire** | 6.5 | **7.73 ±0.24** | underpriced by ~1.2 (7.0-7.3 in the older engine's runs) |
| **Wizard** | 8 | **8.66 ±0.29** | underpriced by ~0.7 |
| **Queen** | 10 | 10.19 ±0.35 | about right |
| **Jester** | 3.5 | 3.65 ±0.15 | about right (+0.2) |
| **Vassal** | 1 | 0.96 ±0.06 | about right |
| **Grunt** | 1 | **0.64 ±0.06** | overpriced by ~0.4 (0.89 in run 15 at 1.5) |
| **Abatis** | 0.5 | 0.47 ±0.06 | about right |

Also off by 0.3 or more: Pawn **0.51** (-0.5), Cannon 3.56 (-0.4), Elephant
0.71, Paladin 1.24, Man 2.74, Bard 3.20, Assassin 0.23 (-0.3 each); Rook
4.84, Princess 8.79 (+0.3). White 53.7% in these games (the quiet first move
is in the engine now; run 15's arm C, before it, was 56.4%).

### (2) At Vampire 7.5, Wizard 8.5 (20,000 games)

Vampire **7.88** (+0.4, "slightly underpriced"), Wizard **8.75** (about
right), Queen 10.39 (+0.4), Jester 3.72, Vassal 0.93, Grunt 0.69, Abatis 0.45;
everything else within 0.5 except the Pawn (0.49) and Cannon (3.55). White
53.4%.

### (3) The meta at the new prices, against run 16's

| Piece | All-round 16 -> 17 | White specialists 16 -> 17 | Black specialists 16 -> 17 |
|---|---|---|---|
| **Vampire** | 88% -> **52%** (1.7 -> 1.1 each) | 95% -> 45% | 100% -> 38% |
| **Wizard** | 35% -> **10%** | 52% -> **0%** | 57% -> **0%** |
| **Queen** | 5% -> **20%** | 2% -> **52%** | 2% -> **57%** |
| Ghost | 35% -> **72%** | 5% -> **75%** | 5% -> **57%** |
| Werewolf | 15% -> 40% | 10% -> 32% | 0% -> 35% |
| Knight | 28% -> 52% | 22% -> 52% | 15% -> 38% |
| Cavalry | 20% -> 28% | 10% -> 35% | 25% -> 62% |
| Necromancer | 38% -> 38% | 55% -> 20% | 48% -> 8% |
| Archer | 60% -> 62% | 70% -> 52% | 70% -> 50% |
| Jester | 57% -> 65% | 72% -> 65% | 82% -> 65% |
| Vassal | 75% -> 90% (2.2 each) | 90% -> 100% | 85% -> 90% |
| Grunt / Abatis | 48% / 38% -> 45% / 48% | 60% / 42% -> 48% / 45% | 48% / 48% -> 48% / 45% |
| Pawn | 22% -> 8% | 10% -> 8% | 5% -> 12% |

Families (55% of points in common), run 16 -> run 17:

| Family | All-round | White-only | Black-only |
|---|---|---|---|
| 2 Vampire + Jester + 2 Vassal | 38% -> **5%** | 70% -> **12%** | 80% -> **22%** |
| **Queen + Ghost + 2 Vassal** | 2% -> **28%** | 0% -> **58%** | 2% -> **50%** |
| Vampire + Jester + Necromancer | 15% -> 10% | 18% -> 8% | 18% -> 8% |
| Vampire + 2 Barbarian + Ghost | 10% -> 20% | 0% -> 2% | - |
| Archer + Vampire + 2 Knight | 2% -> 8% | 0% -> 5% | 0% -> 8% |

All-rounders against the specialists: 43.2% as White against the Black
specialists, 37.5% as Black against the White ones (run 16: 43.0% / 38.0%); 3
of 40 hold 50%+ both ways, as in run 16.

### Reading

- **The Vampire meta breaks at 7.5**: from nearly every army to about half
  the all-rounders and 40-45% of specialists, one each instead of two. At
  7.5 its worth still reads +0.4 (7.88), so 8 would be the measured price;
  7.5 is the first price where the search stops stacking it.
- **The Wizard at 8.5 is priced right by worth (8.75) but the meta drops it
  entirely** in favour of the **Queen** (10, worth 10.4): the specialist
  pools go from Wizard 52-57% / Queen 2% to Wizard 0% / Queen 52-57%. The
  meta's concentration moves rather than disappears: "Queen + Ghost +
  Vassals" becomes 50-58% of the specialists, where "2 Vampires + Jester +
  Vassals" was 70-80%.
- The Ghost (3, worth 3.1-3.2) is the other winner, 5% -> 57-75% of
  specialists; Werewolf, Knight and Cavalry rise with it. Pawn, Grunt and
  Assassin keep measuring under their prices.
- White's and Black's pools still look alike (the quiet first move).
