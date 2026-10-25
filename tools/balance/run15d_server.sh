#!/usr/bin/env bash
# Balance run 15D (Mac, 25 Oct 2026): arm C (run 15: budget 40, the 24 Oct
# prices, the ability rule, the Grunt, Abatis and Vassal) with the White-only
# quiet first move on as well (--white-quiet-first=true: White may not
# capture, break a shield or use an ability on its first move unless in
# check; Black's first move is unrestricted). Runs after run 15 on the same
# server and branch (experiment/run15), from ~/ChessPlus:
#
#   nohup bash tools/balance/run15d_server.sh > ~/plusfish-work/run15/run_d.log 2>&1 < /dev/null &
#
# Into ~/plusfish-work/run15/D/, the same parts as arm C:
# (1) balance report: selfplay 20,000 games, 8,000 nodes, seed 101.
# (2) the all-round pool regrown UNDER THE RULE from C's regrown pool, then run
#     10's colour test on it (round robin, 40 games a pairing, seeds 3000+).
# (3) run 13's colour specialists from D's pool (meta --split-colours
#     --fixed-opponent) and the three grids.
# (4) each D pool army against itself (analyse, 2,000,000 nodes): with the
#     ability rule only, and with both rules.
# (5) first-moves over every game file -> firstmoves.jsonl.
# Then (6) 5,000 random-army games at 32,000 nodes (seed 303) for C and for
#     D: C/selfplay_32k.jsonl, D/selfplay_32k.jsonl, each with a values report.
# Writes ~/plusfish-work/run15/DONE_D at the end. Doesn't switch the server
# off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
export PIECES=~/ChessPlus/data/pieces
BASE=~/plusfish-work/run15
START_POOL="${START_POOL:-$BASE/C/meta_pool.txt}"
mkdir -p "$BASE"
rm -f "$BASE/DONE_D"
cd ~/ChessPlus

pool_armies() {
	grep -v '^#' "$1" | grep -v '^ *$' | awk -F' [|] ' '{ print $2 "|" $1 }' | grep -v '^Standard|'
	echo "Standard|standard"
}

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

# An army against itself at 2,000,000 nodes: the ability rule only, and both rules.
mirror() {
	local name army without with
	name=$(echo "$1" | cut -d'|' -f1)
	army=$(echo "$1" | cut -d'|' -f2)
	without=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" --abilities-need-move=true 2>/dev/null | grep "Best move")
	with=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" --abilities-need-move=true --white-quiet-first=true 2>/dev/null | grep "Best move")
	echo "D pool|$name|$army|$without|$with"
}
export -f mirror

export RULE="--abilities-need-move=true --white-quiet-first=true"
OUT="$BASE/D"
mkdir -p "$OUT"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
log "start arm D; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; rules: $RULE; start pool $START_POOL"

log "(1) selfplay 20000 games, 8000 nodes, seed 101"
"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --pieces "$PIECES" --out "$OUT/selfplay.jsonl" $RULE > "$OUT/selfplay.log" 2>&1
log "(1) selfplay finished (exit $?); values"
"$PF" values "$OUT/selfplay.jsonl" --html "$OUT/report.html" --pieces "$PIECES" --threads 64 $RULE > "$OUT/report.txt" 2> "$OUT/values.log"
log "(1) report written (exit $?)"

log "(2) meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 from $START_POOL, under the rule"
"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --threads 64 --pieces "$PIECES" \
	--pool "$START_POOL" --out "$OUT/meta_pool.txt" $RULE > "$OUT/meta.log" 2>&1
log "(2) meta finished (exit $?)"
if [ -f "$OUT/meta_pool.txt" ]; then
	pool_armies "$OUT/meta_pool.txt" > "$OUT/pool_armies.txt"
	log "(2) round robin of the regrown pool + Standard"
	n=$(round_robin "$OUT" "$OUT/pool_armies.txt")
	log "(2) round robin finished ($n pairings)"

	log "(4) each pool army against itself, 2000000 nodes: the ability rule only, and both rules"
	echo "source|name|army|ability rule only|both rules" > "$OUT/mirror.txt"
	tr '\n' '\0' < "$OUT/pool_armies.txt" | xargs -0 -P 8 -I{} bash -c 'mirror "$1"' _ {} >> "$OUT/mirror.txt"
	log "(4) mirrors finished"

	SPLIT="$OUT/split"
	mkdir -p "$SPLIT"
	log "(3) meta --split-colours --fixed-opponent from D's regrown pool"
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
else
	log "(2) no pool written: the rest skipped"
fi

log "(5) first-moves over every game file of arm D"
files=("$OUT/selfplay.jsonl")
for f in "$OUT"/pairs/*.jsonl "$OUT"/split/*/pairs/*.jsonl; do
	[ -f "$f" ] && files+=("$f")
done
"$PF" first-moves "${files[@]}" --pieces "$PIECES" $RULE > "$OUT/firstmoves.jsonl" 2> "$OUT/firstmoves.log"
log "(5) first-moves finished (exit $?, $(wc -l < "$OUT/firstmoves.jsonl") games)"

log "(6) 5000 random-army games at 32000 nodes, seed 303, for C (ability rule) and D (both rules)"
"$PF" selfplay --games 5000 --nodes 32000 --seed 303 --threads 64 --pieces "$PIECES" --out "$BASE/C/selfplay_32k.jsonl" --abilities-need-move=true > "$BASE/C/selfplay_32k.log" 2>&1
"$PF" values "$BASE/C/selfplay_32k.jsonl" --html "$BASE/C/report_32k.html" --pieces "$PIECES" --threads 64 --abilities-need-move=true > "$BASE/C/report_32k.txt" 2> "$BASE/C/values_32k.log"
log "(6) C's 32k games done (exit $?)"
"$PF" selfplay --games 5000 --nodes 32000 --seed 303 --threads 64 --pieces "$PIECES" --out "$OUT/selfplay_32k.jsonl" $RULE > "$OUT/selfplay_32k.log" 2>&1
"$PF" values "$OUT/selfplay_32k.jsonl" --html "$OUT/report_32k.html" --pieces "$PIECES" --threads 64 $RULE > "$OUT/report_32k.txt" 2> "$OUT/values_32k.log"
log "(6) D's 32k games done (exit $?)"
log "arm D done"
touch "$BASE/DONE_D"
