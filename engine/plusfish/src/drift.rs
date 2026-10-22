//! `plusfish drift`: how far the starting-position score drifts as a game is
//! played out. Random army pairs are played with Plusfish's top move every
//! turn, and its score is logged at every ply, next to its scores of the start
//! at the eval bar's budgets. The games where the start score and the later
//! scores (or the result) disagree most are where its opening judgement is
//! wrong. `--starts <file>` only re-scores the starts of an earlier run (to
//! compare engines or weights on the same games).

use plusfish_core::army::*;
use plusfish_core::defs::*;
use plusfish_core::eval::*;
use plusfish_core::game::*;
use plusfish_core::json::{quote, Json};
use plusfish_core::position::*;
use plusfish_core::search::*;
use plusfish_core::selfplay::*;
use plusfish_core::util::{Args, Rng};
use std::io::Write;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

pub const HELP: &str = "\
drift: play random army pairs with the top move every turn, logging the score
at every ply and the start's score at the eval bar's budgets (JSON lines).
  --games N          (default 1000)       --nodes N   per move (default 40000)
  --eval-nodes 20000,150000   budgets the start is scored at (fresh search each)
  --seed N  --threads N  --out drift.jsonl  --params <weights>
  --pool <file>      draw each army from this pool file half the time
  --starts <file>    only re-score the starts of an earlier drift file
  --features         also write the start's evaluation terms
";

/// Score of the side to move -> White's view, mates capped at +-3000.
fn white_view(p: &Position, score: i32) -> i32 {
    let s = if score.abs() >= MATE_BOUND { 3000 * score.signum() } else { score };
    if p.side == WHITE {
        s
    } else {
        -s
    }
}

/// Army-cost material on the board, White minus Black (kings excluded).
fn material(p: &Position, r: &Rules) -> f64 {
    let mut m = 0.0;
    for t in 0..2 {
        for s in p.squares(t) {
            let i = &r.info[kind_of(p.sq[s])];
            if !i.is_king {
                m += if t == WHITE { i.cost } else { -i.cost };
            }
        }
    }
    m
}

fn start_scores(cat: &Arc<Catalog>, params: &Params, w: &Army, b: &Army, budgets: &[u64], with_features: bool) -> String {
    let g = army_game(cat, w, b, 8, 8);
    let r = &*g.rules;
    let et = EvalTables::new(r);
    let mut parts = vec![format!("\"static\":{}", white_view(&g.pos, evaluate(&g.pos, r, &et, params)))];
    if with_features {
        // The start's evaluation terms (White minus Black), by name.
        let mut acc = Sparse(Default::default());
        features(&g.pos, r, &et, &mut acc);
        let mut f: Vec<(usize, f32)> = acc.0.into_iter().filter(|(_, v)| *v != 0.0).collect();
        f.sort_by_key(|x| x.0);
        let items: Vec<String> = f.iter().map(|(i, v)| format!("{}:{}", quote(&feature_name(cat, *i)), v)).collect();
        parts.push(format!("\"features\":{{{}}},\"phase\":{}", items.join(","), phase(&g.pos, &et)));
    }
    for &n in budgets {
        let mut s = Searcher::new(r, &et, params, 16);
        // The score after each finished depth too (odd/even depths differ).
        let mut by_depth = Vec::new();
        let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], Limits { depth: None, nodes: Some(n), movetime_ms: None, soft_ms: None }, 1, |rep| {
            by_depth.push(white_view(&g.pos, rep.lines[0].score).to_string())
        });
        let line = &rep.lines[0];
        let best = line.pv.first().map(|&m| move_text(r, m)).unwrap_or_default();
        parts.push(format!(
            "\"{}\":{},\"best{}\":{},\"depth{}\":{},\"bydepth{}\":[{}]",
            n,
            white_view(&g.pos, line.score),
            n,
            quote(&best),
            n,
            rep.depth,
            n,
            by_depth.join(",")
        ));
    }
    format!("{{{}}}", parts.join(","))
}

fn play(cat: &Arc<Catalog>, params: &Params, w: &Army, b: &Army, nodes: u64) -> String {
    let mut g = army_game(cat, w, b, 8, 8);
    let rules = g.rules.clone();
    let r = &*rules;
    let et = EvalTables::new(r);
    let mut s = Searcher::new(r, &et, params, 32);
    let (mut evals, mut mats, mut moves) = (Vec::new(), Vec::new(), Vec::new());
    let mut result = 0.5f32;
    let mut reason = String::from("max_plies");
    let (mut win_streak, mut draw_streak) = (0i32, 0);
    for ply in 0..400 {
        let out = g.outcome();
        if out != Outcome::None {
            reason = outcome_name(out).to_string();
            result = out.white_score(g.pos.side).unwrap_or(0.5) as f32;
            break;
        }
        let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], Limits { depth: None, nodes: Some(nodes), movetime_ms: None, soft_ms: None }, 1, |_| {});
        let line = &rep.lines[0];
        let m = line.pv.first().copied().unwrap_or_else(|| g.pos.legal_moves(r)[0]);
        let ws = white_view(&g.pos, line.score);
        evals.push(ws.to_string());
        mats.push(format!("{}", material(&g.pos, r)));
        moves.push(quote(&move_text(r, m)));
        // Adjudication as in self-play.
        if ws.abs() >= 1000 {
            if ws.signum() == win_streak.signum() || win_streak == 0 {
                win_streak += ws.signum();
            } else {
                win_streak = ws.signum();
            }
        } else {
            win_streak = 0;
        }
        if win_streak.abs() >= 6 {
            result = if win_streak > 0 { 1.0 } else { 0.0 };
            reason = "adjudicated_win".into();
            break;
        }
        draw_streak = if ply >= 120 && ws.abs() <= 15 { draw_streak + 1 } else { 0 };
        if draw_streak >= 24 {
            reason = "adjudicated_draw".into();
            break;
        }
        g.play(m);
    }
    format!(
        "\"evals\":[{}],\"mat\":[{}],\"moves\":[{}],\"result\":{},\"reason\":{}",
        evals.join(","),
        mats.join(","),
        moves.join(","),
        result,
        quote(&reason)
    )
}

pub fn run(cat: &Arc<Catalog>, params: &Params, args: &Args) {
    let nodes: u64 = args.num("nodes", 40_000);
    let budgets: Vec<u64> = args.get("eval-nodes").unwrap_or("20000,150000").split(',').map(|s| s.parse().expect("bad --eval-nodes")).collect();
    let seed: u64 = args.num("seed", 1);
    let threads: usize = args.num("threads", 19);
    let out = args.get("out").unwrap_or("drift.jsonl").to_string();
    // The army pairs: from an earlier file, or random (optionally half from a pool).
    let mut pairs: Vec<(usize, Army, Army)> = Vec::new();
    let only_starts = args.get("starts").is_some();
    let with_features = args.flag("features");
    if let Some(path) = args.get("starts") {
        let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {}", path, e));
        for l in text.lines().filter(|l| !l.trim().is_empty()) {
            let j = Json::parse(l).unwrap_or_else(|e| panic!("{}: {}", path, e));
            let a = |k: &str| Army::from_text(cat, j.get(k).and_then(|v| v.as_str()).unwrap()).unwrap();
            pairs.push((j.get("i").and_then(|v| v.as_f64()).unwrap() as usize, a("white"), a("black")));
        }
    } else {
        let pool: Vec<Army> = args
            .get("pool")
            .map(|p| {
                std::fs::read_to_string(p)
                    .unwrap_or_else(|e| panic!("{}: {}", p, e))
                    .lines()
                    .map(|l| l.trim())
                    .filter(|l| !l.is_empty() && !l.starts_with('#'))
                    .filter_map(|l| Army::from_text(cat, l.split('|').next().unwrap().trim()).ok())
                    .collect()
            })
            .unwrap_or_default();
        let games: usize = args.num("games", 1000);
        for i in 0..games {
            let mut rng = Rng::new(seed.wrapping_mul(1_000_003).wrapping_add(i as u64));
            let (mut w, mut b) = random_pair(cat, &mut rng, (BUDGET, BUDGET));
            if !pool.is_empty() && rng.below(2) == 0 {
                loop {
                    let pw = if rng.below(2) == 0 { pool[rng.below(pool.len())].clone() } else { w.clone() };
                    let pb = if rng.below(2) == 0 { pool[rng.below(pool.len())].clone() } else { b.clone() };
                    if !start_is_broken(&army_game(cat, &pw, &pb, 8, 8)) {
                        (w, b) = (pw, pb);
                        break;
                    }
                }
            }
            pairs.push((i, w, b));
        }
    }
    eprintln!("{} games{}, start scored at {:?} nodes -> {}", pairs.len(), if only_starts { " (starts only)".to_string() } else { format!(", {} nodes per move", nodes) }, budgets, out);
    let file = Mutex::new(std::fs::File::create(&out).unwrap_or_else(|e| panic!("{}: {}", out, e)));
    let next = AtomicUsize::new(0);
    let done = AtomicUsize::new(0);
    let t0 = std::time::Instant::now();
    std::thread::scope(|scope| {
        for _ in 0..threads.max(1) {
            scope.spawn(|| loop {
                let k = next.fetch_add(1, Ordering::SeqCst);
                if k >= pairs.len() {
                    break;
                }
                let (i, w, b) = &pairs[k];
                let start = start_scores(cat, params, w, b, &budgets, with_features);
                let mut line = format!("{{\"i\":{},\"white\":{},\"black\":{},\"start\":{}", i, quote(&w.to_text(cat, 8)), quote(&b.to_text(cat, 8)), start);
                if !only_starts {
                    line += ",";
                    line += &play(cat, params, w, b, nodes);
                }
                line += "}";
                writeln!(file.lock().unwrap(), "{}", line).ok();
                let n = done.fetch_add(1, Ordering::SeqCst) + 1;
                if n % 50 == 0 || n == pairs.len() {
                    let el = t0.elapsed().as_secs_f64();
                    eprintln!("  {}/{}  ({:.2}/s, ~{:.0}s left)", n, pairs.len(), n as f64 / el, (pairs.len() - n) as f64 / (n as f64 / el));
                }
            });
        }
    });
}

/// Tuning positions from drift games: quiet positions in each game's first
/// `--plies` plies, each labelled with White's average win chance over the
/// game's scores `--window` plies later (logistic scale `--k` cp), blended
/// with the result by `--blend`. `--split train|test` keeps games with
/// i % 4 != 0 / == 0.
pub fn samples(cat: &Arc<Catalog>, args: &Args, path: &str) -> Vec<Sample> {
    let max_ply: usize = args.num("plies", 40);
    let (lo, hi) = {
        let w = args.get("window").unwrap_or("16,40");
        let (a, b) = w.split_once(',').expect("--window a,b");
        (a.parse::<usize>().unwrap(), b.parse::<usize>().unwrap())
    };
    let k: f64 = args.num("k", 720.0);
    let blend: f64 = args.num("blend", 0.0);
    let split = args.get("split").unwrap_or("all").to_string();
    let wp = |cp: f64| 1.0 / (1.0 + 10f64.powf(-cp.clamp(-1500.0, 1500.0) / k));
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {}", path, e));
    let mut out = Vec::new();
    for l in text.lines().filter(|l| !l.trim().is_empty()) {
        let j = Json::parse(l).unwrap();
        let i = j.get("i").and_then(|v| v.as_f64()).unwrap() as usize;
        if (split == "train" && i % 4 == 0) || (split == "test" && i % 4 != 0) {
            continue;
        }
        let a = |key: &str| Army::from_text(cat, j.get(key).and_then(|v| v.as_str()).unwrap()).unwrap();
        let mut g = army_game(cat, &a("white"), &a("black"), 8, 8);
        let r = g.rules.clone();
        let et = EvalTables::new(&r);
        let evals: Vec<f64> = j.get("evals").and_then(|v| v.as_arr()).unwrap().iter().map(|v| v.as_f64().unwrap()).collect();
        let moves = j.get("moves").and_then(|v| v.as_arr()).unwrap();
        let result = j.get("result").and_then(|v| v.as_f64()).unwrap();
        for (ply, mv) in moves.iter().enumerate() {
            if ply > max_ply {
                break;
            }
            let m = match find_move(&g.pos, &r, mv.as_str().unwrap()) {
                Some(m) => m,
                None => break,
            };
            if !m.is_tactical() && !g.pos.in_check(&r, g.pos.side) {
                let win: Vec<f64> = evals.iter().skip(ply + lo).take(hi + 1 - lo).map(|&c| wp(c)).collect();
                let later = if win.is_empty() { result } else { win.iter().sum::<f64>() / win.len() as f64 };
                let mut acc = Sparse(Default::default());
                features(&g.pos, &r, &et, &mut acc);
                let mut f: Vec<(u16, f32)> = acc.0.into_iter().filter(|(_, v)| *v != 0.0).map(|(k, v)| (k as u16, v)).collect();
                f.sort_by_key(|x| x.0);
                out.push(Sample { feats: f, phase: phase(&g.pos, &et), result: ((1.0 - blend) * later + blend * result) as f32 });
            }
            g.play(m);
        }
    }
    out
}
