// The referee's rules work, with no network: checking armies, building the
// starting position, and asking Plusfish whether moves are legal and how the
// game stands. index.ts does the web part. Everything here copies the game
// (core/army.gd, core/army_setup.gd, scenes/game/plusfish_link.gd) and is
// checked against it by referee_test.ts.

// A rule set (scenes/online/rule_set.gd, written by tools/make_rule_set.gd).
export interface PieceData {
  id: string;
  name: string;
  symbol: string;
  value: number;
  types: number; // 1 King, 2 Royal, 4 Pawn
  ability: number;
  decoy: boolean;
  [key: string]: unknown;
}
export interface RuleSetData {
  pieces: PieceData[];
  buyable: string[];
  width: number;
  height: number;
  budget: number;
  start_rows: number;
  max_copies: number;
  max_extra_royals: number;
  castling_corner: boolean;
  known_abilities: number;
}

// An army as the game sends it (SavedGame.army_to_dict).
export interface ArmyData {
  name?: string;
  pieces: [string, number, number][]; // [piece id, file, row from the owner's edge]
  mirror?: boolean;
}

const KING = 1, ROYAL = 2, PAWN = 4;

// What runs Plusfish: a request (as api.rs reads it) in, its reply lines out.
export type PlusfishRunner = (request: Record<string, unknown>) => string[];

function pieceById(rs: RuleSetData): Map<string, PieceData> {
  return new Map(rs.pieces.map((p) => [p.id, p]));
}

// 39.0 -> "39", 44.5 -> "44.5" (Army.format_points).
function points(value: number): string {
  return Number.isInteger(value) ? String(value) : String(value);
}

// The most of a piece type an army may have, -1 = no limit (Army.max_copies).
function maxCopies(p: PieceData, rs: RuleSetData): number {
  if (p.types & KING) return 1;
  if (p.types & PAWN) return -1;
  if (p.types & ROYAL) return Math.min(rs.max_extra_royals, rs.max_copies);
  return rs.max_copies;
}

// The files the king may start on (Army.king_files).
function kingFiles(width: number): number[] {
  return width % 2 === 1 ? [Math.floor(width / 2)] : [width / 2 - 1, width / 2];
}

// Everything wrong with an army, in the game's own words (Army.problems), plus
// what only a cheat could send (unknown or unbuyable pieces, a broken shape).
export function armyProblems(army: unknown, rs: RuleSetData): string[] {
  const a = army as ArmyData;
  if (!a || typeof a !== "object" || !Array.isArray(a.pieces) || a.pieces.length > 64) {
    return ["That isn't an army."];
  }
  const byId = pieceById(rs);
  const pieces: { def: PieceData; file: number; row: number }[] = [];
  for (const entry of a.pieces) {
    if (!Array.isArray(entry) || entry.length !== 3 || typeof entry[0] !== "string" ||
        !Number.isInteger(entry[1]) || !Number.isInteger(entry[2])) {
      return ["That isn't an army."];
    }
    const def = byId.get(entry[0]);
    if (!def || !rs.buyable.includes(entry[0])) {
      return [`An army can't have a piece called "${entry[0]}".`];
    }
    pieces.push({ def, file: entry[1], row: entry[2] });
  }
  const found: string[] = [];
  const cost = pieces.reduce((sum, p) => sum + p.def.value, 0);
  if (cost > rs.budget) {
    found.push(`Costs ${points(cost)} points; the budget is ${points(rs.budget)}.`);
  }
  const kings = pieces.filter((p) => p.def.types & KING);
  if (kings.length === 0) found.push("Needs a king.");
  for (const king of kings) {
    if (king.row !== 0 || !kingFiles(rs.width).includes(king.file)) {
      found.push("The king must start in the middle of the back row.");
    }
  }
  const extraRoyals = pieces.filter((p) => (p.def.types & ROYAL) && !(p.def.types & KING)).length;
  if (extraRoyals > rs.max_extra_royals) {
    found.push(`Too many royal pieces: ${extraRoyals} besides the king (the most is ${rs.max_extra_royals}).`);
  }
  const checked = new Set<string>();
  for (const p of pieces) {
    if (checked.has(p.def.id)) continue;
    checked.add(p.def.id);
    const limit = maxCopies(p.def, rs);
    const count = pieces.filter((q) => q.def.id === p.def.id).length;
    const royalOnly = (p.def.types & ROYAL) && !(p.def.types & KING);
    if (limit >= 0 && count > limit && !royalOnly) {
      found.push(`Too many ${p.def.name.toLowerCase()}s: ${count} (the most is ${limit}).`);
    }
  }
  const used = new Set<string>();
  for (const p of pieces) {
    if (p.file < 0 || p.file >= rs.width || p.row < 0 || p.row >= rs.start_rows) {
      found.push(`A ${p.def.name.toLowerCase()} is outside the starting rows.`);
    } else if (used.has(`${p.file},${p.row}`)) {
      found.push("Two pieces share a square.");
    }
    used.add(`${p.file},${p.row}`);
  }
  return found;
}

// The starting position Plusfish is given (PlusfishLink.position_for of
// ArmySetup.create_game): White as built, Black turned round (files mirrored
// too unless the army says not to). Both armies must be legal already.
export function startPosition(white: ArmyData, black: ArmyData, rs: RuleSetData): Record<string, unknown> {
  const byId = pieceById(rs);
  const grid = new Map<number, [string, number]>();
  for (const [id, file, row] of white.pieces) grid.set(row * rs.width + file, [id, 0]);
  for (const [id, file, row] of black.pieces) {
    const f = black.mirror ? rs.width - 1 - file : file;
    grid.set((rs.height - 1 - row) * rs.width + f, [id, 1]);
  }
  const board: unknown[] = [];
  const promo: string[] = [];
  for (let rank = 0; rank < rs.height; rank++) {
    for (let file = 0; file < rs.width; file++) {
      const here = grid.get(rank * rs.width + file);
      if (!here) continue;
      board.push([here[0], here[1], file, rank, false, false, false, false]);
      const def = byId.get(here[0])!;
      if (!(def.types & KING) && !(def.types & PAWN) && !promo.includes(def.id)) promo.push(def.id);
    }
  }
  // Most valuable first (ArmySetup.promotion_options_for).
  promo.sort((a, b) => byId.get(b)!.value - byId.get(a)!.value);
  return {
    width: rs.width, height: rs.height, board, side: 0, halfmove: 0, fullmove: 1,
    ep: [], ep_victim: null, lost: [], promo, castling_corner: rs.castling_corner,
  };
}

// Whether Plusfish knows every rule these armies use (PlusfishLink.supports):
// no special ability newer than it knows.
export function supported(white: ArmyData, black: ArmyData, rs: RuleSetData): boolean {
  const byId = pieceById(rs);
  for (const army of [white, black]) {
    for (const [id] of army.pieces) {
      if (byId.get(id)!.ability > rs.known_abilities) return false;
    }
  }
  return true;
}

// Plays `moves` (Move.to_text()) from the start and says how the game stands:
// {legal: true, outcome: "none" | "checkmate" | ...} or {legal: false, error}.
export function judge(white: ArmyData, black: ArmyData, moves: string[], rs: RuleSetData,
    plusfish: PlusfishRunner): { legal: boolean; outcome?: string; error?: string } {
  const request = {
    ...startPosition(white, black, rs), pieces: rs.pieces, moves,
    plies: [moves.length], nodes: 1, depth: 1, hash_mb: 1,
  };
  const lines = plusfish(request);
  if (lines.length === 0) return { legal: false, error: "Plusfish gave no answer" };
  const reply = JSON.parse(lines[0]);
  if (reply.error) return { legal: false, error: String(reply.error) };
  return { legal: true, outcome: String(reply.outcome) };
}
