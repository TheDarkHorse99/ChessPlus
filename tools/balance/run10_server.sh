#!/usr/bin/env bash
# Balance run 10: the White-only quiet first move with strong armies (Mac,
# 23 Oct 2026). Run 9 tested the rule with random armies and with the normal
# meta pool; this grows a meta pool with the rule on (as run 6 did for the
# Front-row rule), then plays run 3's round robin on it. Runs on the sims
# server from ~/ChessPlus with this branch (experiment/white-quiet-first)
# checked out and Plusfish built there (it must stay named "plusfish": the
# server's idle switch-off only counts programs called exactly that):
#
#   nohup bash tools/balance/run10_server.sh > ~/plusfish-work/run10/run.log 2>&1 &
#
# Part 1: grow the meta pool with the rule on (run 2's settings: meta --wide 64
#   --game-climb --king-exposed reject --rounds 15 --seed 1, from the current
#   engine/plusfish/reports/meta_pool.txt plus Standard).
# Part 2: run 3's round robin on the new pool plus Standard, with the rule
#   (40 games a pairing, 20 per colour, 8,000 nodes, --random-plies 4, seeds
#   3000 + pairing number), for Mac's success test.
# Part 3: each new pool army against itself, without and with the rule
#   (plusfish analyse, 2,000,000 nodes, 8 threads).
# Writes ~/plusfish-work/run10/ and DONE at the end. Doesn't switch the server
# off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
export PIECES=~/ChessPlus/data/pieces
export OUT="${OUT:-$HOME/plusfish-work/run10}"
export RULE=--white-quiet-first=true
mkdir -p "$OUT/pairs" "$OUT/logs"
rm -f "$OUT/DONE"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
cd ~/ChessPlus
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; rule $RULE; pieces $PIECES ($(grep '^value' "$PIECES/pawn.tres"))"

log "part 1: meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1, rule"
"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --threads 64 --pieces "$PIECES" \
	--pool engine/plusfish/reports/meta_pool.txt --out "$OUT/meta_pool.txt" "$RULE" > "$OUT/meta.log" 2>&1
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
		--threads 4 --seed $((3000 + $1)) --out "$OUT/pairs/p$1.jsonl" "$RULE" > "$OUT/logs/p$1.txt" 2>&1
	echo "pairing $1 done (exit $?)" >> "$OUT/logs/pairs_done.txt"
}
export -f run_pair
log "part 2: $k pairings of $count armies, 40 games each, 8000 nodes, random plies 4, seeds 3000-$((3000 + k - 1)), rule"
seq 0 $((k - 1)) | xargs -P 16 -I{} bash -c 'run_pair {}'
log "part 2 finished ($(ls "$OUT"/pairs/*.jsonl | wc -l) pairing files)"

mirror() {
	local name army without with
	name=$(echo "$1" | cut -d'|' -f1)
	army=$(echo "$1" | cut -d'|' -f2)
	without=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" 2>/dev/null | grep "Best move")
	with=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" "$RULE" 2>/dev/null | grep "Best move")
	echo "new pool|$name|$army|$without|$with"
}
export -f mirror
log "part 3: each army against itself, 2000000 nodes, 8 threads, 8 at a time, without and with the rule"
echo "source|name|army|without the rule|with the rule" > "$OUT/mirror.txt"
tr '\n' '\0' < "$OUT/armies.txt" | xargs -0 -P 8 -I{} bash -c 'mirror "$1"' _ {} >> "$OUT/mirror.txt"
log "part 3 finished"

log "all done"
touch "$OUT/DONE"
