//! Self-play: engine-vs-engine games between armies, run in parallel, with
//! adjudication, randomised openings, and data collection for tuning and
//! balance reports.

use crate::army::*;
use crate::defs::*;
use crate::eval::*;
use crate::game::*;
use crate::position::*;
use crate::search::*;
use crate::util::Rng;
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

#[derive(Clone, Debug)]
pub struct PlayConfig {
    /// Search nodes per move (deterministic and hardware-independent).
    pub nodes: u64,
    /// Plies at the start played by picking randomly among good moves.
    pub random_plies: usize,
    pub max_plies: usize,
    pub tt_mb: usize,
    /// Record position samples (for tuning) every this many plies (0 = never).
    pub sample_every: usize,
}

impl Default for PlayConfig {
    fn default() -> Self {
        PlayConfig { nodes: 20_000, random_plies: 6, max_plies: 400, tt_mb: 8, sample_every: 0 }
    }
}

/// A position from a game: its features, phase, and how the game ended
/// (1 = White won, 0.5 draw, 0 = Black won).
#[derive(Clone)]
pub struct Sample {
    pub feats: Vec<(u16, f32)>,
    pub phase: f32,
    pub result: f32,
}

#[derive(Clone)]
pub struct GameRecord {
    pub white: Army,
    pub black: Army,
    pub moves: Vec<Move>,
    pub sans: String,
    /// From White's point of view.
    pub result: f32,
    pub reason: String,
    pub plies: usize,
    pub samples: Vec<Sample>,
    /// Which side played with the "A" settings (for A/B tests).
    pub a_is_white: bool,
}

/// True if a king can be captured straight away or starts in check: army
/// pairings the game allows but that make no sense to play (see README).
pub fn start_is_broken(g: &Game) -> bool {
    let r = &g.rules;
    g.pos.in_check(r, WHITE) || g.pos.in_check(r, BLACK)
}

pub fn pick_opening_move(s: &mut Searcher, g: &Game, rng: &mut Rng) -> Move {
    let legal = g.pos.legal_moves(&g.rules);
    let k = legal.len().min(8);
    let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], Limits { depth: Some(3), nodes: Some(200_000), movetime_ms: None, soft_ms: None }, k, |_| {});
    let best = rep.lines.first().map(|l| l.score).unwrap_or(0);
    let good: Vec<&Line> = rep.lines.iter().filter(|l| l.score >= best - 40 && !l.pv.is_empty()).collect();
    if good.is_empty() {
        return legal[rng.below(legal.len())];
    }
    good[rng.below(good.len())].pv[0]
}

/// Plays one game. `pa` plays the side `a_is_white` says; `pb` the other.
pub fn play_game(cat: &Arc<Catalog>, white: &Army, black: &Army, pa: &Params, pb: &Params, a_is_white: bool, cfg: &PlayConfig, seed: u64) -> GameRecord {
    let mut g = army_game(cat, white, black, 8, 8);
    let rules = g.rules.clone();
    let r = &*rules;
    let et = EvalTables::new(r);
    let (pw, pbk) = if a_is_white { (pa, pb) } else { (pb, pa) };
    let mut sw = Searcher::new(r, &et, pw, cfg.tt_mb);
    let mut sb = Searcher::new(r, &et, pbk, cfg.tt_mb);
    let mut rng = Rng::new(seed);
    let mut result = 0.5f32;
    let mut reason = String::from("max_plies");
    let mut win_streak = 0i32;
    let mut draw_streak = 0;
    let mut pending: Vec<(Vec<(u16, f32)>, f32)> = Vec::new();
    for ply in 0..cfg.max_plies {
        let out = g.outcome();
        if out != Outcome::None {
            reason = outcome_name(out).to_string();
            result = out.white_score(g.pos.side).unwrap_or(0.5) as f32;
            break;
        }
        let s = if g.pos.side == WHITE { &mut sw } else { &mut sb };
        let m;
        if ply < cfg.random_plies {
            m = pick_opening_move(s, &g, &mut rng);
        } else {
            let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], Limits { depth: None, nodes: Some(cfg.nodes), movetime_ms: None, soft_ms: None }, 1, |_| {});
            let line = &rep.lines[0];
            m = line.pv.first().copied().unwrap_or_else(|| g.pos.legal_moves(r)[0]);
            let white_score = if g.pos.side == WHITE { line.score } else { -line.score };
            // Adjudication: a clearly won position (both engines agree for a
            // few moves) or a long dead-level one.
            if white_score.abs() >= 1000 {
                if white_score.signum() == win_streak.signum() || win_streak == 0 {
                    win_streak += white_score.signum();
                } else {
                    win_streak = white_score.signum();
                }
            } else {
                win_streak = 0;
            }
            if win_streak.abs() >= 6 {
                result = if win_streak > 0 { 1.0 } else { 0.0 };
                reason = "adjudicated_win".into();
                break;
            }
            if ply >= 120 && white_score.abs() <= 15 {
                draw_streak += 1;
            } else {
                draw_streak = 0;
            }
            if draw_streak >= 24 {
                result = 0.5;
                reason = "adjudicated_draw".into();
                break;
            }
            // A sample for tuning: quiet positions only (not in check, best move quiet).
            if cfg.sample_every > 0 && ply % cfg.sample_every == 0 && !g.pos.in_check(r, g.pos.side) && !m.is_tactical() && !is_mate_score(line.score) {
                let mut acc = Sparse(Default::default());
                features(&g.pos, r, &et, &mut acc);
                let mut f: Vec<(u16, f32)> = acc.0.into_iter().filter(|(_, v)| *v != 0.0).map(|(k, v)| (k as u16, v)).collect();
                f.sort_by_key(|x| x.0);
                pending.push((f, phase(&g.pos, &et)));
            }
        }
        g.play(m);
    }
    let samples = pending.into_iter().map(|(feats, phase)| Sample { feats, phase, result }).collect();
    GameRecord {
        white: white.clone(),
        black: black.clone(),
        sans: g.move_list(),
        moves: g.moves.clone(),
        result,
        reason,
        plies: g.moves.len(),
        samples,
        a_is_white,
    }
}

fn is_mate_score(s: i32) -> bool {
    s.abs() >= MATE_BOUND
}

/// Runs `count` games on `threads` threads. `make_pair(i, rng)` gives game i's
/// armies and whether side A plays White. Calls `progress` as games finish.
pub fn run_games(
    cat: &Arc<Catalog>,
    count: usize,
    threads: usize,
    pa: &Params,
    pb: &Params,
    cfg: &PlayConfig,
    seed: u64,
    make_pair: &(dyn Fn(usize, &mut Rng) -> (Army, Army, bool) + Sync),
    progress: &(dyn Fn(&GameRecord, usize) + Sync),
) -> Vec<GameRecord> {
    let next = AtomicUsize::new(0);
    let done = AtomicUsize::new(0);
    let results: Mutex<Vec<(usize, GameRecord)>> = Mutex::new(Vec::new());
    std::thread::scope(|scope| {
        for _ in 0..threads.max(1) {
            scope.spawn(|| loop {
                let i = next.fetch_add(1, Ordering::SeqCst);
                if i >= count {
                    break;
                }
                let mut rng = Rng::new(seed.wrapping_mul(1_000_003).wrapping_add(i as u64));
                let (w, b, a_white) = make_pair(i, &mut rng);
                let rec = play_game(cat, &w, &b, pa, pb, a_white, cfg, rng.next());
                let n = done.fetch_add(1, Ordering::SeqCst) + 1;
                progress(&rec, n);
                results.lock().unwrap().push((i, rec));
            });
        }
    });
    let mut v = results.into_inner().unwrap();
    v.sort_by_key(|x| x.0);
    v.into_iter().map(|x| x.1).collect()
}

/// Experiment (Mac, Oct 2026), not a game rule: the "front-row rule": no
/// piece may start able to capture anything on the opponent's two starting
/// rows. With `--front-row-rule=true`, random armies follow it.
pub static FRONT_ROW_RULE: AtomicBool = AtomicBool::new(false);
/// Random armies made and how many followed the front-row rule (while it's on).
pub static ARMIES_TRIED: AtomicUsize = AtomicUsize::new(0);
pub static ARMIES_PASSED: AtomicUsize = AtomicUsize::new(0);

/// A random army for `budget`, following the front-row rule when it's on.
fn random_army_for(cat: &Arc<Catalog>, rng: &mut Rng, budget: f64) -> Army {
    loop {
        let a = random_army_budget(cat, rng, budget);
        if !FRONT_ROW_RULE.load(Ordering::Relaxed) {
            return a;
        }
        ARMIES_TRIED.fetch_add(1, Ordering::Relaxed);
        if front_row_ok(cat, &a) {
            ARMIES_PASSED.fetch_add(1, Ordering::Relaxed);
            return a;
        }
    }
}

/// A random pair of armies whose start makes sense (no king capturable or in
/// check at the start).
pub fn random_pair(cat: &Arc<Catalog>, rng: &mut Rng, budgets: (f64, f64)) -> (Army, Army) {
    loop {
        let w = random_army_for(cat, rng, budgets.0);
        let b = random_army_for(cat, rng, budgets.1);
        let g = army_game(cat, &w, &b, 8, 8);
        if !start_is_broken(&g) {
            return (w, b);
        }
    }
}

/// Wins, draws, losses -> score, Elo difference and its 95% margin.
pub fn elo_summary(w: f64, d: f64, l: f64) -> (f64, f64, f64) {
    let n = w + d + l;
    if n == 0.0 {
        return (0.5, 0.0, 0.0);
    }
    let score = (w + d / 2.0) / n;
    let elo = |s: f64| -> f64 {
        let s = s.clamp(1e-4, 1.0 - 1e-4);
        -400.0 * (1.0 / s - 1.0).log10()
    };
    let var = (w * (1.0 - score).powi(2) + d * (0.5 - score).powi(2) + l * (0.0 - score).powi(2)) / n;
    let se = (var / n).sqrt();
    let margin = (elo(score + 1.96 * se) - elo(score - 1.96 * se)) / 2.0;
    (score, elo(score), margin)
}
