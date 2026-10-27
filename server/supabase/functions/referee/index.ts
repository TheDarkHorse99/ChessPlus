// The online referee: a Supabase Edge Function the game calls to create a
// game, join one, or play a move. It checks the caller's sign-in, judges the
// army or move with the game's own rules (referee.ts + Plusfish), and only
// then writes it, through database functions that nobody but the referee may
// call (server/supabase_update_4.sql). Deployed by tools/deploy_referee.sh.
//
// POST {action: "create", seat, white_army, black_army, time_ms, increment_ms, eval_bar, rules}
//      {action: "join", code, white_army, black_army, rules}
//      {action: "move", code, seat, move, expected, think_ms, finished}
//      {action: "quick", white_army, black_army, time_ms (-1 = Any), increment_ms, rules}
//      {action: "health"}
// Reply: {game: {...}} (the game as the caller may see it; null = "nothing
// changed", e.g. the opponent moved first) or {error: "plain words"}.

import { armyProblems, judge, startPosition, supported } from "./referee.ts";
import type { ArmyData, RuleSetData } from "./referee.ts";
import { loadPlusfish } from "./plusfish.ts";
import { RULE_SETS } from "./rules.ts";
import { PLUSFISH_WASM } from "./plusfish_wasm.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
// The server's own key (full access): the older service-role key, or the
// newer secret key.
function serverKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}");
    return String(Object.values(keys)[0] ?? "");
  } catch {
    return "";
  }
}
const KEY = serverKey();

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

function serverHeaders(): Record<string, string> {
  const headers: Record<string, string> = { apikey: KEY, "Content-Type": "application/json" };
  // Old-style keys are tokens that also go in the Authorization header.
  if (KEY.startsWith("eyJ")) headers.Authorization = `Bearer ${KEY}`;
  return headers;
}

// Who is calling: their sign-in's user ID, checked with the sign-in server.
async function caller(req: Request): Promise<string | null> {
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!token) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, { headers: { apikey: KEY, Authorization: `Bearer ${token}` } });
  if (!res.ok) return null;
  const user = await res.json();
  return typeof user?.id === "string" ? user.id : null;
}

// The game as stored (with the players' IDs), or null.
async function storedGame(code: string): Promise<Record<string, any> | null> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/games?select=*&code=eq.${encodeURIComponent(code.trim().toUpperCase())}`,
    { headers: serverHeaders() });
  if (!res.ok) throw new Error(`couldn't read the game (${res.status})`);
  const rows = await res.json();
  return rows[0] ?? null;
}

// Call one of the referee's database functions; its refusal message comes back as an error.
async function rpc(name: string, args: Record<string, unknown>): Promise<Response> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, { method: "POST", headers: serverHeaders(), body: JSON.stringify(args) });
  const text = await res.text();
  if (!res.ok) {
    let message = `the server said ${res.status}`;
    try {
      message = JSON.parse(text).message ?? message;
    } catch { /* not JSON */ }
    return reply({ error: message }, 400);
  }
  return reply({ game: text.trim() === "" ? null : JSON.parse(text) });
}

const UPDATE_NEEDED = "This copy of Overchess is out of date for online play: it updates itself at the main menu.";

function ruleSet(version: unknown): RuleSetData | null {
  return typeof version === "string" ? RULE_SETS[version] ?? null : null;
}

function armyError(army: unknown, rs: RuleSetData): string | null {
  const problems = armyProblems(army, rs);
  return problems.length === 0 ? null : "Your army breaks the army rules: " + problems.join(" ");
}

const plusfish = await loadPlusfish(PLUSFISH_WASM);

async function create(user: string, body: Record<string, any>): Promise<Response> {
  const rs = ruleSet(body.rules);
  if (!rs) return reply({ error: UPDATE_NEEDED }, 400);
  let seat = String(body.seat);
  if (seat === "random") seat = Math.random() < 0.5 ? "white" : "black";
  if (seat !== "white" && seat !== "black") return reply({ error: "Choose White, Black or Random." }, 400);
  const problem = armyError(seat === "white" ? body.white_army : body.black_army, rs);
  if (problem) return reply({ error: problem }, 400);
  return await rpc("referee_create_game", {
    p_user: user, p_seat: seat, p_white_army: body.white_army, p_black_army: body.black_army,
    p_time_ms: body.time_ms, p_increment_ms: body.increment_ms ?? 0, p_eval_bar: !!body.eval_bar, p_rules: body.rules,
  });
}

async function join(user: string, body: Record<string, any>): Promise<Response> {
  const code = String(body.code ?? "").trim().toUpperCase();
  const game = await storedGame(code);
  if (!game) return reply({ error: `There's no game with the code ${code}.` }, 400);
  const rs = ruleSet(game.rules);
  if (!rs || body.rules !== game.rules) {
    return reply({ error: "You and your opponent have different versions of Overchess: both update themselves at the main menu." }, 400);
  }
  if (game.status !== "waiting") {
    return reply({ error: game.status === "cancelled" ? "That game was cancelled." : "That game has already started." }, 400);
  }
  const seat = game.white_id ? "black" : "white";
  const mine = seat === "white" ? body.white_army : body.black_army;
  const problem = armyError(mine, rs);
  if (problem) return reply({ error: problem }, 400);
  const white = (seat === "white" ? mine : game.white_army) as ArmyData;
  const black = (seat === "black" ? mine : game.black_army) as ArmyData;
  // Whether Plusfish can judge this game, and whether it's over before it starts
  // (a king attacked by the armies as they stand: King exposed).
  const refereed = supported(white, black, rs);
  let finished = false;
  if (refereed) {
    const start = judge(white, black, [], rs, plusfish);
    finished = start.legal && start.outcome !== "none";
  }
  return await rpc("referee_join_game", {
    p_user: user, p_code: code, p_white_army: body.white_army, p_black_army: body.black_army,
    p_finished: finished, p_refereed: refereed,
  });
}

async function move(user: string, body: Record<string, any>): Promise<Response> {
  const code = String(body.code ?? "").trim().toUpperCase();
  const game = await storedGame(code);
  if (!game) return reply({ error: `There's no game with the code ${code}.` }, 400);
  const text = String(body.move ?? "");
  const refereed = !!game.refereed;
  let finished = !!body.finished;
  // Judge only a move that would be played: the game on, at the expected move,
  // by the side to move (the database function turns away the rest, e.g. the
  // opponent moved first; it also checks the seat is the caller's).
  const mover = game.move_count % 2 === 0 ? "white" : "black";
  if (refereed && game.status === "playing" && game.move_count === body.expected && body.seat === mover) {
    const rs = ruleSet(game.rules);
    if (!rs) return reply({ error: UPDATE_NEEDED }, 400);
    const verdict = judge(game.white_army, game.black_army, [...(game.moves as string[]), text], rs, plusfish);
    if (!verdict.legal) return reply({ error: "That move isn't allowed." }, 400);
    finished = verdict.outcome !== "none";
  }
  return await rpc("referee_play_move", {
    p_user: user, p_code: code, p_seat: body.seat, p_move: text, p_expected: body.expected,
    p_think_ms: body.think_ms, p_finished: finished, p_refereed: refereed,
  });
}

// Quick match: check both armies (the side isn't known yet), join the queue,
// then try to pair with whoever fits. Reply {game} once paired, else
// {game: null, waiting: true}; the waiting player checks the queue
// (quick_match_status) and asks again when someone who fits is there.
async function quick(user: string, body: Record<string, any>): Promise<Response> {
  const rs = ruleSet(body.rules);
  if (!rs) return reply({ error: UPDATE_NEEDED }, 400);
  const problem = armyError(body.white_army, rs) ?? armyError(body.black_army, rs);
  if (problem) return reply({ error: problem }, 400);
  const entered = await rpcData("referee_quick_enter", {
    p_user: user, p_white_army: body.white_army, p_black_army: body.black_army, p_time_ms: body.time_ms,
    p_increment_ms: body.increment_ms ?? 0, p_rules: body.rules,
  });
  if ("error" in entered) return reply({ error: entered.error }, 400);
  if (entered.data?.code) {
    return reply({ game: null, paired: entered.data.code });
  }
  for (const other of (entered.data?.candidates ?? []) as Record<string, any>[]) {
    const iAmWhite = Math.random() < 0.5;
    const white = (iAmWhite ? body.white_army : other.white_army) as ArmyData;
    const black = (iAmWhite ? other.black_army : body.black_army) as ArmyData;
    if (armyError(white, rs) || armyError(black, rs)) continue;
    const refereed = supported(white, black, rs);
    let finished = false;
    if (refereed) {
      const start = judge(white, black, [], rs, plusfish);
      finished = start.legal && start.outcome !== "none";
    }
    const paired = await rpcData("referee_quick_pair", {
      p_user: user, p_other: other.user_id, p_white_user: iAmWhite ? user : other.user_id,
      p_finished: finished, p_refereed: refereed,
    });
    if (!("error" in paired) && paired.data) return reply({ game: paired.data });
  }
  return reply({ game: null, waiting: true });
}

// Like rpc(), but hands back the data: {data} or {error}.
async function rpcData(name: string, args: Record<string, unknown>): Promise<{ data?: any; error?: string }> {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, { method: "POST", headers: serverHeaders(), body: JSON.stringify(args) });
  const text = await res.text();
  if (!res.ok) {
    try {
      return { error: JSON.parse(text).message ?? `the server said ${res.status}` };
    } catch {
      return { error: `the server said ${res.status}` };
    }
  }
  return { data: text.trim() === "" ? null : JSON.parse(text) };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return reply({ error: "POST only" }, 405);
  let body: Record<string, any>;
  try {
    body = await req.json();
  } catch {
    return reply({ error: "That request isn't readable." }, 400);
  }
  try {
    if (body.action === "health") {
      return reply({ ok: true, server_key: KEY !== "", rule_sets: Object.keys(RULE_SETS) });
    }
    const user = await caller(req);
    if (!user) return reply({ error: "Please sign in again." }, 401);
    switch (body.action) {
      case "create": return await create(user, body);
      case "join": return await join(user, body);
      case "move": return await move(user, body);
      case "quick": return await quick(user, body);
    }
    return reply({ error: "unknown action" }, 400);
  } catch (e) {
    return reply({ error: `The referee had a problem: ${e instanceof Error ? e.message : e}` }, 500);
  }
});
