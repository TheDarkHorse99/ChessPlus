//! Position evaluation. A weighted sum of features (each counted White minus
//! Black), blended between a middlegame and an endgame weight by how much
//! material is left. Being linear, the weights can be fitted to game results
//! (`tune.rs`), and the fitted material weights double as measured piece values.
//!
//! Every piece-specific term is per piece type and worked out from the piece
//! data, so new pieces get sensible behaviour without code changes.

use crate::defs::*;
use crate::position::*;
use std::collections::HashMap;

pub const FE_MAT: usize = 0;
pub const FE_MOB: usize = 1;
pub const FE_SHIELD: usize = 2;
pub const FE_ABIL: usize = 3;
/// Squares the piece would reach from its square on an empty board, minus
/// its average over the board: a Knight on the rim or a Berserker on the last
/// row (where it can never move again) is worth less.
pub const FE_REACH: usize = 4;
/// On a square it can never leave (a Berserker on the last row): it can only
/// stand in the way. Unless tuned, cancels 90% of its material.
pub const FE_DEAD: usize = 5;
/// + relative row (0..7, further rows count as 7): where on the board a piece
/// that doesn't promote stands.
pub const FE_ROW: usize = 6;
pub const ROWS: usize = 8;
/// Opening corrections: each is the feature times `opening` (the share of
/// both sides' pieces, not counting pawn types and kings, that haven't moved
/// yet), so they fade as the armies develop. At the start every piece stands
/// on its first two rows, where the middlegame's reach, row and mobility
/// weights misjudge it: a piece still at home in the middlegame usually means
/// a bad game, at move 0 it means nothing (drift analysis, Oct 2026).
pub const FE_OMAT: usize = FE_ROW + ROWS;
pub const FE_OMOB: usize = FE_OMAT + 1;
pub const FE_OREACH: usize = FE_OMAT + 2;
/// On its second row (a first-row piece counts only in `omat`).
pub const FE_OROW1: usize = FE_OMAT + 3;
pub const FE_OABIL: usize = FE_OMAT + 4;
pub const PER_KIND: usize = FE_OABIL + 1;
pub const G: usize = MAX_KINDS * PER_KIND;
pub const G_CENTER: usize = G;
pub const G_DEVELOP: usize = G + 1;
pub const G_ADV: usize = G + 2; // + relative row (0..16)
pub const G_PASSED: usize = G + 18; // + relative row (0..16)
pub const G_DOUBLED: usize = G + 34;
pub const G_ISOLATED: usize = G + 35;
pub const G_KSHIELD: usize = G + 36;
pub const G_KZONE: usize = G + 37;
pub const G_KCENTER: usize = G + 38;
pub const G_RAISE: usize = G + 39;
pub const G_TEMPO: usize = G + 40;
pub const G_HANGING: usize = G + 41;
pub const G_THREAT: usize = G + 42;
/// The side to move, times `opening`.
pub const G_OTEMPO: usize = G + 43;
pub const NFEAT: usize = G + 44;

pub fn feature_name(cat: &Catalog, i: usize) -> String {
    if i < G {
        let k = i / PER_KIND;
        let id = cat.defs.get(k).map(|d| d.id.clone()).unwrap_or(format!("kind{}", k));
        let f = i % PER_KIND;
        if f >= FE_OMAT {
            let what = ["omat", "omob", "oreach", "orow1", "oability"][f - FE_OMAT];
            return format!("{}:{}", what, id);
        }
        if f >= FE_ROW {
            return format!("row{}:{}", f - FE_ROW, id);
        }
        let what = ["mat", "mob", "shield", "ability", "reach", "dead"][f];
        return format!("{}:{}", what, id);
    }
    match i {
        G_CENTER => "center".into(),
        G_DEVELOP => "undeveloped".into(),
        x if (G_ADV..G_ADV + 16).contains(&x) => format!("advance:{}", x - G_ADV),
        x if (G_PASSED..G_PASSED + 16).contains(&x) => format!("passed:{}", x - G_PASSED),
        G_DOUBLED => "doubled".into(),
        G_ISOLATED => "isolated".into(),
        G_KSHIELD => "king_shelter".into(),
        G_KZONE => "king_zone_attacks".into(),
        G_KCENTER => "king_center".into(),
        G_RAISE => "raise_potential".into(),
        G_TEMPO => "tempo".into(),
        G_HANGING => "hanging".into(),
        G_THREAT => "threatened".into(),
        G_OTEMPO => "otempo".into(),
        _ => format!("f{}", i),
    }
}

/// The tuned weights built into the program (params/tuned.txt).
pub const BUILTIN_PARAMS: &str = include_str!("../params/tuned.txt");

/// Middlegame/endgame weight per feature, in centipawns.
#[derive(Clone)]
pub struct Params {
    pub w: Vec<[f32; 2]>,
    /// Which features have been tuned (the rest are defaults from piece costs).
    pub tuned: Vec<bool>,
}

impl Params {
    /// Starting weights: material from the army costs, the rest hand-picked.
    pub fn defaults(cat: &Catalog) -> Params {
        let mut w = vec![[0.0f32; 2]; NFEAT];
        for (k, d) in cat.defs.iter().enumerate() {
            let v = (d.value * 100.0) as f32;
            w[k * PER_KIND + FE_MAT] = if d.is_king() { [0.0, 0.0] } else { [v, v] };
            w[k * PER_KIND + FE_MOB] = if d.is_king() { [0.0, 4.0] } else { [4.0, 4.0] };
            w[k * PER_KIND + FE_SHIELD] = [v * 0.5, v * 0.5];
            w[k * PER_KIND + FE_ABIL] = match d.ability {
                Ability::CrackShot => [v * 0.4, v * 0.4],
                Ability::RaiseDead => [30.0, 30.0],
                // On the board with Haunt unused: being captured only sends it
                // away for a move (a lost one counts most of its material).
                Ability::Haunt => [v * 0.4, v * 0.4],
                Ability::SongOfSlumber => [25.0, 25.0],
                Ability::FullMoon => [20.0, 20.0],
                Ability::None => [0.0, 0.0],
            };
        }
        w[G_CENTER] = [6.0, 2.0];
        w[G_DEVELOP] = [-12.0, 0.0];
        let adv_mg = [0.0, 0.0, 3.0, 8.0, 16.0, 30.0, 55.0, 80.0];
        let adv_eg = [0.0, 0.0, 6.0, 16.0, 32.0, 55.0, 90.0, 120.0];
        for row in 0..16 {
            let i = row.min(7);
            w[G_ADV + row] = [adv_mg[i], adv_eg[i]];
            w[G_PASSED + row] = [adv_mg[i] * 0.5, adv_eg[i]];
        }
        w[G_DOUBLED] = [-8.0, -18.0];
        w[G_ISOLATED] = [-8.0, -12.0];
        w[G_KSHIELD] = [10.0, 0.0];
        w[G_KZONE] = [-7.0, -2.0];
        w[G_KCENTER] = [-8.0, 12.0];
        w[G_RAISE] = [60.0, 60.0];
        w[G_TEMPO] = [15.0, 5.0];
        w[G_HANGING] = [-10.0, -10.0];
        w[G_THREAT] = [-30.0, -25.0];
        Params { w, tuned: vec![false; NFEAT] }
    }

    /// Reads "name mg eg" lines over the defaults. Names that don't match a
    /// piece in this catalog are ignored.
    pub fn load_over(&mut self, cat: &Catalog, text: &str) {
        let mut names: HashMap<String, usize> = HashMap::new();
        for i in 0..NFEAT {
            names.insert(feature_name(cat, i), i);
        }
        for line in text.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() < 3 {
                continue;
            }
            if let (Some(&i), Ok(mg), Ok(eg)) = (names.get(parts[0]), parts[1].parse::<f32>(), parts[2].parse::<f32>()) {
                self.w[i] = [mg, eg];
                self.tuned[i] = true;
            }
        }
        for k in 0..cat.len() {
            let d = k * PER_KIND + FE_DEAD;
            if !self.tuned[d] {
                let m = self.w[k * PER_KIND + FE_MAT];
                self.w[d] = [-0.9 * m[0], -0.9 * m[1]];
            }
        }
    }

    pub fn save(&self, cat: &Catalog, used: &[bool]) -> String {
        let mut out = String::from("# Plusfish evaluation weights: <feature> <middlegame> <endgame> (centipawns)\n");
        for i in 0..NFEAT {
            if i < G && i / PER_KIND >= cat.len() {
                continue;
            }
            if !used[i] {
                continue;
            }
            out += &format!("{} {:.1} {:.1}\n", feature_name(cat, i), self.w[i][0], self.w[i][1]);
        }
        out
    }
}

/// Collects features.
pub trait Acc {
    fn add(&mut self, f: usize, v: f32);
}

pub struct Weighted<'a> {
    pub w: &'a [[f32; 2]],
    pub mg: f32,
    pub eg: f32,
}
impl<'a> Acc for Weighted<'a> {
    #[inline(always)]
    fn add(&mut self, f: usize, v: f32) {
        let w = self.w[f];
        self.mg += w[0] * v;
        self.eg += w[1] * v;
    }
}

pub struct Sparse(pub HashMap<usize, f32>);
impl Acc for Sparse {
    fn add(&mut self, f: usize, v: f32) {
        *self.0.entry(f).or_insert(0.0) += v;
    }
}

/// Per-game constants for the evaluation.
pub struct EvalTables {
    /// Squares reached from each square on an empty board, per kind and team
    /// (like `PracticeBot.reach`), and the average over the board.
    reach_avg: Vec<f32>,
    /// Squares reached from each square minus the average, [(kind * 2 + team) * nsq + square].
    reach_rel: Vec<f32>,
    /// Squares a piece can never leave, per kind and team (bit masks).
    dead: Vec<u128>,
    center: Vec<f32>,
    /// Phase weight per kind: non-pawn, non-king material (army cost).
    phase_value: Vec<f32>,
    phase_total: f32,
    raise_ref: f32,
}

impl EvalTables {
    pub fn new(r: &Rules) -> EvalTables {
        let nk = r.info.len();
        let mut reach_avg = vec![0.0f32; nk];
        let mut reach_rel = vec![0.0f32; nk * 2 * r.nsq];
        let mut dead = vec![0u128; nk * 2];
        for k in 0..nk {
            for t in 0..2 {
                for s in 0..r.nsq {
                    let mut seen = 0u128;
                    for ray in r.rays_of(k, t, s) {
                        let sqs = r.ray_squares(ray);
                        if ray.is_path {
                            seen |= 1u128 << sqs[sqs.len() - 1];
                            continue;
                        }
                        let lim = ray.lim_moved.max(ray.lim_unmoved).min(ray.len) as usize;
                        for (i, &q) in sqs[..lim].iter().enumerate() {
                            if i >= ray.leap as usize {
                                seen |= 1u128 << q;
                            }
                        }
                    }
                    reach_rel[(k * 2 + t) * r.nsq + s] = seen.count_ones() as f32;
                    let i = &r.info[k];
                    if seen == 0 && !i.can_promote && i.ability == Ability::None {
                        dead[k * 2 + t] |= 1u128 << s;
                    }
                }
            }
            let own = &mut reach_rel[k * 2 * r.nsq..(k + 1) * 2 * r.nsq];
            reach_avg[k] = own[..r.nsq].iter().sum::<f32>() / r.nsq as f32;
            for v in own.iter_mut() {
                *v -= reach_avg[k];
            }
        }
        let cx = (r.w - 1) as f32 / 2.0;
        let cy = (r.h - 1) as f32 / 2.0;
        let center = (0..r.nsq)
            .map(|s| {
                let dx = (r.file(s) as f32 - cx).abs();
                let dy = (r.rank(s) as f32 - cy).abs();
                (cx.min(cy) - dx.max(dy)).max(0.0)
            })
            .collect();
        let phase_value: Vec<f32> = r.info.iter().map(|i| if i.is_pawn || i.is_king { 0.0 } else { i.cost as f32 }).collect();
        EvalTables { reach_avg, reach_rel, dead, center, phase_value, phase_total: 62.0, raise_ref: 3.0 }
    }
}

/// 1.0 = full middlegame, 0.0 = bare endgame.
pub fn phase(p: &Position, et: &EvalTables) -> f32 {
    let mut npm = 0.0;
    for s in p.squares(WHITE).chain(p.squares(BLACK)) {
        npm += et.phase_value[kind_of(p.sq[s])];
    }
    (npm / et.phase_total).min(1.0)
}

/// Adds every feature of `p` to `acc` (White minus Black).
pub fn features<A: Acc>(p: &Position, r: &Rules, et: &EvalTables, acc: &mut A) {
    let mut att = [0u128; 2];
    let mut pawn_files = [[0u8; 26]; 2];
    // First pass: attack maps (needed for king safety and hanging pieces) and
    // pawn files.
    let mut mob = [[0u16; 64]; 2];
    let mut mob_n = [0usize; 2];
    // Attack sets with the attacker's cost, to find pieces attacked by
    // something cheaper.
    let mut by_cost: [[(f32, u128); 64]; 2] = [[(0.0, 0); 64]; 2];
    let (mut unmoved, mut pieces) = (0u32, 0u32);
    for t in 0..2 {
        for s in p.squares(t) {
            let c = p.sq[s];
            let k = kind_of(c);
            if !r.info[k].is_pawn && !r.info[k].is_king {
                pieces += 1;
                if c & MOVED == 0 {
                    unmoved += 1;
                }
            }
            let (m, a) = mobility(p, r, s, c);
            att[t] |= a;
            if mob_n[t] < 64 {
                mob[t][mob_n[t]] = m;
                by_cost[t][mob_n[t]] = (if r.info[k].is_king { 1000.0 } else { r.info[k].cost as f32 }, a);
                mob_n[t] += 1;
            }
            if r.info[k].is_pawn {
                pawn_files[t][r.file(s) as usize] += 1;
            }
        }
    }
    let opening = if pieces == 0 { 0.0 } else { unmoved as f32 / pieces as f32 };
    for t in 0..2 {
        let sign = if t == WHITE { 1.0 } else { -1.0 };
        let them = 1 - t;
        let mut i = 0;
        let mut best_raise = 0.0f32;
        let mut has_necro = false;
        for s in p.squares(t) {
            let c = p.sq[s];
            let k = kind_of(c);
            let info = &r.info[k];
            let base = k * PER_KIND;
            acc.add(base + FE_MAT, sign);
            let m = if i < 64 { mob[t][i] } else { 0 } as f32;
            i += 1;
            acc.add(base + FE_MOB, sign * (m - et.reach_avg[k] * 0.5));
            let reach = et.reach_rel[(k * 2 + t) * r.nsq + s];
            if reach != 0.0 {
                acc.add(base + FE_REACH, sign * reach);
            }
            let row = if t == WHITE { r.rank(s) } else { r.h - 1 - r.rank(s) };
            if opening > 0.0 {
                let o = sign * opening;
                acc.add(base + FE_OMAT, o);
                acc.add(base + FE_OMOB, o * (m - et.reach_avg[k] * 0.5));
                if reach != 0.0 {
                    acc.add(base + FE_OREACH, o * reach);
                }
                if row == 1 {
                    acc.add(base + FE_OROW1, o);
                }
                if info.ability != Ability::None && c & USED == 0 {
                    acc.add(base + FE_OABIL, o);
                }
            }
            if et.dead[k * 2 + t] & (1u128 << s) != 0 {
                acc.add(base + FE_DEAD, sign);
            }
            if r.shielded(c) {
                acc.add(base + FE_SHIELD, sign);
            }
            if info.ability != Ability::None && c & USED == 0 {
                acc.add(base + FE_ABIL, sign);
                if info.ability == Ability::RaiseDead {
                    has_necro = true;
                }
            }
            let file = r.file(s);
            if info.is_king {
                acc.add(G_KCENTER, sign * et.center[s]);
                let fwd = if t == WHITE { 1 } else { -1 };
                let mut shelter = 0.0;
                let mut zone = 0u128;
                for dx in -1..=1 {
                    for dy in -1..=1 {
                        let (x, y) = (file + dx, r.rank(s) + dy);
                        if x >= 0 && y >= 0 && x < r.w && y < r.h {
                            zone |= 1u128 << (y * r.w + x);
                        }
                    }
                    let (x, y) = (file + dx, r.rank(s) + fwd);
                    if x >= 0 && y >= 0 && x < r.w && y < r.h {
                        let g = p.sq[(y * r.w + x) as usize];
                        if g != 0 && team_of(g) == t {
                            shelter += 1.0;
                        }
                    }
                }
                acc.add(G_KSHIELD, sign * shelter);
                acc.add(G_KZONE, sign * (att[them] & zone).count_ones() as f32);
                continue;
            }
            if info.can_promote {
                acc.add(G_ADV + row.clamp(0, 15) as usize, sign);
                if info.is_pawn {
                    // Passed: no enemy pawn-type piece ahead on this or a neighbouring file.
                    let mut passed = true;
                    'scan: for x in (file - 1).max(0)..=(file + 1).min(r.w - 1) {
                        let mut y = r.rank(s) + if t == WHITE { 1 } else { -1 };
                        while y >= 0 && y < r.h {
                            let o = p.sq[(y * r.w + x) as usize];
                            if o != 0 && team_of(o) == them && r.info[kind_of(o)].is_pawn {
                                passed = false;
                                break 'scan;
                            }
                            y += if t == WHITE { 1 } else { -1 };
                        }
                    }
                    if passed {
                        acc.add(G_PASSED + row.clamp(0, 15) as usize, sign);
                    }
                    let f = file as usize;
                    let left = f > 0 && pawn_files[t][f - 1] > 0;
                    let right = f + 1 < r.w as usize && pawn_files[t][f + 1] > 0;
                    if !left && !right {
                        acc.add(G_ISOLATED, sign);
                    }
                }
            } else {
                acc.add(base + FE_ROW + row.clamp(0, ROWS as i32 - 1) as usize, sign);
                acc.add(G_CENTER, sign * et.center[s]);
                if row == 0 && !info.castle {
                    acc.add(G_DEVELOP, sign);
                }
            }
            // Attacked by the enemy and not defended.
            let bit = 1u128 << s;
            if att[them] & bit != 0 && att[t] & bit == 0 {
                acc.add(G_HANGING, sign);
            }
            // Attacked by a cheaper enemy piece.
            if att[them] & bit != 0 {
                let v = info.cost as f32 - 0.25;
                if by_cost[them][..mob_n[them]].iter().any(|&(cv, a)| cv < v && a & bit != 0) {
                    acc.add(G_THREAT, sign);
                }
            }
        }
        for f in 0..r.w as usize {
            if pawn_files[t][f] > 1 {
                acc.add(G_DOUBLED, sign * (pawn_files[t][f] - 1) as f32);
            }
        }
        if p.ghosts[t] != 0 {
            // Lost Ghosts that can still Haunt come back onto any empty square.
            let g = r.haunt_kind as usize * PER_KIND + FE_MAT;
            acc.add(g, sign * 0.8 * p.ghosts[t].count_ones() as f32);
        }
        if has_necro {
            for k in 0..r.info.len() {
                if p.lost[t][k] > 0 && !r.info[k].is_pawn && r.info[k].ability != Ability::RaiseDead {
                    best_raise = best_raise.max(r.info[k].cost as f32);
                }
            }
            acc.add(G_RAISE, sign * (best_raise - et.raise_ref).max(0.0));
        }
    }
    acc.add(G_TEMPO, if p.side == WHITE { 1.0 } else { -1.0 });
    if opening > 0.0 {
        acc.add(G_OTEMPO, if p.side == WHITE { opening } else { -opening });
    }
}

/// How many squares the piece on `s` can move to now (ignoring checks), and the
/// squares it attacks (could capture on, including its own pieces' squares).
#[inline]
pub fn mobility(p: &Position, r: &Rules, s: usize, c: u16) -> (u16, u128) {
    let k = kind_of(c);
    let t = team_of(c);
    let moved = c & MOVED != 0;
    let mut n = 0u16;
    let mut a = 0u128;
    for ray in r.rays_of(k, t, s) {
        let sqs = r.ray_squares(ray);
        if ray.is_path {
            let last = sqs.len() - 1;
            if sqs[..last].iter().all(|&q| p.sq[q as usize] == 0) {
                let q = sqs[last] as usize;
                let o = p.sq[q];
                if ray.mode != Mode::MoveOnly {
                    a |= 1u128 << q;
                }
                if (o == 0 && ray.mode != Mode::CaptureOnly) || (o != 0 && team_of(o) != t && ray.mode != Mode::MoveOnly) {
                    n += 1;
                }
            }
            continue;
        }
        let limit = (if moved { ray.lim_moved } else { ray.lim_unmoved }).min(ray.len) as usize;
        let leap = ray.leap as usize;
        let mut i = 0;
        while i < limit {
            let q = sqs[i] as usize;
            let o = p.sq[q];
            if i < leap {
                if ray.leap_own && (o == 0 || team_of(o) != t) {
                    break;
                }
                i += 1;
                continue;
            }
            if o == 0 {
                if ray.mode != Mode::CaptureOnly {
                    n += 1;
                }
                if ray.mode != Mode::MoveOnly && !ray.hop {
                    a |= 1u128 << q;
                }
                i += 1;
                continue;
            }
            if ray.hop {
                if ray.mode != Mode::MoveOnly {
                    for j in i + 1..limit {
                        let q2 = sqs[j] as usize;
                        a |= 1u128 << q2;
                        let o2 = p.sq[q2];
                        if o2 != 0 {
                            if team_of(o2) != t {
                                n += 1;
                            }
                            break;
                        }
                    }
                }
            } else if ray.mode != Mode::MoveOnly {
                a |= 1u128 << q;
                if team_of(o) != t {
                    n += 1;
                }
            }
            break;
        }
    }
    (n, a)
}

/// The score for the side to move, in centipawns.
#[inline]
pub fn evaluate(p: &Position, r: &Rules, et: &EvalTables, params: &Params) -> i32 {
    let mut acc = Weighted { w: &params.w, mg: 0.0, eg: 0.0 };
    features(p, r, et, &mut acc);
    let ph = phase(p, et);
    let white = acc.mg * ph + acc.eg * (1.0 - ph);
    let s = if p.side == WHITE { white } else { -white };
    s.round() as i32
}

/// The material value of a kind for move ordering and pruning, in centipawns.
pub fn piece_value(params: &Params, kind: usize) -> i32 {
    let w = params.w[kind * PER_KIND + FE_MAT];
    ((w[0] + w[1]) * 0.5).max(50.0) as i32
}
