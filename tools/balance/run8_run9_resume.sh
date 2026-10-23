#!/usr/bin/env bash
# Resumes balance runs 8 and 9 (23 Oct 2026) after the server's idle switch-off
# stopped it at 05:10 UTC: that check (tools/sims_server/chessplus-idle-check)
# only counts programs named exactly "plusfish", and the first driver had
# copied the two builds as pf-main and pf-wq, so the server looked idle. Now
# each build is called plusfish, in its own folder. Run 9's parts 0-2 had
# finished; this does run 9's part 3, then run 8 at both prices.
#
#   nohup bash ~/plusfish-work/run8_run9_resume.sh > ~/plusfish-work/run89_resume.log 2>&1 &
set -u
W=~/plusfish-work
log() { echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $*" | tee -a "$W/run89_progress.log"; }
fail() { log "FAILED: $*"; touch "$W/run89_FAILED"; exit 1; }
rm -f "$W/run89_DONE" "$W/run89_FAILED"
mkdir -p "$W/bin/main" "$W/bin/wq"
[ -f "$W/bin/pf-main" ] && mv "$W/bin/pf-main" "$W/bin/main/plusfish"
[ -f "$W/bin/pf-wq" ] && mv "$W/bin/pf-wq" "$W/bin/wq/plusfish"
[ -x "$W/bin/main/plusfish" ] && [ -x "$W/bin/wq/plusfish" ] || fail "binaries"
log "resuming (idle switch-off had stopped the server at 05:10 UTC); builds now named plusfish"
cd ~/ChessPlus

log "run 9, part 3 (redone in full)"
git checkout -q --detach origin/experiment/white-quiet-first || fail "checkout white-quiet-first"
export PF="$W/bin/wq/plusfish" PIECES="$W/pieces/p100" OUT="$W/run9" RULE=--white-quiet-first=true
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] resumed: part 3 again (the server had switched itself off during it)" >> "$OUT/progress.log"
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
echo "source|name|army|without the rule|with the rule" > "$OUT/mirror.txt"
tr '\n' '\0' < "$OUT/mirror_armies.txt" | xargs -0 -P 8 -I{} bash -c 'mirror "$1"' _ {} >> "$OUT/mirror.txt"
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] part 3 finished ($(($(wc -l < "$OUT/mirror.txt") - 1)) armies)" >> "$OUT/progress.log"
echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] all done" >> "$OUT/progress.log"
touch "$OUT/DONE"
log "run 9 done"

git checkout -q --detach origin/experiment/cheap-pawns || fail "checkout cheap-pawns"
for setting in "0.75 p075" "0.5 p050"; do
	set -- $setting
	log "run 8, Pawn $1"
	OUT="$W/run8/$2" PF="$W/bin/main/plusfish" PIECES="$W/pieces/$2" PRICE="$1" bash tools/balance/run8_server.sh
	[ -f "$W/run8/$2/DONE" ] || fail "run 8 Pawn $1 didn't finish"
done

log "all done"
touch "$W/run89_DONE"
