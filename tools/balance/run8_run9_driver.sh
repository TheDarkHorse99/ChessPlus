#!/usr/bin/env bash
# Balance runs 8 and 9 on the sims server, one after the other (Mac, 23 Oct
# 2026). Copied to the server and started from the PC:
#
#   nohup bash ~/plusfish-work/run8_run9_driver.sh > ~/plusfish-work/run89.log 2>&1 &
#
# 1. Fetches main, experiment/white-quiet-first and experiment/cheap-pawns and
#    builds two Plusfish programs: main's (runs 8 and 9's control) and the
#    branch with --white-quiet-first (run 9). A failed build stops everything
#    (cargo would otherwise leave the old program in place).
# 2. Makes three pieces folders: main's (Pawn 1), the cheap-pawns branch's
#    (Pawn 0.75) and a copy of that with the Pawn at 0.5. Nothing else differs.
# 3. Checks the new rule with perft: on White's first move a capture is barred
#    (fewer moves with the rule), not when White is in check, and never for Black.
# 4. Run 9 (tools/balance/run9_server.sh, from its branch), then run 8 at both
#    prices (tools/balance/run8_server.sh, from its branch).
# Writes ~/plusfish-work/run89_DONE at the end, or run89_FAILED. Doesn't switch
# the server off: the PC stops it through AWS (tools/sims_server.sh stop).
set -u
W=~/plusfish-work
mkdir -p "$W/bin" "$W/pieces"
rm -f "$W/run89_DONE" "$W/run89_FAILED"
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" | tee -a "$W/run89_progress.log"; }
fail() { log "FAILED: $*"; touch "$W/run89_FAILED"; exit 1; }
cd ~/ChessPlus

log "fetching branches"
git fetch -q --depth 1 origin \
	+refs/heads/main:refs/remotes/origin/main \
	+refs/heads/experiment/white-quiet-first:refs/remotes/origin/experiment/white-quiet-first \
	+refs/heads/experiment/cheap-pawns:refs/remotes/origin/experiment/cheap-pawns || fail "fetch"

build() {
	git checkout -q --detach "$1" || fail "checkout $1"
	rm -f engine/plusfish/target/release/plusfish
	(cd engine/plusfish && ~/.cargo/bin/cargo build --release -q) || fail "build $1"
	cp engine/plusfish/target/release/plusfish "$W/bin/$2" || fail "copy $2"
	log "built $2 from $1 ($(git rev-parse --short HEAD))"
}
build origin/main pf-main
rm -rf "$W/pieces/p100" && cp -r data/pieces "$W/pieces/p100"
build origin/experiment/white-quiet-first pf-wq
git checkout -q --detach origin/experiment/cheap-pawns || fail "checkout cheap-pawns"
rm -rf "$W/pieces/p075" "$W/pieces/p050"
cp -r data/pieces "$W/pieces/p075" && cp -r data/pieces "$W/pieces/p050"
sed -i 's/^value = 0.75$/value = 0.5/' "$W/pieces/p050/pawn.tres"
for p in p100 p075 p050; do log "pieces $p: Pawn $(grep '^value' "$W/pieces/$p/pawn.tres")"; done
[ "$(grep '^value' "$W/pieces/p100/pawn.tres")" = "value = 1" ] || fail "p100 pawn cost"
[ "$(grep '^value' "$W/pieces/p075/pawn.tres")" = "value = 0.75" ] || fail "p075 pawn cost"
[ "$(grep '^value' "$W/pieces/p050/pawn.tres")" = "value = 0.5" ] || fail "p050 pawn cost"

# perft 1 without and with the rule.
count() { "$W/bin/pf-wq" perft --fen "$1" --depth 1 --pieces "$W/pieces/p100" $2 2>/dev/null | awk '/^perft/ { print $4 }'; }
check() {
	local without with
	without=$(count "$2" "")
	with=$(count "$2" "--white-quiet-first=true")
	log "rule check, $1: $without moves without the rule, $with with it"
	[ -n "$without" ] && [ -n "$with" ] || fail "rule check $1 gave no count"
	case "$3" in
		fewer) [ "$with" -lt "$without" ] || fail "rule check $1: expected fewer moves" ;;
		same) [ "$with" -eq "$without" ] || fail "rule check $1: expected the same moves" ;;
	esac
}
check "White's first move, can capture" "4k3/8/8/8/8/8/3r4/4K3 w - - 0 1" fewer
check "White in check, capture allowed" "4k3/8/8/8/8/8/4r3/4K3 w - - 0 1" same
check "Black's first move, unrestricted" "4k3/3R4/8/8/8/8/8/4K3 b - - 0 1" same
check "White's second move, unrestricted" "4k3/8/8/8/8/8/3r4/4K3 w - - 0 2" same

log "run 9"
git checkout -q --detach origin/experiment/white-quiet-first || fail "checkout white-quiet-first"
PF="$W/bin/pf-wq" PF_MAIN="$W/bin/pf-main" PIECES="$W/pieces/p100" bash tools/balance/run9_server.sh
[ -f "$W/run9/DONE" ] || fail "run 9 didn't finish"

git checkout -q --detach origin/experiment/cheap-pawns || fail "checkout cheap-pawns"
for setting in "0.75 p075" "0.5 p050"; do
	set -- $setting
	log "run 8, Pawn $1"
	OUT="$W/run8/$2" PF="$W/bin/pf-main" PIECES="$W/pieces/$2" PRICE="$1" bash tools/balance/run8_server.sh
	[ -f "$W/run8/$2/DONE" ] || fail "run 8 Pawn $1 didn't finish"
done

log "all done"
touch "$W/run89_DONE"
