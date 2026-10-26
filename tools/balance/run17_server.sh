#!/usr/bin/env bash
# Balance run 17 (Mac, 26 Oct 2026): the Vampire and Wizard repriced, measured
# two ways. Plusfish is main's engine (Nicholas's PR #28) with the split-colours
# meta search (branch experiment/meta-share). Runs on the sims server from
# ~/ChessPlus with that branch checked out and Plusfish built (named
# "plusfish", for the idle switch-off):
#
#   nohup bash tools/balance/run17_server.sh > ~/plusfish-work/run17/run.log 2>&1 < /dev/null &
#
# (1) A/: the balance report at today's prices: selfplay 20,000 games, 8,000
#     nodes, seed 101, then values.
# The Vampire's new price is picked from that report (Mac: "7 or 7.5"): its
# measured worth rounded to the nearer half point, kept within 7-7.5. The
# Wizard goes to 8.5. A copy of the piece files with those two values is
# pieces_b/ (nothing in the game changes).
# (2) B/: the balance report again at the new prices.
# (3) B/meta/: run 16's meta-share method at the new prices (4 independent
#     all-round searches from scratch, 4 specialist searches against the top
#     3 of each, all-rounders against specialists), via run16_server.sh with
#     BASE and PIECES overridden.
# Writes ~/plusfish-work/run17/DONE at the end. Doesn't switch the server off.
set -u
export PF=~/ChessPlus/engine/plusfish/target/release/plusfish
BASE=~/plusfish-work/run17
mkdir -p "$BASE/A" "$BASE/B"
rm -f "$BASE/DONE"
cd ~/ChessPlus
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" >> "$BASE/progress.log"; }
log "start; game version $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD)); $(nproc) cores"

PIECES_A=~/ChessPlus/data/pieces
log "(1) balance report at today's prices: selfplay 20000 games, 8000 nodes, seed 101"
"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --pieces "$PIECES_A" --out "$BASE/A/selfplay.jsonl" > "$BASE/A/selfplay.log" 2>&1
"$PF" values "$BASE/A/selfplay.jsonl" --html "$BASE/A/report.html" --pieces "$PIECES_A" --threads 64 > "$BASE/A/report.txt" 2> "$BASE/A/values.log"
log "(1) report written (exit $?)"

# The Vampire's measured worth -> 7 or 7.5.
worth=$(awk '$1 == "Vampire" { print $4; exit }' "$BASE/A/report.txt")
price=$(awk -v w="${worth:-7}" 'BEGIN { p = int(w * 2 + 0.5) / 2; if (p < 7) p = 7; if (p > 7.5) p = 7.5; print p }')
log "Vampire worth ${worth:-?} -> new price $price; Wizard 8.5"
PIECES_B="$BASE/pieces_b"
rm -rf "$PIECES_B"
cp -r "$PIECES_A" "$PIECES_B"
sed -i "s/^value = .*/value = $price/" "$PIECES_B/vampire.tres"
sed -i "s/^value = .*/value = 8.5/" "$PIECES_B/wizard.tres"
echo "Vampire $price, Wizard 8.5" > "$BASE/B/prices.txt"
grep -H "^value" "$PIECES_B/vampire.tres" "$PIECES_B/wizard.tres" >> "$BASE/progress.log"

log "(2) balance report at the new prices"
"$PF" selfplay --games 20000 --nodes 8000 --seed 101 --threads 64 --pieces "$PIECES_B" --out "$BASE/B/selfplay.jsonl" > "$BASE/B/selfplay.log" 2>&1
"$PF" values "$BASE/B/selfplay.jsonl" --html "$BASE/B/report.html" --pieces "$PIECES_B" --threads 64 > "$BASE/B/report.txt" 2> "$BASE/B/values.log"
log "(2) report written (exit $?)"

log "(3) the meta by share at the new prices (run16_server.sh with BASE and PIECES overridden)"
BASE="$BASE/B/meta" PIECES="$PIECES_B" bash tools/balance/run16_server.sh > "$BASE/B/meta_run.log" 2>&1
log "(3) finished (exit $?)"
log "all done"
touch "$BASE/DONE"
