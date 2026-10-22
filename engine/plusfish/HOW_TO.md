# Plusfish how-to: piece values, training and the meta pool

Step-by-step recipes for the jobs you'll want to re-run after changing the
game: what each piece is worth, training Plusfish's judgement (its piece and
positional values), and growing the meta pool of strongest armies. The
[README](README.md) lists every command and option; this file says which ones
to run, in what order, and how to read what comes out.

| Job | When | Needs Rust? | Time (19 cores) |
|---|---|---|---|
| [1. Piece values](#1-piece-values-the-balance-report) | after changing costs, moves or rules, or adding a piece | no | ~40 min |
| [2. Train Plusfish's judgement](#2-train-plusfishs-judgement-tuning) | after adding a piece or changing its rules | only to put the result in the game | ~1 min + a 5 min test match (+75 min for the opening terms) |
| [3. The meta pool](#3-the-meta-pool) | after cost or rule changes, new pieces, or a stronger engine | no | 2-4 hours |
| [4. Quick questions](#4-quick-questions) | any time | no | seconds to minutes |
| [5. After changing a piece's rules](#5-after-changing-a-pieces-rules) | before 1-3 | sometimes | minutes |

If you're doing several, do them in this order: **5, then 2, then 1, then 3**.
Jobs 1 and 3 use Plusfish's judgement to play their games, so they come out
better once it has been trained on the current rules.

You can hand any of these to Claude: "Do job 1 from
engine/plusfish/HOW_TO.md and show me the report" is enough. See
[Asking Claude to run these](#asking-claude-to-run-these).

## Before you start

* Run everything from **Git Bash** in the ChessPlus folder. Plusfish then
  finds the piece files (`data/pieces/`) by itself, so a cost or move you
  change in a `.tres` file is picked up straight away, with nothing to rebuild.
* Every command below starts with the committed program:

  ```
  PF=engine/plusfish/bin/plusfish.exe
  ```

  (Type that once per Git Bash window.) `$PF --help` lists every command.
* Keep the big output files **outside the repo**, so they never end up in a
  commit (16,000 games is about 14 MB):

  ```
  mkdir -p ../plusfish-work
  ```

* **Keep the PC usable.** These jobs use every core unless told otherwise.
  Give them `--threads N` (or `--concurrency N` for `enginematch`), a few
  less than your core count (19 on a 24-core PC). For a job that runs for
  hours, also start it at low priority, so everything else stays responsive:

  ```
  cmd //c start "" //b //wait //belownormal $PF selfplay ...
  ```

* **Rust** is only needed to put new weights into the game (end of job 2) or
  to change Plusfish's own code. Everything else runs on the committed
  `plusfish.exe`. Installing Rust means downloading `rustup-init.exe` from
  https://rustup.rs (free, MIT/Apache-2.0 licence). On Windows it also needs
  Microsoft's "Visual Studio Build Tools" (the C++ part, a few GB), and the
  web version needs `rustup target add wasm32-unknown-unknown` once. If you'd
  rather not install it, send the weights file to Nicholas and he'll build it.

## 1. Piece values (the balance report)

What every piece is actually worth compared with its cost, measured from
thousands of engine-vs-engine games between random armies.

**1. Play the games** (about 40 minutes on 19 cores, ~7 games a second):

```
$PF selfplay --games 16000 --threads 19 --out ../plusfish-work/games.jsonl
```

It prints progress and how long is left. Each side's army is random, with a
budget between 33 and 39 points (this spread is what lets it tell a piece's
strength apart from "having more points"; leave it on).

**2. Make the report** (about a minute):

```
$PF values ../plusfish-work/games.jsonl --html ../plusfish-work/balance_report.html > ../plusfish-work/balance_report.txt
```

Open `balance_report.html` in a browser (or read the `.txt`). The current
one is in `reports/balance_report.txt` / `.html` to compare with.

**3. Read it.** One row per piece:

| Column | Meaning |
|---|---|
| cost | the cost in the piece's `.tres` file |
| games | games where either army had this piece |
| **worth (army)** | **the number that matters**: what one extra piece of this type at the start is worth, from game results, on the same scale as costs (the average piece's worth = its cost), with a 95% range. It counts everything: abilities, one-shot pieces, how often it gets traded |
| Elo/piece | the same thing in Elo (rating points): how much one extra piece raises the side's strength |
| worth (on board) | what it's worth while standing on the board mid-game: more precise, but blind to what happens when it leaves (a Ram's whole point is the capture that removes it, a Ghost's is coming back) |
| verdict | UNDERPRICED / OVERPRICED when worth (army) is at least half a point off the cost and the cost is outside its range; "slightly" when the cost is outside the range but less than half a point off; "about right" when the cost is inside the range |

How much to trust it:

* **The ± range** is how sure the number is. 16,000 games gives about ±0.2
  for a 3-point piece and ±0.4 for a Queen. Four times the games halves the
  range: 4,000 games (10 minutes) is fine for a quick look (about ±0.4), but
  not for small differences.
* **It's engine play, not human play.** Plusfish is good at tactics and never
  forgets an ability, so tricky pieces may be worth less to people. Treat it
  as a strong hint.
* **Pieces depend on each other.** The Squire is worth most with Knights to
  protect; random armies don't always have them. For a piece like that, also
  try a head-to-head match (job 4).
* **Changing one cost moves the others a little**, because the scale is the
  average. Change a few costs at a time, then re-run.

To update the copy in the repo, copy the two report files over
`engine/plusfish/reports/balance_report.txt` and `.html` and commit them
(not the games file).

Options worth knowing: `--nodes N` (how hard each move is thought about;
default 8,000; more is stronger but slower), `--seed N` (a different set of
random armies), `--params <file>` (play with other weights, e.g. fresh ones
from job 2 before they're built in).

## 2. Train Plusfish's judgement (tuning)

Plusfish judges a position with a list of **weights**: for each piece type,
what it's worth (separately for the middlegame and the endgame), how much its
mobility counts, its shield, its unused ability, and **where it stands**: how
many squares it reaches from its square (a Knight on the rim reaches fewer),
which row it is on, and whether it is stuck on a square it can never leave (a
Berserker on the last row). Plus general things: pawn advances, passed pawns,
king safety, and so on.

These weights are *not* the piece costs. They're learned from self-play games
("Texel tuning": the weights are fitted so the evaluation predicts which side
went on to win). They live in `params/tuned.txt`, which is built into the
program. A new piece type starts with weights guessed from its cost until
it's tuned, and a piece whose rules changed keeps weights learned under the
old rules. Either way Plusfish misjudges it until you re-train.

**1. Games.** Use the games from job 1 (the same file works for both).

**2. Tune** (under a minute). Two recipes:

*Piece weights only* (worth, mobility, shield, ability; this is the usual
one, and enough after a cost change or a new piece):

```
$PF tune ../plusfish-work/games.jsonl --out ../plusfish-work/params.txt --only mat,mob,shield,ability --threads 19
```

*Piece weights plus where pieces stand* (after adding a piece that only moves
one way or only a short distance, or changing one; this is how the current
weights were made). Copy all of it into Git Bash:

```
POS=mat,mob,shield,ability
for p in berserker assassin cavalry ghost werewolf werewolf_wolf vampire knight man elephant paladin catapult rogue squire jester necromancer king; do
  POS="$POS,reach:$p,dead:$p"
  for r in 0 1 2 3 4 5 6 7; do POS="$POS,row$r:$p"; done
done
$PF tune ../plusfish-work/games.jsonl --out ../plusfish-work/params.txt --only "$POS" --threads 19
```

The list is the pieces whose moves differ forwards and backwards, and the
short-range ones; add a new piece's id (its `.tres` file name) if it's like
them. Giving "where it stands" weights to every piece wasn't any stronger
(ELO_LOG #26). Don't tune everything at once (no `--only`): that was tried and
made the pawn weights jagged (ELO_LOG #25).

*Opening terms* (after either recipe, whenever you've re-tuned the piece
weights or added a piece; about 75 minutes). How each piece is judged at the
very start, while the armies are still on their first two rows. These
weights learn it from what happens 16 to 40 plies later in games Plusfish
plays against itself (README, "Opening terms"; `reports/START_EVAL.md`):

```
$PF drift --games 4000 --nodes 40000 --threads 19 --params ../plusfish-work/params.txt --pool engine/plusfish/reports/meta_pool.txt --out ../plusfish-work/drift.jsonl
$PF tune ../plusfish-work/drift.jsonl --drift --params ../plusfish-work/params.txt --only omat,omob,oreach,orow1,oability,otempo --threads 19 --out ../plusfish-work/params_open.txt
```

`--pool` makes about half the armies meta pool ones, so the opening terms
also learn from the kind of armies people build. `params_open.txt` is then
the whole set (the piece weights plus the opening ones): use it in place of
`params.txt` in steps 3 and 4. More games help: the built-in weights were
fitted on 9,000 (three runs like this one).

`params.txt` is a plain text file, one weight per line:
`mat:knight 358.9 175.5` means Plusfish counts a Knight as 359 in the
middlegame and 176 in the endgame, where a Pawn is about 80. These are
Plusfish's own units, learned from games; they don't have to match the costs.

**3. Check it's actually stronger** (about 5 minutes). The new weights play
the old ones over 1,000 pairs of games:

```
$PF enginematch --engine-a "$PF@../plusfish-work/params.txt" --engine-b $PF --nodes 6000 --pairs 1000 --concurrency 19
```

`exe@weights.txt` means "this program, with these weights". At the end it
prints `A is +25.3 ±11.0 Elo vs B (95%)` or similar: the new weights' gain. Keep the new weights
if the whole range is above zero (here 14 to 36). If the range includes zero,
it isn't clearly better: play more pairs, or don't use it.

**4. Put it in the game** (needs Rust):

```
cp ../plusfish-work/params.txt engine/plusfish/params/tuned.txt
bash engine/plusfish/build.sh
```

`build.sh` rebuilds `bin/plusfish.exe` (PC) and `web/plusfish.wasm` (web).
Run the game's tests, then commit `params/tuned.txt` and both built files
together, and add a line to `ELO_LOG.md` (what was tuned, on which games, the
match result). Without Rust, send `params.txt` to Nicholas.

## 3. The meta pool

The pool is the ten armies that hold up best against each other in games,
by Plusfish: `reports/meta_pool.txt` (the armies) and `reports/META_POOL.md`
(how they were found, and what they say about the pieces). It's how to find
out what strong players will build, and which pieces every strong army uses.
Re-grow it after changing costs or rules, adding pieces, or training (job 2).

**1. Grow it** (about 12 minutes a round; 10 rounds is about 2 hours). It
starts from the current pool and keeps improving it:

```
$PF meta --wide 38 --pool engine/plusfish/reports/meta_pool.txt --out ../plusfish-work/meta_pool.txt --game-climb --king-exposed reject --rounds 10 --threads 19 --seed 1
```

Each round, 38 armies are improved one small change at a time (swap, move,
add or remove a piece) using the eval bar's judgement, the best three play
40 games against every member, and games decide whether one joins, replaces
a similar member, or is thrown away. Armies that break the army rules under
the current costs are dropped from the starting pool, so after a cost change
the pool refills itself.

* The pool file is written after **every round**, so you can stop at any
  time and lose at most one round. To carry on later, start again with
  `--pool ../plusfish-work/meta_pool.txt` and a new `--seed`.
* `--king-exposed reject` throws out armies that leave the other king
  attacked before the first move (the game's temporary "King exposed" rule
  would make those instant wins; we don't want the pool built on that).
* **It won't settle on one answer.** Last time, 16 of 17 rounds changed the
  pool: the strongest armies beat each other in circles. So stop after a
  fixed number of rounds rather than waiting for it to finish.

**2. Read it.** Each line of `meta_pool.txt` is
`army | name | cost | games (Elo) | eval | pieces`:

* **games**: its average score in games against the other members (50% =
  average), with the same in Elo. This decides who stays.
* **eval**: how much better than the others the eval bar thinks it is at the
  start, in hundredths of a pawn.
* **army**: the layout, back row / front row, files a to h (two-letter
  symbols in brackets, digits for empty squares). `$PF army "<army>"` lists
  its pieces and cost.

Pieces that appear in every army are the ones to look at for being too
cheap; pieces that never appear may be too expensive (or just not suited to
how the engine plays).

**3. Put it in the repo:** copy the file over
`engine/plusfish/reports/meta_pool.txt`, and add a short section to
`reports/META_POOL.md` (what changed, the command, what the pool says).

Variations:

* **"What's the best army with a Cannon on e1?"**:
  `$PF climb-fixed --pool engine/plusfish/reports/meta_pool.txt --keep C@e1 --empty e2 --out ../plusfish-work/fixed.txt --threads 19`
  (`--keep SYMBOL@square` on the builder's rows 1-2, `--empty` squares).
* **"How well does the eval bar's opinion of the start predict the
  winner?"**: `$PF start-check --help`.

## 4. Quick questions

```
$PF army "R(SQ)BQKB(SQ)R/PPPPPPPP"
```

The army's cost and anything that breaks the army rules.

```
$PF match --white "RNBQKBNR/PPPPPPPP" --black "R(SQ)BQKBNR/PPPPPPPP" --games 400 --threads 19
```

Two armies head-to-head (they swap colours every game): A's score, the Elo
difference with a 95% range, and how games ended. Good for "is this piece
worth more in this army?" or "is a Squire better than a Bishop next to two
Knights?". 400 games takes a few minutes; the ± range tells you if that was
enough.

```
$PF analyse --white standard --black "R(CV)BWKB(CV)R/PPPPPPPP" --time 10
```

Who's better at the start of a matchup, and the best lines.

To see what one cost change does to the values: change the cost in the
piece's `.tres` file, then job 1 with `--games 4000` for a first look (10
minutes), and the full 16,000 before deciding.

## 5. After changing a piece's rules

Plusfish reads the piece files, so it depends on what you changed:

* **Only how it moves** (directions, how far, paths, leaps, first-move
  steps, move-only / capture-only): nothing to change in Plusfish. Check it
  agrees with the game by counting moves from a position with the piece
  (perft): `$PF perft --fen "<fen>" --depth 3` should give the same number as
  the game's own perft for that position.
* **A special rule or ability** (anything in `core/` that isn't in the move
  data, like the Squire's protection or the Jester's swap): Plusfish has its
  own copy of the rules, so its code needs changing (Rust), then checking
  against the game over hundreds of traced games (README, "How we know the
  rules are right"). Until then `PlusfishLink.supports()` should turn
  Plusfish off for games with that piece, or it will show wrong evaluations.
  Ask Nicholas, or Claude if Rust is installed.

Then train (job 2) and re-value (job 1): the piece's old weights were learned
under the old rules.

## Asking Claude to run these

Claude can do every job here: "Do job 1 from engine/plusfish/HOW_TO.md with
16,000 games and show me the report", "Grow the meta pool (job 3) for 10
rounds". Worth telling it:

* how many cores to leave free ("use at most 19 threads, at low priority").
* For the meta pool: Claude's background commands are stopped after 2 hours,
  so it should start runs that long detached (`cmd //c start "" //b
  //belownormal ...`, without `//wait`) and check the output file now and
  then.
* Installing Rust is a download, so Claude will ask you first.

## Files

| File | What it is |
|---|---|
| `bin/plusfish.exe` | the program (the game runs it for the eval bar; you run it for these jobs). Rebuilt by `build.sh` |
| `params/tuned.txt` | Plusfish's trained weights, built into the program (job 2) |
| `reports/balance_report.txt` / `.html` | the latest piece values (job 1) |
| `reports/meta_pool.txt` / `META_POOL.md` | the meta pool and how it was found (job 3) |
| `reports/FINDINGS.md` | earlier findings (the king-capture bug, first balance rounds) |
| `ELO_LOG.md` | every engine change that was measured, and by how much it helped |
| `README.md` | every command and how the engine works |
