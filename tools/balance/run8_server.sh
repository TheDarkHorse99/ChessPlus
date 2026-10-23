#!/usr/bin/env bash
# Balance run 8: cheaper pawns (Mac, 23 Oct 2026). Pawns measure about 0.7
# against a cost of 1, so armies skip the pawn wall that closes lines in chess:
# with cheaper pawns, do strong armies build walls on their own? Branch
# experiment/cheap-pawns sets the Pawn's cost to 0.75 in data/pieces/pawn.tres;
# the 0.5 price is a copy of the pieces folder with only that number changed
# (made by tools/balance/run8_run9_driver.sh). Plusfish itself is unchanged
# (main's). Runs on the sims server, once per price:
#
#   PF=<plusfish> PIECES=<pieces folder> PRICE=0.75 bash tools/balance/run8_server.sh
#
# Same settings as before, so the results compare directly:
# Part 1: grow a meta pool under that price, as in run 2 (meta --wide 64
#   --game-climb --king-exposed reject --rounds 15 --seed 1, from the current
#   engine/plusfish/reports/meta_pool.txt plus Standard).
# Part 2: run 3's round robin on that pool plus Standard (40 games a pairing,
#   20 with each colour, 8,000 nodes, --random-plies 4, seeds 3000 + pairing
#   number).
# Part 3: random-army self-play (20,000 games, 8,000 nodes, seed 101,
#   selfplay's defaults otherwise), and its balance report (piece worths).
# Writes ~/plusfish-work/run8/p<price>/ and DONE there at the end. Doesn't
# switch the server off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF PIECES
export OUT="${OUT:?set OUT, e.g. ~/plusfish-work/run8/p075}"
mkdir -p "$OUT/pairs" "$OUT/logs"
rm -f "$OUT/DONE"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
cd ~/ChessPlus
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; Pawn cost $PRICE; pieces $PIECES ($(grep '^value' "$PIECES/pawn.tres"))"

log "part 1: meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1"
"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --threads 64 --pieces "$PIECES" \
	--pool engine/plusfish/reports/meta_pool.txt --out "$OUT/meta_pool.txt" > "$OUT/meta.log" 2>&1
log "part 1 finished (exit $?)"

grep -v '^#' "$OUT/meta_pool.txt" | grep -v '^ *$' | awk -F' [|] ' '{ print $2 "|" $1 }' | grep -v '^Standard|' > "$OUT/armies.txt"
echo "Standard|standard" >> "$OUT/armies.txt"
count=$(wc -l < "$OUT/armies.txt")
: > "$OUT/pairings.txt"
k=0
for ((i = 0; i < count; i++)); do
	for ((j = i + 1; j < count; j++)); do
		echo "$k|$i|$j" >> "$OUT/pairings.txt"
		k=$((k + 1))
	done
done
run_pair() {
	local line i j a b
	line=$(sed -n "$(($1 + 1))p" "$OUT/pairings.txt")
	i=$(echo "$line" | cut -d'|' -f2)
	j=$(echo "$line" | cut -d'|' -f3)
	a=$(sed -n "$((i + 1))p" "$OUT/armies.txt" | cut -d'|' -f2)
	b=$(sed -n "$((j + 1))p" "$OUT/armies.txt" | cut -d'|' -f2)
	"$PF" match --white "$a" --black "$b" --games 40 --nodes 8000 --random-plies 4 --pieces "$PIECES" \
		--threads 4 --seed $((3000 + $1)) --out "$OUT/pairs/p$1.jsonl" > "$OUT/logs/p$1.txt" 2>&1
	echo "pairing $1 done (exit $?)" >> "$OUT/logs/pairs_done.txt"
}
export -f run_pair
log "part 2: $k pairings of $count armies, 40 games each, 8000 nodes, random plies 4, seeds 3000-$((3000 + k - 1))"
seq 0 $((k - 1)) | xargs -P 16 -I{} bash -c 'run_pair {}'
log "part 2 finished ($(ls "$OUT"/pairs/*.jsonl | wc -l) pairing files)"

log "part 3: selfplay 20000 games, 8000 nodes, seed 101"
"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --pieces "$PIECES" \
	--out "$OUT/selfplay_8k.jsonl" > "$OUT/logs/selfplay_8k.txt" 2>&1
log "part 3 finished (exit $?)"
"$PF" values "$OUT/selfplay_8k.jsonl" --pieces "$PIECES" --html "$OUT/report_8k.html" > "$OUT/report_8k.txt" 2>&1
log "report written (exit $?)"

log "all done"
touch "$OUT/DONE"
