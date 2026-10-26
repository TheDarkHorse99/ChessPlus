# Balance run 16: the meta by share (AWS sims server, 26 October 2026)

Mac's question (26 Oct 2026): where do the bots think the meta is now, with
the rules and prices of 24-25 October, but not as a top-10 pool: as a
**percentage breakdown of the armies in the meta**, with similar builds
counted as one archetype, **split into White-only armies, Black-only armies
and all-round armies** (all-rounders counted where they hold up against the
colour specialists). Report only, no pass/fail lines.

## Method

Plusfish is Nicholas's build of PR #28 (every rule the game has, retrained
weights) with the split-colours meta search merged in (branch
`experiment/meta-share`). Four independent runs of everything ("seeds"), so
the percentages come from a population rather than one search's ten armies:

| Phase | What | Settings |
|---|---|---|
| 1 | 4 all-round searches **from scratch** (Standard plus random climbers; no starting pool, so the official pool doesn't steer them), 10 armies each -> 40 all-rounders | `meta --wide 64 --game-climb --king-exposed reject --rounds 12 --seed 1..4`, two searches at a time with 32 threads each |
| 2 | the opponent set for the specialists: the top 3 of each all-round pool (12 armies), frozen | |
| 3 | 4 specialist searches: a White pool and a Black pool each, judged only as that colour against the opponent set -> 40 White specialists, 40 Black specialists | `--split-colours --fixed-opponent --pool opponents.txt`, same settings |
| 4 | all-rounders against the specialists: every all-rounder as White against every Black specialist, every White specialist against every all-rounder as Black | 20 games a pairing, colours fixed, 8,000 nodes, `--random-plies 4` (3,200 pairings) |

**Archetypes** (`tools/balance/run16_analyse.py`): an army is its piece
list, placement ignored. Two armies are "similar" when the points they have
in common (summing the lesser count of each piece type, times its cost) are
at least 70% of the budget; archetypes are built greedily from the most
central armies and named by the pieces most of their members share. The
report gives each archetype's share of the all-rounders, of the White
specialists and of the Black specialists, with an example army, plus the
all-rounders that score 50% or more both as White against the Black
specialists and as Black against the White specialists.

- Server: `chessplus-sims`, c8g.16xlarge (64 Graviton4 cores). Script:
  `tools/balance/run16_server.sh` (the branch). Expected: about 6-7 hours,
  roughly $17 metered.
- Game files (not in the repo): `Documents\ChessPlusSims\run16\`.

## Results (`report.md` at 70% similarity, `report_coarse.md` at 55%)

Server 00:28-05:12 UTC 26 Oct (4.6 hours of searching and games; a second
short start of 5 minutes to fetch the results after a dropped copy; about
$12.50 metered), stopped through AWS. Branch commit 48c9201.

### The meta in one line

**The Vampire is in nearly every strong army** (88% of all-rounders, 95% of
White specialists, 100% of Black specialists, 1.7 of them on average), with
the Wizard (35-58%), Archer (60-70%), Jester (58-82%) and the new 1-point
**Vassal as the filler of choice** (75-90% of armies, about 2 each). The
Grunt is in half the armies, the Abatis in 40-48%; the Pawn in 5-22%. Queen,
Princess, Lance, Bard, Rogue, Werewolf and Man are rare (under 20%).

### Families (55% of points in common)

| Family | All-round (40) | White-only (40) | Black-only (40) |
|---|---|---|---|
| **2 Vampire + Jester + 2 Vassal** (and whatever else fits) | 50% | 65% | **88%** |
| Vampire + Archer + 2 Jester | 10% | 15% | 10% |
| Wizard + Vampire + Necromancer | 12% | 8% | - |
| 2 Vampire + Barbarian + 2 Vassal | 8% | 5% | - |
| Wizard + Rook + Archer (+ Vassals, Parapet) | 5% | 2% | - |
| Queen + Vampire + 2 Vassal | 2% | 2% | 2% |
| 2 Bard + 2 Archer + 2 Bishop | 5% | - | - |
| 2 Vampire + 2 Ghost + Rogue | 5% | - | - |
| two armies on their own | 2% | 2% | - |

### Archetypes (70% of points in common): the biggest

| Archetype | All-round | White-only | Black-only |
|---|---|---|---|
| Wizard + Vampire + Archer (+ Barbarian, Necromancer) | 8% | 25% | 25% |
| 2 Vampire + 2 Archer + Rook (+ Jester, Vassal) | 8% | 28% | 20% |
| 2 Vampire + Wizard + Vassal | 5% | 18% | 22% |
| 2 Vampire + Wizard + Archer + 4 Vassal | 10% | 2% | 10% |
| 2 Archer + Vampire + 2 Jester (+ Cannon, Lance) | 8% | 10% | 5% |
| 2 Vampire + 2 Rook + Necromancer | 5% | 5% | 8% |
| 2 Vampire + Archer + Ghost | 10% | - | 2% |
| 2 Vampire + 2 Barbarian + Bishop | 10% | - | - |
| 17 smaller ones (1-2 armies each) | 36% | 12% | 8% |

27 archetypes in 120 armies at this cut, 15 of them single armies: the
all-rounders are the most varied (they were grown from scratch and only
have to beat each other); the specialists converge on three archetypes that
hold 60-70% of each colour pool. **White's and Black's specialist pools look
the same** (the same three archetypes lead both, in nearly the same shares),
as run 15D found under this rule: with White's quiet first move, the colours
no longer want different armies. Black leans a little more to Rams (45% vs
22%) and Jesters (82% vs 72%); White a little more to Grunts and Elephants.

### All-rounders against the specialists

All-rounders as White against the Black specialists: **43.0%**; White
specialists against all-rounders as Black: **62.0%** (so the all-rounders
score 38% as Black). Only **3 of 40 all-rounders hold 50%+ against both**:
S3 Wide 10a `(VS)(SQ)1CK(GR)P(BD)/(BD)LRB(AB)A(BR)B` (2 Bards, 2 Bishops,
Rook, Archer: 66.9% / 61.9%), S4 Wide 6b `R1JK(PA)1JR/1PB(BR)(NC)VA1`
(2 Jesters, 2 Rooks, Vampire: 53.1% / 60.7%) and S4 Wide 7a
`QJ(PD)1K(WW)(VS)1/1L(BR)GVG(BR)(AB)` (Queen, Vampire, 2 Ghosts: 51.4% /
52.5%). **Read this with care:** the specialists were grown against the best
of these very all-rounders, so beating all-rounders is what they were
selected for (run 12's lesson). It says the all-round pools are beatable by a
targeted build, not that all-rounders are bad in general; the three that
still hold are the interesting ones.

### Reading

- The meta is a Vampire meta: 1.7 Vampires an army, in almost every army,
  at 6.5 points (its worth has measured 7.0-7.3 in every run since run 1).
  If anything is to be repriced next, it's the Vampire, up.
- The 1-point Vassal is bought everywhere as the filler; the Grunt and
  Abatis are bought by about half the armies at their new prices.
- The colours have converged: a player's default White and Black armies
  needn't differ under today's rules.
- Front rows are a little emptier than before (6.7-7.0 of 8): the quiet
  first move took away the reason to pack strikers forward.
