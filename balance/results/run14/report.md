# Balance run 14: the 24 October prices and the ability rule (report)

Made by `tools/balance/run14_analyse.py`. Arm A: budget 40 and the new prices (Queen 10, Bishop 3.5, Rook 4.5, Werewolf 3.5, Parapet 2.5, Jester 3.5). Arm B: arm A plus the ability rule (Plusfish `--abilities-need-move=true`: a special ability needs a move first; a capture or a shield break counts as a move; a Ghost captured before it moved can't Haunt). Normal rules otherwise. Points = percentage points.

## (1) Piece values: 20,000 random-army games per arm, 8,000 nodes

Arm A: Balance report from 20000 self-play games / White scores 56.2% overall (first-move edge with equal armies: +52 Elo); 24% draws; 128 plies per game on average
Arm B: Balance report from 20000 self-play games / White scores 55.8% overall (first-move edge with equal armies: +49 Elo); 24% draws; 127 plies per game on average

"Worth" = what one extra piece at the start is worth by game results, on the cost scale (±95%). Bold = repriced on 24 Oct; * = has a special ability.

| Piece | Cost | Worth, A | Verdict, A | Worth, B | Verdict, B | B minus A |
|---|---|---|---|---|---|---|
| **Queen** | 10.0 | 9.91 ±0.37 | about right | 10.05 ±0.37 | about right | +0.14 |
| Princess | 8.5 | 8.35 ±0.32 | about right | 8.55 ±0.31 | about right | +0.20 |
| Wizard | 8.0 | 8.40 ±0.31 | slightly underpriced (+0.4) | 8.34 ±0.31 | slightly underpriced (+0.3) | -0.06 |
| Vampire | 6.5 | 7.23 ±0.26 | UNDERPRICED by ~0.7 | 7.20 ±0.25 | UNDERPRICED by ~0.7 | -0.03 |
| **Rook** | 4.5 | 4.72 ±0.19 | slightly underpriced (+0.2) | 4.81 ±0.19 | slightly underpriced (+0.3) | +0.09 |
| Archer* | 4.5 | 4.97 ±0.19 | slightly underpriced (+0.5) | 4.78 ±0.19 | slightly underpriced (+0.3) | -0.19 |
| Squire | 4.0 | 3.86 ±0.17 | about right | 3.89 ±0.17 | about right | +0.03 |
| Cannon | 4.0 | 3.80 ±0.17 | slightly overpriced (-0.2) | 3.86 ±0.17 | about right | +0.06 |
| Chariot | 4.0 | 3.74 ±0.17 | slightly overpriced (-0.3) | 3.87 ±0.17 | about right | +0.13 |
| **Bishop** | 3.5 | 3.47 ±0.16 | about right | 3.47 ±0.16 | about right | +0.00 |
| Bard* | 3.5 | 3.20 ±0.16 | slightly overpriced (-0.3) | 3.26 ±0.16 | slightly overpriced (-0.2) | +0.06 |
| **Werewolf*** | 3.5 | 3.43 ±0.16 | about right | 3.16 ±0.16 | slightly overpriced (-0.3) | -0.27 |
| Necromancer* | 3.5 | 3.80 ±0.16 | slightly underpriced (+0.3) | 3.39 ±0.16 | about right | -0.41 |
| Lance | 3.5 | 3.38 ±0.16 | about right | 3.37 ±0.16 | about right | -0.01 |
| **Jester** | 3.5 | 3.51 ±0.16 | about right | 3.65 ±0.16 | about right | +0.14 |
| Rogue | 3.5 | 3.50 ±0.16 | about right | 3.64 ±0.16 | about right | +0.14 |
| Ram | 3.0 | 3.04 ±0.15 | about right | 3.13 ±0.15 | about right | +0.09 |
| Knight | 3.0 | 3.27 ±0.15 | slightly underpriced (+0.3) | 3.15 ±0.15 | slightly underpriced (+0.2) | -0.12 |
| Galleon | 3.0 | 3.21 ±0.15 | slightly underpriced (+0.2) | 3.25 ±0.15 | slightly underpriced (+0.2) | +0.04 |
| Man | 3.0 | 2.74 ±0.14 | slightly overpriced (-0.3) | 2.73 ±0.14 | slightly overpriced (-0.3) | -0.01 |
| Ghost* | 3.0 | 3.16 ±0.15 | slightly underpriced (+0.2) | 3.17 ±0.14 | slightly underpriced (+0.2) | +0.01 |
| Cavalry | 3.0 | 3.36 ±0.15 | slightly underpriced (+0.4) | 3.37 ±0.15 | slightly underpriced (+0.4) | +0.01 |
| Catapult | 3.0 | 2.86 ±0.14 | about right | 2.93 ±0.14 | about right | +0.07 |
| **Parapet** | 2.5 | 2.60 ±0.13 | about right | 2.61 ±0.13 | about right | +0.01 |
| Barbarian | 2.5 | 2.74 ±0.13 | slightly underpriced (+0.2) | 2.68 ±0.13 | slightly underpriced (+0.2) | -0.06 |
| Paladin | 1.5 | 1.46 ±0.10 | about right | 1.46 ±0.10 | about right | +0.00 |
| Elephant | 1.0 | 0.75 ±0.09 | slightly overpriced (-0.2) | 0.81 ±0.09 | slightly overpriced (-0.2) | +0.06 |
| Pawn | 1.0 | 0.71 ±0.04 | slightly overpriced (-0.3) | 0.70 ±0.04 | slightly overpriced (-0.3) | -0.01 |
| Assassin | 0.5 | 0.38 ±0.08 | slightly overpriced (-0.1) | 0.40 ±0.07 | slightly overpriced (-0.1) | +0.02 |

### White's edge in the random-army games

| | Games | White's score (95%) | Draws | White won both of a pair | White's 1st move captures/ability | Black's 1st move captures/ability | | Plies | Pawns per army |
|---|---|---|---|---|---|---|---|---|---|
| Arm A | 20000 | 56.2% (55.6%-56.8%) | 23.7% | 12.9% | 25.0% | 21.0% |  | 128 | 3.3 |
| Arm B | 20000 | 55.8% (55.2%-56.4%) | 23.8% | 12.8% | 21.0% | 17.4% |  | 127 | 3.3 |

## (2) Arm A: the all-round pool regrown from run 7's pool

| Army | Pieces | Pawns | ...in the front row | Cost |
|---|---|---|---|---|
| Wide 15b `2(NC)KRNPA/(PD)VVN(PA)G1(AS)` | 13 | 1 | 0 | 40 |
| Wide 14a `AB(NC)(PD)K1(BR)(AS)/RV1N(AS)NG(NC)` | 14 | 0 | 0 | 40 |
| Wide 10c `(SQ)P(SQ)NK(PA)P(NC)/A(BR)(BR)EN(PD)GG` | 16 | 2 | 0 | 40 |
| Wide 15c `QPE1KPP(SQ)/LBA(RM)EGG(AS)` | 15 | 3 | 0 | 40 |
| Wide 11c `(PD)(RO)PKEJP(NC)/(AS)AGG(CV)(PD)V(GA)` | 16 | 2 | 0 | 40 |
| Wide 12c `AP(BR)(RO)KJP(NC)/(PD)P(AS)V(PA)GAE` | 16 | 3 | 1 | 40 |
| Wide 11a `R(GA)(NC)NKP(CV)(NC)/L(CV)E(GA)(BR)A(AS)(AS)` | 16 | 1 | 0 | 40 |
| Wide 8c `(SQ)PNKCPP(NC)/(RM)GE(BR)(GA)(PA)GA` | 16 | 3 | 0 | 40 |
| Wide 13b `(AS)(NC)(AS)KNP(PA)J/(PD)G(PD)NRGAA` | 16 | 1 | 0 | 40 |
| Wide 9c `RW2K(NC)2/L(RO)B1NGRG` | 11 | 0 | 0 | 40 |

**Piece diversity:** 23 piece types (not the King) in 10 armies. Armies with each: Archer 9, Ghost 9, Necromancer 9, Pawn 8, Assassin 7, Knight 7, Elephant 6, Paladin 6, Barbarian 5, Parapet 5, Rook 5, Vampire 4, Bishop 3, Galleon 3, Jester 3, Lance 3, Rogue 3, Squire 3, Cavalry 2, Ram 2, Cannon 1, Queen 1, Wizard 1


### Round robin of arm A's pool + Standard (40 games a pairing, 8,000 nodes, --random-plies 4, seeds 3000+)

| | |
|---|---|
| Games | 2200 |
| White's score | 56.2% |
| White's first move a capture or ability | 56.8% |
| Black's first move a capture or ability | 45.0% |
| White won both games of a swapped pair (chess 23%) | 16.1% |

**Each army's gap (score as White minus score as Black, points, 95% range)**

| Army | Gap | As White | As Black |
|---|---|---|---|
| Wide 15b | +0.5 (-6.1 to +7.1) | 80.8% | 80.2% |
| Wide 14a | +21.2 (+12.9 to +29.6) | 61.5% | 40.2% |
| Wide 10c | +3.5 (-4.6 to +11.6) | 61.3% | 57.8% |
| Wide 15c | +19.0 (+10.5 to +27.5) | 65.8% | 46.8% |
| Wide 11c | +9.2 (+1.4 to +17.1) | 55.2% | 46.0% |
| Wide 12c | +7.0 (-1.4 to +15.4) | 61.0% | 54.0% |
| Wide 11a | +22.7 (+14.5 to +31.0) | 58.0% | 35.2% |
| Wide 8c | +26.7 (+18.6 to +34.9) | 59.5% | 32.8% |
| Wide 13b | +14.0 (+7.1 to +20.9) | 49.2% | 35.2% |
| Wide 9c | +13.2 (+6.1 to +20.4) | 46.2% | 33.0% |
| Standard | -1.2 (-8.2 to +5.7) | 19.5% | 20.8% |

Pairings with either colour at 80%+: Wide 14a vs Wide 11a (White 98.8%); Wide 14a vs Wide 9c (White 92.5%); Wide 10c vs Wide 15c (White 80.0%); Wide 15c vs Wide 11a (White 83.8%); Wide 15c vs Wide 8c (White 85.0%); Wide 15c vs Standard (White 0.0%); Wide 11a vs Wide 8c (White 100.0%)

White's score with its 95% range: 56.2% (54.4%-58.0%).

## (2) Arm B: the all-round pool regrown from run 7's pool

| Army | Pieces | Pawns | ...in the front row | Cost |
|---|---|---|---|---|
| Wide 15a `AG(BR)K(GA)P(SQ)B/GAN(RM)E(AS)N(AS)` | 16 | 1 | 0 | 40 |
| Wide 5b `(GA)2KC2N/B(GA)VJA(RM)(PD)A` | 12 | 0 | 0 | 40 |
| Wide 14a `APPAK(CV)(NC)(NC)/(AS)B(BR)(GA)(BR)(PA)(SQ)(AS)` | 16 | 2 | 0 | 40 |
| Wide 14c `R(BR)(BR)JK(RO)N1/1GAG(CH)(GA)(GA)1` | 13 | 0 | 0 | 40 |
| Wide 13a `(NC)G(PD)(RM)KN(BD)1/1(CV)ALR(PD)(CV)(PA)` | 14 | 0 | 0 | 40 |
| Wide 12c `(PD)1JK1Q(NC)(AS)/(AS)1LLVG(PA)(PD)` | 13 | 0 | 0 | 40 |
| Wide 10b `W(PA)2K(RO)B(NC)/1L(PA)GV2B` | 11 | 0 | 0 | 40 |
| Wide 10c `(CH)P(RO)RKPP(PA)/G(BR)(AS)L(NC)G(CV)B` | 16 | 3 | 0 | 40 |
| Wide 13c `W(BR)(NC)GKNP(CV)/(AS)A(RM)(BR)GPP(AS)` | 16 | 3 | 2 | 40 |
| Wide 11a `RP(RO)KP(CV)1G/(RM)L(PA)PV(BR)A(AS)` | 15 | 3 | 1 | 40 |

**Piece diversity:** 25 piece types (not the King) in 10 armies. Armies with each: Ghost 8, Archer 7, Assassin 6, Barbarian 6, Necromancer 6, Parapet 6, Bishop 5, Cavalry 5, Knight 5, Lance 5, Pawn 5, Ram 5, Galleon 4, Rogue 4, Rook 4, Vampire 4, Jester 3, Paladin 3, Chariot 2, Squire 2, Wizard 2, Bard 1, Cannon 1, Elephant 1, Queen 1


### Round robin of arm B's pool + Standard (40 games a pairing, 8,000 nodes, --random-plies 4, seeds 3000+)

| | |
|---|---|
| Games | 2200 |
| White's score | 53.6% |
| White's first move a capture or ability | 43.6% |
| Black's first move a capture or ability | 51.1% |
| White won both games of a swapped pair (chess 23%) | 11.5% |

**Each army's gap (score as White minus score as Black, points, 95% range)**

| Army | Gap | As White | As Black |
|---|---|---|---|
| Wide 15a | +14.0 (+6.1 to +21.9) | 63.0% | 49.0% |
| Wide 5b | +18.0 (+10.9 to +25.1) | 84.8% | 66.8% |
| Wide 14a | +0.0 (-8.5 to +8.5) | 51.5% | 51.5% |
| Wide 14c | -2.0 (-9.4 to +5.4) | 49.5% | 51.5% |
| Wide 13a | +6.2 (-1.5 to +14.0) | 56.2% | 50.0% |
| Wide 12c | +10.5 (+1.7 to +19.3) | 52.0% | 41.5% |
| Wide 10b | +1.5 (-7.0 to +10.0) | 47.2% | 45.8% |
| Wide 10c | +17.8 (+9.8 to +25.7) | 55.8% | 38.0% |
| Wide 13c | -1.5 (-9.2 to +6.2) | 66.5% | 68.0% |
| Wide 11a | +19.2 (+11.3 to +27.2) | 46.0% | 26.8% |
| Standard | -5.2 (-12.0 to +1.5) | 16.8% | 22.0% |

Pairings with either colour at 80%+: Wide 15a vs Wide 11a (White 87.5%); Wide 5b vs Wide 12c (White 83.8%); Wide 5b vs Wide 10c (White 85.0%); Wide 10c vs Wide 11a (White 81.2%)

White's score with its 95% range: 53.6% (51.8%-55.4%).

## (4) Arm B's pool armies against themselves (Plusfish at 2,000,000 nodes, 8 threads)

White's first-move advantage in pawns; negative = Black ahead. Chess: +0.29 (top engines +0.20 to +0.35).

| Army | Without the rule | With the rule |
|---|---|---|
| Wide 12c `(PD)1JK1Q(NC)(AS)/(AS)1LLVG(PA)(PD)` | +0.89 (Lxd7) | +1.16 (Lxd7) |
| Wide 10b `W(PA)2K(RO)B(NC)/1L(PA)GV2B` | +2.09 (Lxb8=W+) | +1.62 (Lxb8=W+) |
| Wide 5b `(GA)2KC2N/B(GA)VJA(RM)(PD)A` | +2.29 (Kc1) | +1.84 (Kc1) |
| Wide 13a `(NC)G(PD)(RM)KN(BD)1/1(CV)ALR(PD)(CV)(PA)` | +0.07 (CVc3) | +0.02 (Lxd7+) |
| Wide 15a `AG(BR)K(GA)P(SQ)B/GAN(RM)E(AS)N(AS)` | +3.61 (Axg7!) | +0.37 (Nf4) |
| Wide 14a `APPAK(CV)(NC)(NC)/(AS)B(BR)(GA)(BR)(PA)(SQ)(AS)` | +1.39 (Bxg7) | +1.08 (Bxg7) |
| Wide 14c `R(BR)(BR)JK(RO)N1/1GAG(CH)(GA)(GA)1` | +0.25 (Aa4) | +0.17 (Aa4) |
| Wide 10c `(CH)P(RO)RKPP(PA)/G(BR)(AS)L(NC)G(CV)B` | +0.22 (Lxd7+) | +0.14 (Gf3) |
| Wide 11a `RP(RO)KP(CV)1G/(RM)L(PA)PV(BR)A(AS)` | +3.01 (Axb7!) | +1.13 (Af3) |
| Wide 13c `W(BR)(NC)GKNP(CV)/(AS)A(RM)(BR)GPP(AS)` | +3.63 (Axg7!) | +0.70 (Axg7) |
| Standard `standard` | +0.22 (d4) | +0.19 (e4) |

Without the rule: median +1.39; within ±0.35: 4 of 11; over +1: Wide 10b +2.09, Wide 5b +2.29, Wide 15a +3.61, Wide 14a +1.39, Wide 11a +3.01, Wide 13c +3.63; Black ahead by more than a pawn: none

With the rule: median +0.70; within ±0.35: 4 of 11; over +1: Wide 12c +1.16, Wide 10b +1.62, Wide 5b +1.84, Wide 14a +1.08, Wide 11a +1.13; Black ahead by more than a pawn: none

## (3) Arm B: colour specialists (run 13's method on B's regrown pool)

A White army is judged only as White against B's all-round pool + Standard playing Black, frozen; a Black army only as Black against them playing White (`meta --split-colours --fixed-opponent`). All games below have fixed colours, 40 games a pairing, 8,000 nodes, `--random-plies 4`.


**White pool (judged only as White)**

| Army | Score in games | Pieces | Pawns (front row) | Long-range in front row | Archers | Ability pieces |
|---|---|---|---|---|---|---|
| Wide W15a `3CK(RO)(PR)1/W1LL(RM)(PD)1A` | 95.6% (+533) | 10 | 0 (0) | 5 | 1 | 1 |
| Wide W14b `EW(RM)MK(NC)P1/1(PD)L(RM)PBAB` | 81.9% (+263) | 14 | 2 (1) | 5 | 1 | 2 |
| Wide W9c `APP(CV)KEPL/N1(NC)(SQ)PJVL` | 78.0% (+219) | 15 | 4 (1) | 2 | 1 | 2 |
| Wide W12b `R3KGW(NC)/1(RM)L(PA)G(PD)CB` | 76.7% (+207) | 12 | 0 (0) | 5 | 0 | 3 |
| Wide W14a `2R(PA)K1W(CV)/P(PA)L(CV)(PD)GCB` | 74.9% (+190) | 13 | 1 (1) | 4 | 0 | 1 |
| Wide W3a `(AS)(PA)1JK1(PR)L/(CV)(PD)1B(AS)V(CV)L` | 72.2% (+165) | 13 | 0 (0) | 3 | 0 | 0 |
| Wide W5a `P(GA)G(NC)K(SQ)(AS)1/1(BR)A(RM)(GA)(AS)WL` | 71.8% (+163) | 14 | 1 (0) | 5 | 1 | 3 |
| Wide W7c `1Q(NC)1KG(PD)L/R2(RM)(GA)G(AS)L` | 71.5% (+160) | 12 | 0 (0) | 4 | 0 | 3 |
| Wide W14c `1WPGK(CV)1C/(PD)(PD)L(RM)(PA)PAB` | 71.2% (+158) | 14 | 2 (1) | 5 | 1 | 2 |
| Wide W2a `E(CV)1KCE(CT)W/AG(GA)L(NC)(AS)(PD)(AS)` | 70.5% (+151) | 15 | 0 (0) | 3 | 1 | 3 |

Averages (not Standard): 13.2 pieces, 1.0 pawns (0.4 in the front row), 4.1 long-range pieces in the front row, 0.6 Archers, 2.0 ability pieces.

**Black pool (judged only as Black)**

| Army | Score in games | Pieces | Pawns (front row) | Long-range in front row | Archers | Ability pieces |
|---|---|---|---|---|---|---|
| Wide B15a `A1JEK(BR)PM/(AS)VVNP(BR)PG` | 71.9% (+163) | 15 | 3 (2) | 2 | 1 | 2 |
| Wide B1a `(NC)(PD)ENKPPW/PAJVP(AS)P(RM)` | 68.9% (+138) | 16 | 5 (3) | 3 | 1 | 2 |
| Wide B11a `AA(AS)(CV)KP(NC)P/(NC)B(GA)(BR)(BR)(PA)R1` | 66.5% (+119) | 15 | 2 (0) | 4 | 2 | 4 |
| Wide B14a `(AS)GP(BR)KP(CV)(RM)/WA(NC)G(BR)PN(AS)` | 62.5% (+89) | 16 | 3 (1) | 2 | 1 | 4 |
| Wide 15a `AG(BR)K(GA)P(SQ)B/GAN(RM)E(AS)N(AS)` | 60.3% (+73) | 16 | 1 (0) | 2 | 2 | 4 |
| Wide B15b `AGJEKPP(NC)/(AS)BVNP(BR)(BR)G` | 58.0% (+56) | 16 | 3 (1) | 2 | 1 | 4 |
| Wide B3a `AP(CH)AK(CV)1(NC)/(AS)B(GA)(BR)(BR)(GA)(SQ)(AS)` | 52.4% (+17) | 15 | 1 (0) | 3 | 2 | 3 |
| Wide 5b `(GA)2KC2N/B(GA)VJA(RM)(PD)A` | 51.7% (+12) | 12 | 0 (0) | 6 | 2 | 2 |
| Wide 14c `R(BR)(BR)JK(RO)N1/1GAG(CH)(GA)(GA)1` | 50.7% (+5) | 13 | 0 (0) | 4 | 1 | 3 |
| Wide B2a `(NC)PPWKPCE/A(PA)G(RM)(GA)(BR)(PD)(AS)` | 48.5% (-10) | 16 | 3 (0) | 4 | 1 | 3 |

Averages (not Standard): 15.0 pieces, 2.1 pawns (0.7 in the front row), 3.2 long-range pieces in the front row, 1.4 Archers, 3.1 ability pieces.

Piece types, White pool: 26 piece types in 10 armies: Lance 10, Paladin 8, Wizard 7, Archer 6, Ghost 6, Necromancer 6, Ram 6, Bishop 5, Cannon 5, Cavalry 5, Pawn 5, Assassin 4, Parapet 4, Elephant 3, Galleon 3, Rook 3, Jester 2, Princess 2, Squire 2, Vampire 2, Barbarian 1, Catapult 1, Knight 1, Man 1, Queen 1, Rogue 1

Piece types, Black pool: 23 piece types in 10 armies: Archer 10, Assassin 8, Barbarian 8, Pawn 8, Knight 7, Galleon 6, Ghost 6, Necromancer 6, Bishop 5, Elephant 5, Jester 5, Ram 5, Vampire 4, Cavalry 3, Paladin 3, Wizard 3, Cannon 2, Chariot 2, Parapet 2, Rook 2, Squire 2, Man 1, Rogue 1

| | White's score | vs B's all-round round robin |
|---|---|---|
| All-rounders as White against all-rounders as Black (B's round robin) | 53.6% | |
| White specialists against all-rounders as Black | 69.9% (68.8%-71.0%) | White gains +16.3 points |
| All-rounders as White against Black specialists | 46.1% (45.0%-47.3%) | Black gains +7.5 points |
| White specialists against Black specialists | 70.6% (69.4%-71.7%) | +17.0 points for White overall |
| Uneven specialist matchups (either side at 80%+, Standard left out) | 60 of 100 | |

Run 13 (normal rules, old prices, no ability rule): White specialists +11.0, Black specialists +13.5, specialists vs specialists 56.7% (all-rounders 59.4%).

Each White army as White (all Black armies) and each Black army as Black (all White armies):

| White army | Score as White | | Black army | Score as Black |
|---|---|---|---|---|
| Wide W15a | 100.0% | | Wide B15a | 45.0% |
| Wide W14b | 92.0% | | Wide B1a | 34.8% |
| Wide W9c | 60.8% | | Wide B11a | 17.3% |
| Wide W12b | 84.1% | | Wide B14a | 25.5% |
| Wide W14a | 84.4% | | Wide 15a | 18.3% |
| Wide W3a | 74.2% | | Wide B15b | 46.9% |
| Wide W5a | 56.4% | | Wide B3a | 35.8% |
| Wide W7c | 64.1% | | Wide 5b | 43.3% |
| Wide W14c | 79.4% | | Wide 14c | 13.0% |
| Wide W2a | 59.4% | | Wide B2a | 39.1% |
| Standard | 21.6% | | Standard | 4.7% |

Pairings at 80%+: Wide W15a vs Wide B15a (White 100.0%); Wide W15a vs Wide B1a (White 100.0%); Wide W15a vs Wide B11a (White 100.0%); Wide W15a vs Wide B14a (White 100.0%); Wide W15a vs Wide 15a (White 100.0%); Wide W15a vs Wide B15b (White 100.0%); Wide W15a vs Wide B3a (White 100.0%); Wide W15a vs Wide 5b (White 100.0%); Wide W15a vs Wide 14c (White 100.0%); Wide W15a vs Wide B2a (White 100.0%); Wide W14b vs Wide B1a (White 100.0%); Wide W14b vs Wide B11a (White 100.0%); Wide W14b vs Wide B14a (White 100.0%); Wide W14b vs Wide B15b (White 100.0%); Wide W14b vs Wide B3a (White 100.0%); Wide W14b vs Wide 14c (White 100.0%); Wide W14b vs Wide B2a (White 100.0%); Wide W9c vs Wide B1a (White 0.0%); Wide W9c vs Wide B11a (White 100.0%); Wide W9c vs Wide B14a (White 100.0%); Wide W9c vs Wide 15a (White 85.0%); Wide W9c vs Wide B15b (White 0.0%); Wide W9c vs Wide 14c (White 100.0%); Wide W12b vs Wide B1a (White 100.0%); Wide W12b vs Wide B11a (White 100.0%); Wide W12b vs Wide B14a (White 100.0%); Wide W12b vs Wide 15a (White 100.0%); Wide W12b vs Wide B3a (White 100.0%); Wide W12b vs Wide 5b (White 100.0%); Wide W12b vs Wide 14c (White 100.0%); Wide W14a vs Wide B1a (White 100.0%); Wide W14a vs Wide B11a (White 100.0%); Wide W14a vs Wide B14a (White 100.0%); Wide W14a vs Wide 15a (White 100.0%); Wide W14a vs Wide B15b (White 100.0%); Wide W14a vs Wide B3a (White 100.0%); Wide W14a vs Wide 14c (White 100.0%); Wide W3a vs Wide B1a (White 82.5%); Wide W3a vs Wide B11a (White 100.0%); Wide W3a vs Wide B14a (White 87.5%); Wide W3a vs Wide 15a (White 100.0%); Wide W3a vs Wide 14c (White 100.0%); Wide W3a vs Wide B2a (White 81.2%); Wide W5a vs Wide B15a (White 83.8%); Wide W5a vs Wide B1a (White 0.0%); Wide W5a vs Wide B14a (White 0.0%); Wide W5a vs Wide 15a (White 100.0%); Wide W5a vs Wide 14c (White 86.2%); Wide W7c vs Wide B15a (White 20.0%); Wide W7c vs Wide B1a (White 100.0%); Wide W7c vs Wide 14c (White 100.0%); Wide W14c vs Wide B1a (White 100.0%); Wide W14c vs Wide B11a (White 100.0%); Wide W14c vs Wide B14a (White 100.0%); Wide W14c vs Wide B15b (White 0.0%); Wide W14c vs Wide B3a (White 100.0%); Wide W14c vs Wide 14c (White 100.0%); Wide W14c vs Wide B2a (White 100.0%); Wide W2a vs Wide B14a (White 87.5%); Wide W2a vs Wide 15a (White 100.0%)

## (5) White's first move, every game of each arm

Random armies = the 20,000 balance-report games of the arm; pool games = its regrown pool's round robin and, for B, the specialist grids (strong armies, so far more first-move contact). "Hit" = a capture, a shield break or a special ability on move 1. "Free" = a capture or shield break where Black could not capture (or break the shield of) the mover where it stood afterwards; "recaptured" = Black's reply did hit it. White's score = points per game in those games.

| | A, random armies | B, random armies | A, pool games | B, pool games |
|---|---|---|---|---|
| Games | 20000 | 20000 | 2200 | 16720 |
| White's first move a hit | 25.0% (4993) | 21.0% (4198) | 56.8% (1250) | 53.3% (8910) |
| ...a capture | 20.6% | 20.7% | 26.0% | 52.8% |
| ...a shield break | 0.2% | 0.3% | 1.1% | 0.5% |
| ...a special ability | 4.1% (819: Archer 179, Werewolf 640) | 0.0% (0: -) | 29.7% (653: Archer 653) | 0.0% (0: -) |
| ...giving check | 14.7% of hits | 17.4% of hits | 0.0% of hits | 29.2% of hits |
| White's score after a first-move hit | 67.0% | 68.9% | 58.4% | 70.9% |
| White's score after a quiet first move | 52.6% | 52.3% | 53.2% | 49.9% |
| Free hits (not recapturable) | 34.9% of hits, White scores 78.6% | 41.8% of hits, White scores 78.6% | 10.0% of hits, White scores 62.0% | 5.2% of hits, White scores 73.3% |
| Recapturable hits | 47.8% of hits, recaptured 74.7% of those, White scores 62.5% | 55.6% of hits, recaptured 75.9% of those, White scores 61.6% | 55.5% of hits, recaptured 78.7% of those, White scores 61.8% | 90.6% of hits, recaptured 78.3% of those, White scores 71.4% |
| Mean material taken on move 1 (points, minus a Ram that died) | 3.89 | 3.90 | 3.44 | 3.08 |

### A, random armies: by the piece that hit (move 1)

| Mover | Hits | Share of hits | White's score | Free | Recaptured |
|---|---|---|---|---|---|
| Lance | 1846 | 37.0% | 72.5% | 33.6% | 48.2% |
| Cannon | 1001 | 20.0% | 63.1% | 30.1% | 55.2% |
| Werewolf | 640 | 12.8% | 52.1% | 95.3% | 0.8% |
| Wizard | 486 | 9.7% | 72.0% | 72.4% | 24.7% |
| Rook | 312 | 6.2% | 69.2% | 56.1% | 36.2% |
| Archer | 272 | 5.4% | 70.0% | 84.6% | 5.1% |
| Bishop | 178 | 3.6% | 64.9% | 44.9% | 37.6% |
| Queen | 161 | 3.2% | 68.6% | 87.6% | 12.4% |
| Ram | 97 | 1.9% | 58.2% | 0.0% | 0.0% |

**By the piece hit:**

| Target | Cost | Hit on move 1 | Share of hits | White's score |
|---|---|---|---|---|
| Pawn | 1.0 | 527 | 10.6% | 70.4% |
| Jester | 3.5 | 452 | 9.1% | 61.5% |
| Princess | 8.5 | 225 | 4.5% | 83.8% |
| Lance | 3.5 | 214 | 4.3% | 66.8% |
| Wizard | 8.0 | 212 | 4.2% | 76.2% |
| Vampire | 6.5 | 194 | 3.9% | 77.6% |
| Rook | 4.5 | 187 | 3.7% | 69.3% |
| Queen | 10.0 | 187 | 3.7% | 84.2% |
| Barbarian | 2.5 | 178 | 3.6% | 57.0% |
| Archer | 4.5 | 153 | 3.1% | 66.0% |
| Cannon | 4.0 | 132 | 2.6% | 61.7% |
| Squire | 4.0 | 128 | 2.6% | 69.9% |
| Chariot | 4.0 | 127 | 2.5% | 69.7% |
| Bishop | 3.5 | 123 | 2.5% | 67.9% |
| Necromancer | 3.5 | 118 | 2.4% | 67.8% |
| Cavalry | 3.0 | 117 | 2.3% | 66.2% |
| Parapet | 2.5 | 113 | 2.3% | 67.7% |
| Ram | 3.0 | 99 | 2.0% | 68.2% |
| Werewolf | 3.5 | 94 | 1.9% | 72.3% |
| Galleon | 3.0 | 93 | 1.9% | 65.1% |
| Rogue | 3.5 | 88 | 1.8% | 67.0% |
| Bard | 3.5 | 88 | 1.8% | 69.9% |
| Knight | 3.0 | 87 | 1.7% | 63.2% |
| Assassin | 0.5 | 87 | 1.7% | 73.6% |
| Catapult | 3.0 | 84 | 1.7% | 71.4% |
| Elephant | 1.0 | 83 | 1.7% | 72.3% |
| Man | 3.0 | 69 | 1.4% | 66.7% |
| Paladin | 1.5 | 49 | 1.0% | 36.7% |
| Ghost | 3.0 | 45 | 0.9% | 68.9% |

**Commonest hits (mover -> target):** Lance x Pawn 229 (White 72.5%, free 60.7%); Lance x Jester 217 (White 66.8%, free 18.4%); Cannon x Jester 108 (White 51.4%, free 17.6%); Lance x Barbarian 92 (White 48.4%, free 16.3%); Lance x Lance 91 (White 66.5%, free 12.1%); Cannon x Princess 80 (White 87.5%, free 20.0%); Cannon x Wizard 74 (White 73.6%, free 14.9%); Wizard x Pawn 72 (White 64.6%, free 94.4%); Rook x Pawn 69 (White 77.5%, free 92.8%); Cannon x Queen 64 (White 81.2%, free 21.9%); Cannon x Vampire 63 (White 68.3%, free 17.5%); Cannon x Rook 62 (White 62.1%, free 27.4%); Lance x Bishop 62 (White 70.2%, free 32.3%); Lance x Vampire 61 (White 84.4%, free 27.9%); Lance x Cavalry 57 (White 73.7%, free 24.6%)

### B, random armies: by the piece that hit (move 1)

| Mover | Hits | Share of hits | White's score | Free | Recaptured |
|---|---|---|---|---|---|
| Lance | 1838 | 43.8% | 71.6% | 33.6% | 48.1% |
| Cannon | 1037 | 24.7% | 62.9% | 30.3% | 56.1% |
| Wizard | 473 | 11.3% | 69.9% | 76.1% | 21.1% |
| Rook | 311 | 7.4% | 70.9% | 56.3% | 34.7% |
| Bishop | 175 | 4.2% | 61.4% | 46.9% | 35.4% |
| Queen | 148 | 3.5% | 75.3% | 89.2% | 9.5% |
| Archer | 109 | 2.6% | 76.1% | 68.8% | 21.1% |
| Ram | 107 | 2.5% | 65.9% | 0.0% | 0.0% |

**By the piece hit:**

| Target | Cost | Hit on move 1 | Share of hits | White's score |
|---|---|---|---|---|
| Pawn | 1.0 | 512 | 12.2% | 72.8% |
| Jester | 3.5 | 415 | 9.9% | 61.7% |
| Princess | 8.5 | 230 | 5.5% | 83.7% |
| Wizard | 8.0 | 217 | 5.2% | 75.3% |
| Queen | 10.0 | 192 | 4.6% | 86.5% |
| Vampire | 6.5 | 189 | 4.5% | 76.2% |
| Rook | 4.5 | 182 | 4.3% | 66.2% |
| Lance | 3.5 | 181 | 4.3% | 63.3% |
| Barbarian | 2.5 | 166 | 4.0% | 57.8% |
| Archer | 4.5 | 141 | 3.4% | 64.2% |
| Cannon | 4.0 | 120 | 2.9% | 66.2% |
| Chariot | 4.0 | 119 | 2.8% | 71.4% |
| Squire | 4.0 | 118 | 2.8% | 69.5% |
| Necromancer | 3.5 | 112 | 2.7% | 65.6% |
| Cavalry | 3.0 | 111 | 2.6% | 61.7% |
| Bishop | 3.5 | 111 | 2.6% | 66.7% |
| Parapet | 2.5 | 99 | 2.4% | 69.7% |
| Ghost | 3.0 | 95 | 2.3% | 57.4% |
| Ram | 3.0 | 92 | 2.2% | 68.5% |
| Galleon | 3.0 | 91 | 2.2% | 63.7% |
| Bard | 3.5 | 88 | 2.1% | 67.6% |
| Rogue | 3.5 | 84 | 2.0% | 69.6% |
| Werewolf | 3.5 | 84 | 2.0% | 75.0% |
| Knight | 3.0 | 83 | 2.0% | 63.3% |
| Assassin | 0.5 | 82 | 2.0% | 73.8% |
| Catapult | 3.0 | 79 | 1.9% | 65.2% |
| Elephant | 1.0 | 78 | 1.9% | 68.6% |
| Paladin | 1.5 | 65 | 1.5% | 46.2% |
| Man | 3.0 | 62 | 1.5% | 62.9% |

**Commonest hits (mover -> target):** Lance x Pawn 224 (White 74.8%, free 61.6%); Lance x Jester 214 (White 60.7%, free 17.8%); Cannon x Jester 105 (White 55.2%, free 18.1%); Lance x Lance 91 (White 62.1%, free 12.1%); Lance x Barbarian 90 (White 55.0%, free 16.7%); Cannon x Princess 83 (White 88.0%, free 19.3%); Cannon x Wizard 77 (White 76.0%, free 14.3%); Rook x Pawn 71 (White 81.7%, free 90.1%); Wizard x Pawn 71 (White 69.0%, free 94.4%); Cannon x Queen 67 (White 80.6%, free 20.9%); Cannon x Vampire 64 (White 72.7%, free 17.2%); Cannon x Rook 62 (White 62.1%, free 29.0%); Lance x Bishop 61 (White 69.7%, free 32.8%); Lance x Vampire 60 (White 79.2%, free 28.3%); Lance x Princess 59 (White 89.8%, free 33.9%)

### A, pool games: by the piece that hit (move 1)

| Mover | Hits | Share of hits | White's score | Free | Recaptured |
|---|---|---|---|---|---|
| Archer | 758 | 60.6% | 57.0% | 70.2% | 18.9% |
| Lance | 225 | 18.0% | 64.4% | 0.0% | 87.6% |
| Bishop | 143 | 11.4% | 60.1% | 14.0% | 86.0% |
| Rook | 93 | 7.4% | 49.5% | 0.0% | 84.9% |
| Cannon | 27 | 2.2% | 72.2% | 0.0% | 14.8% |
| Ram | 4 | 0.3% | 50.0% | 0.0% | 0.0% |

**By the piece hit:**

| Target | Cost | Hit on move 1 | Share of hits | White's score |
|---|---|---|---|---|
| Archer | 4.5 | 238 | 19.0% | 62.2% |
| Jester | 3.5 | 199 | 15.9% | 79.1% |
| Ghost | 3.0 | 114 | 9.1% | 52.6% |
| Vampire | 6.5 | 107 | 8.6% | 44.4% |
| Bishop | 3.5 | 80 | 6.4% | 49.4% |
| Rook | 4.5 | 80 | 6.4% | 71.2% |
| Pawn | 1.0 | 60 | 4.8% | 55.0% |
| Galleon | 3.0 | 53 | 4.2% | 30.2% |
| Necromancer | 3.5 | 40 | 3.2% | 92.5% |
| Knight | 3.0 | 40 | 3.2% | 41.2% |
| Rogue | 3.5 | 40 | 3.2% | 75.0% |
| Assassin | 0.5 | 40 | 3.2% | 0.0% |
| Ram | 3.0 | 28 | 2.2% | 64.3% |
| Elephant | 1.0 | 26 | 2.1% | 7.7% |
| Paladin | 1.5 | 25 | 2.0% | 42.0% |
| Lance | 3.5 | 20 | 1.6% | 97.5% |
| Barbarian | 2.5 | 20 | 1.6% | 55.0% |
| Cavalry | 3.0 | 20 | 1.6% | 75.0% |
| Parapet | 2.5 | 20 | 1.6% | 62.5% |

**Commonest hits (mover -> target):** Archer x Jester 153 (White 77.5%, free 73.9%); Archer x Archer 133 (White 65.0%, free 75.2%); Archer x Ghost 87 (White 46.6%, free 62.1%); Archer x Rook 80 (White 71.2%, free 100.0%); Archer x Vampire 60 (White 41.7%, free 66.7%); Archer x Bishop 60 (White 65.8%, free 33.3%); Lance x Pawn 60 (White 55.0%, free 0.0%); Bishop x Archer 54 (White 39.8%, free 0.0%); Lance x Necromancer 40 (White 92.5%, free 0.0%); Archer x Knight 40 (White 41.2%, free 0.0%); Lance x Archer 31 (White 83.9%, free 0.0%); Lance x Galleon 26 (White 38.5%, free 0.0%); Archer x Paladin 25 (White 42.0%, free 100.0%); Lance x Jester 22 (White 95.5%, free 0.0%); Bishop x Lance 20 (White 97.5%, free 0.0%)

### B, pool games: by the piece that hit (move 1)

| Mover | Hits | Share of hits | White's score | Free | Recaptured |
|---|---|---|---|---|---|
| Lance | 4397 | 49.3% | 70.8% | 8.2% | 72.7% |
| Bishop | 2169 | 24.3% | 76.2% | 1.3% | 76.8% |
| Archer | 873 | 9.8% | 67.1% | 8.4% | 83.5% |
| Cannon | 663 | 7.4% | 79.2% | 0.0% | 61.7% |
| Ram | 375 | 4.2% | 57.1% | 0.0% | 0.0% |
| Rook | 247 | 2.8% | 51.8% | 0.0% | 97.2% |
| Wizard | 186 | 2.1% | 51.3% | 1.6% | 41.4% |

**By the piece hit:**

| Target | Cost | Hit on move 1 | Share of hits | White's score |
|---|---|---|---|---|
| Pawn | 1.0 | 1185 | 13.3% | 91.2% |
| Barbarian | 2.5 | 1042 | 11.7% | 56.9% |
| Ghost | 3.0 | 924 | 10.4% | 66.6% |
| Jester | 3.5 | 787 | 8.8% | 75.8% |
| Archer | 4.5 | 780 | 8.8% | 51.3% |
| Bishop | 3.5 | 546 | 6.1% | 42.6% |
| Parapet | 2.5 | 499 | 5.6% | 90.8% |
| Galleon | 3.0 | 495 | 5.6% | 67.9% |
| Rook | 4.5 | 469 | 5.3% | 82.2% |
| Necromancer | 3.5 | 414 | 4.6% | 77.9% |
| Vampire | 6.5 | 349 | 3.9% | 79.4% |
| Wizard | 8.0 | 329 | 3.7% | 74.6% |
| Ram | 3.0 | 321 | 3.6% | 61.7% |
| Assassin | 0.5 | 279 | 3.1% | 66.8% |
| Rogue | 3.5 | 191 | 2.1% | 100.0% |
| Lance | 3.5 | 108 | 1.2% | 72.7% |
| Paladin | 1.5 | 86 | 1.0% | 71.5% |
| Knight | 3.0 | 63 | 0.7% | 53.2% |
| Cavalry | 3.0 | 43 | 0.5% | 66.3% |

**Commonest hits (mover -> target):** Lance x Barbarian 658 (White 55.4%, free 0.0%); Lance x Pawn 580 (White 85.0%, free 27.6%); Bishop x Pawn 457 (White 98.9%, free 1.3%); Lance x Ghost 436 (White 72.2%, free 0.0%); Bishop x Parapet 427 (White 91.2%, free 0.0%); Lance x Rook 416 (White 86.3%, free 0.0%); Lance x Necromancer 341 (White 83.4%, free 0.0%); Lance x Bishop 287 (White 38.3%, free 0.0%); Lance x Wizard 280 (White 74.3%, free 0.0%); Bishop x Galleon 245 (White 80.4%, free 0.0%); Lance x Ram 243 (White 68.5%, free 0.0%); Archer x Archer 239 (White 50.8%, free 0.0%); Lance x Jester 229 (White 77.7%, free 0.0%); Bishop x Barbarian 229 (White 59.6%, free 0.0%); Lance x Galleon 221 (White 51.6%, free 0.0%)

## Success lines (from the README, written before the run)

- 1. Each repriced piece within 0.5 of its new cost (arm A): **yes** (Queen -0.09, Bishop -0.03, Rook +0.22, Werewolf -0.07, Parapet +0.10, Jester +0.01)
- 2. No piece more than 1.0 off its cost (arm A): **yes** (worst: Vampire +0.73, Archer +0.47, Wizard +0.40, Cavalry +0.36)
- 3. Ability pieces within 1.0 of cost under the rule and none down more than 0.5 from A to B: **yes** (Archer -0.19 (A 4.97, B 4.78); Necromancer -0.41 (A 3.80, B 3.39); Ghost +0.01 (A 3.16, B 3.17); Bard +0.06 (A 3.20, B 3.26); Werewolf -0.27 (A 3.43, B 3.16))
- 4. The rule doesn't widen White's edge: B's random-army score no higher than A's, and B's round robin passes Mac's lines (50-55%, no gap over 30, no pairing at 80%+): **no** (random armies A 56.2% (55.6%-56.8%), B 55.8% (55.2%-56.4%); B's round robin White 53.6% (51.8%-55.4%), biggest gap +19.2, pairings at 80%+: 4)
- 5. Under the rule no game starts with an ability, and White's first-move capture share (random armies) is no higher than A's: **yes** (abilities on move 1 in B's 36720 games: 0; first-move captures in random armies A 20.6%, B 20.7%)
- 6. Diversity: B's pool has at least as many piece types as A's (within 2) and at least 3 of the 5 ability types: **yes** (types A 23, B 25; ability types in B's pool: Ghost, Archer, Necromancer, Bard)
- **Result: FAILED**
