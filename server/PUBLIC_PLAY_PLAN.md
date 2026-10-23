# Getting online play ready for the public (plan, Oct 21 2026)

Status (22 Oct 2026): step 1 (locking the server: sign-in, checked functions,
server clocks, limits, cheaper syncing) is built in `server/supabase_update_3.sql`
and the game; LIVE since 22 Oct 2026 (live check 26/26). Moves are checked by the
server for turn and order but not yet for legality: that's the referee, next.

## Why

`server/supabase_setup.sql` lets the public key read, create and change any game
(`using (true)`). With only the key (it's in the public repo and the web game),
anyone can:
- read every game, all chat, and both players' IDs (the only proof of who a player is)
- rewrite moves or results, or take over seats
- post chat as either player
- cheat with a modified client (illegal moves, extra clock time, false wins)
- fill the 500 MB free database

Polling also downloads the whole row every 1.5 s, so the free 5 GB a month of
downloads covers only a few hundred hours of play.

Checked and safe: the web chat list uses `textContent`
(`scenes/common/web_overlay.gd` `setItems`), so strangers' messages can't inject HTML.

## Mac's decisions

- **Finding games:** a "Quick match" button (Mac's name) on the Play online
  screen, beside Create game / Join game. Codes still work.
- **Quick match time:** pick no limit / 3 / 5 / 10 / 15 / 30 minutes, or Any;
  players are paired only when their choices fit. Both Any: 10 minutes each,
  Claude's default (tell Mac).
- **King exposed pairings:** allowed in quick match (the game ends at once).
- **Accounts:** none. Each device signs in to Supabase anonymously and
  invisibly; this can become a real account later.
- **Chat with strangers:** typed chat plus **Mute** and **Report** buttons.
  Reports go to a table Mac checks in Supabase; a `banned` table blocks a device.
- **Anti-cheat:** a full referee. The server checks every move.
- **Downloads OK'd and done:**
  - Supabase CLI 2.121.0: `C:\Tools\supabase-cli\supabase.exe`
  - Deno 2.9.7: `C:\Tools\deno\deno.exe`
  - Both MIT licensed, checksums verified.

## Key finding: the referee needs no Rust

`web/plusfish.wasm` has no imports. Its `pf_run` request (`engine/plusfish/src/api.rs`)
already does what the referee needs:
- It replays `moves` and fails with `illegal or unknown move: ...` on a bad one.
- With `plies: [n]` it reports the final position's `outcome`: none, checkmate,
  stalemate, ..., or king_exposed (at ply 0).

Send `nodes: 1, depth: 1, hash_mb: 1` so it barely searches.

When more than one Jester could take the same hit, the attacker chooses which
and the move names it (`c7xe5/d4`); core and Plusfish both make one move per
Jester, so they agree.

## Design

**Identity**
- Supabase Anonymous Sign-ins.
  - Mac turns them on: Authentication > Sign In / Providers > Allow anonymous sign-ins.
  - Sign in with `POST /auth/v1/signup {}` and refresh with
    `POST /auth/v1/token?grant_type=refresh_token`.
  - Keep the session in UserSettings (section "online_auth").
  - On a failed refresh, re-read the saved session, then sign up again.
- Seats store `auth.uid()::text` in `white_id` / `black_id`. The same user may
  hold both seats (two copies on one phone), so every call also passes the seat.
- Continue online game saves the code plus the team, not a player ID.

**SQL: `server/supabase_update_3.sql`**
- Revoke anon and authenticated access to the tables. Drop the old policies and `post_chat(text,text,text)`.
- Revoke execute on each new function from public/anon (Supabase grants it by default), then grant only what's intended.
- New `games` columns:
  - `version` (bumped by the touch trigger)
  - `turn_started_at`
  - `rules`
  - `kind` ('code' or 'quick')
  - `created_by`
  - `reserved_for` (the rematch opponent)
- New tables:
  - `match_queue` (user_id pk, armies, time_ms with -1 = Any, rules, game_code, seen_at, entered_at)
  - `reports` (code, reporter, reported, reason, chat/moves snapshot; unique per reporter and game)
  - `banned` (user_id)
  - `shared_armies.owner_id`
- Player functions (authenticated):
  - `get_game(code, known_version)`: `{version, unchanged}` when nothing changed. Otherwise the game without IDs, plus `you` (seats) and `turn_ms` (how long the current turn has run, by server time). Non-players get no chat.
  - `resign_game`, `offer_draw`, `answer_draw`, `cancel_game`, `claim_timeout`
  - `send_chat`: up to 200 characters, about 5 messages per 10 s, 300 per game, with an `at` time on each message
  - `report_player`
  - `quick_match_status`: also tries to pair; uses `pg_advisory_xact_lock`
  - `leave_quick_match`
  - `share_army`: 4 KB cap, 20 an hour
  - `get_shared_army`
- Referee-only functions (service_role):
  - `referee_create_game(user, seat or random, armies {white, black}, time, eval_bar, rules, rematch_of)`: creates the code on the server, 30 games an hour, at most 5 waiting. With `rematch_of`: if the opponent already offered, it returns `{rematch: code}` instead.
  - `referee_join_game(user, code, armies, rules, finished_at_start)`
  - `referee_play_move(user, code, seat, move, expected_count, think_ms, finished)`
  - `referee_quick_match(user, armies, time, rules)`
- **Clocks:** charge `clamp(think_ms, server_elapsed - 2500, server_elapsed)`.
  - A timeout claim by the opponent needs `elapsed > remaining + 2500`; claiming your own needs `elapsed > remaining`.
  - The client waits 2 s before claiming again after a refusal (`game.gd` `_process`).
- **Cleanup**, run inside game creation, 200 rows at a time:
  - finished, cancelled or playing games untouched for 30 days
  - waiting games after 1 day
  - queue entries after 1 hour

**Referee Edge Function** (`server/supabase/functions/referee/`, deployed with `--workdir server`)
- Deploy: `supabase functions deploy referee --project-ref mwifzxkilmlgqcbkswkn --use-api --no-verify-jwt`.
  - Mac runs `supabase login` first, in his browser.
  - Put a `.gdignore` in `server/supabase`.
- No libraries, only `fetch`:
  - check the user with `GET /auth/v1/user`
  - call the database with the service key: `SUPABASE_SERVICE_ROLE_KEY`, else `SUPABASE_SECRET_KEYS`; send `Authorization` only for `eyJ...` keys
  - answer CORS preflight (the web game runs on github.io)
- Actions:
  - `create`, `join`: check both armies; join also checks ply 0 for king_exposed
  - `move`: replays all moves plus the new one in Plusfish
  - `quick_match`
  - `health`
- **Army checks** (port of `Army.problems`):
  - budget 39, exactly one King on row 0 at the middle files
  - at most 1 extra royal, at most 2 copies of most pieces
  - rows 0-1 only, no shared squares, buyable ids only (no wolf form)
  - names cut to 30 characters
- **Start position** (port of `ArmySetup.create_game`):
  - Black is flipped; files mirrored if `mirror`
  - promotion options = types on the board, no king or pawn types, most valuable first
  - same request shape as `PlusfishLink.position_for`
- **Rule sets:** `tools/make_rule_set.gd` writes `rules/<version>.json`
  - contents: pieces from `PlusfishLink._def_to_dict`, sorted by id, forms included; the buyable ids; GameRules army numbers; 8x8; castling_corner
  - version = sha256 of `JSON.stringify(data, "", true)`, first 12 characters
  - it also writes the `rules.ts` index and Deno test fixtures made with the real GDScript
  - the client's `RuleSet.version()` uses the same code
  - join and quick match need equal versions
  - refuse when `PlusfishLink.supports` would fail
- `plusfish_wasm.ts` (base64 of `web/plusfish.wasm`) is generated at deploy/test time and git-ignored.
- `tools/deploy_referee.sh` runs the generators, then `deno test`, then deploys.
- When piece rules change, deploy the referee before the web build.

**Client**
- `OnlineBackend`
  - `call_function(name, args)` and `referee(action, args)`; returns `{ok, rows, error}`
  - an RPC that returns null gives `rows: []` (the old "someone changed it first")
  - errors use the server's message
- `SupabaseBackend`: auth plus a session slot, so live tests can use two identities.
- `MemoryBackend`
  - acts as the same server in GDScript, with a `user` per instance (`MemoryBackend.new("host")`)
  - legality checked with core `GameState`
  - a settable clock
- `OnlineSession`
  - `send_move(text)` replaces `send_moves`
  - every army is sent as `{white, black}` resolved through `ArmyChoices.resolver`, since the side may not be known
  - `find_quick_match` / `cancel_quick_match`
  - `report`
- `game.gd`
  - re-sync from the server on a rejected or out-of-step move
  - claim retry delay
  - rematch through create with `rematch_of`
  - Mute (hides their chat for this game and its rematches) and Report (pop-up, then auto-mute; wording is Claude's draft, for Mac to change)
- Other screens:
  - lobby: Quick match with Any + the time list, "Looking for an opponent..." and Cancel
  - `army_share` uses the new RPCs
  - `main.gd` self-test and Continue are updated
- Polling: `get_game` with a version is a tiny reply; download the full game only when it changed.

**Tests**
- `tests/online_test.gd` rewritten for the new backend: cheating attempts, clocks, quick match, chat limits, reports.
- Deno tests for the army checks, the start position against the fixtures, and Plusfish judging (fool's mate, an illegal move, king exposed).
- `tools/online_live_test.gd` runs against the real server after deploying.

**Go-live order** (old copies of the game stop working online until they update at the main menu):
1. Mac turns on anonymous sign-ins.
2. Mac runs the update 3 SQL.
3. Mac runs `supabase login`; Claude deploys the referee.
4. Claude runs the live test.
5. Claude deploys the web build.
