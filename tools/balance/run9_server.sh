#!/usr/bin/env bash
# Balance run 9: the White-only quiet first move (Mac, 23 Oct 2026): White may
# not capture, break a shield or use an ability on its first move unless it's
# in check; Black's first move is unrestricted. Tested in Plusfish only
# (--white-quiet-first=true, branch experiment/white-quiet-first). Runs on the
# sims server, after tools/balance/run8_run9_driver.sh has built the binaries:
#
#   PF=<rule binary> PF_MAIN=<main binary> PIECES=<pieces folder> \
#       bash tools/balance/run9_server.sh
#
# Same settings as runs 2-5, so the results compare directly:
# Part 0 (control): random-army self-play with today's Plusfish and no rule
#   (20,000 games, 8,000 nodes, seed 101): runs 2, 4 and 5 used the Plusfish
#   from before Nicholas's PR #26, so this is the like-for-like baseline.
# Part 1: random-army self-play with the rule (20,000 games, 8,000 nodes, seed
#   101, selfplay's defaults otherwise).
# Part 2: run 3's round robin on the current meta pool plus Standard (40 games
#   a pairing, 8,000 nodes, --random-plies 4, seeds 3000 + pairing number).
# Part 3: each army against itself (Plusfish at 2,000,000 nodes, 8 threads),
#   without and with the rule: run 4's armies, run 5's 40 armies, and the
#   current pool.
# Writes ~/plusfish-work/run9/ and DONE at the end. Doesn't switch the server
# off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF PF_MAIN PIECES
export OUT="${OUT:-$HOME/plusfish-work/run9}"
export RULE=--white-quiet-first=true
mkdir -p "$OUT/pairs" "$OUT/logs"
rm -f "$OUT/DONE"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
cd ~/ChessPlus
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores; rule $RULE; pieces $PIECES"

log "part 0 (control): selfplay 20000 games, 8000 nodes, seed 101, no rule, main's Plusfish"
"$PF_MAIN" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --pieces "$PIECES" \
	--out "$OUT/selfplay_control.jsonl" > "$OUT/logs/selfplay_control.txt" 2>&1
log "part 0 finished (exit $?)"
"$PF_MAIN" values "$OUT/selfplay_control.jsonl" --pieces "$PIECES" --html "$OUT/report_control.html" > "$OUT/report_control.txt" 2>&1

log "part 1: selfplay 20000 games, 8000 nodes, seed 101, rule"
"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --pieces "$PIECES" \
	--out "$OUT/selfplay_8k.jsonl" "$RULE" > "$OUT/logs/selfplay_8k.txt" 2>&1
log "part 1 finished (exit $?)"
"$PF" values "$OUT/selfplay_8k.jsonl" --pieces "$PIECES" --html "$OUT/report_8k.html" > "$OUT/report_8k.txt" 2>&1

grep -v '^#' engine/plusfish/reports/meta_pool.txt | grep -v '^ *$' | awk -F' [|] ' '{ print $2 "|" $1 }' \
	| grep -v '^Standard|' > "$OUT/armies.txt"
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

# Part 3's armies: source|name|army.
: > "$OUT/mirror_armies.txt"
awk -F'|' '{ print "run 4|" $1 "|" $2 }' balance/results/run4/armies.txt >> "$OUT/mirror_armies.txt"
awk -F'|' '{ print "run 5 (" $1 ")|" NR "|" $2 }' balance/results/run5/mirror_armies.txt >> "$OUT/mirror_armies.txt"
awk -F'|' '{ print "current pool|" $1 "|" $2 }' "$OUT/armies.txt" >> "$OUT/mirror_armies.txt"
mirror() {
	local source name army without with
	source=$(echo "$1" | cut -d'|' -f1)
	name=$(echo "$1" | cut -d'|' -f2)
	army=$(echo "$1" | cut -d'|' -f3)
	without=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" 2>/dev/null | grep "Best move")
	with=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 --pieces "$PIECES" "$RULE" 2>/dev/null | grep "Best move")
	echo "$source|$name|$army|$without|$with"
}
export -f mirror
log "part 3: $(wc -l < "$OUT/mirror_armies.txt") armies against themselves, 2000000 nodes, 8 threads, 8 at a time, without and with the rule"
echo "source|name|army|without the rule|with the rule" > "$OUT/mirror.txt"
tr '\n' '\0' < "$OUT/mirror_armies.txt" | xargs -0 -P 8 -I{} bash -c 'mirror "$1"' _ {} >> "$OUT/mirror.txt"
log "part 3 finished"

log "all done"
touch "$OUT/DONE"
