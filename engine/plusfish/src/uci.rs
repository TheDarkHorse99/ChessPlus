//! A UCI-style text protocol, so a GUI or the game itself can drive the engine:
//!
//!   uci / isready / ucinewgame / quit
//!   setoption name Hash value <MB>   |   setoption name MultiPV value <n>
//!   setoption name <search constant> value <n>    (SearchParams, for tuning)
//!   position startpos [moves ...]                 (standard chess)
//!   position army <white army> <black army> [moves ...]
//!   position fen <fen ...> [moves ...]
//!   go [depth N] [nodes N] [movetime ms] [wtime ms btime ms] [infinite]
//!   stop
//!   eval      (static evaluation, with the biggest terms)
//!   d         (show the board, FEN and legal moves)
//!
//! Moves use the game's move text ("e2-e4", "e7-e8=Q", "a1!c3", "d2!=Q");
//! SAN ("Nf3") is accepted too.

use crate::army::*;
use crate::defs::*;
use crate::eval::*;
use crate::game::*;
use crate::search::*;
use std::io::{BufRead, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

pub fn run(cat: Arc<Catalog>, params: Arc<Params>) {
    let stdin = std::io::stdin();
    let mut game = army_game(&cat, &standard(&cat), &standard(&cat), 8, 8);
    let mut hash_mb = 64usize;
    let mut multipv = 1usize;
    let mut threads = 1usize;
    let mut sp = SearchParams::default();
    let stop = Arc::new(AtomicBool::new(false));
    let mut worker: Option<std::thread::JoinHandle<Option<SearchTables>>> = None;
    // The last "position" setup (everything before "moves"), its game before
    // any moves and its evaluation tables, so a game's next position is cheap.
    let mut base: Option<(Vec<String>, Game, Arc<EvalTables>)> = None;
    // Hash table and history, kept between moves of one game.
    let mut tables: Option<SearchTables> = None;
    let out = Arc::new(Mutex::new(()));
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        let words: Vec<&str> = line.split_whitespace().collect();
        if words.is_empty() {
            continue;
        }
        let say = |s: String| {
            let _g = out.lock().unwrap();
            println!("{}", s);
            std::io::stdout().flush().ok();
        };
        match words[0] {
            "uci" => {
                say("id name Plusfish 0.1".into());
                say("id author Plusfish for Chess Plus".into());
                say("option name Hash type spin default 64 min 1 max 4096".into());
                say("option name MultiPV type spin default 1 min 1 max 32".into());
                say("option name Threads type spin default 1 min 1 max 256".into());
                for s in SEARCH_PARAM_SPECS {
                    say(format!("option name {} type spin default {} min {} max {}", s.name, s.default, s.min, s.max));
                }
                say("uciok".into());
            }
            "isready" => say("readyok".into()),
            "ucinewgame" => {
                if let Some(w) = worker.take() {
                    stop.store(true, Ordering::SeqCst);
                    w.join().ok();
                }
                tables = None;
            }
            "setoption" => {
                let name = words.iter().position(|&w| w == "name").and_then(|i| words.get(i + 1)).map(|s| s.to_lowercase());
                let value = words.iter().position(|&w| w == "value").and_then(|i| words.get(i + 1)).and_then(|v| v.parse::<usize>().ok());
                match (name.as_deref(), value) {
                    (Some("hash"), Some(v)) => {
                        hash_mb = v;
                        tables = None;
                    }
                    (Some("multipv"), Some(v)) => multipv = v.max(1),
                    (Some("threads"), Some(v)) => threads = v.max(1),
                    (Some(n), _) if sp.get(n).is_some() => {
                        let v = words.iter().position(|&w| w == "value").and_then(|i| words.get(i + 1)).and_then(|v| v.parse::<i32>().ok());
                        match v {
                            Some(v) => {
                                sp.set(n, v);
                            }
                            None => say("info string bad value".into()),
                        }
                    }
                    _ => say("info string unknown option".into()),
                }
            }
            "position" => {
                let mi = words.iter().position(|&w| w == "moves");
                let head = &words[1..mi.unwrap_or(words.len())];
                let head_key: Vec<String> = head.iter().map(|w| w.to_string()).collect();
                let cached = base.as_ref().filter(|b| b.0 == head_key).map(|b| b.1.clone());
                let built = match cached {
                    Some(g) => Ok(g),
                    None => match head.first().copied() {
                        Some("startpos") => game_from_fen(&cat, STANDARD_FEN, None),
                        Some("fen") => game_from_fen(&cat, &head[1..].join(" "), None),
                        Some("army") if head.len() >= 3 => {
                            let mut rng = crate::util::Rng::from_time();
                            match (parse_army(&cat, head[1], &mut rng), parse_army(&cat, head[2], &mut rng)) {
                                (Ok(w), Ok(b)) => Ok(army_game(&cat, &w, &b, 8, 8)),
                                (Err(e), _) | (_, Err(e)) => Err(e),
                            }
                        }
                        _ => Err("expected startpos, fen or army".into()),
                    }
                    .map(|g| {
                        // A new setup: new rules, so the old tables don't fit.
                        let et = Arc::new(EvalTables::new(&g.rules));
                        base = Some((head_key.clone(), g.clone(), et));
                        tables = None;
                        g
                    }),
                };
                match built {
                    Ok(mut g) => {
                        if let Some(i) = mi {
                            for mv in &words[i + 1..] {
                                if let Err(e) = g.play_text(mv) {
                                    say(format!("info string {}", e));
                                    break;
                                }
                            }
                        }
                        game = g;
                    }
                    Err(e) => say(format!("info string {}", e)),
                }
            }
            "d" => {
                let r = &game.rules;
                say(board_text(&game.pos, r));
                say(format!("fen {}", fen(&game.pos, r, true)));
                let moves: Vec<String> = game.pos.legal_moves(r).into_iter().map(|m| move_text(r, m)).collect();
                say(format!("legal {}", moves.join(" ")));
                say(format!("outcome {}", outcome_name(game.outcome())));
            }
            "eval" => {
                let r = &game.rules;
                let et = EvalTables::new(r);
                say(eval_breakdown(&game, &et, &params));
                say(format!("eval {} (side to move)", score_text(evaluate(&game.pos, r, &et, &params))));
            }
            "go" => {
                if let Some(w) = worker.take() {
                    stop.store(true, Ordering::SeqCst);
                    w.join().ok();
                }
                stop.store(false, Ordering::SeqCst);
                let num = |key: &str| words.iter().position(|&w| w == key).and_then(|i| words.get(i + 1)).and_then(|v| v.parse::<u64>().ok());
                let mut limits = Limits { depth: num("depth").map(|d| d as i32), nodes: num("nodes"), movetime_ms: num("movetime"), soft_ms: None };
                let my_time = if game.pos.side == 0 { num("wtime") } else { num("btime") };
                let my_inc = if game.pos.side == 0 { num("winc") } else { num("binc") };
                if let Some(t) = my_time {
                    let (soft, hard) = time_for_move(t, my_inc.unwrap_or(0));
                    limits.movetime_ms = Some(hard);
                    limits.soft_ms = Some(soft);
                }
                let infinite = words.contains(&"infinite");
                if !infinite && limits.depth.is_none() && limits.nodes.is_none() && limits.movetime_ms.is_none() {
                    limits.movetime_ms = Some(2000);
                }
                let g = game.clone();
                let params = params.clone();
                let stop2 = stop.clone();
                let out2 = out.clone();
                let mpv = multipv;
                let mb = hash_mb;
                let nthreads = threads;
                let sp2 = sp;
                let et = match &base {
                    Some(b) if Arc::ptr_eq(&b.1.rules, &g.rules) => b.2.clone(),
                    _ => Arc::new(EvalTables::new(&g.rules)),
                };
                let old_tables = tables.take();
                worker = Some(std::thread::spawn(move || {
                    let r = &*g.rules;
                    let et = &*et;
                    let mut s = match old_tables {
                        Some(t) => Searcher::with_tables(r, et, &params, t),
                        None => Searcher::new(r, et, &params, mb),
                    };
                    s.stop = stop2;
                    s.sp = sp2;
                    let keys = &g.keys[..g.keys.len() - 1];
                    let rep = s.search_threads(&g.pos, keys, limits, mpv, nthreads, |rep| {
                        let _l = out2.lock().unwrap();
                        for (i, line) in rep.lines.iter().enumerate() {
                            let nps = if rep.ms > 0 { rep.nodes * 1000 / rep.ms } else { 0 };
                            println!(
                                "info depth {} seldepth {} multipv {} score {} nodes {} nps {} time {} pv {}",
                                rep.depth,
                                rep.seldepth,
                                i + 1,
                                score_uci(line.score),
                                rep.nodes,
                                nps,
                                rep.ms,
                                line.pv.iter().map(|&m| move_text(r, m)).collect::<Vec<_>>().join(" ")
                            );
                        }
                        std::io::stdout().flush().ok();
                    });
                    let _l = out2.lock().unwrap();
                    match rep.lines.first().and_then(|l| l.pv.first()) {
                        Some(&m) => println!("bestmove {}", move_text(r, m)),
                        None => println!("bestmove (none)"),
                    }
                    std::io::stdout().flush().ok();
                    Some(s.into_tables())
                }));
                if !infinite {
                    // Synchronous unless "infinite": simpler for scripts.
                    if let Some(w) = worker.take() {
                        tables = w.join().ok().flatten();
                    }
                }
            }
            "stop" => {
                stop.store(true, Ordering::SeqCst);
                if let Some(w) = worker.take() {
                    tables = w.join().ok().flatten();
                }
            }
            "quit" => break,
            _ => say(format!("info string unknown command: {}", words[0])),
        }
    }
    stop.store(true, Ordering::SeqCst);
    if let Some(w) = worker.take() {
        w.join().ok();
    }
}

/// How long to think with `left` ms on the clock and `inc` ms added per move:
/// (the time we aim for, the most we'll take).
pub fn time_for_move(left: u64, inc: u64) -> (u64, u64) {
    let soft = left / 35 + inc * 3 / 4;
    let hard = (soft * 4).min(left / 4 + inc).min(left.saturating_sub(left / 10 + 20)).max(5);
    (soft.min(hard), hard)
}

/// The evaluation split into its biggest parts (White's point of view).
pub fn eval_breakdown(game: &Game, et: &EvalTables, params: &Params) -> String {
    let r = &game.rules;
    let mut acc = Sparse(Default::default());
    features(&game.pos, r, et, &mut acc);
    let ph = phase(&game.pos, et);
    let mut parts: Vec<(String, f32, f32)> = acc
        .0
        .iter()
        .filter(|(_, v)| **v != 0.0)
        .map(|(&f, &v)| {
            let w = params.w[f];
            (feature_name(&r.cat, f), v, v * (w[0] * ph + w[1] * (1.0 - ph)))
        })
        .collect();
    parts.sort_by(|a, b| b.2.abs().partial_cmp(&a.2.abs()).unwrap());
    let mut out = format!("phase {:.2} (1 = opening, 0 = endgame)\n{:<28} {:>8} {:>9}\n", ph, "term (White - Black)", "count", "pawns");
    for (name, v, c) in parts.iter().take(16) {
        out += &format!("{:<28} {:>8.1} {:>+9.2}\n", name, v, c / 100.0);
    }
    let mop = mop_up(&game.pos, r);
    if mop != 0 {
        out += &format!("{:<28} {:>8} {:>+9.2}\n", "lone King to the edge", "", mop as f32 / 100.0);
    }
    out.trim_end().to_string()
}
