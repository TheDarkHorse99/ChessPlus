//! Checking Plusfish's rules against the game's own GDScript engine: perft on
//! known positions, and replaying random games traced by the game itself
//! (`verify/plusfish_trace.gd`), comparing every position's FEN, legal moves,
//! check and outcome.

use crate::army::*;
use crate::defs::*;
use crate::game::*;
use crate::json::Json;
use crate::position::*;
use crate::util::Rng;
use std::sync::Arc;

/// Known perft counts (standard chess) from the Chess Programming Wiki, the
/// same ones the game's perft_test.gd checks.
pub const PERFT_SUITE: &[(&str, &[u64])] = &[
    (STANDARD_FEN, &[20, 400, 8902, 197281, 4865609]),
    ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", &[48, 2039, 97862, 4085603]),
    ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", &[14, 191, 2812, 43238, 674624]),
    ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", &[6, 264, 9467, 422333]),
    ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", &[44, 1486, 62379, 2103487]),
];

pub fn run_perft_suite(cat: &Arc<Catalog>) -> bool {
    let mut ok = true;
    for (fen, counts) in PERFT_SUITE {
        let g = game_from_fen(cat, fen, None).expect("bad suite FEN");
        for (d, &want) in counts.iter().enumerate() {
            let t = std::time::Instant::now();
            let got = perft(&g.pos, &g.rules, d as u32 + 1);
            let pass = got == want;
            ok &= pass;
            println!(
                "{} depth {}: {} (expected {}) {:.2}s{}",
                if pass { "PASS" } else { "FAIL" },
                d + 1,
                got,
                want,
                t.elapsed().as_secs_f64(),
                if d == 0 { format!("  {}", fen) } else { String::new() }
            );
        }
    }
    ok
}

fn army_line(cat: &Catalog, a: &Army) -> String {
    a.pieces.iter().map(|p| format!("{}@{},{}", cat.defs[p.0].id, p.1, p.2)).collect::<Vec<_>>().join(";")
}

/// Writes random army pairs for the GDScript tracer. With `favor` (piece
/// kinds), each army holds at least two of them where it can, so their rules
/// get exercised.
pub fn write_trace_games(cat: &Catalog, count: usize, seed: u64, plies: usize, favor: &[usize]) -> String {
    let mut rng = Rng::new(seed);
    let mut out = String::new();
    let army = |rng: &mut Rng| {
        let mut a = random_army(cat, rng);
        for _ in 0..300 {
            if favor.is_empty() || a.pieces.iter().filter(|p| favor.contains(&p.0)).count() >= 2 {
                break;
            }
            a = random_army(cat, rng);
        }
        a
    };
    for i in 0..count {
        let w = army(&mut rng);
        let b = if i % 5 == 0 { w.clone() } else { army(&mut rng) };
        out += &format!("{}|{}|{}|{}\n", army_line(cat, &w), army_line(cat, &b), seed * 1000 + i as u64, plies);
    }
    out
}

fn parse_army_line(cat: &Catalog, s: &str) -> Army {
    let mut pieces = Vec::new();
    for item in s.split(';').filter(|x| !x.is_empty()) {
        let (id, sq) = item.split_once('@').unwrap();
        let (f, r) = sq.split_once(',').unwrap();
        pieces.push((cat.kind_by_id(id).unwrap(), f.parse().unwrap(), r.parse().unwrap()));
    }
    // The game's tracer builds a plain Army, which is mirrored for Black.
    Army { name: String::new(), pieces, mirror: true }
}

fn outcome_code(o: Outcome) -> i64 {
    match o {
        Outcome::None => 0,
        Outcome::Checkmate => 1,
        Outcome::Stalemate => 2,
        Outcome::FiftyMoves => 3,
        Outcome::Repetition => 4,
        Outcome::Insufficient => 5,
        Outcome::KingExposed => 6,
    }
}

/// Replays the traced games; returns (positions checked, mismatches).
pub fn check_trace(cat: &Arc<Catalog>, games_text: &str, trace_text: &str, max_report: usize) -> (usize, usize) {
    let games: Vec<(Army, Army)> = games_text
        .lines()
        .filter(|l| !l.trim().is_empty())
        .map(|l| {
            let p: Vec<&str> = l.split('|').collect();
            (parse_army_line(cat, p[0]), parse_army_line(cat, p[1]))
        })
        .collect();
    let mut checked = 0;
    let mut bad = 0;
    let mut current: Option<(usize, Game)> = None;
    let mut skip_game = usize::MAX;
    let mut cover = Coverage::default();
    for line in trace_text.lines() {
        if line.trim().is_empty() {
            continue;
        }
        let rec = match Json::parse(line) {
            Ok(r) => r,
            Err(e) => {
                println!("bad trace line: {}", e);
                continue;
            }
        };
        let gi = rec.get("g").and_then(|v| v.as_f64()).unwrap() as usize;
        if gi == skip_game {
            continue;
        }
        if current.as_ref().map(|c| c.0) != Some(gi) {
            let (w, b) = &games[gi];
            current = Some((gi, army_game(cat, w, b, 8, 8)));
        }
        let (_, game) = current.as_mut().unwrap();
        let ply = rec.get("ply").and_then(|v| v.as_f64()).unwrap() as usize;
        let r = game.rules.clone();
        let mut problems = Vec::new();
        let want_fen = rec.get("fen").and_then(|v| v.as_str()).unwrap();
        let got_fen = fen(&game.pos, &r, false);
        if want_fen != got_fen {
            problems.push(format!("FEN differs:\n  game:     {}\n  plusfish: {}", want_fen, got_fen));
        }
        let want: Vec<String> = rec.get("moves").and_then(|v| v.as_arr()).unwrap().iter().map(|m| m.as_str().unwrap().to_string()).collect();
        let mut got: Vec<String> = game.pos.legal_moves(&r).into_iter().map(|m| move_text(&r, m)).collect();
        got.sort();
        if want != got {
            let missing: Vec<_> = want.iter().filter(|m| !got.contains(m)).collect();
            let extra: Vec<_> = got.iter().filter(|m| !want.contains(m)).collect();
            problems.push(format!("moves differ: missing {:?}, extra {:?} (counts {} vs {})", missing, extra, want.len(), got.len()));
        }
        let want_check = rec.get("check").and_then(|v| v.as_bool()).unwrap();
        if want_check != game.pos.in_check(&r, game.pos.side) {
            problems.push(format!("check differs: game says {}", want_check));
        }
        let want_out = rec.get("outcome").and_then(|v| v.as_f64()).unwrap() as i64;
        let got_out = outcome_code(game.outcome());
        if want_out != got_out {
            problems.push(format!("outcome differs: game {} plusfish {}", want_out, got_out));
        }
        checked += 1;
        if !problems.is_empty() {
            bad += 1;
            if bad <= max_report {
                println!("game {} ply {}: {}", gi, ply, want_fen);
                for p in &problems {
                    println!("  {}", p);
                }
                println!("  moves so far: {}", game.moves.iter().map(|&m| move_text(&r, m)).collect::<Vec<_>>().join(" "));
            }
            skip_game = gi;
            continue;
        }
        cover.position(&game.pos, &r, game.outcome());
        if let Some(played) = rec.get("played").and_then(|v| v.as_str()) {
            let before = game.pos.clone();
            match game.play_text(played) {
                Ok(m) => cover.played(&before, &r, m),
                Err(_) => {
                    println!("game {} ply {}: can't play {}", gi, ply, played);
                    bad += 1;
                    skip_game = gi;
                }
            }
        }
    }
    cover.report();
    (checked, bad)
}

fn bits128(mut b: u128) -> impl Iterator<Item = usize> {
    std::iter::from_fn(move || {
        if b == 0 {
            return None;
        }
        let s = b.trailing_zeros() as usize;
        b &= b - 1;
        Some(s)
    })
}

/// What a trace exercised, so a clean check can be trusted.
#[derive(Default)]
struct Coverage {
    counts: std::collections::BTreeMap<&'static str, usize>,
}

impl Coverage {
    fn add(&mut self, what: &'static str) {
        *self.counts.entry(what).or_insert(0) += 1;
    }

    fn position(&mut self, p: &Position, r: &Rules, out: Outcome) {
        let mut legal = p.legal_moves(r);
        if p.frozen != NO_SQ {
            self.add("positions with a sleeping piece");
        }
        if r.parapets != 0 && p.squares(0).chain(p.squares(1)).any(|s| r.is_parapet(p.sq[s])) {
            self.add("positions with a Parapet");
            // Would a leap be possible if the Parapets weren't there?
            let mut bare = p.clone();
            for s in p.squares(0).chain(p.squares(1)).collect::<Vec<_>>() {
                if r.is_parapet(p.sq[s]) {
                    let c = bare.remove(r, s);
                    // Keep the square taken (by a plain piece of the same team)
                    // so only the leaping rule differs.
                    bare.put(r, s, code(r.info.iter().position(|i| i.is_pawn).unwrap_or(0), team_of(c)) | MOVED);
                }
            }
            let mut wider = bare.legal_moves(r);
            wider.retain(|m| !legal.contains(m));
            if !wider.is_empty() {
                self.add("positions where a Parapet stopped a leap or screen");
            }
        }
        if r.guards != 0 {
            let mut all = Vec::new();
            p.gen_pseudo(r, &mut all, GEN_ALL);
            if all.iter().any(|m| m.flags & F_DECOY != 0) {
                self.add("positions offering a Jester swap");
            }
            // A Squire's protected piece that the side to move attacks.
            let them = 1 - p.side;
            let shielded_by_squire = p.squares(them).any(|s| {
                let c = p.sq[s];
                let prot = r.info[kind_of(c)].protects;
                prot != 0 && bits128(p.pattern(r, s, c) & p.occ[them]).any(|q| prot & (1u64 << kind_of(p.sq[q])) != 0 && p.attacked(r, q, p.side))
            });
            if shielded_by_squire {
                self.add("positions where a Squire protects an attacked piece");
            }
            // ...one it couldn't move to (pieces in between: Mac's Oct 2026 rule).
            let through = p.squares(them).any(|s| {
                let c = p.sq[s];
                let prot = r.info[kind_of(c)].protects;
                prot != 0 && bits128(p.pattern(r, s, c) & !p.reach(r, s, c) & p.occ[them]).any(|q| prot & (1u64 << kind_of(p.sq[q])) != 0 && p.attacked(r, q, p.side))
            });
            if through {
                self.add("...with a piece in the Squire's way");
            }
        }
        legal.retain(|m| m.flags & F_HAUNT != 0);
        if !legal.is_empty() {
            self.add("positions offering Haunt");
        }
        if out == Outcome::KingExposed {
            self.add("games ending with the king exposed at the start");
        }
    }

    fn played(&mut self, before: &Position, r: &Rules, m: Move) {
        let f = m.flags;
        if f & F_HAUNT != 0 {
            self.add("played: Haunt");
        }
        if f & F_SONG != 0 {
            self.add("played: Song of Slumber");
        }
        if f & F_MOON != 0 {
            self.add("played: Full Moon");
        }
        if f & F_RAISE != 0 {
            self.add("played: Raise Dead");
        }
        if f & F_CRACK != 0 {
            self.add("played: Crack Shot");
        }
        if f & F_DECOY != 0 {
            self.add("played: Jester swap");
        }
        if f & F_SHIELD != 0 && before.sq[m.to as usize] & GAINED != 0 {
            self.add("played: gained shield broken");
        }
        if f & F_CAPTURE != 0 && r.info[kind_of(before.sq[m.from as usize])].gains_shield && !r.shielded(before.sq[m.from as usize]) {
            self.add("played: Vampire gains a shield");
        }
    }

    fn report(&self) {
        for (what, n) in &self.counts {
            println!("  {:<55} {}", what, n);
        }
    }
}

/// One JSON line per game of a saved game file (`selfplay` / `match --out`):
/// White's first move, its kind, the piece that made it, the piece it hit,
/// whether the move gave check, whether Black could then capture (or break the
/// shield of) the mover where it stood ("recapturable"), and whether Black's
/// actual reply did ("recaptured"). `stands` is false when the mover left the
/// board itself (a Ram). Balance run 14's move-1 tally.
pub fn first_move_facts(cat: &Arc<Catalog>, label: &str, games_text: &str) -> String {
    let q = crate::json::quote;
    let games = crate::report::read_games(cat, games_text);
    let mut out = String::new();
    for (i, sg) in games.iter().enumerate() {
        let mut g = army_game(cat, &sg.white, &sg.black, 8, 8);
        let r = g.rules.clone();
        let mut kind = "none";
        let (mut first, mut mover, mut target) = (String::new(), String::new(), String::new());
        let (mut check, mut recapturable, mut recaptured, mut stands) = (false, false, false, false);
        if let Some(text) = sg.moves.first() {
            if let Some(m) = find_move(&g.pos, &r, text) {
                first = text.clone();
                let from = m.from as usize;
                let mover_kind = if m.flags & F_HAUNT != 0 { m.extra as usize } else { kind_of(g.pos.sq[from]) };
                mover = cat.defs[mover_kind].id.clone();
                kind = if m.flags & F_ABILITY != 0 {
                    "ability"
                } else if m.flags & F_SHIELD != 0 {
                    "shield"
                } else if m.is_capture() {
                    "capture"
                } else {
                    "quiet"
                };
                let target_sq = if m.flags & F_DECOY != 0 {
                    Some(m.extra as usize)
                } else if m.flags & F_SONG != 0 {
                    Some(m.to as usize)
                } else if m.is_capture() || m.flags & F_SHIELD != 0 {
                    Some(m.capture_square() as usize)
                } else {
                    None
                };
                if let Some(s) = target_sq {
                    let c = g.pos.sq[s];
                    if c != 0 {
                        target = cat.defs[kind_of(c)].id.clone();
                    }
                }
                if m.flags & F_RAISE != 0 {
                    target = cat.defs[m.extra as usize].id.clone();
                }
                // Where the mover stands afterwards: abilities and shield breaks leave it put.
                let at = if m.flags & (F_ABILITY | F_SHIELD) != 0 { from } else { m.to as usize };
                g.play(m);
                check = g.pos.in_check(&r, g.pos.side);
                stands = g.pos.sq[at] != 0 && team_of(g.pos.sq[at]) == WHITE;
                let hits = |mm: &Move| (mm.is_capture() && mm.capture_square() as usize == at) || (mm.flags & F_SHIELD != 0 && mm.to as usize == at);
                if stands {
                    recapturable = g.pos.legal_moves(&r).iter().any(|mm| hits(mm));
                    if let Some(reply) = sg.moves.get(1) {
                        if let Some(rm) = find_move(&g.pos, &r, reply) {
                            recaptured = hits(&rm);
                        }
                    }
                }
            }
        }
        out += &format!(
            "{{\"file\":{},\"i\":{},\"result\":{},\"kind\":\"{}\",\"move\":{},\"mover\":{},\"target\":{},\"check\":{},\"stands\":{},\"recapturable\":{},\"recaptured\":{}}}\n",
            q(label), i, sg.result, kind, q(&first), q(&mover), q(&target), check, stands, recapturable, recaptured
        );
    }
    out
}
