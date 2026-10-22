#!/usr/bin/env bash
# Balance run 4: Mac's "Quiet first move" rule (no captures or abilities on
# either side's first move), tested in Plusfish only (--quiet-first-move=true,
# branch experiment/quiet-first-move). Runs on the sims server from
# ~/ChessPlus after checking out that branch and building Plusfish:
#
#   nohup bash tools/balance/run4_server.sh > ~/plusfish-work/run4/run.log 2>&1 &
#
# Same settings as before, so the results compare directly:
# Part 1: run 3's meta pool round robin (10 pool armies + Standard, 40 games a
#   pairing, 8,000 nodes, --random-plies 4, seeds 3000 + pairing number).
# Part 2: run 2's random-army self-play at 8,000 nodes (20,000 games, seed 101,
#   selfplay's defaults otherwise).
# Part 3: each army against itself (White's first-move advantage), Plusfish's
#   evaluation at 2,000,000 nodes on 8 threads, with and without the rule.
# Writes ~/plusfish-work/run4/ and DONE at the end. Doesn't switch the server
# off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
export OUT=~/plusfish-work/run4
export RULE=--quiet-first-move=true
mkdir -p "$OUT/pairs" "$OUT/logs"
rm -f "$OUT/DONE"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
cd ~/ChessPlus
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; rule $RULE"

grep -v '^#' engine/plusfish/reports/meta_pool.txt | grep -v '^ *$' \
	| awk -F' [|] ' '{ print $2 "|" $1 }' > "$OUT/armies.txt"
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
		--threads 4 --seed $((3000 + $1)) --out "$OUT/pairs/p$1.jsonl" "$RULE" > "$OUT/logs/p$1.txt" 2>&1
	echo "pairing $1 done (exit $?)" >> "$OUT/logs/pairs_done.txt"
}
export -f run_pair

log "part 1: $k pairings, 40 games each, 8000 nodes, random plies 4, seeds 3000-$((3000 + k - 1))"
seq 0 $((k - 1)) | xargs -P 16 -I{} bash -c 'run_pair {}'
log "part 1 finished ($(ls "$OUT"/pairs/*.jsonl | wc -l) pairing files)"

log "part 2: selfplay 20000 games, 8000 nodes, seed 101"
"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --out "$OUT/selfplay_8k.jsonl" "$RULE" > "$OUT/logs/selfplay_8k.txt" 2>&1
log "part 2 finished (exit $?)"

log "part 3: each army against itself, 2000000 nodes, 8 threads, without and with the rule"
echo "army|without the rule|with the rule" > "$OUT/mirror.txt"
while IFS='|' read -r name army; do
	without=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 2>/dev/null | grep "Best move")
	with=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 "$RULE" 2>/dev/null | grep "Best move")
	echo "$name|$without|$with" >> "$OUT/mirror.txt"
done < "$OUT/armies.txt"
log "part 3 finished"

log "all done"
touch "$OUT/DONE"
