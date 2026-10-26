# Balance run 16: the meta by share (report)

Made by `tools/balance/run16_analyse.py`. 4 independent searches under today's rules and prices (Nicholas's Plusfish of PR #28): 40 all-round armies grown from scratch, 40 White-only and 40 Black-only armies grown against a frozen set of the best all-rounders. An army is its piece list (placement ignored); two armies belong to the same archetype when the points they have in common reach 70% of the budget (28 of 40), built greedily around the most-connected armies. Shares are percentages of each population.

## Archetypes and their share of each population

| # | Archetype (pieces most members have, mean count) | All-round (40) | White-only (40) | Black-only (40) | Armies | Example |
|---|---|---|---|---|---|---|
| 1 | **Wizard + Vampire + Archer** (Wizard, Vampire, Archer, Barbarian, Necromancer) | 8% | 25% | 25% | 23 | S4 Wide B10a `1(BR)(VS)K(NC)3/(RM)(BR)ARVWJ(AB)` |
| 2 | **2 Vampire + 2 Archer + Rook** (Vampire x2.0, Archer x1.9, Rook, Jester, Vassal) | 8% | 28% | 20% | 22 | S1 Wide W7a `2(VS)KA(GR)(VS)1/(SQ)VAJ(CT)1VR` |
| 3 | **2 Vampire + Wizard + Vassal** (Vampire x2.0, Wizard, Vassal) | 5% | 18% | 22% | 18 | S4 Wide B5c `(VS)2WK1(PD)B/(RM)JJVV(CV)2` |
| 4 | **2 Vampire + Wizard + Archer** (Vampire x1.9, Wizard, Archer, Vassal x3.8) | 10% | 2% | 10% | 9 | S1 Wide 6a `WG1BK(VS)(VS)1/E(VS)VA(AB)(BR)V(GR)` |
| 5 | **2 Archer + Vampire + 2 Jester** (Archer x1.8, Vampire, Jester x1.8, Cannon, Lance) | 8% | 10% | 5% | 9 | S1 S2 Wide 10a `1(VS)JCK(NC)1(BD)/(GR)(PD)AALJV1` |
| 6 | **2 Vampire + 2 Rook + Necromancer** (Vampire x2.0, Rook x1.9, Necromancer, Jester, Knight) | 5% | 5% | 8% | 7 | S1 S4 Wide 11a `(SQ)J1(NC)KN(VS)1/1(BR)V1VR(AB)R` |
| 7 | **2 Vampire + Archer + Ghost** (Vampire x2.0, Archer, Ghost, Jester, Necromancer) | 10% | - | 2% | 5 | S2 Wide B3a `1L(VS)JK(NC)(VS)(VS)/(RM)2BVAGV` |
| 8 | **2 Vampire + 2 Barbarian + Bishop** (Vampire x2.0, Barbarian x1.5, Bishop, Parapet, Jester) | 10% | - | - | 4 | S1 Wide 3a `(BR)1BKJ(CT)(GR)(AS)/(PA)(CT)N(AB)(CH)VV1` |
| 9 | **2 Jester + 2 Rook + Vampire** (Jester x2.0, Rook x1.5, Vampire, Bishop x1.5, Archer) | 2% | - | 2% | 2 | S1 Wide B4a `1J(VS)K2(RM)B/J1V(NC)RA(RM)B` |
| 10 | **Wizard + 2 Rook + Archer** (Wizard, Rook x1.5, Archer, Vassal x3.5, Werewolf) | 5% | - | - | 2 | S2 Wide 8a `(VS)(WW)(AS)CK(VS)W(VS)/A(AB)R(BR)(GR)(BR)(PA)(RM)` |
| 11 | **2 Vampire + Princess + 2 Barbarian** (Vampire x2.0, Princess, Barbarian x2.0, Vassal x3.0, Parapet) | 5% | - | - | 2 | S3 Wide 6a `(BR)(PA)1NK1(RM)(VS)/PVV(WW)(BR)(PR)2` |
| 12 | **Princess + 2 Jester + Vampire** (Princess, Jester x2.0, Vampire, Rook, Vassal x2.0) | 2% | - | 2% | 2 | S3 Wide B3a `CRJJK1(VS)1/(AB)(BR)V1(PD)(NC)(PR)1` |
| 13 | **Wizard + Vampire + 2 Ghost** (Wizard, Vampire, Ghost x2.0, Rook, Necromancer) | 2% | - | - | 1 | S1 Wide 11c `1(VS)(WW)(GR)K1(NC)B/WR(BR)VGG1(AS)` |
| 14 | **2 Vampire + 2 Jester + 2 Ghost** (Vampire x2.0, Jester x2.0, Ghost x2.0, Squire, Knight) | 2% | - | - | 1 | S1 Wide 10c `1(AS)(VS)KGN(VS)(GR)/JVJV(SQ)G(CV)(AB)` |
| 15 | **2 Vampire + 2 Bishop + 2 Ram** (Vampire x2.0, Bishop x2.0, Ram x2.0, Jester, Werewolf) | - | 2% | - | 1 | S1 Wide W2c `1(RM)(PA)K(WW)JBE/(GR)1(RM)GV1VB` |
| 16 | **2 Archer + Wizard + Squire** (Archer x2.0, Wizard, Squire, Necromancer, Jester) | - | 2% | - | 1 | S1 Wide W6c `(VS)W(SQ)K(WW)(RM)1A/EGJ(NC)(AB)A1(AS)` |
| 17 | **2 Archer + 2 Squire + 2 Bishop** (Archer x2.0, Squire x2.0, Bishop x2.0, Rook, Vassal x3.0) | 2% | - | - | 1 | S2 Wide 4a `(PD)(VS)RK(RM)(VS)(VS)(SQ)/(SQ)AGEA1BB` |
| 18 | **2 Vampire + Princess + Cannon** (Vampire x2.0, Princess, Cannon, Necromancer, Bishop) | - | 2% | - | 1 | S2 Wide W8b `(VS)(VS)(GR)KC(NC)2/1(BR)BE(PR)VV(GR)` |
| 19 | **Queen + Vampire + Rook** (Queen, Vampire, Rook, Archer, Chariot) | - | - | 2% | 1 | S2 Wide B4c `(VS)(CV)RK(VS)1QB/(CH)(VS)1(GR)AV2` |
| 20 | **Wizard + Vampire + Rogue** (Wizard, Vampire, Rogue, Necromancer, Bishop) | 2% | - | - | 1 | S3 Wide 12a `WG(AS)1K(RO)2/BV1(BR)(CV)L(RM)(NC)` |
| 21 | **2 Bard + 2 Bishop + Rook** (Bard x2.0, Bishop x2.0, Rook, Archer, Squire) | 2% | - | - | 1 | S3 Wide 10a `(VS)(SQ)1CK(GR)P(BD)/(BD)LRB(AB)A(BR)B` |
| 22 | **2 Vampire + 2 Knight + 2 Barbarian** (Vampire x2.0, Knight x2.0, Barbarian x2.0, Squire, Chariot) | 2% | - | - | 1 | S3 Wide 6c `(NC)(AS)(VS)NK(BR)(VS)1/V(SQ)N(CH)V(BR)(AB)(PD)` |
| 23 | **Wizard + 2 Ghost + 2 Barbarian** (Wizard, Ghost x2.0, Barbarian x2.0, Archer, Necromancer) | 2% | - | - | 1 | S3 Wide 11c `1(PA)(NC)GKP2/(GA)AB(BR)N(BR)GW` |
| 24 | **Wizard + Rook + Archer** (Wizard, Rook, Archer, Cannon, Necromancer) | - | 2% | - | 1 | S3 Wide W3c `1WNK(NC)R1C/E(VS)(PD)(CV)JA(PA)1` |
| 25 | **Queen + Vampire + 2 Parapet** (Queen, Vampire, Parapet x2.0, Cannon, Bishop) | - | 2% | - | 1 | S3 Wide W12c `1(CT)(VS)CK1(VS)1/B(PA)1V(PA)Q(WW)L` |
| 26 | **2 Vampire + Queen + Archer** (Vampire x2.0, Queen, Archer, Jester, Galleon) | 2% | - | - | 1 | S4 Wide 3c `P1(GA)1KP1(CV)/1JVA1VQ(VS)` |
| 27 | **Queen + Vampire + 2 Ghost** (Queen, Vampire, Ghost x2.0, Barbarian x2.0, Jester) | 2% | - | - | 1 | S4 Wide 7a `QJ(PD)1K(WW)(VS)1/1L(BR)GVG(BR)(AB)` |

27 archetypes in 120 armies (15 of them armies on their own).

## Pieces by population (share of armies that have the piece, and the mean number when they do)

| Piece | Cost | All-round | White-only | Black-only |
|---|---|---|---|---|
| Queen | 10.0 | 5% (x1.0) | 2% (x1.0) | 2% (x1.0) |
| Princess | 8.5 | 8% (x1.0) | 2% (x1.0) | 2% (x1.0) |
| Wizard | 8.0 | 35% (x1.0) | 52% (x1.0) | 58% (x1.0) |
| Vampire | 6.5 | 88% (x1.7) | 95% (x1.6) | 100% (x1.7) |
| Archer | 4.5 | 60% (x1.2) | 70% (x1.7) | 70% (x1.4) |
| Rook | 4.5 | 35% (x1.2) | 52% (x1.1) | 52% (x1.1) |
| Chariot | 4.0 | 18% (x1.0) | 18% (x1.0) | 8% (x1.0) |
| Cannon | 4.0 | 12% (x1.0) | 18% (x1.1) | 10% (x1.0) |
| Squire | 4.0 | 20% (x1.1) | 18% (x1.0) | 10% (x1.0) |
| Necromancer | 3.5 | 38% (x1.0) | 55% (x1.0) | 48% (x1.0) |
| Bard | 3.5 | 10% (x1.5) | 5% (x1.0) | 2% (x1.0) |
| Rogue | 3.5 | 8% (x1.0) | - | 2% (x1.0) |
| Jester | 3.5 | 58% (x1.3) | 72% (x1.3) | 82% (x1.2) |
| Bishop | 3.5 | 50% (x1.1) | 25% (x1.5) | 25% (x1.3) |
| Werewolf | 3.0 | 15% (x1.0) | 10% (x1.0) | - |
| Knight | 3.0 | 28% (x1.2) | 22% (x1.0) | 15% (x1.0) |
| Galleon | 3.0 | 20% (x1.0) | 10% (x1.0) | 15% (x1.0) |
| Lance | 3.0 | 18% (x1.0) | 18% (x1.0) | 8% (x1.0) |
| Cavalry | 3.0 | 20% (x1.1) | 10% (x1.0) | 25% (x1.0) |
| Man | 3.0 | - | 2% (x1.0) | - |
| Ghost | 3.0 | 35% (x1.5) | 5% (x1.0) | 5% (x1.0) |
| Catapult | 3.0 | 15% (x1.2) | 12% (x1.0) | 20% (x1.0) |
| Ram | 3.0 | 30% (x1.0) | 22% (x1.1) | 45% (x1.2) |
| Parapet | 2.5 | 35% (x1.1) | 28% (x1.1) | 18% (x1.0) |
| Barbarian | 2.5 | 58% (x1.4) | 35% (x1.4) | 42% (x1.2) |
| Paladin | 1.5 | 35% (x1.0) | 28% (x1.0) | 28% (x1.1) |
| Pawn | 1.0 | 22% (x1.1) | 10% (x1.0) | 5% (x1.0) |
| Elephant | 1.0 | 8% (x1.0) | 20% (x1.0) | 5% (x1.0) |
| Grunt | 1.0 | 48% (x1.0) | 60% (x1.3) | 48% (x1.1) |
| Vassal | 1.0 | 75% (x2.2) | 90% (x1.3) | 85% (x1.9) |
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
| **S3 Wide 10a** `(VS)(SQ)1CK(GR)P(BD)/(BD)LRB(AB)A(BR)B` | #21 2 Bard + 2 Bishop + Rook | 66.9% | 61.9% |
| S2 Wide 9a `1(BD)(GR)CK1BJ/1(PD)AA(SQ)(BD)V1` | #5 2 Archer + Vampire + 2 Jester | 68.1% | 46.6% |
| **S4 Wide 6b** `R1JK(PA)1JR/1PB(BR)(NC)VA1` | #9 2 Jester + 2 Rook + Vampire | 53.1% | 60.7% |
| **S4 Wide 7a** `QJ(PD)1K(WW)(VS)1/1L(BR)GVG(BR)(AB)` | #27 Queen + Vampire + 2 Ghost | 51.4% | 52.5% |
| S1 Wide 9a `1(GR)(VS)KA(VS)(AB)1/BVJA(CT)1VR` | #2 2 Vampire + 2 Archer + Rook | 53.2% | 47.8% |
| S2 Wide 10a `1(VS)JCK(NC)1(BD)/(GR)(PD)AALJV1` | #5 2 Archer + Vampire + 2 Jester | 56.9% | 44.0% |
| S4 Wide 9a `LR1(VS)KC(VS)(VS)/2J(BD)VJAB` | #5 2 Archer + Vampire + 2 Jester | 49.6% | 49.5% |
| S3 Wide 11a `2(RM)WK(PD)(NC)(GR)/AJ1V(BR)(CT)1(CV)` | #1 Wizard + Vampire + Archer | 52.8% | 44.2% |
| S1 Wide 11a `(GA)(NC)(VS)K2AW/(BR)(BR)1(AB)A1JV` | #1 Wizard + Vampire + Archer | 53.6% | 41.9% |
| S4 Wide 6c `(VS)1(PA)1KW(PD)B/1(RM)VV(CH)B2` | #3 2 Vampire + Wizard + Vassal | 55.1% | 37.8% |
| S2 Wide 4a `(PD)(VS)RK(RM)(VS)(VS)(SQ)/(SQ)AGEA1BB` | #17 2 Archer + 2 Squire + 2 Bishop | 42.0% | 49.4% |
| S2 Wide 8a `(VS)(WW)(AS)CK(VS)W(VS)/A(AB)R(BR)(GR)(BR)(PA)(RM)` | #10 Wizard + 2 Rook + Archer | 49.6% | 39.2% |
| S3 Wide 9c `R2JKN2/1J(VS)WV(BR)V(GR)` | #3 2 Vampire + Wizard + Vassal | 44.1% | 44.7% |
| S3 Wide 9a `R(VS)(VS)(WW)KR(VS)L/AG(RM)W(PA)1(VS)1` | #10 Wizard + 2 Rook + Archer | 50.4% | 37.7% |
| S1 Wide 11c `1(VS)(WW)(GR)K1(NC)B/WR(BR)VGG1(AS)` | #13 Wizard + Vampire + 2 Ghost | 43.8% | 40.6% |
| S4 Wide 12a `(GR)(GA)(AB)K(PA)2J/B(BR)(SQ)(CH)V(BR)V1` | #8 2 Vampire + 2 Barbarian + Bishop | 38.1% | 44.1% |
| S4 Wide 5c `R(VS)(VS)(AS)K(PR)(VS)1/1BAJV(AS)(PD)J` | #12 Princess + 2 Jester + Vampire | 46.2% | 35.8% |
| S2 Wide 3a `(CV)W(VS)K(RM)(CV)J1/1(AS)(BR)(PA)V1A(PD)` | #1 Wizard + Vampire + Archer | 37.5% | 42.5% |
| S4 Wide 11a `(SQ)J1(NC)KN(VS)1/1(BR)V1VR(AB)R` | #6 2 Vampire + 2 Rook + Necromancer | 42.2% | 37.4% |
| S3 Wide 11c `1(PA)(NC)GKP2/(GA)AB(BR)N(BR)GW` | #23 Wizard + 2 Ghost + 2 Barbarian | 42.6% | 36.5% |
| S2 Wide 10c `(GR)1(PA)PKR1(VS)/(AB)AVA(AB)JV(NC)` | #2 2 Vampire + 2 Archer + Rook | 43.3% | 34.8% |
| S3 Wide 6a `(BR)(PA)1NK1(RM)(VS)/PVV(WW)(BR)(PR)2` | #11 2 Vampire + Princess + 2 Barbarian | 44.4% | 33.1% |
| S4 Wide 10c `1(NC)1GK(GR)P1/1JVA(RM)V(RO)(CH)` | #7 2 Vampire + Archer + Ghost | 38.4% | 38.2% |
| S4 Wide 3c `P1(GA)1KP1(CV)/1JVA1VQ(VS)` | #26 2 Vampire + Queen + Archer | 44.1% | 32.2% |
| S1 Wide 12a `(VS)AJK(VS)1NJ/(PD)(VS)VBEV1(NC)` | #7 2 Vampire + Archer + Ghost | 42.3% | 32.4% |
| S4 Wide 11c `(PD)1(WW)K(NC)1(VS)1/JRV(BR)VG(CH)(AS)` | #6 2 Vampire + 2 Rook + Necromancer | 37.3% | 36.8% |
| S3 Wide 12a `WG(AS)1K(RO)2/BV1(BR)(CV)L(RM)(NC)` | #20 Wizard + Vampire + Rogue | 40.2% | 32.8% |
| S1 Wide 3a `(BR)1BKJ(CT)(GR)(AS)/(PA)(CT)N(AB)(CH)VV1` | #8 2 Vampire + 2 Barbarian + Bishop | 36.4% | 33.8% |
| S2 Wide 12a `W(VS)(VS)K(VS)(PA)(VS)1/A(VS)(VS)(RM)(GA)VV1` | #4 2 Vampire + Wizard + Archer | 39.8% | 28.9% |
| S2 Wide 8c `1(CH)1(GA)K1W1/(AS)G(BR)VAG(PD)B` | #4 2 Vampire + Wizard + Archer | 36.6% | 31.5% |
| S1 Wide 6a `WG1BK(VS)(VS)1/E(VS)VA(AB)(BR)V(GR)` | #4 2 Vampire + Wizard + Archer | 33.9% | 31.9% |
| S1 Wide 12c `(VS)(VS)(CT)K(VS)(RM)A1/(AB)GGVJV(BR)(GR)` | #7 2 Vampire + Archer + Ghost | 33.9% | 30.9% |
| S3 Wide 6c `(NC)(AS)(VS)NK(BR)(VS)1/V(SQ)N(CH)V(BR)(AB)(PD)` | #22 2 Vampire + 2 Knight + 2 Barbarian | 33.6% | 31.1% |
| S1 Wide 10c `1(AS)(VS)KGN(VS)(GR)/JVJV(SQ)G(CV)(AB)` | #14 2 Vampire + 2 Jester + 2 Ghost | 33.6% | 29.4% |
| S2 Wide 7b `(PD)W1(VS)K(GR)(VS)(VS)/A(VS)(SQ)(CT)PVV1` | #4 2 Vampire + Wizard + Archer | 38.2% | 24.4% |
| S1 Wide 7c `JV(VS)KNN2/BV(GR)(AB)(VS)RA(PD)` | #2 2 Vampire + 2 Archer + Rook | 27.7% | 33.9% |
| S3 Wide 7c `1(PR)(VS)(VS)K(BR)(VS)(VS)/(GA)VV(PA)(BR)(VS)G1` | #11 2 Vampire + Princess + 2 Barbarian | 28.3% | 31.9% |
| S2 Wide 7c `N(VS)(VS)K(GR)(NC)J1/VB(PA)(CV)(BR)V1(PA)` | #8 2 Vampire + 2 Barbarian + Bishop | 30.3% | 27.4% |
| S3 Wide 12b `PG(AS)(NC)K(RO)2/BVVG(CV)L(RM)1` | #7 2 Vampire + Archer + Ghost | 30.6% | 24.6% |
| S1 Wide 3b `(GR)(VS)(VS)KN(CT)(BR)(AS)/(PA)B(BR)(AB)(CV)VV(GA)` | #8 2 Vampire + 2 Barbarian + Bishop | 27.9% | 25.9% |

Archetypes among the all-rounders that hold up: #21 2 Bard + 2 Bishop + Rook 33%; #9 2 Jester + 2 Rook + Vampire 33%; #27 Queen + Vampire + 2 Ghost 33%
