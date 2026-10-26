# Balance run 16: the meta by share (report)

Made by `tools/balance/run16_analyse.py`. 4 independent searches under today's rules and prices (Nicholas's Plusfish of PR #28): 40 all-round armies grown from scratch, 40 White-only and 40 Black-only armies grown against a frozen set of the best all-rounders. An army is its piece list (placement ignored); two armies belong to the same archetype when the points they have in common reach 55% of the budget (22 of 40), built greedily around the most-connected armies. Shares are percentages of each population.

## Archetypes and their share of each population

| # | Archetype (pieces most members have, mean count) | All-round (40) | White-only (40) | Black-only (40) | Armies | Example |
|---|---|---|---|---|---|---|
| 1 | **2 Vampire + Jester + 2 Vassal** (Vampire x1.8, Jester, Vassal x1.5) | 50% | 65% | 88% | 81 | S3 Wide W5a `W1(SQ)1KN1J/(VS)(BR)A1V(AB)V1` |
| 2 | **Vampire + Archer + 2 Jester** (Vampire, Archer, Jester x1.8) | 10% | 15% | 10% | 14 | S1 Wide B4a `1J(VS)K2(RM)B/J1V(NC)RA(RM)B` |
| 3 | **Wizard + Vampire + Necromancer** (Wizard, Vampire, Necromancer) | 12% | 8% | - | 8 | S1 Wide 11c `1(VS)(WW)(GR)K1(NC)B/WR(BR)VGG1(AS)` |
| 4 | **2 Vampire + Barbarian + 2 Vassal** (Vampire x2.0, Barbarian, Vassal x2.4) | 8% | 5% | - | 5 | S1 Wide 3b `(GR)(VS)(VS)KN(CT)(BR)(AS)/(PA)B(BR)(AB)(CV)VV(GA)` |
| 5 | **Wizard + Rook + Archer** (Wizard, Rook, Archer, Vassal x2.7, Parapet) | 5% | 2% | - | 3 | S2 Wide 8a `(VS)(WW)(AS)CK(VS)W(VS)/A(AB)R(BR)(GR)(BR)(PA)(RM)` |
| 6 | **Queen + Vampire + 2 Vassal** (Queen, Vampire, Vassal x2.0) | 2% | 2% | 2% | 3 | S3 Wide W12c `1(CT)(VS)CK1(VS)1/B(PA)1V(PA)Q(WW)L` |
| 7 | **2 Bard + 2 Archer + 2 Bishop** (Bard x2.0, Archer x1.5, Bishop x1.5, Squire, Cannon) | 5% | - | - | 2 | S2 Wide 9a `1(BD)(GR)CK1BJ/1(PD)AA(SQ)(BD)V1` |
| 8 | **2 Vampire + 2 Ghost + Rogue** (Vampire x2.0, Ghost x1.5, Rogue, Necromancer, Ram) | 5% | - | - | 2 | S3 Wide 12b `PG(AS)(NC)K(RO)2/BVVG(CV)L(RM)1` |
| 9 | **2 Archer + Wizard + Squire** (Archer x2.0, Wizard, Squire, Necromancer, Jester) | - | 2% | - | 1 | S1 Wide W6c `(VS)W(SQ)K(WW)(RM)1A/EGJ(NC)(AB)A1(AS)` |
| 10 | **2 Archer + 2 Squire + 2 Bishop** (Archer x2.0, Squire x2.0, Bishop x2.0, Rook, Vassal x3.0) | 2% | - | - | 1 | S2 Wide 4a `(PD)(VS)RK(RM)(VS)(VS)(SQ)/(SQ)AGEA1BB` |

10 archetypes in 120 armies (2 of them armies on their own).

## Pieces by population (share of armies that have the piece, and the mean number when they do)

| Piece | Cost | All-round | White-only | Black-only |
|---|---|---|---|---|
| Queen | 10.0 | 5% (x1.0) | 2% (x1.0) | 2% (x1.0) |
| Princess | 8.5 | 8% (x1.0) | 2% (x1.0) | 2% (x1.0) |
| Wizard | 8.0 | 35% (x1.0) | 52% (x1.0) | 58% (x1.0) |
| Vampire | 6.5 | 88% (x1.7) | 95% (x1.6) | 100% (x1.7) |
| Rook | 4.5 | 35% (x1.2) | 52% (x1.1) | 52% (x1.1) |
| Archer | 4.5 | 60% (x1.2) | 70% (x1.7) | 70% (x1.4) |
| Squire | 4.0 | 20% (x1.1) | 18% (x1.0) | 10% (x1.0) |
| Chariot | 4.0 | 18% (x1.0) | 18% (x1.0) | 8% (x1.0) |
| Cannon | 4.0 | 12% (x1.0) | 18% (x1.1) | 10% (x1.0) |
| Bishop | 3.5 | 50% (x1.1) | 25% (x1.5) | 25% (x1.3) |
| Necromancer | 3.5 | 38% (x1.0) | 55% (x1.0) | 48% (x1.0) |
| Bard | 3.5 | 10% (x1.5) | 5% (x1.0) | 2% (x1.0) |
| Rogue | 3.5 | 8% (x1.0) | - | 2% (x1.0) |
| Jester | 3.5 | 58% (x1.3) | 72% (x1.3) | 82% (x1.2) |
| Lance | 3.0 | 18% (x1.0) | 18% (x1.0) | 8% (x1.0) |
| Werewolf | 3.0 | 15% (x1.0) | 10% (x1.0) | - |
| Cavalry | 3.0 | 20% (x1.1) | 10% (x1.0) | 25% (x1.0) |
| Knight | 3.0 | 28% (x1.2) | 22% (x1.0) | 15% (x1.0) |
| Galleon | 3.0 | 20% (x1.0) | 10% (x1.0) | 15% (x1.0) |
| Ram | 3.0 | 30% (x1.0) | 22% (x1.1) | 45% (x1.2) |
| Man | 3.0 | - | 2% (x1.0) | - |
| Ghost | 3.0 | 35% (x1.5) | 5% (x1.0) | 5% (x1.0) |
| Catapult | 3.0 | 15% (x1.2) | 12% (x1.0) | 20% (x1.0) |
| Parapet | 2.5 | 35% (x1.1) | 28% (x1.1) | 18% (x1.0) |
| Barbarian | 2.5 | 58% (x1.4) | 35% (x1.4) | 42% (x1.2) |
| Paladin | 1.5 | 35% (x1.0) | 28% (x1.0) | 28% (x1.1) |
| Grunt | 1.0 | 48% (x1.0) | 60% (x1.3) | 48% (x1.1) |
| Pawn | 1.0 | 22% (x1.1) | 10% (x1.0) | 5% (x1.0) |
| Vassal | 1.0 | 75% (x2.2) | 90% (x1.3) | 85% (x1.9) |
| Elephant | 1.0 | 8% (x1.0) | 20% (x1.0) | 5% (x1.0) |
| Abatis | 0.5 | 38% (x1.1) | 42% (x1.2) | 48% (x1.2) |
| Assassin | 0.5 | 30% (x1.1) | 8% (x1.0) | 2% (x1.0) |

Front row: all-round 7.0 of 8 squares filled, 0.8 pawn types there, 10.7 pieces an army; White 6.7 of 8 squares filled, 0.9 pawn types there, 10.2 pieces an army; Black 6.7 of 8 squares filled, 1.0 pawn types there, 9.8 pieces an army.

## All-rounders against the colour specialists (20 games a pairing, colours fixed)

| | White's score |
|---|---|
| All-rounders as White against the Black specialists | 43.0% (42.5%-43.4%) |
| White specialists against the all-rounders as Black | 62.0% (61.5%-62.5%) |

**All-rounders that hold up against both colours' specialists (50% or more each way): 3 of 40.**

| All-rounder | Archetype | As White vs Black specialists | As Black vs White specialists |
|---|---|---|---|
| **S3 Wide 10a** `(VS)(SQ)1CK(GR)P(BD)/(BD)LRB(AB)A(BR)B` | #7 2 Bard + 2 Archer + 2 Bishop | 66.9% | 61.9% |
| S2 Wide 9a `1(BD)(GR)CK1BJ/1(PD)AA(SQ)(BD)V1` | #7 2 Bard + 2 Archer + 2 Bishop | 68.1% | 46.6% |
| **S4 Wide 6b** `R1JK(PA)1JR/1PB(BR)(NC)VA1` | #2 Vampire + Archer + 2 Jester | 53.1% | 60.7% |
| **S4 Wide 7a** `QJ(PD)1K(WW)(VS)1/1L(BR)GVG(BR)(AB)` | #6 Queen + Vampire + 2 Vassal | 51.4% | 52.5% |
| S1 Wide 9a `1(GR)(VS)KA(VS)(AB)1/BVJA(CT)1VR` | #1 2 Vampire + Jester + 2 Vassal | 53.2% | 47.8% |
| S2 Wide 10a `1(VS)JCK(NC)1(BD)/(GR)(PD)AALJV1` | #2 Vampire + Archer + 2 Jester | 56.9% | 44.0% |
| S4 Wide 9a `LR1(VS)KC(VS)(VS)/2J(BD)VJAB` | #2 Vampire + Archer + 2 Jester | 49.6% | 49.5% |
| S3 Wide 11a `2(RM)WK(PD)(NC)(GR)/AJ1V(BR)(CT)1(CV)` | #1 2 Vampire + Jester + 2 Vassal | 52.8% | 44.2% |
| S1 Wide 11a `(GA)(NC)(VS)K2AW/(BR)(BR)1(AB)A1JV` | #1 2 Vampire + Jester + 2 Vassal | 53.6% | 41.9% |
| S4 Wide 6c `(VS)1(PA)1KW(PD)B/1(RM)VV(CH)B2` | #1 2 Vampire + Jester + 2 Vassal | 55.1% | 37.8% |
| S2 Wide 4a `(PD)(VS)RK(RM)(VS)(VS)(SQ)/(SQ)AGEA1BB` | #10 2 Archer + 2 Squire + 2 Bishop | 42.0% | 49.4% |
| S2 Wide 8a `(VS)(WW)(AS)CK(VS)W(VS)/A(AB)R(BR)(GR)(BR)(PA)(RM)` | #5 Wizard + Rook + Archer | 49.6% | 39.2% |
| S3 Wide 9c `R2JKN2/1J(VS)WV(BR)V(GR)` | #1 2 Vampire + Jester + 2 Vassal | 44.1% | 44.7% |
| S3 Wide 9a `R(VS)(VS)(WW)KR(VS)L/AG(RM)W(PA)1(VS)1` | #5 Wizard + Rook + Archer | 50.4% | 37.7% |
| S1 Wide 11c `1(VS)(WW)(GR)K1(NC)B/WR(BR)VGG1(AS)` | #3 Wizard + Vampire + Necromancer | 43.8% | 40.6% |
| S4 Wide 12a `(GR)(GA)(AB)K(PA)2J/B(BR)(SQ)(CH)V(BR)V1` | #1 2 Vampire + Jester + 2 Vassal | 38.1% | 44.1% |
| S4 Wide 5c `R(VS)(VS)(AS)K(PR)(VS)1/1BAJV(AS)(PD)J` | #2 Vampire + Archer + 2 Jester | 46.2% | 35.8% |
| S2 Wide 3a `(CV)W(VS)K(RM)(CV)J1/1(AS)(BR)(PA)V1A(PD)` | #1 2 Vampire + Jester + 2 Vassal | 37.5% | 42.5% |
| S4 Wide 11a `(SQ)J1(NC)KN(VS)1/1(BR)V1VR(AB)R` | #1 2 Vampire + Jester + 2 Vassal | 42.2% | 37.4% |
| S3 Wide 11c `1(PA)(NC)GKP2/(GA)AB(BR)N(BR)GW` | #3 Wizard + Vampire + Necromancer | 42.6% | 36.5% |
| S2 Wide 10c `(GR)1(PA)PKR1(VS)/(AB)AVA(AB)JV(NC)` | #1 2 Vampire + Jester + 2 Vassal | 43.3% | 34.8% |
| S3 Wide 6a `(BR)(PA)1NK1(RM)(VS)/PVV(WW)(BR)(PR)2` | #4 2 Vampire + Barbarian + 2 Vassal | 44.4% | 33.1% |
| S4 Wide 10c `1(NC)1GK(GR)P1/1JVA(RM)V(RO)(CH)` | #8 2 Vampire + 2 Ghost + Rogue | 38.4% | 38.2% |
| S4 Wide 3c `P1(GA)1KP1(CV)/1JVA1VQ(VS)` | #1 2 Vampire + Jester + 2 Vassal | 44.1% | 32.2% |
| S1 Wide 12a `(VS)AJK(VS)1NJ/(PD)(VS)VBEV1(NC)` | #1 2 Vampire + Jester + 2 Vassal | 42.3% | 32.4% |
| S4 Wide 11c `(PD)1(WW)K(NC)1(VS)1/JRV(BR)VG(CH)(AS)` | #3 Wizard + Vampire + Necromancer | 37.3% | 36.8% |
| S3 Wide 12a `WG(AS)1K(RO)2/BV1(BR)(CV)L(RM)(NC)` | #3 Wizard + Vampire + Necromancer | 40.2% | 32.8% |
| S1 Wide 3a `(BR)1BKJ(CT)(GR)(AS)/(PA)(CT)N(AB)(CH)VV1` | #1 2 Vampire + Jester + 2 Vassal | 36.4% | 33.8% |
| S2 Wide 12a `W(VS)(VS)K(VS)(PA)(VS)1/A(VS)(VS)(RM)(GA)VV1` | #1 2 Vampire + Jester + 2 Vassal | 39.8% | 28.9% |
| S2 Wide 8c `1(CH)1(GA)K1W1/(AS)G(BR)VAG(PD)B` | #3 Wizard + Vampire + Necromancer | 36.6% | 31.5% |
| S1 Wide 6a `WG1BK(VS)(VS)1/E(VS)VA(AB)(BR)V(GR)` | #1 2 Vampire + Jester + 2 Vassal | 33.9% | 31.9% |
| S1 Wide 12c `(VS)(VS)(CT)K(VS)(RM)A1/(AB)GGVJV(BR)(GR)` | #1 2 Vampire + Jester + 2 Vassal | 33.9% | 30.9% |
| S3 Wide 6c `(NC)(AS)(VS)NK(BR)(VS)1/V(SQ)N(CH)V(BR)(AB)(PD)` | #1 2 Vampire + Jester + 2 Vassal | 33.6% | 31.1% |
| S1 Wide 10c `1(AS)(VS)KGN(VS)(GR)/JVJV(SQ)G(CV)(AB)` | #1 2 Vampire + Jester + 2 Vassal | 33.6% | 29.4% |
| S2 Wide 7b `(PD)W1(VS)K(GR)(VS)(VS)/A(VS)(SQ)(CT)PVV1` | #1 2 Vampire + Jester + 2 Vassal | 38.2% | 24.4% |
| S1 Wide 7c `JV(VS)KNN2/BV(GR)(AB)(VS)RA(PD)` | #1 2 Vampire + Jester + 2 Vassal | 27.7% | 33.9% |
| S3 Wide 7c `1(PR)(VS)(VS)K(BR)(VS)(VS)/(GA)VV(PA)(BR)(VS)G1` | #4 2 Vampire + Barbarian + 2 Vassal | 28.3% | 31.9% |
| S2 Wide 7c `N(VS)(VS)K(GR)(NC)J1/VB(PA)(CV)(BR)V1(PA)` | #1 2 Vampire + Jester + 2 Vassal | 30.3% | 27.4% |
| S3 Wide 12b `PG(AS)(NC)K(RO)2/BVVG(CV)L(RM)1` | #8 2 Vampire + 2 Ghost + Rogue | 30.6% | 24.6% |
| S1 Wide 3b `(GR)(VS)(VS)KN(CT)(BR)(AS)/(PA)B(BR)(AB)(CV)VV(GA)` | #4 2 Vampire + Barbarian + 2 Vassal | 27.9% | 25.9% |

Archetypes among the all-rounders that hold up: #7 2 Bard + 2 Archer + 2 Bishop 33%; #2 Vampire + Archer + 2 Jester 33%; #6 Queen + Vampire + 2 Vassal 33%
