# Plusfish

A Stockfish-style analysis and balancing engine for **Chess Plus**
(github.com/TheDarkHorse99/ChessPlus).

It reads the game's own piece files (`data/pieces/*.tres`), so it always plays
by the current rules. Change a piece's moves or cost in the game and Plusfish
picks the change up automatically, no code changes needed. It is a separate
Rust program; the game itself is untouched.

What it's for:

* **Evals**: "who's better here, and what's the best move?" for any position or
  army matchup, with the best lines (`analyse`, `eval`, `uci`).
* **Balancing**: thousands of engine-vs-engine games between random armies,
  then statistics on what each piece is actually worth compared with its cost
  (`selfplay`, `values`), plus head-to-head army tests with Elo and error bars
  (`match`).

To re-run the piece values, train the engine or grow the meta pool, follow
the step-by-step recipes in [HOW_TO.md](HOW_TO.md).

## Inside the game: the eval bar

When a game is over, the game screen shows an eval bar beside the board, a
blue arrow for Plusfish's best move, and "best: ..." in the status line, for
the final position and for any earlier position tapped in the move list.
During a game the bar alone shows (always against the bot, and when chosen for
local and online games); best moves are only ever shown afterwards. The game
side is `res://scenes/game/plusfish_link.gd` (`PlusfishLink`) and
`res://scenes/game/eval_bar.gd` (`EvalBar`). `PlusfishLink.supports()` turns
the bar off for games with a special ability newer than Plusfish knows
(`KNOWN_ABILITIES`).

* PC: the game runs `plusfish evalgame` (this folder's `bin/plusfish.exe`, or a
  fresh `target/release` build) on a background thread, sends the game once,
  and gets one reply line per position.
* Web: `web/plusfish.wasm` (this crate built for WebAssembly) is loaded by
  `web/plusfish.js`, which the page includes; the game calls it through
  JavaScriptBridge, one position at a time.
* The request (see `src/api.rs`) carries the piece types as the game has them
  loaded, the exact starting board and the moves played, so Plusfish never has
  to repeat how armies are set up.

After changing the engine, run `bash engine/plusfish/build.sh`. It rebuilds
both, and both outputs are committed so the game works without Rust.

## Build

Install Rust (rustup.rs), then:

```
cargo build --release
```

The program is `target/release/plusfish` (`plusfish.exe` on Windows). It finds
the piece folder by itself if the ChessPlus repo sits next to it or in the
current folder; otherwise pass `--pieces <ChessPlus>/data/pieces` or set
`CHESSPLUS_PIECES`.

## Armies

Wherever an army is asked for you can give:

* `standard`, `random`, or `random:<seed>`
* a saved army file from the game's army builder (a `.tres` file in
  `%APPDATA%\Godot\app_userdata\<game>\armies\` on Windows)
* text: the owner's back row, `/`, then the row in front, files a to h, using
  FEN letters, two-letter symbols in brackets, digits for empty squares. The
  standard set is `RNBQKBNR/PPPPPPPP`; `R(CV)BWKB(CV)R/PPPP1PPP` swaps the
  knights for Cavalry, the queen for a Wizard, and leaves e2 empty.

`plusfish army "<army>"` shows an army's cost and anything that breaks the
army rules.

As in the game, an army played as Black is turned round as a whole (files
mirrored too), so it looks from Black's side as it was built; `standard` keeps
real chess's d-file queen. Saved army files keep the game's
`mirror_for_black` setting.

## Analysis

```
plusfish analyse --white standard --black "R(CV)BWKB(CV)R/PPPPPPPP" --time 10
plusfish analyse --fen "<fen>" --depth 16 --multipv 3
plusfish analyse --white standard --black standard --moves "e4 e5 Nf3" --time 5
plusfish eval --fen "<fen>"          # static evaluation, biggest terms first
```

Scores are in pawns from White's point of view; `#3` means mate in 3.

FENs are the game's own dialect (`core/fen.gd`): two-letter symbols in
brackets `(PD)`, `'` after a piece = broken shield, `+` = a shield gained by
capturing (Vampire), `^` = ability used; a Werewolf that has changed is its
wolf form `(WF)^`. Two optional extra fields that the game's reader ignores:
`lost=Qn(PD)G^G` (lost pieces in the order lost, which matter for Raise Dead
and Haunt; `G^` = a lost Ghost whose Haunt is used) and `promo=QR(CH)` (the promotion
choices; without it, FEN positions promote to Q/R/B/N like the game's FEN
tests). Army games promote like the real game: to any non-king, non-pawn type
on the board at the start.

### UCI-style protocol

`plusfish uci` speaks a UCI-like protocol on stdin/stdout, so a GUI or script
(or later the game itself) can drive it:

```
position army RNBQKBNR/PPPPPPPP R(CV)BWKB(CV)R/PPPPPPPP moves e2-e4
go movetime 2000
...
info depth 10 seldepth 21 multipv 1 score cp -143 nodes 555819 nps 398722 time 1394 pv e7-e6 b1-c3 f8-e7 d1-f3 ...
bestmove e7-e6
```

Also `position fen ...`, `position startpos`, `go depth N / nodes N /
wtime .. btime .. / infinite` + `stop`, `setoption name MultiPV value 3`,
`d` (board, FEN, legal moves) and `eval`. Moves use the game's move text
(`e2-e4`, `e7-e8=Q`, Crack Shot `a1!c3`, Raise Dead `d2!=Q`, Haunt `@e3`,
Song of Slumber `c1~g5`, Full Moon `e4!`); SAN like `Nf3` is accepted too.
A Jester swap is written like any capture.

## Balancing

### Head-to-head

```
plusfish match --white "<army A>" --black "<army B>" --games 400
```

A and B swap colours every game. You get A's score, the Elo difference with a
95% margin, how games ended, and White's overall score. `--out games.jsonl`
saves the games. With `--armies random --params a.txt --params-b b.txt` it
A/B-tests two evaluation files over random army pairs instead.

### Piece values

```
plusfish selfplay --games 20000 --out games.jsonl   # ~1 hour on 24 cores
plusfish values games.jsonl --html report.html
```

`values` fits two logistic regressions to the results:

* **Worth (army)**: each game's result against the difference in each piece
  type between the two starting armies. This is the number that matters for
  army building: what an extra piece of that type is worth at the start,
  counting everything (abilities, one-shot pieces, how often it gets traded).
  Self-play varies each side's budget between 33 and 39 points
  (`--budget-spread`). Without that, every army costs about 39, and a piece's
  strength can't be told apart from how much points are worth in general.
* **Worth (on board)**: results against the material on the board in quiet
  positions during games. Much more precise, but it only sees pieces while
  they're on the board (the Ram's whole point is the capture that removes it).

Both are put on the army-cost scale (scaled so that worth equals cost on
average across pieces), with 95% ranges. A piece is flagged under/overpriced
when it's at least half a point off and outside its range. The numbers come
from engine play, which isn't human play; treat them as strong hints, and
re-run after changing costs.

### Tuning the engine

```
plusfish selfplay --games 20000 --nodes 6000 --out games.jsonl --threads 19
plusfish tune games.jsonl --out params.txt --only mat,mob,shield,ability
plusfish enginematch --engine-a plusfish.exe@params.txt --engine-b plusfish.exe --nodes 6000 --pairs 1000
```

The evaluation is a weighted sum of features: material, mobility, shield and
ability terms for each piece type, plus pawn advancement, passed pawns, king
shelter, king-zone attacks, Raise Dead potential and so on. Where a piece
stands counts too: per piece type, how many squares it would reach from its
square on an empty board (`reach`, a Knight on the rim reaches fewer), which
row it is on (`row0`..`row7`, for pieces that don't promote), and `dead` for a
square it can never leave (a Berserker on the last row; unless tuned, that
cancels 90% of its material). The tuned weights give these only to pieces
whose moves differ forwards and backwards (Berserker, Assassin, Cavalry,
Ghost, Werewolf and wolf, Vampire) and short-range pieces (Knight, Man,
Elephant, Paladin, Catapult, Rogue, Squire, Jester, Necromancer, King):
giving them to every piece was no stronger (ELO_LOG #26). `tune` fits the
weights to self-play results (Texel tuning). The tuned weights in
`params/tuned.txt` are built into the program; `--params none` falls back to
weights derived from army costs, which is also what any new piece type gets
until you re-tune. Re-tune whenever pieces are added or costs change: the
October 2026 re-tune (all 30 pieces) was worth +75 Elo, mostly from valuing
the new pieces. `--only` limits tuning to some features (the per-piece ones
are well determined; a full re-tune made pawn-advance weights jagged and
judged the pool armies worse), `--freeze` keeps some fixed, `--skip N`
ignores each game's first N plies. An engine given as `<exe>@<weights.txt>`
(enginematch, start-check) plays with those weights instead of its own.

**Opening terms.** At the start every piece stands on its first two rows,
where the middlegame's `reach`, row and mobility weights misjudge it: a
Vampire still on its back row in the middlegame usually means a bad game (so
its tuned reach weight is large), but at move 0 it means nothing, and that
weight alone cost every Vampire about 2 pawns in start scores. So each piece
type also has `omat`, `omob`, `oreach`, `orow1` (on its second row) and
`oability` terms, plus a global `otempo`. Each is the matching feature times
the share of pieces (not pawn types or kings) that haven't moved yet, so
they fade as the armies develop. They are tuned on positions from the first
40 plies of `drift` games (below), each labelled with how the game went 16 to
40 plies later:

```
plusfish tune drift.jsonl --drift --only omat,omob,oreach,orow1,oability,otempo --threads 19 --out params.txt
```

`--drift` reads a drift file instead of self-play games (`--plies 40`,
`--window 16,40`, `--k 720` = the logistic scale the later scores are turned
into win chances with, and the tuning uses that same scale; `--blend B` mixes
in the result; `--split train|test` keeps games with `i % 4 != 0` / `== 0`).

### Judging the starting position

```
plusfish start-check --engines old.exe,new.exe --pairs 150 --games 20 --pool pool.txt --truth truth.txt
```

How well each engine's score of the starting position predicts which army
wins: every army pair is played 20 times with each colour to find the truth
(kept in `--truth` and reused), then each engine scores both starts. It
reports the correlation with the real results (and the best possible with
that many games), how often it picks the right side, and White's edge.

```
plusfish drift --games 4000 --nodes 40000 --threads 19 --out drift.jsonl
plusfish drift --starts drift.jsonl --params new.txt --out starts.jsonl
```

`drift` plays random army pairs (both full budget) with the top move every
turn (`--nodes` per move) and writes one JSON line per game: the start's
score at the eval bar's budgets (`--eval-nodes 20000,150000`, a fresh search
each, plus the score after each finished depth), the score at every ply,
the material balance, the moves and the result. The games where the start
score and the later scores disagree most are where the opening judgement is
wrong; `reports/START_EVAL.md` is what 12,000 of them showed. `--starts`
only re-scores the starts of an earlier file (another build or `--params`),
so engines can be compared on the same games; `--features` adds the start's
evaluation terms by name; `--pool <file>` draws half the armies from a pool.

### Growing an army pool from the eval bar (`meta`)

```
plusfish meta --pool old_pool.txt --out meta_pool.txt --max 10 --threads 16
```

A way to find the strongest builds by Plusfish's own judgement, to re-run
whenever the engine improves (better evaluation, new pieces, new costs):

1. Start from a pool (`--pool`, armies that now break the army rules are left
   out; Standard is always added).
2. Odd rounds start from a random legal army, even rounds from a pool member
   (climbing against the others, so it competes to replace itself). Hill-climb it: try one small
   change per thread (swap a piece's type, move one, swap two, add, remove,
   trade), keep the best if it raises the army's mean turn-0 eval-bar score
   against every pool member, and stop after `--patience` batches without a
   gain. Scores average both colours so White's first move cancels, and an
   army that leaves a king attacked before the first move against any member
   is rejected (that rule is temporary).
3. Score the result at the eval bar's budget (`--nodes`, 20,000 as on the web).
   If its piece list differs from every member's by at least `--min-diff`
   pieces (default 3; layout is ignored), it joins; past `--max` armies the
   member with the lowest mean score against the others is dropped. If it's
   close to a member and does better against the rest of the pool, it replaces
   that member; otherwise it's thrown away.
4. Stop after `--stable` rounds without a change (or `--rounds`).

The pool is written after every round (`army | name | cost | score | pieces`,
readable by `enginematch --pool` and `start-check --pool`), with a log beside
it. It finds what *Plusfish thinks* is strong; `start-check --pool` then plays
the pool out to see how far games agree, which is also a good place to look
for evaluation mistakes to fix.

### Searching wide (`meta --wide`)

```
plusfish meta --wide 38 --pool reports/meta_pool.txt --out meta_pool.txt --game-climb --threads 19
```

Plain `meta` follows one climber a round and trusts the eval. `--wide N`
searches more widely and lets games decide (`plusfish meta --help` lists
every setting):

1. N armies climb at once on cheap turn-0 evals (most from random armies,
   `--refine` from pool members), each on its own thread.
2. The finishers are re-scored at the eval bar's budget and the best
   `--shortlist` go on.
3. With `--game-climb`, the best of those is polished with games: a few tweaks
   the eval likes are each played against every member on the same openings,
   and the best is kept if it scores clearly more.
4. Each shortlisted army plays `--games` games against every member. Games,
   not the eval, decide whether it joins, replaces a similar member (if it
   scores at least `--replace-margin` more against the rest) or is thrown away.

`--king-exposed win` (the default with `--wide`) scores a start that leaves
Black's king attacked as an instant White win, as the game does now;
`--king-exposed reject` throws such armies out, as plain `meta` does.
`reports/meta_pool.txt` was grown with `reject` (see `reports/META_POOL.md`).
The pool file shows each member's game score and eval
(`army | name | cost | games (Elo) | eval | pieces`).

### Climbing one army with squares pinned (`climb-fixed`)

```
plusfish climb-fixed --pool reports/meta_pool.txt --keep C@e1 --empty e2 --out fixed_climb.txt
```

Hill-climbs the best army against a pool while some pieces must stay on
given squares (`--keep SYMBOL@square`, builder rows 1-2) and some squares must
stay empty (`--empty`). Climbs start from every pool member (with the pins
forced on) and `--restarts` random armies. Starts are scored by the game's
rules, so an instant win from a king attacked at the start counts; the report
gives each army's score with and without those wins.

### Testing engine changes

`match --params` compares evaluation weights; to compare two *builds* of the
engine, save the old program and play them against each other over UCI:

```
plusfish enginematch --engine-a new.exe --engine-b old.exe --nodes 6000 --pairs 4000 --sprt 0,5
plusfish enginematch --engine-a new.exe --engine-b old.exe --tc 10+0.1 --pairs 400 --concurrency 20
plusfish enginematch --engine-a p.exe --engine-b p.exe --uci-a "Threads=4" --tc 5+0.05 --concurrency 3
```

Random army pairs, each played twice from the same opening with colours
swapped; Elo with a 95% margin worked out from the pairs' results; `--sprt
E0,E1` stops once the new build is shown to be at least E1 or at most E0 Elo
better. `--nodes` (fixed nodes per move: strength per node, as in self-play
and the eval bar), `--tc BASE+INC` (a clock per game) or `--movetime MS`.
Every measured change is in `ELO_LOG.md`.

The search's margins and limits (pruning, reductions, history, singular
extensions, correction history weights) are UCI options with the built-in
values as defaults (`uci` lists them; `enginematch --uci-a "rfp_margin=97;..."`
tries others). `plusfish spsa` tunes them by SPSA: each step plays a game
pair between the values nudged up and down at random (random armies, fixed
nodes) and moves towards the winner; it logs the values as it goes and ends
with a `--uci-a` list to verify with `enginematch`:

```
plusfish spsa --pairs 12000 --concurrency 16 --r-end 0.01 --log spsa_log.txt --skip rfp_depth,lmp_depth
```

`--only` / `--skip` choose the constants, `--start <log or "a=1;b=2">`
carries on from earlier values.

`plusfish bench` searches fixed positions to a fixed depth: the node total is
a fingerprint (a pure speed-up mustn't change it) and nodes/s the speed.
`plusfish speed` times evaluation, move generation and making moves;
`plusfish see-check` compares the static exchange evaluation with a brute
force search.

## How we know the rules are right

The engine is a line-by-line port of `core/move_generator.gd` and
`core/game_state.gd`, checked two ways:

* `plusfish perft-suite`: the standard perft counts (start position,
  Kiwipete, CPW positions 3 to 5), the same ones the game's tests use, one
  depth deeper.
* `trace-games` / `trace-check`: the game's own engine (running headless in
  Godot, `verify/plusfish_trace.gd`) plays hundreds of random custom-army
  games biased towards captures, abilities, promotions and castling, and logs
  every position's FEN, full legal move list, check status and outcome.
  Plusfish replays them and must match exactly. 630 games, 142,000 positions,
  zero mismatches, covering Crack Shot, Raise Dead, shields, Rams, cannons,
  en passant, castling, promotions and all five game endings. After the
  third batch of pieces (Oct 2026), another 850 games (169,000 positions),
  700 of them leaning towards the 11 new pieces (`--favor`): 2 mismatches,
  both the two-Jester case below. `trace-check` lists what a trace
  covered: Haunts, Songs of Slumber, Full Moons, Jester swaps, Vampire
  shields gained and broken, Parapets stopping leaps and Cannon screens,
  Squires protecting attacked pieces, and kings exposed before the first move.
After Mac's Parapet change (Oct 2026: a Parapet only stops the opponent's
jumps and Cannon screens, never its own side's), 120 more games leaning
towards Parapets and leaping pieces (28,627 positions, 10,467 with a
Parapet, 5,100 where one stopped a leap or screen): no Parapet mismatches,
one two-Jester case.
After Mac's Squire and Berserker changes (Oct 2026: a Squire protects Knights
anywhere in its move pattern, even with pieces in between; the Berserker's
L-moves go 2 straight then 1 sideways), 350 more games leaning towards
Squires, Knights and Berserkers (78,784 positions, 11,258 with a Berserker,
229 where a Squire protected an attacked Knight, 68 of them through a piece
in its way): two mismatches, both the two-Jester case. The old engine
failed on the Squire positions.
After Mac's Jester change (Oct 2026: if more than one Jester could take the
hit, the attacker chooses which), 600 more games with two Jesters an army
(143,303 positions, 353 offering a choice of Jesters, 95 such choices
played): zero mismatches (the engine before failed 110 games). Perft from six
two-Jester positions (with Archers, Squires, Rams, Bards and more) matches the
game's own count to depth 3, two of them to depth 4.

```
plusfish trace-games --count 40 --seed 1 > games.txt
plusfish trace-games --count 40 --seed 1 --favor parapet,jester,ghost > games.txt
godot --headless --path <ChessPlus> -s res://tools/plusfish_trace.gd -- games.txt trace.jsonl
plusfish trace-check games.txt trace.jsonl
```

(Copy `verify/plusfish_trace.gd` into the game's `tools/` folder first.)

If more than one Jester could take the same hit, the attacker chooses which
(Mac, Oct 2026): the capture is one move per Jester, and its text names the
Jester's square (`c7xe5/d4`, Crack Shot `a1!c3/d4`, SAN `Bxe5/d4`). A text
without it, from before the rule, finds the Jester on the lower square
(the game finds the first in its piece list, which may differ).

## Engine details

Mailbox board up to 128 squares, precomputed rays for every piece type, team
and square, reverse attack tables (as in the game), copy-make, Zobrist keys
that follow the game's repetition rule exactly. Search: iterative deepening,
aspiration windows, principal variation search, a lock-free transposition
table (also used in quiescence), null-move pruning, reverse futility and
futility pruning, late move reductions and pruning, an "improving" signal,
check and singular extensions (with multi-cut), killer, counter-move and
history ordering (with penalties), capture history and continuation history
(by piece type, so they suit any army), correction history (the search learns
how far the evaluation is off for positions with the same material, pawns,
pieces or last move, and corrects it), the hash move tried before the other
moves are generated, quiet moves pruned before they're made when they surely
can't matter, a static exchange evaluation that works for every piece type
(ordering, quiescence and pruning), MultiPV, and a quiescence search over
captures, shield breaks, Crack Shots and promotions. Lazy SMP on several
threads (`analyse --threads N`, UCI `setoption name Threads`; not in the
WebAssembly build, which has no threads). Clock games use a soft time target
that stretches while the best move keeps changing. About 5M perft
nodes/s and 0.5M search nodes/s per core; the game's GDScript bot does about
4,500.

Limits: boards up to 128 squares (16x8, 11x11, ...) and 64 piece types
(forms such as the Werewolf's wolf count; the game had 31 in Oct 2026).
