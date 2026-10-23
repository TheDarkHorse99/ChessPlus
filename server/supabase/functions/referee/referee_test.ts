// The referee's tests: it must agree with the game itself on the cases
// tools/make_rule_set.gd wrote (army problems, starting positions, whole
// games and how they end). Run (from the project folder):
//   C:\Tools\deno\deno.exe test --allow-read server/supabase/functions/referee/referee_test.ts

import { armyProblems, judge, startPosition, supported } from "./referee.ts";
import type { ArmyData } from "./referee.ts";
import { loadPlusfish } from "./plusfish.ts";
import { RULE_SETS } from "./rules.ts";
import cases from "./test_cases.json" with { type: "json" };

const here = new URL(".", import.meta.url);
const plusfish = await loadPlusfish(await Deno.readFile(new URL("../../../../web/plusfish.wasm", here)));
const rs = RULE_SETS[cases.version];

function check(ok: boolean, what: string): void {
  if (!ok) throw new Error(what);
}

// JSON with object keys sorted, so the order fields are listed in doesn't matter.
function canonical(value: unknown): string {
  return JSON.stringify(value, (_key, v) =>
    v && typeof v === "object" && !Array.isArray(v)
      ? Object.fromEntries(Object.entries(v).sort(([a], [b]) => a.localeCompare(b)))
      : v);
}

function same(a: unknown, b: unknown, what: string): void {
  const x = canonical(a), y = canonical(b);
  if (x !== y) throw new Error(`${what}\n  got:      ${x}\n  expected: ${y}`);
}

Deno.test("the rule set of the test cases is known", () => {
  check(rs !== undefined, `rule set ${cases.version} missing from rules.ts`);
});

Deno.test("army problems match the game's", () => {
  for (const game of cases.games) {
    same(armyProblems(game.white, rs), game.white_problems, "White's army problems");
    same(armyProblems(game.black, rs), game.black_problems, "Black's army problems");
  }
  for (const broken of cases.broken) {
    same(armyProblems(broken.army, rs), broken.problems, "a broken army's problems");
  }
});

Deno.test("a cheat's armies are refused", () => {
  check(armyProblems({ pieces: [["werewolf_wolf", 3, 0], ["king", 4, 0]] }, rs).length > 0, "the wolf form can't be bought");
  check(armyProblems({ pieces: [["dragon", 3, 0]] }, rs).length > 0, "an unknown piece");
  check(armyProblems({ pieces: "lots" }, rs).length > 0, "not an army at all");
  check(armyProblems({ pieces: [["king", 4.5, 0]] }, rs).length > 0, "a piece between squares");
});

Deno.test("starting positions match the game's", () => {
  for (const game of cases.games) {
    const ours = startPosition(game.white as ArmyData, game.black as ArmyData, rs);
    const theirs = game.start as Record<string, unknown>;
    // Promotion choices: the same pieces (equal values may be listed in either order).
    same([...(ours.promo as string[])].sort(), [...(theirs.promo as string[])].sort(), "promotion choices");
    same({ ...ours, promo: [] }, { ...theirs, promo: [] }, "starting position");
    same(supported(game.white as ArmyData, game.black as ArmyData, rs), game.supported, "Plusfish knows these armies");
  }
});

Deno.test("whole games: every move legal, and the same ending", () => {
  for (const game of cases.games) {
    if (!game.supported) continue;
    const result = judge(game.white as ArmyData, game.black as ArmyData, game.moves, rs, plusfish);
    check(result.legal, `a legal game was refused: ${result.error}`);
    same(result.outcome, game.outcome, `the game's ending after ${game.moves.length} moves`);
  }
});

Deno.test("the attacker chooses which Jester takes the hit", () => {
  // The short game in tools/make_rule_set.gd: the Wizard on b1 takes on b8,
  // where Black's Jesters on a8 and c8 could both take the hit.
  const game = cases.games.find((g) => g.moves.includes("b1xb8/a8"));
  check(game !== undefined && game.supported, "a game with two Jesters on a side is refereed");
  const white = game!.white as ArmyData, black = game!.black as ArmyData;
  check(judge(white, black, ["b1xb8/c8"], rs, plusfish).legal, "the other Jester may take it instead");
  check(!judge(white, black, ["b1xb8/d8"], rs, plusfish).legal, "but not a square without a Jester");
});

Deno.test("illegal moves are refused", () => {
  const game = cases.games[0];
  const white = game.white as ArmyData, black = game.black as ArmyData;
  check(!judge(white, black, ["e2-e5"], rs, plusfish).legal, "a pawn can't jump 3 squares");
  check(!judge(white, black, ["e7-e5"], rs, plusfish).legal, "White can't move Black's pawn");
  check(!judge(white, black, ["e2-e4", "e7-e5", "d1-d8"], rs, plusfish).legal, "a queen can't pass through pieces");
  check(!judge(white, black, ["nonsense"], rs, plusfish).legal, "nonsense isn't a move");
  check(judge(white, black, ["e2-e4"], rs, plusfish).legal, "e4 is fine");
});
