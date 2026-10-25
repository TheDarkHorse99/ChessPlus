#!/usr/bin/env bash
# Balance run 13: separate White and Black armies, each colour judged against
# the all-round pool frozen (Mac, 24 Oct 2026). Runs 11 and 12 judged each
# colour against the other colour's pool, which was itself being searched, and
# the pools chased each other (run 11) or cycled (run 12). Here meta
# --split-colours --fixed-opponent judges a White army only as White against
# the starting all-round pool (run 7's; run 10's for the rule) plus Standard,
# frozen for the whole run, and a Black army only as Black against the same
# pool: the two searches are independent. 15 rounds each, as run 11.
# Everything else as run 11. Original description:
# Balance run 11: separate White and Black armies (Mac, 24 Oct 2026). Players
# can set a default army for each colour, used when the colour is decided at
# random. What armies does Plusfish come up with when it may pick a different
# army for each colour, and how do they play? Report only, no pass/fail (Mac).
# Two rule sets: the normal rules, and the White-only quiet first move
# (--white-quiet-first=true). Runs on the sims server from ~/ChessPlus with
# branch experiment/colour-armies checked out and Plusfish built there (it
# must stay named "plusfish": the server's idle switch-off only counts that):
#
#   nohup bash tools/balance/run13_server.sh > ~/plusfish-work/run13/run.log 2>&1 &
#
# For each rule set:
# Part 1: grow a White pool and a Black pool side by side (meta --wide 64
#   --game-climb --king-exposed reject --rounds 15 --seed 1 --split-colours;
#   run 2's settings). A White army is judged only as White against the Black
#   pool, and the other way round. Start: normal rules from the official pool
#   (run 7's); the rule from run 10's pool (grown under the rule).
# Part 2: specialists against specialists: every White army against every
#   Black army, 40 games each with the same colours (match --fixed-colours),
#   8,000 nodes, --random-plies 4, seeds 4000 + pairing number.
# Part 3: specialists against all-rounders: the White armies against that rule
#   set's ordinary pool playing Black (seeds 5000+), and the ordinary pool
#   playing White against the Black armies (seeds 6000+), same settings.
# Writes ~/plusfish-work/run13/<normal|rule>/ and ~/plusfish-work/run13/DONE.
# Doesn't switch the server off: the PC stops it through AWS.
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
export PIECES=~/ChessPlus/data/pieces
BASE=~/plusfish-work/run13
mkdir -p "$BASE"
rm -f "$BASE/DONE"
cd ~/ChessPlus

# name|army lines from a pool file (Standard as "standard").
pool_armies() {
	grep -v '^#' "$1" | grep -v '^ *$' | awk -F' [|] ' '{ print $2 "|" $1 }' | grep -v '^Standard|'
	echo "Standard|standard"
}

# Plays every army in list $2 as White against every army in list $3 as
# Black: 40 games each, colours fixed, seeds $4 + pairing number. Writes
# $1/pairings.txt (number|white index|black index) and $1/pairs/p<n>.jsonl.
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

for setting in "normal|engine/plusfish/reports/meta_pool.txt|" "rule|engine/plusfish/reports/meta_pool_white_quiet_first.txt|--white-quiet-first=true"; do
	IFS='|' read -r label start rule <<< "$setting"
	export RULE=$rule
	OUT="$BASE/$label"
	mkdir -p "$OUT"
	log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
	log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; rules: $label ${RULE:-(none)}; start pool $start"

	log "part 1: meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --split-colours --fixed-opponent"
	"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --threads 64 --split-colours=true --fixed-opponent=true \
		--pieces "$PIECES" --pool "$start" --out "$OUT/meta_pool.txt" $RULE > "$OUT/meta_run.log" 2>&1
	log "part 1 finished (exit $?)"
	[ -f "$OUT/meta_pool_white.txt" ] && [ -f "$OUT/meta_pool_black.txt" ] || { log "no pools written"; continue; }

	pool_armies "$OUT/meta_pool_white.txt" > "$OUT/white_armies.txt"
	pool_armies "$OUT/meta_pool_black.txt" > "$OUT/black_armies.txt"
	pool_armies "$start" > "$OUT/ordinary_armies.txt"

	log "part 2: White armies against Black armies"
	n=$(play_grid "$OUT/specialists" "$OUT/white_armies.txt" "$OUT/black_armies.txt" 4000)
	log "part 2 finished ($n pairings)"
	log "part 3: White armies against the ordinary pool, then the ordinary pool against Black armies"
	n=$(play_grid "$OUT/white_vs_ordinary" "$OUT/white_armies.txt" "$OUT/ordinary_armies.txt" 5000)
	m=$(play_grid "$OUT/ordinary_vs_black" "$OUT/ordinary_armies.txt" "$OUT/black_armies.txt" 6000)
	log "part 3 finished ($n and $m pairings)"
	log "all done"
done
touch "$BASE/DONE"
