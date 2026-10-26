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

## Results

(pending)
