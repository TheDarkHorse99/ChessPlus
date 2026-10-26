#!/usr/bin/env bash
# Balance run 16, the meta by share (Mac, 26 Oct 2026): not one top-10 pool
# but a population of strong armies, so that archetypes can be counted as a
# percentage of the meta; split into all-round armies, White-only armies and
# Black-only armies, with the all-rounders also played against the colour
# specialists. Today's rules and prices (Nicholas's Plusfish of PR #28 with the
# split-colours meta search merged in, branch experiment/meta-share). Runs on
# the sims server from ~/ChessPlus with that branch checked out and Plusfish
# built (named "plusfish", for the idle switch-off):
#
#   nohup bash tools/balance/run16_server.sh > ~/plusfish-work/run16/run.log 2>&1 < /dev/null &
#
# SEEDS independent searches (default 4), two at a time with 32 threads each:
# Phase 1, all-rounders: meta --wide 64 --game-climb --king-exposed reject
#   --rounds 12 --seed <s>, from scratch (Standard plus random climbers, no
#   starting pool), 10 armies each -> all/pool_<s>.txt.
# Phase 2, the fixed opponent set for the specialists: the top 3 of each
#   all-round pool -> opponents.txt (pool format).
# Phase 3, specialists: meta --wide 64 --game-climb --king-exposed reject
#   --rounds 12 --seed <s> --split-colours --fixed-opponent --pool opponents.txt
#   -> split/pool_<s>_white.txt and _black.txt, 10 + 10 each.
# Phase 4, all-rounders against the specialists: every all-round army as White
#   against every Black specialist (seeds 7000+) and every White specialist
#   against every all-rounder as Black (seeds 8000+), 20 games a pairing,
#   colours fixed, 8,000 nodes, --random-plies 4.
# Writes ~/plusfish-work/run16/DONE at the end. Doesn't switch the server off:
# the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
# BASE and PIECES may be set by the caller (run 17 reuses this at other prices).
export PIECES="${PIECES:-$HOME/ChessPlus/data/pieces}"
BASE="${BASE:-$HOME/plusfish-work/run16}"
SEEDS="${SEEDS:-4}"
mkdir -p "$BASE/all" "$BASE/split" "$BASE/logs"
rm -f "$BASE/DONE"
cd ~/ChessPlus
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$BASE/progress.log"; }
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; $SEEDS seeds"

export BASE
log "phase 1: $SEEDS all-round searches from scratch, two at a time"
seq 1 "$SEEDS" | xargs -P 2 -I{} bash -c '
	"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 12 --seed {} --threads 32 --pieces "$PIECES" \
		--out "$BASE/all/pool_{}.txt" > "$BASE/logs/all_{}.log" 2>&1
	echo "all-round seed {} done (exit $?)" >> "$BASE/progress.log"'
log "phase 1 finished"

log "phase 2: the opponent set = the top 3 of each all-round pool"
{
	echo "# Run 16 opponent set: the top 3 armies of each all-round search (seeds 1-$SEEDS), frozen for the specialist searches."
	for s in $(seq 1 "$SEEDS"); do
		grep -v '^#' "$BASE/all/pool_$s.txt" | grep -v '^ *$' | head -3 | sed "s/| Wide /| S${s} Wide /"
	done
} > "$BASE/opponents.txt"
log "phase 2 finished ($(grep -vc '^#' "$BASE/opponents.txt") opponents)"

log "phase 3: $SEEDS specialist searches against the opponent set, two at a time"
seq 1 "$SEEDS" | xargs -P 2 -I{} bash -c '
	"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 12 --seed {} --threads 32 --split-colours=true --fixed-opponent=true \
		--pieces "$PIECES" --pool "$BASE/opponents.txt" --out "$BASE/split/pool_{}.txt" > "$BASE/logs/split_{}.log" 2>&1
	echo "specialist seed {} done (exit $?)" >> "$BASE/progress.log"'
log "phase 3 finished"

# name|army lists, names prefixed with the seed so they stay unique.
pool_list() {   # $1 pool file, $2 prefix
	grep -v '^#' "$1" | grep -v '^ *$' | awk -F' [|] ' -v p="$2" '{ print p $2 "|" $1 }' | grep -v '|standard$' | grep -v 'Standard|'
}
: > "$BASE/all_rounders.txt"; : > "$BASE/white_specialists.txt"; : > "$BASE/black_specialists.txt"
for s in $(seq 1 "$SEEDS"); do
	pool_list "$BASE/all/pool_$s.txt" "S$s " >> "$BASE/all_rounders.txt"
	[ -f "$BASE/split/pool_${s}_white.txt" ] && pool_list "$BASE/split/pool_${s}_white.txt" "S$s " >> "$BASE/white_specialists.txt"
	[ -f "$BASE/split/pool_${s}_black.txt" ] && pool_list "$BASE/split/pool_${s}_black.txt" "S$s " >> "$BASE/black_specialists.txt"
done
log "populations: $(wc -l < "$BASE/all_rounders.txt") all-rounders, $(wc -l < "$BASE/white_specialists.txt") White specialists, $(wc -l < "$BASE/black_specialists.txt") Black specialists"

play_grid() {   # $1 dir, $2 whites list, $3 blacks list, $4 seed base
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
		"$PF" match --white "$w" --black "$b" --games 20 --nodes 8000 --random-plies 4 --fixed-colours=true \
			--pieces "$PIECES" --threads 4 --seed $((GRID_SEED + {})) --out "$GRID_DIR/pairs/p{}.jsonl" > "$GRID_DIR/logs/p{}.txt" 2>&1'
	echo "$k"
}
log "phase 4: all-rounders as White against the Black specialists"
n=$(play_grid "$BASE/allround_vs_black" "$BASE/all_rounders.txt" "$BASE/black_specialists.txt" 7000)
log "phase 4a finished ($n pairings); White specialists against all-rounders as Black"
m=$(play_grid "$BASE/white_vs_allround" "$BASE/white_specialists.txt" "$BASE/all_rounders.txt" 8000)
log "phase 4b finished ($m pairings)"
log "all done"
touch "$BASE/DONE"
