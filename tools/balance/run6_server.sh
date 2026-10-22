#!/usr/bin/env bash
# Balance run 6: the Front-row rule with strong armies. Plusfish's army check
# enforces the rule when given --front-row-rule=true (branch
# experiment/front-row-rule). Runs on the sims server from ~/ChessPlus after
# checking out that branch and building Plusfish:
#
#   nohup bash tools/balance/run6_server.sh > ~/plusfish-work/run6/run.log 2>&1 &
#
# Part 1: regrow the meta pool under the rule (run 2's settings: meta --wide 64
#   --game-climb --king-exposed reject --rounds 15 --seed 1, from the current
#   pool; members breaking the rule are left out).
# Part 2: run 3's round robin on the new pool plus Standard (40 games a
#   pairing, 8,000 nodes, --random-plies 4, seeds 3000 + pairing number), for
#   Mac's success test.
# Part 3: each new pool army against itself (2,000,000 nodes, 8 threads).
# Part 4: random armies following the rule at 32,000 nodes (10,000 games,
#   seed 202), to check run 5's 52% at more depth.
# Writes ~/plusfish-work/run6/ and DONE at the end. Doesn't switch the server
# off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
export OUT=~/plusfish-work/run6
export RULE=--front-row-rule=true
mkdir -p "$OUT/pairs" "$OUT/logs"
rm -f "$OUT/DONE"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
cd ~/ChessPlus
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; rule $RULE"

log "part 1: meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1"
"$PF" meta --wide 64 --game-climb --king-exposed reject --rounds 15 --seed 1 --threads 64 \
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
	"$PF" match --white "$a" --black "$b" --games 40 --nodes 8000 --random-plies 4 \
		--threads 4 --seed $((3000 + $1)) --out "$OUT/pairs/p$1.jsonl" > "$OUT/logs/p$1.txt" 2>&1
	echo "pairing $1 done (exit $?)" >> "$OUT/logs/pairs_done.txt"
}
export -f run_pair
log "part 2: $k pairings of $count armies, 40 games each, 8000 nodes, random plies 4, seeds 3000-$((3000 + k - 1))"
seq 0 $((k - 1)) | xargs -P 16 -I{} bash -c 'run_pair {}'
log "part 2 finished ($(ls "$OUT"/pairs/*.jsonl | wc -l) pairing files)"

mirror() {
	local name army result
	name=$(echo "$1" | cut -d'|' -f1)
	army=$(echo "$1" | cut -d'|' -f2)
	result=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 2>/dev/null | grep "Best move")
	echo "$name|$army|$result"
}
export -f mirror
log "part 3: each army against itself, 2000000 nodes, 8 threads, 8 at a time"
echo "name|army|result" > "$OUT/mirror.txt"
tr '\n' '\0' < "$OUT/armies.txt" | xargs -0 -P 8 -I{} bash -c 'mirror "$1"' _ {} >> "$OUT/mirror.txt"
log "part 3 finished"

log "part 4: selfplay 10000 games, 32000 nodes, seed 202, front-row rule"
"$PF" selfplay --games 10000 --nodes 32000 --seed 202 --threads 64 --out "$OUT/selfplay_32k.jsonl" "$RULE" > "$OUT/logs/selfplay_32k.txt" 2>&1
log "part 4 finished (exit $?); $(grep 'front-row rule:' "$OUT/logs/selfplay_32k.txt" | tail -1)"

log "all done"
touch "$OUT/DONE"
