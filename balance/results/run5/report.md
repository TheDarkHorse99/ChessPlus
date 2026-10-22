# Balance run 5: the front-row rule (report)

Made by `tools/balance/run5_analyse.py`. "Run 2" = random armies without the rule; "run 5" = random armies that follow it, same seed and settings (20,000 self-play games, 8,000 nodes per move, 4 random opening plies). Points = percentage points.

## Random-army games

| | Run 2 (no rule) | Run 5 (front-row rule) |
|---|---|---|
| Games | 20000 | 20000 |
| White's score (95%) | 56.1% (55.5%-56.7%) | 52.0% (51.4%-52.6%) |
| Draws | 22.7% | 22.0% |
| White won both games of a swapped pair (chess benchmark 23%) | 12.6% (12.0%-13.3%), 10000 pairs | 10.1% (9.5%-10.7%), 10000 pairs |
| Games where White's first move captures or uses an ability | 23.5% | 2.3% |
| Mean game length (plies) | 128 | 135 |

How many of Plusfish's random armies followed the rule: 40000 of 165970 random armies passed (24.1%).

## Each army against itself (Plusfish at 2,000,000 nodes, 8 threads)

White's first-move advantage in pawns. Chess: +0.29 (top engines +0.20 to +0.35). The first 20 different armies from each set of games.

| | Armies | Median | Mean | Within +0.35 | Over +1.00 | Highest |
|---|---|---|---|---|---|---|
| Front-row rule | 20 | +0.26 | +0.27 | 17 | 0 | +0.79 |
| No rule (run 2) | 18 | +0.32 | +1.75 | 9 | 6 | mate |

(Mean with mates counted as +9.)

| Set | Army | White's advantage | Plusfish's first move |
|---|---|---|---|
| rule | `(PR)(AS)(GA)(PR)KQ(NC)E/5P2` | +0.60 | PRad4+ |
| rule | `J(SQ)(CT)KBMMB/PPPPV1PE` | +0.26 | g4 |
| rule | `(GA)AGKV(RM)(NC)(RM)/(CH)E(BR)E(AS)P(AS)P` | +0.25 | CHa6 |
| rule | `(PR)(RM)VKE(BD)(CT)J/1P1(GA)P1(AS)1` | +0.32 | b3 |
| rule | `Q(NC)(NC)KVENJ/(AS)PPPPPPP` | +0.34 | b3 |
| rule | `(GA)(CT)NKJM(BD)(CT)/P(BR)PPPPPP` | +0.18 | g3 |
| rule | `(PA)BQ(CV)KJ(CV)(CT)/PPP1P(AS)1(PD)` | +0.09 | Qe3 |
| rule | `(CH)(CT)(PR)(CT)K(RO)NB/(AS)PNPPPPP` | +0.22 | g3 |
| rule | `(CH)B(SQ)K1(NC)(PD)Q/PPPPPPPP` | +0.15 | c4 |
| rule | `(CH)(GA)(RO)KQEEV/P1PPPPPP` | +0.33 | g3 |
| rule | `(CH)(WW)AQK(SQ)(GA)M/(AS)PEE1P1P` | +0.28 | Eb4+ |
| rule | `RJ(CT)(CT)KE(PD)Q/PPPPPPPP` | +0.22 | g3 |
| rule | `VE(BD)KM(BD)(PR)E/P(BR)PPPPPP` | +0.37 | f4 |
| rule | `RVMJKM(CV)V/P(AS)(AS)PP(BR)P1` | +0.11 | AScc3 |
| rule | `(PA)(GA)V(PR)K(BR)N(WW)/PPPPPPPP` | +0.29 | d4 |
| rule | `(CT)(RO)EK(BD)EN(NC)/(BD)PPPPPV1` | +0.08 | Vf3 |
| rule | `V1(PR)BK(PD)(CT)(CV)/PPPPPPPP` | +0.33 | b4 |
| no rule | `(PA)(PR)(PD)KJ(WW)C(PA)/1B3L1P` | +10.98 | Cxg8+ |
| rule | `(PA)(PD)Q(RO)K(NC)NV/2(BR)(BR)1PP1` | +0.79 | Qa3 |
| rule | `(GA)(CT)(WW)GKN(PR)(PR)/P(AS)4P1` | +0.07 | PRh4+ |
| no rule | `(CH)(AS)MKJN(WW)A/PPPPPLPP` | +0.39 | g4 |
| no rule | `(AS)(PR)Q(AS)K(PD)N(BD)/PPP2LPP` | +0.17 | Qe3 |
| rule | `(CH)(AS)(CT)KB(NC)(SQ)R/PP1(BR)PJ(BR)(NC)` | +0.21 | BRd3 |
| no rule | `(PA)(RM)(CT)(PR)KM(RO)(SQ)/PP(AS)1PLPP` | +0.09 | CTd2 |
| no rule | `Q(PR)(PR)K(AS)E(NC)(GA)/P1E5` | +3.32 | PRb5+ |
| no rule | `(PA)(NC)V(NC)KBWB/2(PD)P1PL1` | +3.24 | Lxg8=PD |
| no rule | `(CH)Q(RM)VKEB(PA)/N2(CH)(AS)2P` | #3 | Bb6+ |
| no rule | `EC(CV)KV(NC)(CV)J/(AS)PPPPEBL` | +2.11 | Bxb7 |
| no rule | `(PA)(RM)(NC)(WW)K(PR)(GA)M/2EPPPPE` | +0.12 | e3 |
| no rule | `(CT)AGK(NC)(PR)WC/1(AS)P4(PD)` | +2.02 | Cxh8 |
| no rule | `(PD)C(PD)KW(CV)(RO)C/P(PA)P(SQ)PP1P` | +0.15 | Cxb8 |
| no rule | `(GA)AGKV(RM)(NC)(RM)/(CH)E(BR)E(AS)P(AS)P` | +0.16 | f4 |
| no rule | `(CH)(NC)NK(PR)(SQ)AC/(PD)3P(AS)2` | +0.41 | Cxh8 |
| no rule | `(CH)AC(NC)KE(AS)(PA)/P(PD)PP(CT)PP(BR)` | +0.08 | c4 |
| no rule | `(PA)(PD)VK(AS)(CV)WN/1(BR)1(CV)(AS)(RM)2` | +0.58 | Wg4 |
| no rule | `(CH)(RO)(RO)KE(SQ)C(PD)/PNP(RM)PPPL` | +0.19 | g4 |
| no rule | `RWVK(CT)JE(PA)/1(GA)2E1(GA)(AS)` | +0.22 | Ra3 |
| no rule | `RC(GA)KB(CT)(NC)(PA)/P(PD)PPPP(AS)J` | +0.25 | Cxb7 |
