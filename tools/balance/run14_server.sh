#!/usr/bin/env bash
# Balance run 14: the 24 Oct 2026 prices and the ability rule (Mac, 24 Oct
# 2026). Two arms, normal rules otherwise:
#   A: budget 40 (Plusfish's BUDGET too); Queen 10, Bishop 3.5, Rook 4.5,
#      Werewolf 3.5, Parapet 2.5, Jester 3.5 (the piece files on this branch).
#   B: arm A plus the game's new ability rule (--abilities-need-move=true):
#      a special ability can't be used until the piece has moved at least
#      once; a capture or a shield break counts as a move even when the piece
#      stays put; a Ghost captured before it ever moved can't Haunt.
# Runs on the sims server from ~/ChessPlus with branch experiment/run14
# checked out and Plusfish built there (it must stay named "plusfish": the
# server's idle switch-off only counts programs called exactly that):
#
#   nohup bash tools/balance/run14_server.sh > ~/plusfish-work/run14/run.log 2>&1 &
#
# For each arm (A, then B), into ~/plusfish-work/run14/<arm>/:
# (1) balance report: selfplay 20,000 games, 8,000 nodes, seed 101 (run 1's
#     settings; budgets 34-40), then plusfish values -> report.txt / .html.
# (2) the all-round pool regrown from run 7's pool (meta --wide 64 --game-climb
#     --king-exposed reject --rounds 15 --seed 1), then run 10's colour test on
#     it: round robin of the pool + Standard, 40 games a pairing (20 per
#     colour), 8,000 nodes, --random-plies 4, seeds 3000 + pairing number.
# (3) B only: run 13's colour specialists from B's regrown pool (meta
#     --split-colours --fixed-opponent, the regrown pool + Standard frozen as
#     the opponent), then specialists vs specialists (seeds 4000+) and
#     specialists vs the all-rounders (5000+ / 6000+), 40 games a pairing,
#     colours fixed.
# (4) B only: each regrown-pool army against itself (plusfish analyse,
#     2,000,000 nodes, 8 threads), with the rule and without.
# (5) first-moves: one line per game of every game file of the arm (White's
#     first move, mover, target, recapturable, recaptured) -> firstmoves.jsonl.
# (6) piece-type diversity is read from the pool files by the analyser.
# Writes ~/plusfish-work/run14/DONE at the end. Doesn't switch the server off:
# the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
export PIECES=~/ChessPlus/data/pieces
BASE=~/plusfish-work/run14
START_POOL=engine/plusfish/reports/meta_pool.txt
mkdir -p "$BASE"
rm -f "$BASE/DONE"
cd ~/ChessPlus

# name|army lines from a pool file (Standard as "standard").
pool_armies() {
	grep -v '^#' "$1" | grep -v '^ *$' | awk -F' [|] ' '{ print $2 "|" $1 }' | grep -v '^Standard|'
	echo "Standard|standard"
}

# Run 10's round robin: every pair of armies in list $2, 40 games each (20 per
# colour), seeds 3000 + pairing number. Writes $1/armies.txt, pairings.txt,
# pairs/p<n>.jsonl, logs/.
round_robin() {
	local dir=$1 list=$2 count k=0
	mkdir -p "$dir/pairs" "$dir/logs"
	cp "$list" "$dir/armies.txt"
	count=$(wc -l < "$dir/armies.txt")
	: > "$dir/pairings.txt"
	for ((i = 0; i < count; i++)); do
		for ((j = i + 1; j < count; j++)); do
			echo "$k|$i|$j" >> "$dir/pairings.txt"
			k=$((k + 1))
		done
	done
	export RR_DIR=$dir
	seq 0 $((k - 1)) | xargs -P 16 -I{} bash -c '
		line=$(sed -n "$(({} + 1))p" "$RR_DIR/pairings.txt")
		a=$(sed -n "$(( $(echo "$line" | cut -d"|" -f2) + 1 ))p" "$RR_DIR/armies.txt" | cut -d"|" -f2)
		b=$(sed -n "$(( $(echo "$line" | cut -d"|" -f3) + 1 ))p" "$RR_DIR/armies.txt" | cut -d"|" -f2)
		"$PF" match --white "$a" --black "$b" --games 40 --nodes 8000 --random-plies 4 --pieces "$PIECES" \
			--threads 4 --seed $((3000 + {})) --out "$RR_DIR/pairs/p{}.jsonl" $RULE > "$RR_DIR/logs/p{}.txt" 2>&1'
	echo "$k"
}

# Run 13's grid: every army in list $2 as White against every army in list $3
# as Black, 40 games each, colours fixed, seeds $4 + pairing number.
play_grid() {
	local dir=$1 whites=$2 blacks=$3 seed=$4 k=0 nw nb
	mkdir -p "$dir/pairs" "$dir/logs"
	cp "$whites" "$dir/whites.txt"
	cp "$blacks" "$dir/blacks.txt"
	nw=$(wc -l < "$whites")
	nb=$(wc -l < "$blacks")
	: > "$dir/pairings.txt"
	for ((i = 0; i < nw; i++)); do
		for ((j = 0; j < nb; j++)); do
			echo "$k|$i|$j" >> "$dir/pairings.txt"
			k=$((k + 1))
		done
	done
	export GRID_DIR=$dir GRID_SEED=$seed
	seq 0 $((k - 1)) | xargs -P 16 -I{} bash -c '
		line=$(sed -n "$(({} + 1))p" "$GRID_DIR/pairings.txt")
		w=$(sed -n "$(( $(echo "$line" | cut -d"|" -f2) + 1 ))p" "$GRID_DIR/whites.txt" | cut -d"|" -f2)
		b=$(sed -n "$(( $(echo "$line" | cut -d"|" -f3) + 1 ))p" "$GRID_DIR/blacks.txt" | cut -d"|" -f2)
		"$PF" match --white "$w" --black "$b" --games 40 --nodes 8000 --random-plies 4 --fixed-colours=true \
			--pieces "$PIECES" --threads 4 --seed $((GRID_SEED + {})) --out "$GRID_DIR/pairs/p{}.jsonl" $RULE > "$GRID_DIR/logs/p{}.txt" 2>&1'
	echo "$k"
}

# An army against itself at 2,000,000 nodes, without and with the rule.
mirror() {
	local name army without with
	name=$(echo "$1" | cut -d'|' -f1)
	army=$(echo "$1" | cut -d'|' -f2)
	without=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" 2>/dev/null | grep "Best move")
	with=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" --abilities-need-move=true 2>/dev/null | grep "Best move")
	echo "B pool|$name|$army|$without|$with"
}
export -f mirror

for arm in A B; do
	if [ "$arm" = A ]; then RULE=""; else RULE="--abilities-need-move=true"; fi
	export RULE
	OUT="$BASE/$arm"
	mkdir -p "$OUT"
	log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
	log "start arm $arm; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; rule: ${RULE:-(none)}; queen $(grep '^value' "$PIECES/queen.tres"); budget $($PF army standard --pieces "$PIECES" 2>/dev/null | head -1)"

	log "(1) selfplay 20000 games, 8000 nodes, seed 101"
	"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --pieces "$PIECES" --out "$OUT/selfplay.jsonl" $RULE > "$OUT/selfplay.log" 2>&1
	log "(1) selfplay finished (exit $?); values"
	"$PF" values "$OUT/selfplay.jsonl" --html "$OUT/report.html" --pieces "$PIECES" --threads 64 $RULE > "$OUT/report.txt" 2> "$OUT/values.log"
	log "(1) report written (exit $?)"

	log "(2) meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 from $START_POOL"
	"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --threads 64 --pieces "$PIECES" \
		--pool "$START_POOL" --out "$OUT/meta_pool.txt" $RULE > "$OUT/meta.log" 2>&1
	log "(2) meta finished (exit $?)"
	if [ -f "$OUT/meta_pool.txt" ]; then
		pool_armies "$OUT/meta_pool.txt" > "$OUT/pool_armies.txt"
		log "(2) round robin of the regrown pool + Standard"
		n=$(round_robin "$OUT" "$OUT/pool_armies.txt")
		log "(2) round robin finished ($n pairings)"
	else
		log "(2) no pool written: round robin skipped"
	fi

	if [ "$arm" = B ] && [ -f "$OUT/meta_pool.txt" ]; then
		log "(4) each pool army against itself, 2000000 nodes, 8 threads, 8 at a time, without and with the rule"
		echo "source|name|army|without the rule|with the rule" > "$OUT/mirror.txt"
		tr '\n' '\0' < "$OUT/pool_armies.txt" | xargs -0 -P 8 -I{} bash -c 'mirror "$1"' _ {} >> "$OUT/mirror.txt"
		log "(4) mirrors finished"

		SPLIT="$OUT/split"
		mkdir -p "$SPLIT"
		log "(3) meta --split-colours --fixed-opponent from B's regrown pool"
		"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --threads 64 --split-colours=true --fixed-opponent=true \
			--pieces "$PIECES" --pool "$OUT/meta_pool.txt" --out "$SPLIT/meta_pool.txt" $RULE > "$SPLIT/meta_run.log" 2>&1
		log "(3) split meta finished (exit $?)"
		if [ -f "$SPLIT/meta_pool_white.txt" ] && [ -f "$SPLIT/meta_pool_black.txt" ]; then
			pool_armies "$SPLIT/meta_pool_white.txt" > "$SPLIT/white_armies.txt"
			pool_armies "$SPLIT/meta_pool_black.txt" > "$SPLIT/black_armies.txt"
			cp "$OUT/pool_armies.txt" "$SPLIT/ordinary_armies.txt"
			log "(3) specialists vs specialists"
			n=$(play_grid "$SPLIT/specialists" "$SPLIT/white_armies.txt" "$SPLIT/black_armies.txt" 4000)
			log "(3) specialists vs specialists finished ($n pairings); specialists vs the all-rounders"
			n=$(play_grid "$SPLIT/white_vs_ordinary" "$SPLIT/white_armies.txt" "$SPLIT/ordinary_armies.txt" 5000)
			m=$(play_grid "$SPLIT/ordinary_vs_black" "$SPLIT/ordinary_armies.txt" "$SPLIT/black_armies.txt" 6000)
			log "(3) grids finished ($n and $m pairings)"
		else
			log "(3) no colour pools written: grids skipped"
		fi
	fi

	log "(5) first-moves over every game file of arm $arm"
	files=("$OUT/selfplay.jsonl")
	for f in "$OUT"/pairs/*.jsonl "$OUT"/split/*/pairs/*.jsonl; do
		[ -f "$f" ] && files+=("$f")
	done
	"$PF" first-moves "${files[@]}" --pieces "$PIECES" $RULE > "$OUT/firstmoves.jsonl" 2> "$OUT/firstmoves.log"
	log "(5) first-moves finished (exit $?, $(wc -l < "$OUT/firstmoves.jsonl") games)"
	log "arm $arm done"
done
touch "$BASE/DONE"
