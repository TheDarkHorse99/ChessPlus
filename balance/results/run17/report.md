# Balance run 17: the Vampire and Wizard repriced (report)

Made by `tools/balance/run17_analyse.py`. A = today's prices; B = Vampire 7.5, Wizard 8.5 (the Vampire's price picked from A's measured worth, Mac: 7 or 7.5). Main's Plusfish (Nicholas's PR #28). 20,000 random-army games at 8,000 nodes for each report; run 16's meta-share method for the meta.

## Piece values

A, today's prices: Balance report from 20000 self-play games / White scores 53.7% overall (first-move edge with equal armies: +33 Elo); 19% draws; 128 plies per game on average
B, Vampire 7.5, Wizard 8.5: Balance report from 20000 self-play games / White scores 53.4% overall (first-move edge with equal armies: +30 Elo); 19% draws; 129 plies per game on average

"Worth" = what one extra piece at the start is worth by game results, on the cost scale (±95%). The pieces Mac asked about first.

| Piece | Cost A | Worth A | Verdict A | Cost B | Worth B | Verdict B |
|---|---|---|---|---|---|---|
| **Vampire** | 6.5 | 7.73 ±0.24 | UNDERPRICED by ~1.2 | 7.5 | 7.88 ±0.27 | slightly underpriced (+0.4) |
| **Wizard** | 8.0 | 8.66 ±0.29 | UNDERPRICED by ~0.7 | 8.5 | 8.75 ±0.31 | about right |
| **Queen** | 10.0 | 10.19 ±0.35 | about right | 10.0 | 10.39 ±0.36 | slightly underpriced (+0.4) |
| **Jester** | 3.5 | 3.65 ±0.15 | slightly underpriced (+0.2) | 3.5 | 3.72 ±0.15 | slightly underpriced (+0.2) |
| **Vassal** | 1.0 | 0.96 ±0.06 | about right | 1.0 | 0.93 ±0.07 | about right |
| **Grunt** | 1.0 | 0.64 ±0.06 | slightly overpriced (-0.4) | 1.0 | 0.69 ±0.07 | slightly overpriced (-0.3) |
| **Abatis** | 0.5 | 0.47 ±0.06 | about right | 0.5 | 0.45 ±0.06 | about right |
| Princess | 8.5 | 8.79 ±0.30 | about right | 8.5 | 8.81 ±0.30 | slightly underpriced (+0.3) |
| Rook | 4.5 | 4.84 ±0.18 | slightly underpriced (+0.3) | 4.5 | 4.93 ±0.18 | slightly underpriced (+0.4) |
| Archer | 4.5 | 4.62 ±0.17 | about right | 4.5 | 4.76 ±0.18 | slightly underpriced (+0.3) |
| Cannon | 4.0 | 3.56 ±0.16 | slightly overpriced (-0.4) | 4.0 | 3.55 ±0.16 | slightly overpriced (-0.5) |
| Squire | 4.0 | 4.19 ±0.16 | slightly underpriced (+0.2) | 4.0 | 4.27 ±0.17 | slightly underpriced (+0.3) |
| Chariot | 4.0 | 3.88 ±0.16 | about right | 4.0 | 3.95 ±0.17 | about right |
| Rogue | 3.5 | 3.52 ±0.15 | about right | 3.5 | 3.62 ±0.15 | about right |
| Bishop | 3.5 | 3.44 ±0.15 | about right | 3.5 | 3.36 ±0.15 | about right |
| Bard | 3.5 | 3.20 ±0.14 | slightly overpriced (-0.3) | 3.5 | 3.26 ±0.15 | slightly overpriced (-0.2) |
| Necromancer | 3.5 | 3.68 ±0.15 | slightly underpriced (+0.2) | 3.5 | 3.66 ±0.15 | slightly underpriced (+0.2) |
| Catapult | 3.0 | 3.05 ±0.13 | about right | 3.0 | 3.05 ±0.14 | about right |
| Ram | 3.0 | 3.05 ±0.13 | about right | 3.0 | 3.11 ±0.14 | about right |
| Werewolf | 3.0 | 3.20 ±0.14 | slightly underpriced (+0.2) | 3.0 | 3.18 ±0.14 | slightly underpriced (+0.2) |
| Ghost | 3.0 | 3.11 ±0.14 | about right | 3.0 | 3.17 ±0.14 | slightly underpriced (+0.2) |
| Galleon | 3.0 | 3.05 ±0.13 | about right | 3.0 | 3.09 ±0.14 | about right |
| Lance | 3.0 | 2.83 ±0.13 | slightly overpriced (-0.2) | 3.0 | 2.86 ±0.14 | about right |
| Man | 3.0 | 2.74 ±0.13 | slightly overpriced (-0.3) | 3.0 | 2.80 ±0.14 | slightly overpriced (-0.2) |
| Knight | 3.0 | 3.04 ±0.13 | about right | 3.0 | 3.14 ±0.14 | about right |
| Cavalry | 3.0 | 3.19 ±0.13 | slightly underpriced (+0.2) | 3.0 | 3.14 ±0.14 | slightly underpriced (+0.1) |
| Parapet | 2.5 | 2.70 ±0.12 | slightly underpriced (+0.2) | 2.5 | 2.55 ±0.13 | about right |
| Barbarian | 2.5 | 2.73 ±0.12 | slightly underpriced (+0.2) | 2.5 | 2.79 ±0.13 | slightly underpriced (+0.3) |
| Paladin | 1.5 | 1.24 ±0.09 | slightly overpriced (-0.3) | 1.5 | 1.30 ±0.10 | slightly overpriced (-0.2) |
| Pawn | 1.0 | 0.51 ±0.06 | slightly overpriced (-0.5) | 1.0 | 0.49 ±0.07 | OVERPRICED by ~0.5 |
| Elephant | 1.0 | 0.71 ±0.08 | slightly overpriced (-0.3) | 1.0 | 0.66 ±0.08 | slightly overpriced (-0.3) |
| Assassin | 0.5 | 0.23 ±0.07 | slightly overpriced (-0.3) | 0.5 | 0.19 ±0.07 | slightly overpriced (-0.3) |

A: White 53.7% (53.1%-54.3%) in the random-army games, 18.5% draws.

B: White 53.4% (52.8%-54.1%) in the random-army games, 18.8% draws.

## The meta at the new prices, against run 16's

Share of armies with the piece (mean number when they do). Run 16 = today's prices; run 17 = Vampire 7.5, Wizard 8.5.

| Piece | All-round 16 | All-round 17 | White 16 | White 17 | Black 16 | Black 17 |
|---|---|---|---|---|---|---|
| **Queen** | 5% (x1.0) | 20% (x1.0) | 2% (x1.0) | 52% (x1.0) | 2% (x1.0) | 57% (x1.0) |
| Princess | 8% (x1.0) | 10% (x1.0) | 2% (x1.0) | 2% (x1.0) | 2% (x1.0) | - |
| **Wizard** | 35% (x1.0) | 10% (x1.0) | 52% (x1.0) | - | 57% (x1.0) | - |
| **Vampire** | 88% (x1.7) | 52% (x1.1) | 95% (x1.6) | 45% (x1.4) | 100% (x1.7) | 38% (x1.6) |
| Rook | 35% (x1.2) | 42% (x1.0) | 52% (x1.1) | 62% (x1.1) | 52% (x1.1) | 52% (x1.0) |
| Archer | 60% (x1.2) | 62% (x1.2) | 70% (x1.7) | 52% (x1.2) | 70% (x1.4) | 50% (x1.6) |
| Chariot | 18% (x1.0) | 8% (x1.0) | 18% (x1.0) | 10% (x1.0) | 8% (x1.0) | 10% (x1.0) |
| Cannon | 12% (x1.0) | 12% (x1.2) | 18% (x1.1) | 2% (x1.0) | 10% (x1.0) | 5% (x1.0) |
| Squire | 20% (x1.1) | 20% (x1.1) | 18% (x1.0) | 12% (x1.0) | 10% (x1.0) | 12% (x1.0) |
| **Jester** | 57% (x1.3) | 65% (x1.3) | 72% (x1.3) | 65% (x1.5) | 82% (x1.2) | 65% (x1.3) |
| Necromancer | 38% (x1.0) | 38% (x1.0) | 55% (x1.0) | 20% (x1.0) | 48% (x1.0) | 8% (x1.0) |
| Rogue | 8% (x1.0) | 22% (x1.0) | - | 12% (x1.0) | 2% (x1.0) | 8% (x1.0) |
| Bishop | 50% (x1.1) | 55% (x1.4) | 25% (x1.5) | 25% (x1.4) | 25% (x1.3) | 38% (x1.7) |
| Bard | 10% (x1.5) | 8% (x1.0) | 5% (x1.0) | 18% (x1.0) | 2% (x1.0) | 18% (x1.0) |
| Knight | 28% (x1.2) | 52% (x1.3) | 22% (x1.0) | 52% (x1.1) | 15% (x1.0) | 38% (x1.3) |
| Galleon | 20% (x1.0) | 20% (x1.0) | 10% (x1.0) | 18% (x1.1) | 15% (x1.0) | 15% (x1.0) |
| Ghost | 35% (x1.5) | 72% (x1.3) | 5% (x1.0) | 75% (x1.5) | 5% (x1.0) | 57% (x1.3) |
| Lance | 18% (x1.0) | 22% (x1.0) | 18% (x1.0) | 22% (x1.0) | 8% (x1.0) | 18% (x1.3) |
| Werewolf | 15% (x1.0) | 40% (x1.1) | 10% (x1.0) | 32% (x1.0) | - | 35% (x1.0) |
| Catapult | 15% (x1.2) | 12% (x1.0) | 12% (x1.0) | 2% (x1.0) | 20% (x1.0) | 2% (x1.0) |
| Ram | 30% (x1.0) | 20% (x1.4) | 22% (x1.1) | 12% (x1.6) | 45% (x1.2) | 35% (x1.1) |
| Cavalry | 20% (x1.1) | 28% (x1.4) | 10% (x1.0) | 35% (x1.1) | 25% (x1.0) | 62% (x1.2) |
| Man | - | - | 2% (x1.0) | - | - | - |
| Barbarian | 57% (x1.4) | 57% (x1.5) | 35% (x1.4) | 60% (x1.3) | 42% (x1.2) | 57% (x1.5) |
| Parapet | 35% (x1.1) | 30% (x1.3) | 28% (x1.1) | 45% (x1.1) | 18% (x1.0) | 40% (x1.2) |
| Paladin | 35% (x1.0) | 35% (x1.1) | 28% (x1.0) | 32% (x1.2) | 28% (x1.1) | 25% (x1.0) |
| Pawn | 22% (x1.1) | 8% (x1.0) | 10% (x1.0) | 8% (x1.0) | 5% (x1.0) | 12% (x1.0) |
| **Vassal** | 75% (x2.2) | 90% (x2.2) | 90% (x1.3) | 100% (x2.2) | 85% (x1.9) | 90% (x2.6) |
| Elephant | 8% (x1.0) | 15% (x1.0) | 20% (x1.0) | 5% (x1.0) | 5% (x1.0) | 12% (x1.0) |
| **Grunt** | 48% (x1.0) | 45% (x1.4) | 60% (x1.3) | 48% (x1.2) | 48% (x1.1) | 48% (x1.3) |
| **Abatis** | 38% (x1.1) | 48% (x1.5) | 42% (x1.2) | 45% (x1.7) | 48% (x1.2) | 45% (x1.8) |
| Assassin | 30% (x1.1) | 25% (x1.2) | 8% (x1.0) | 18% (x1.0) | 2% (x1.0) | 5% (x1.0) |

### Families (55% of points in common): run 16 -> run 17

| Archetype | All-round 16 -> 17 | White 16 -> 17 | Black 16 -> 17 | Example (run 17 if any) |
|---|---|---|---|---|
| **2 Vampire + Jester + 2 Vassal** | 38% -> 5% | 70% -> 12% | 80% -> 22% | S1 Wide 6c `(VS)(VS)RK(VS)PJ(GR)/J(PD)(WW)(AB)(CV)VV(AB)` |
| **Queen + Ghost + 2 Vassal** | 2% -> 28% | 0% -> 58% | 2% -> 50% | S1 Wide 11c `(GA)J(VS)K(VS)N(PA)1/Q1A(BR)G(CV)1L` |
| **Vampire + Jester + Necromancer** | 15% -> 10% | 18% -> 8% | 18% -> 8% | S1 Wide 12a `(GR)(VS)JK(RM)(GA)(VS)C/(GR)RG(BR)A(AB)GA` |
| **Vampire + 2 Barbarian + Ghost** | 10% -> 20% | 0% -> 2% | 0% -> 0% | S1 Wide 8a `(WW)B(GR)(WW)K(VS)1(VS)/G(CT)GV(PD)(BR)BJ` |
| **Archer + Vampire + 2 Knight** | 2% -> 8% | 0% -> 5% | 0% -> 8% | S1 Wide 9a `NW1CK(VS)(VS)(AB)/(SQ)(PD)NA(VS)(GR)JJ` |
| **2 Vampire + Jester + Ghost** | 8% -> 2% | 2% -> 8% | 0% -> 0% | S1 Wide W10b `(VS)(VS)RK(VS)(GR)(WW)(GR)/(PD)VJ(AB)GVJ(AB)` |
| **Queen + 2 Cavalry + 2 Barbarian** | 0% -> 2% | 0% -> 2% | 0% -> 10% | S1 S3 Wide 4c `Q1(CV)K(VS)(BR)(VS)(GR)/(CH)R(BR)(AB)(RM)(CV)B(AB)` |
| **Wizard + Archer + Ghost** | 5% -> 8% | 0% -> 0% | 0% -> 0% | S2 Wide 6a `JW(VS)K(VS)(NC)(VS)(VS)/(GR)J(PD)(AB)(CV)ANB` |
| **Vampire + 2 Bishop + Jester** | 0% -> 8% | 0% -> 0% | 0% -> 2% | S2 Wide 3a `1(AS)(VS)RK1A1/1V1BJ(PR)BL` |
| **2 Archer + Cannon + Grunt** | 5% -> 0% | 2% -> 0% | 0% -> 0% | S2 Wide 9a `1(BD)(GR)CK1BJ/1(PD)AA(SQ)(BD)V1` |
| **2 Vampire + Princess + 2 Barbarian** | 5% -> 0% | 2% -> 0% | 0% -> 0% | S2 Wide W8b `(VS)(VS)(GR)KC(NC)2/1(BR)BE(PR)VV(GR)` |
| **Wizard + Archer + Werewolf** | 5% -> 0% | 2% -> 0% | 0% -> 0% | S3 Wide 9a `R(VS)(VS)(WW)KR(VS)L/AG(RM)W(PA)1(VS)1` |

19 archetypes over both runs' 240 armies, 6 of them single armies.

### Archetypes (70%): run 16 -> run 17

| Archetype | All-round 16 -> 17 | White 16 -> 17 | Black 16 -> 17 | Example (run 17 if any) |
|---|---|---|---|---|
| **2 Vampire + Archer + Rook** | 8% -> 2% | 25% -> 5% | 20% -> 10% | S1 Wide 6c `(VS)(VS)RK(VS)PJ(GR)/J(PD)(WW)(AB)(CV)VV(AB)` |
| **Wizard + Vampire + Archer** | 8% -> 2% | 25% -> 0% | 25% -> 0% | S4 Wide 12c `(VS)(VS)G(NC)K(WW)W(GR)/(AS)(AB)V(AB)(AB)(BR)(BR)A` |
| **Queen + Ghost + Barbarian** | 0% -> 8% | 0% -> 25% | 0% -> 28% | S1 Wide 11c `(GA)J(VS)K(VS)N(PA)1/Q1A(BR)G(CV)1L` |
| **2 Vampire + Wizard + Vassal** | 5% -> 0% | 18% -> 0% | 22% -> 0% | S4 Wide B5c `(VS)2WK1(PD)B/(RM)JJVV(CV)2` |
| **2 Vampire + Rook + Jester** | 8% -> 0% | 10% -> 0% | 8% -> 0% | S3 Wide W10c `1R1VKN1(VS)/2J(SQ)(NC)AV(BR)` |
| **Queen + 2 Archer + 2 Bishop** | 0% -> 5% | 0% -> 8% | 0% -> 12% | S1 S3 Wide 10a `QA(GR)K(VS)1(VS)1/BJA(AB)(AB)(RO)GB` |
| **2 Archer + Vampire + 2 Jester** | 8% -> 0% | 10% -> 0% | 5% -> 0% | S1 S2 Wide 10a `1(VS)JCK(NC)1(BD)/(GR)(PD)AALJV1` |
| **2 Vampire + Wizard + Archer** | 10% -> 0% | 0% -> 0% | 10% -> 0% | S1 Wide 6a `WG1BK(VS)(VS)1/E(VS)VA(AB)(BR)V(GR)` |
| **Queen + 2 Cavalry + Rook** | 0% -> 2% | 0% -> 5% | 2% -> 10% | S1 S3 Wide 4c `Q1(CV)K(VS)(BR)(VS)(GR)/(CH)R(BR)(AB)(RM)(CV)B(AB)` |
| **2 Vampire + 2 Bishop + Ram** | 0% -> 2% | 2% -> 2% | 0% -> 10% | S1 Wide W5c `(VS)(VS)(VS)(RM)KN(VS)1/BVBVJP(RM)(AB)` |
| **2 Archer + Vampire + 2 Knight** | 0% -> 2% | 0% -> 5% | 0% -> 10% | S1 Wide B7a `(VS)1NKN2A/(PA)(VS)(BR)(CV)V(SQ)A(BD)` |
| **2 Vampire + Ghost + Archer** | 8% -> 2% | 0% -> 2% | 2% -> 0% | S3 Wide 9a `1(GA)(VS)K(WW)1G1/L(RM)(BR)(BR)AVJB` |

64 archetypes over both runs' 240 armies, 36 of them single armies.

All-rounders against the specialists at the new prices: 43.2% as White against the Black specialists, 37.5% as Black against the White ones (run 16: 43.0% / 38.0%); 3 of 40 all-rounders hold 50%+ both ways (run 16: 3 of 40).

## Success line (from the README, written before the run)

- Vampire in under 60% of the all-round armies (run 16: 87.5%): **yes** (52.5% of 40 all-rounders, 1.1 each; White specialists 45.0%, Black 37.5%)
