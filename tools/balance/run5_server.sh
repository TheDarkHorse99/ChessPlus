#!/usr/bin/env bash
# Balance run 5: the "front-row rule" (no piece may start able to capture
# anything on the opponent's two starting rows), tested in Plusfish only
# (--front-row-rule=true makes self-play's random armies follow it; branch
# experiment/front-row-rule). Runs on the sims server from ~/ChessPlus after
# checking out that branch and building Plusfish:
#
#   nohup bash tools/balance/run5_server.sh > ~/plusfish-work/run5/run.log 2>&1 &
#
# Part 1: run 2's random-army self-play at 8,000 nodes (20,000 games, seed 101,
#   selfplay's defaults otherwise), every army following the rule.
# Part 2: each army against itself (White's first-move advantage, Plusfish at
#   2,000,000 nodes on 8 threads): 20 armies from part 1 (following the rule)
#   and 20 from run 2's games (not), 8 at a time.
# Writes ~/plusfish-work/run5/ and DONE at the end. Doesn't switch the server
# off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
export OUT=~/plusfish-work/run5
mkdir -p "$OUT/logs"
rm -f "$OUT/DONE"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$OUT/progress.log"; }
cd ~/ChessPlus
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores"

log "part 1: selfplay 20000 games, 8000 nodes, seed 101, front-row rule"
"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --out "$OUT/selfplay_8k.jsonl" --front-row-rule=true > "$OUT/logs/selfplay_8k.txt" 2>&1
log "part 1 finished (exit $?); $(grep 'front-row rule:' "$OUT/logs/selfplay_8k.txt" | tail -1)"

# The first 20 different White armies in a game file.
first_armies() { grep -o '"white":"[^"]*"' "$1" | cut -d'"' -f4 | awk '!seen[$0]++' | head -20; }
first_armies "$OUT/selfplay_8k.jsonl" | sed 's/^/rule|/' > "$OUT/mirror_armies.txt"
first_armies ~/plusfish-work/run2/games_8k_seed101.jsonl | sed 's/^/no rule|/' >> "$OUT/mirror_armies.txt"

mirror() {
	local kind army result
	kind=$(echo "$1" | cut -d'|' -f1)
	army=$(echo "$1" | cut -d'|' -f2)
	result=$("$PF" analyse --white "$army" --black "$army" --nodes 2000000 --threads 8 2>/dev/null | grep "Best move")
	echo "$kind|$army|$result"
}
export -f mirror
log "part 2: 40 armies against themselves, 2000000 nodes, 8 threads, 8 at a time"
echo "kind|army|result" > "$OUT/mirror.txt"
tr '\n' '\0' < "$OUT/mirror_armies.txt" | xargs -0 -P 8 -I{} bash -c 'mirror "$1"' _ {} >> "$OUT/mirror.txt"
log "part 2 finished"

log "all done"
touch "$OUT/DONE"
