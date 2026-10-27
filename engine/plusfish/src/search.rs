//! The search: iterative deepening alpha-beta (principal variation search) with
//! a transposition table, null-move pruning, late-move reductions, check
//! extensions, killer/history move ordering and a quiescence search over
//! captures, shield breaks, Crack Shots and promotions.

use crate::defs::MAX_KINDS;
use crate::endgame::{self, Probe};
use crate::eval::*;
use crate::position::*;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use crate::util::now_ms;

pub const INF: i32 = 32000;
pub const MATE: i32 = 31000;
pub const MATE_BOUND: i32 = MATE - 1000;
const MAX_PLY: usize = 128;
/// "Not worked out" in the capture gains `order` fills in.
const NO_GAIN: i32 = i32::MIN;

#[derive(Clone, Copy, Default)]
struct TTEntry {
    key: u64,
    mv: Move,
    score: i16,
    eval: i16,
    depth: i8,
    bound: u8,
    age: u8,
}

/// The transposition table: buckets of two entries (a new result replaces
/// the shallower or older one). Entries are three 64-bit words: the key XOR
/// the two data words, then the data. Threads can share it without locks: a
/// half-written entry fails the key check and is just a miss.
pub struct TT {
    words: Vec<AtomicU64>,
    mask: usize,
}

impl TT {
    pub fn new(mb: usize) -> TT {
        let entries = (mb.max(1) * 1024 * 1024 / 24).next_power_of_two() / 2;
        let entries = entries.max(1024);
        TT { words: (0..entries * 3).map(|_| AtomicU64::new(0)).collect(), mask: entries / 2 - 1 }
    }

    pub fn mb(&self) -> usize {
        self.words.len() * 8 / (1024 * 1024)
    }

    pub fn clear(&self) {
        for w in &self.words {
            w.store(0, Ordering::Relaxed);
        }
    }

    /// The entry for `key` (index, entry): the one holding it, or else the one
    /// a new result would replace (whose key won't match).
    #[inline(always)]
    fn probe(&self, key: u64, age: u8) -> (usize, TTEntry) {
        let b = ((key as usize) & self.mask) * 2;
        let e0 = self.load(b);
        if e0.key == key {
            return (b, e0);
        }
        let e1 = self.load(b + 1);
        if e1.key == key {
            return (b + 1, e1);
        }
        let worth = |e: &TTEntry| if e.bound == 0 { -1000 } else { e.depth as i32 - if e.age != age { 8 } else { 0 } };
        if worth(&e1) < worth(&e0) {
            (b + 1, e1)
        } else {
            (b, e0)
        }
    }

    #[inline(always)]
    fn load(&self, slot: usize) -> TTEntry {
        let i = slot * 3;
        let k = self.words[i].load(Ordering::Relaxed);
        let a = self.words[i + 1].load(Ordering::Relaxed);
        let b = self.words[i + 2].load(Ordering::Relaxed);
        TTEntry {
            key: k ^ a ^ b,
            mv: Move {
                from: a as u8,
                to: (a >> 8) as u8,
                flags: (a >> 16) as u8 as u16 | ((b >> 40) as u8 as u16) << 8,
                promo: (a >> 24) as u8,
                extra: (a >> 32) as u8,
                steps: (a >> 40) as u8,
            },
            score: (a >> 48) as u16 as i16,
            eval: b as u16 as i16,
            depth: (b >> 16) as u8 as i8,
            bound: (b >> 24) as u8,
            age: (b >> 32) as u8,
        }
    }

    #[inline(always)]
    fn store(&self, slot: usize, e: TTEntry) {
        let m = e.mv;
        let a = m.from as u64
            | (m.to as u64) << 8
            | (m.flags as u8 as u64) << 16
            | (m.promo as u64) << 24
            | (m.extra as u64) << 32
            | (m.steps as u64) << 40
            | (e.score as u16 as u64) << 48;
        // The move's high flag bits ride in the second word.
        let b = e.eval as u16 as u64 | (e.depth as u8 as u64) << 16 | (e.bound as u64) << 24 | (e.age as u64) << 32 | ((m.flags >> 8) as u64) << 40;
        let i = slot * 3;
        self.words[i].store(e.key ^ a ^ b, Ordering::Relaxed);
        self.words[i + 1].store(a, Ordering::Relaxed);
        self.words[i + 2].store(b, Ordering::Relaxed);
    }
}

/// Static evaluation correction history: for positions sharing a key (the
/// material on the board; the pawn-type pieces; each side's other pieces;
/// the move that led here), how far search results have landed from the
/// static evaluation. The corrected evaluation drives the pruning and
/// quiescence's stand-pat; the hash table keeps the raw one.
const CORR_SIZE: usize = 16384;
const _: () = assert!(CORR_SIZE >= MAX_SQ * MAX_SQ);
const CORR_TABLES: usize = 5;
/// Entries are hundredths of a point times CORR_GRAIN, at most +-CORR_MAX.
const CORR_GRAIN: i32 = 256;
const CORR_MAX: i32 = 64 * CORR_GRAIN;

const B_EXACT: u8 = 1;
const B_LOWER: u8 = 2;
const B_UPPER: u8 = 3;

/// One tunable search constant: its name (also the UCI option name), the
/// default, the range it may take, and SPSA's perturbation size (`c`, roughly
/// a change that costs a few Elo).
#[derive(Clone, Copy, Debug)]
pub struct ParamSpec {
    pub name: &'static str,
    pub default: i32,
    pub min: i32,
    pub max: i32,
    pub c: f64,
}

macro_rules! search_params {
    ($($(#[$doc:meta])* $name:ident = $def:expr, $min:expr, $max:expr, $c:expr;)*) => {
        /// The search's margins and limits as plain fields (read in the hot
        /// path like constants). Defaults are the hand-set values; UCI
        /// `setoption name <field> value <n>` and `plusfish spsa` change them.
        #[derive(Clone, Copy, Debug, PartialEq)]
        pub struct SearchParams {
            $($(#[$doc])* pub $name: i32,)*
            /// From lmr_base / lmr_div (hundredths), worked out once.
            pub lmr_base_f: f32,
            pub lmr_div_f: f32,
        }

        pub const SEARCH_PARAM_SPECS: &[ParamSpec] = &[$(ParamSpec { name: stringify!($name), default: $def, min: $min, max: $max, c: $c },)*];

        impl Default for SearchParams {
            fn default() -> Self {
                let mut p = SearchParams { $($name: $def,)* lmr_base_f: 0.0, lmr_div_f: 1.0 };
                p.derive();
                p
            }
        }

        impl SearchParams {
            pub fn get(&self, name: &str) -> Option<i32> {
                match name {
                    $(stringify!($name) => Some(self.$name),)*
                    _ => None,
                }
            }

            /// Sets one constant by name (clamped to its range); false if
            /// there's no such name.
            pub fn set(&mut self, name: &str, v: i32) -> bool {
                let spec = match SEARCH_PARAM_SPECS.iter().find(|s| s.name == name) {
                    Some(s) => s,
                    None => return false,
                };
                let v = v.clamp(spec.min, spec.max);
                match name {
                    $(stringify!($name) => self.$name = v,)*
                    _ => return false,
                }
                self.derive();
                true
            }
        }
    };
}

search_params! {
    /// Reverse futility: margin per depth, bonus when improving, max depth.
    rfp_margin = 90, 20, 250, 10.0;
    rfp_improving = 45, 0, 150, 10.0;
    rfp_depth = 6, 1, 12, 0.6;
    /// Null move: min depth; reduction = (nmp_base + depth * nmp_depth_mul) / 256.
    nmp_depth = 3, 1, 8, 0.6;
    nmp_base = 768, 256, 1536, 64.0;
    nmp_depth_mul = 64, 0, 192, 12.0;
    /// Quiet moves with SEE < -see_quiet * depth^2, depth <= see_quiet_depth.
    see_quiet = 50, 5, 200, 8.0;
    see_quiet_depth = 3, 0, 8, 0.6;
    /// Captures with SEE < -see_capture * depth, depth <= see_capture_depth.
    see_capture = 120, 10, 400, 15.0;
    see_capture_depth = 4, 0, 10, 0.6;
    /// Late-move pruning: more than (base + depth^2 * mul) / 100 quiet moves,
    /// depth <= lmp_depth (the _imp pair when improving).
    lmp_base = 300, 0, 1000, 50.0;
    lmp_mul = 200, 50, 600, 30.0;
    lmp_base_imp = 400, 0, 1000, 50.0;
    lmp_mul_imp = 300, 50, 800, 40.0;
    lmp_depth = 3, 0, 8, 0.6;
    /// Futility: static eval + fut_base + fut_mul * depth <= alpha, depth <= fut_depth.
    fut_base = 100, 0, 400, 15.0;
    fut_mul = 120, 20, 400, 15.0;
    fut_depth = 3, 0, 8, 0.6;
    /// LMR: (lmr_base + ln depth * ln moves / lmr_div) in hundredths, -lmr_pv
    /// on PV nodes, -history / lmr_history; from lmr_depth (at least 2: the
    /// reduction is clamped to new_depth - 1) and after
    /// lmr_moves (lmr_moves_pv) moves.
    lmr_base = 75, -100, 300, 10.0;
    lmr_div = 220, 100, 500, 20.0;
    lmr_pv = 1, 0, 3, 0.6;
    lmr_history = 9000, 1000, 30000, 1200.0;
    lmr_depth = 3, 2, 8, 0.6;
    lmr_moves = 2, 1, 8, 0.6;
    lmr_moves_pv = 4, 1, 10, 0.6;
    /// History bonus: depth^2 * hist_mul, at most hist_max.
    hist_mul = 16, 2, 64, 2.0;
    hist_max = 1600, 200, 6000, 200.0;
    /// Aspiration window: first half-width.
    asp_delta = 30, 5, 150, 5.0;
    /// Quiescence: delta margin; captures with SEE below -q_see are skipped.
    q_delta = 150, 0, 600, 20.0;
    q_see = 50, 0, 300, 10.0;
    /// Move ordering: captures with SEE below -order_see go after the killers.
    order_see = 50, 0, 300, 10.0;
    /// Capture ordering: capture history divided by this.
    cap_order_div = 8, 1, 64, 1.5;
    /// Singular extensions: least depth; margin per depth (hundredths of a
    /// centipawn) below the hash move's score that the other moves must stay under.
    se_depth = 7, 4, 14, 0.6;
    se_margin = 200, 25, 1000, 40.0;
    /// Correction history: weight of the material, pawn, per-side pieces and
    /// last-move tables (64 = all of it); update = diff * depth / corr_bonus_div.
    corr_w_mat = 32, 0, 128, 6.0;
    corr_w_pawn = 32, 0, 128, 6.0;
    corr_w_pieces = 32, 0, 128, 6.0;
    corr_w_last = 32, 0, 128, 6.0;
    corr_bonus_div = 8, 2, 32, 1.5;
}

impl SearchParams {
    fn derive(&mut self) {
        self.lmr_base_f = self.lmr_base as f32 / 100.0;
        self.lmr_div_f = self.lmr_div as f32 / 100.0;
    }

    /// "name=value;name=value" (as enginematch's --uci-a takes) for the
    /// constants that differ from the defaults.
    pub fn changed_text(&self) -> String {
        let d = SearchParams::default();
        SEARCH_PARAM_SPECS
            .iter()
            .filter(|s| self.get(s.name) != d.get(s.name))
            .map(|s| format!("{}={}", s.name, self.get(s.name).unwrap()))
            .collect::<Vec<_>>()
            .join(";")
    }
}

#[derive(Clone, Copy, Debug, Default)]
pub struct Limits {
    pub depth: Option<i32>,
    pub nodes: Option<u64>,
    pub movetime_ms: Option<u64>,
    /// With a clock: the time we'd like to use. The search stops after a depth
    /// once past it, sooner when the best move has stayed the same for a few
    /// depths and later when it keeps changing. `movetime_ms` is the hard limit.
    pub soft_ms: Option<u64>,
}

#[derive(Clone, Debug)]
pub struct Line {
    pub score: i32,
    pub pv: Vec<Move>,
}

#[derive(Clone, Debug)]
pub struct Report {
    pub depth: i32,
    pub seldepth: usize,
    pub nodes: u64,
    pub ms: u64,
    pub lines: Vec<Line>,
}

/// The tables a search learns from (hash table, history), kept between moves
/// of one game: `Searcher::into_tables` / `Searcher::with_tables`.
pub struct SearchTables {
    tt: Arc<TT>,
    age: u8,
    history: Vec<i32>,
    corr: Vec<i16>,
    cont: Vec<Vec<i16>>,
    cap_hist: Vec<i16>,
}

/// "No move" in `Searcher::ckeys`.
const NO_KEY: u32 = u32::MAX;
/// Most entries in one continuation-history table (2 bytes each, so 2 MB);
/// with more than 16 piece kinds on 64 squares, kinds share slots.
const MAX_CONT: usize = 1 << 20;

pub struct Searcher<'a> {
    pub r: &'a Rules,
    pub et: &'a EvalTables,
    pub params: &'a Params,
    /// Search margins and limits (defaults unless tuning).
    pub sp: SearchParams,
    tt: Arc<TT>,
    age: u8,
    killers: [[Move; 2]; MAX_PLY + 2],
    /// The move played to reach each ply (NONE after a null move).
    played: [Move; MAX_PLY + 2],
    /// Static evaluation at each ply (-INF when in check), for "improving".
    evals: [i32; MAX_PLY + 2],
    /// Counter-moves: the quiet reply that last refuted a move, by side and
    /// that move's from/to squares.
    counter: Vec<Move>,
    history: Vec<i32>,
    /// Correction history: [table][side to move][key % CORR_SIZE].
    corr: Vec<i16>,
    /// Compact slot of each piece kind (only the kinds in this game get one),
    /// how many slots, and the board flipped top to bottom (squares as seen by
    /// Black).
    kslot: [u8; MAX_KINDS],
    nslots: usize,
    flip: Vec<u8>,
    /// The move played to reach each ply as (kind slot, square from its
    /// mover's side), or NO_KEY.
    ckeys: [u32; MAX_PLY + 2],
    /// Continuation history, one table per ply back (CONT_PLIES):
    /// [that move][this move], keys as in `ckeys` (mover's view, so both
    /// colours share it).
    cont: Vec<Vec<i16>>,
    /// Capture history: [mover's slot, square][captured slot], mover's view.
    cap_hist: Vec<i16>,
    pv: Vec<[Move; MAX_PLY + 1]>,
    pv_len: [usize; MAX_PLY + 1],
    buffers: Vec<Vec<Move>>,
    /// Move-ordering scores and capture gains, per ply (`order`).
    order_bufs: Vec<(Vec<i32>, Vec<i32>)>,
    keys: Vec<u64>,
    values: Vec<i32>,
    pub nodes: u64,
    seldepth: usize,
    start: u64,
    limits: Limits,
    pub stop: Arc<AtomicBool>,
    stopped: bool,
    /// True while the first depth runs: limits don't apply until there's a move.
    must_finish: bool,
    root_excluded: Vec<Move>,
    /// The move a singular-extension search leaves out at each ply (NONE
    /// normally). Such a node neither cuts off on nor stores to the hash table.
    excluded: [Move; MAX_PLY + 2],
    /// The depth the current iteration started with (singular extensions
    /// stop at twice that many plies).
    root_depth: i32,
    /// Lazy SMP helpers search one ply deeper on odd thread numbers, so the
    /// threads don't all do the same work.
    depth_offset: i32,
    /// The score of the root move that last raised alpha (its line is pv[0]).
    root_score: i32,
    /// Score King + piece v King endings from the built-in tables (on; off
    /// only to test them).
    pub use_tables: bool,
}

fn is_mate(s: i32) -> bool {
    s.abs() >= MATE_BOUND
}

fn to_tt(s: i32, ply: usize) -> i32 {
    if s >= MATE_BOUND {
        s + ply as i32
    } else if s <= -MATE_BOUND {
        s - ply as i32
    } else {
        s
    }
}

fn from_tt(s: i32, ply: usize) -> i32 {
    if s >= MATE_BOUND {
        s - ply as i32
    } else if s <= -MATE_BOUND {
        s + ply as i32
    } else {
        s
    }
}

impl<'a> Searcher<'a> {
    pub fn new(r: &'a Rules, et: &'a EvalTables, params: &'a Params, tt_mb: usize) -> Searcher<'a> {
        let values = (0..r.info.len()).map(|k| piece_value(params, k)).collect();
        let present: Vec<usize> = (0..r.info.len().min(MAX_KINDS)).filter(|&k| r.kinds_present & (1u64 << k) != 0).collect();
        let mut nslots = present.len().max(1);
        while nslots > 1 && (nslots * r.nsq) * (nslots * r.nsq) > MAX_CONT {
            nslots -= 1;
        }
        let mut kslot = [0u8; MAX_KINDS];
        for (i, &k) in present.iter().enumerate() {
            kslot[k] = (i % nslots) as u8;
        }
        let w = r.w as usize;
        let flip = (0..r.nsq).map(|s| ((r.h as usize - 1 - s / w) * w + s % w) as u8).collect();
        let stride = nslots * r.nsq;
        Searcher {
            r,
            et,
            params,
            sp: SearchParams::default(),
            tt: Arc::new(TT::new(tt_mb)),
            age: 0,
            killers: [[Move::NONE; 2]; MAX_PLY + 2],
            played: [Move::NONE; MAX_PLY + 2],
            evals: [-INF; MAX_PLY + 2],
            counter: vec![Move::NONE; 2 * MAX_SQ * MAX_SQ],
            history: vec![0; 2 * MAX_SQ * MAX_SQ],
            corr: vec![0; CORR_TABLES * 2 * CORR_SIZE],
            kslot,
            nslots,
            flip,
            ckeys: [NO_KEY; MAX_PLY + 2],
            cont: (0..CONT_PLIES).map(|_| vec![0; stride * stride]).collect(),
            cap_hist: vec![0; stride * nslots],
            pv: vec![[Move::NONE; MAX_PLY + 1]; MAX_PLY + 1],
            pv_len: [0; MAX_PLY + 1],
            buffers: (0..MAX_PLY + 2).map(|_| Vec::with_capacity(128)).collect(),
            order_bufs: (0..MAX_PLY + 2).map(|_| (Vec::with_capacity(128), Vec::with_capacity(128))).collect(),
            keys: Vec::with_capacity(512),
            values,
            nodes: 0,
            seldepth: 0,
            start: now_ms(),
            limits: Limits::default(),
            stop: Arc::new(AtomicBool::new(false)),
            stopped: false,
            must_finish: false,
            root_excluded: Vec::new(),
            excluded: [Move::NONE; MAX_PLY + 2],
            root_depth: 0,
            depth_offset: 0,
            root_score: 0,
            use_tables: true,
        }
    }

    /// A searcher that carries on with tables from an earlier one.
    pub fn with_tables(r: &'a Rules, et: &'a EvalTables, params: &'a Params, t: SearchTables) -> Searcher<'a> {
        let mut s = Searcher::new(r, et, params, 1);
        s.tt = t.tt;
        s.age = t.age;
        s.history = t.history;
        s.corr = t.corr;
        if t.cont.iter().map(|c| c.len()).eq(s.cont.iter().map(|c| c.len())) && t.cap_hist.len() == s.cap_hist.len() {
            s.cont = t.cont;
            s.cap_hist = t.cap_hist;
        }
        s
    }

    pub fn into_tables(self) -> SearchTables {
        SearchTables { tt: self.tt, age: self.age, history: self.history, corr: self.corr, cont: self.cont, cap_hist: self.cap_hist }
    }

    pub fn tt_mb(t: &SearchTables) -> usize {
        t.tt.mb()
    }

    pub fn clear(&mut self) {
        self.tt.clear();
        for h in self.history.iter_mut() {
            *h = 0;
        }
        for c in self.corr.iter_mut() {
            *c = 0;
        }
        for h in self.cont.iter_mut().flatten().chain(self.cap_hist.iter_mut()) {
            *h = 0;
        }
    }

    #[inline]
    fn eval(&self, p: &Position) -> i32 {
        evaluate(p, self.r, self.et, self.params)
    }

    /// The correction-history slots for `p` (one per table, side to move
    /// included): material (a sum of one random number per piece kind and
    /// team, so only the counts matter), pawn-type pieces, and each side's
    /// other pieces (kind, team and square, from the Zobrist numbers), and
    /// the move that led here (`prev`; none = usize::MAX, not used).
    fn corr_slots(&self, p: &Position, prev: Move) -> [usize; CORR_TABLES] {
        let z = &self.r.z.piece;
        let (mut mat, mut pawns, mut pieces) = (0u64, 0u64, [0u64; 2]);
        let mut occ = p.occupied();
        while occ != 0 {
            let s = occ.trailing_zeros() as usize;
            occ &= occ - 1;
            let c = p.sq[s];
            let (k, t) = (kind_of(c), team_of(c));
            mat = mat.wrapping_add(z[k * 2 + t]);
            let h = z[(s * crate::defs::MAX_KINDS + k) * 2 + t];
            if self.r.info[k].is_pawn {
                pawns ^= h;
            } else {
                pieces[t] ^= h;
            }
        }
        let slot = |table: usize, h: u64| (table * 2 + p.side) * CORR_SIZE + (mix64(h) as usize & (CORR_SIZE - 1));
        let last = if prev == Move::NONE { usize::MAX } else { (4 * 2 + p.side) * CORR_SIZE + prev.from as usize * MAX_SQ + prev.to as usize };
        [slot(0, mat), slot(1, pawns), slot(2, pieces[0]), slot(3, pieces[1]), last]
    }

    /// The static evaluation plus what the correction history has learned.
    fn corrected(&self, raw: i32, slots: &[usize; CORR_TABLES]) -> i32 {
        // How much each table counts (64 = all of it): material, pawns,
        // White's pieces, Black's pieces, last move.
        let sp = &self.sp;
        let weights = [sp.corr_w_mat, sp.corr_w_pawn, sp.corr_w_pieces, sp.corr_w_pieces, sp.corr_w_last];
        let mut sum = 0;
        for t in 0..CORR_TABLES {
            if weights[t] != 0 && slots[t] != usize::MAX {
                sum += self.corr[slots[t]] as i32 * weights[t];
            }
        }
        (raw + sum / (64 * CORR_GRAIN)).clamp(-MATE_BOUND + 1, MATE_BOUND - 1)
    }

    /// `diff` = search result - corrected evaluation: each entry gains
    /// diff * depth / corr_bonus_div (bounded), shrinking as it nears CORR_MAX ("gravity",
    /// as Stockfish does it).
    fn update_corr(&mut self, slots: &[usize; CORR_TABLES], diff: i32, depth: i32) {
        let bonus = (diff * CORR_GRAIN * depth / self.sp.corr_bonus_div).clamp(-CORR_MAX / 4, CORR_MAX / 4);
        for t in 0..CORR_TABLES {
            if slots[t] != usize::MAX {
                let e = &mut self.corr[slots[t]];
                let v = *e as i32 + bonus - *e as i32 * bonus.abs() / CORR_MAX;
                *e = v.clamp(-CORR_MAX, CORR_MAX) as i16;
            }
        }
    }

    fn time_up(&mut self) -> bool {
        if self.stopped {
            return true;
        }
        if self.must_finish {
            // An outside "stop" still counts, and so does a far-overrun node
            // limit (a safety net: depth 1 should never take this long).
            if self.nodes & 1023 == 0 && self.stop.load(Ordering::Relaxed) {
                self.stopped = true;
            }
            if let Some(n) = self.limits.nodes {
                if self.nodes >= n.saturating_mul(64).max(1 << 20) {
                    self.stopped = true;
                }
            }
            return self.stopped;
        }
        if self.nodes & 1023 == 0 {
            if self.stop.load(Ordering::Relaxed) {
                self.stopped = true;
            }
            if let Some(ms) = self.limits.movetime_ms {
                if (now_ms() - self.start) >= ms {
                    self.stopped = true;
                }
            }
        }
        if let Some(n) = self.limits.nodes {
            if self.nodes >= n {
                self.stopped = true;
            }
        }
        self.stopped
    }

    /// Searches `pos`. `history_keys`: repetition keys of the game's earlier
    /// positions (oldest first, not including `pos`), so repetitions count.
    /// `report` is called after each finished depth.
    pub fn search(&mut self, pos: &Position, history_keys: &[u64], limits: Limits, multipv: usize, mut report: impl FnMut(&Report)) -> Report {
        self.start = now_ms();
        self.limits = limits;
        self.nodes = 0;
        self.stopped = false;
        self.age = self.age.wrapping_add(1);
        self.killers = [[Move::NONE; 2]; MAX_PLY + 2];
        for h in self.history.iter_mut() {
            *h /= 8;
        }
        let max_depth = limits.depth.unwrap_or(MAX_PLY as i32 - 8).min(MAX_PLY as i32 - 8);
        let root_moves = pos.legal_moves(self.r);
        let mut best = Report { depth: 0, seldepth: 0, nodes: 0, ms: 0, lines: Vec::new() };
        if root_moves.is_empty() {
            let score = if pos.in_check(self.r, pos.side) { -MATE } else { 0 };
            best.lines.push(Line { score, pv: Vec::new() });
            return best;
        }
        let multipv = multipv.max(1).min(root_moves.len());
        let mut prev_scores: Vec<i32> = vec![0; multipv];
        let mut stable = 0;
        let mut last_best = Move::NONE;
        for depth in 1..=max_depth {
            self.seldepth = 0;
            self.must_finish = depth == 1;
            let mut lines: Vec<Line> = Vec::new();
            self.root_excluded.clear();
            for idx in 0..multipv {
                let mut delta = self.sp.asp_delta;
                let mut alpha = -INF;
                let mut beta = INF;
                if depth >= 4 && !is_mate(prev_scores[idx]) {
                    alpha = prev_scores[idx] - delta;
                    beta = prev_scores[idx] + delta;
                }
                let score = loop {
                    self.keys.clear();
                    self.keys.extend_from_slice(history_keys);
                    self.root_depth = depth + self.depth_offset;
                    let s = self.negamax(pos, depth + self.depth_offset, alpha, beta, 0, true, false);
                    if self.stopped {
                        break s;
                    }
                    if s <= alpha {
                        alpha = (alpha - delta).max(-INF);
                        beta = (alpha + beta) / 2;
                    } else if s >= beta {
                        beta = (beta + delta).min(INF);
                    } else {
                        break s;
                    }
                    delta += delta;
                    if delta > 1000 {
                        alpha = -INF;
                        beta = INF;
                    }
                };
                if self.stopped && (depth > 1 || idx > 0) {
                    // Stopped part-way: a root move that was fully searched and
                    // beat the window is better than the last depth's choice.
                    if multipv == 1 && depth > 1 && self.pv_len[0] > 0 && !best.lines.is_empty() {
                        best.lines[0] = Line { score: self.root_score, pv: self.pv[0][..self.pv_len[0]].to_vec() };
                    }
                    break;
                }
                let pv: Vec<Move> = self.pv[0][..self.pv_len[0]].to_vec();
                if pv.is_empty() {
                    break;
                }
                self.root_excluded.push(pv[0]);
                lines.push(Line { score, pv });
            }
            if self.stopped && (depth > 1) && lines.len() < multipv {
                // Keep the previous depth's complete result, but take a better
                // first line if one finished.
                if let Some(l) = lines.first() {
                    if !best.lines.is_empty() && l.pv.first() == best.lines[0].pv.first() {
                        best.lines[0] = l.clone();
                    }
                }
                break;
            }
            lines.sort_by(|a, b| b.score.cmp(&a.score));
            for (i, l) in lines.iter().enumerate() {
                prev_scores[i] = l.score;
            }
            best = Report { depth, seldepth: self.seldepth, nodes: self.nodes, ms: (now_ms() - self.start), lines };
            report(&best);
            if self.stopped {
                break;
            }
            if multipv == 1 && is_mate(best.lines[0].score) && depth > 8 && (MATE - best.lines[0].score.abs()) < depth {
                break;
            }
            let first = best.lines[0].pv.first().copied().unwrap_or(Move::NONE);
            stable = if first == last_best { stable + 1 } else { 0 };
            last_best = first;
            if let Some(soft) = limits.soft_ms {
                let f = if stable >= 3 { 0.6 } else if stable == 0 && depth > 4 { 1.6 } else { 1.0 };
                if (now_ms() - self.start) as f64 >= soft as f64 * f {
                    break;
                }
            }
            if let Some(ms) = limits.movetime_ms {
                // Don't start a depth we're unlikely to finish.
                if (now_ms() - self.start) * 2 > ms && limits.depth.is_none() {
                    break;
                }
            }
        }
        self.must_finish = false;
        if best.lines.is_empty() {
            // Only possible after an outside "stop" during depth 1.
            best.lines.push(Line { score: 0, pv: vec![root_moves[0]] });
        }
        best.nodes = self.nodes;
        best.ms = now_ms() - self.start;
        best
    }

    /// `search` on `threads` threads (Lazy SMP): helper threads search the
    /// same position with their own move-ordering tables, sharing the hash
    /// table, and stop when this (the main) thread finishes. Only the main
    /// thread's limits and results count; the node total includes helpers.
    /// Native only: the WebAssembly build has no threads.
    #[cfg(not(target_arch = "wasm32"))]
    pub fn search_threads(&mut self, pos: &Position, history_keys: &[u64], limits: Limits, multipv: usize, threads: usize, report: impl FnMut(&Report)) -> Report {
        if threads <= 1 {
            return self.search(pos, history_keys, limits, multipv, report);
        }
        let helper_stop = Arc::new(AtomicBool::new(false));
        let (r, et, params) = (self.r, self.et, self.params);
        let age = self.age;
        let sp = self.sp;
        let use_tables = self.use_tables;
        std::thread::scope(|sc| {
            let mut handles = Vec::new();
            for i in 1..threads {
                let tt = self.tt.clone();
                let hs = helper_stop.clone();
                handles.push(sc.spawn(move || {
                    let mut h = Searcher::new(r, et, params, 1);
                    h.tt = tt;
                    h.sp = sp;
                    h.use_tables = use_tables;
                    h.age = age;
                    h.stop = hs;
                    h.depth_offset = (i % 2) as i32;
                    let lim = Limits { depth: limits.depth, nodes: None, movetime_ms: None, soft_ms: None };
                    h.search(pos, history_keys, lim, 1, |_| {});
                    h.nodes
                }));
            }
            let mut rep = self.search(pos, history_keys, limits, multipv, report);
            helper_stop.store(true, Ordering::SeqCst);
            for h in handles {
                rep.nodes += h.join().unwrap_or(0);
            }
            rep
        })
    }

    /// Without threads (WebAssembly): an ordinary search.
    #[cfg(target_arch = "wasm32")]
    pub fn search_threads(&mut self, pos: &Position, history_keys: &[u64], limits: Limits, multipv: usize, _threads: usize, report: impl FnMut(&Report)) -> Report {
        self.search(pos, history_keys, limits, multipv, report)
    }

    fn is_repetition(&self, p: &Position) -> bool {
        let n = self.keys.len();
        let window = (p.halfmove as usize).min(n);
        for i in 1..=window {
            if self.keys[n - i] == p.key {
                return true;
            }
        }
        false
    }

    /// The hash move is tried before the other moves are even generated: it
    /// often cuts off. If `tt_move` is a move here (in `mode`: a stored move
    /// is checked against this position), makes it the only move in the list
    /// and returns true; `rest_moves` adds the others when it's been searched.
    fn hash_move_first(&self, p: &Position, mode: u8, tt_move: Move, moves: &mut Vec<Move>, scores: &mut Vec<i32>, gains: &mut Vec<i32>) -> bool {
        if tt_move == Move::NONE || !p.is_pseudo_legal(self.r, tt_move, mode, moves) {
            return false;
        }
        moves.clear();
        moves.push(tt_move);
        scores.clear();
        scores.push(10_000_000);
        gains.clear();
        gains.push(NO_GAIN);
        true
    }

    /// After `hash_move_first`: the other moves, in the order they'd have had
    /// if all were generated at once (the hash move swapped to the front).
    fn rest_moves(&self, p: &Position, mode: u8, tt_move: Move, ply: usize, moves: &mut Vec<Move>, scores: &mut Vec<i32>, gains: &mut Vec<i32>) {
        p.gen_pseudo(self.r, moves, mode);
        if let Some(j) = moves[1..].iter().position(|&x| x == tt_move) {
            moves[j + 1] = moves[1];
            moves.remove(1);
        }
        self.order(p, moves, tt_move, ply, scores, gains);
    }

    /// Fills `scores` (move ordering, higher first) for `moves`, and `gains`
    /// with NO_GAIN (capture gains not worked out yet, `select`).
    fn order(&self, p: &Position, moves: &[Move], tt_move: Move, ply: usize, scores: &mut Vec<i32>, gains: &mut Vec<i32>) {
        let us = p.side;
        scores.clear();
        gains.clear();
        gains.resize(moves.len(), NO_GAIN);
        scores.extend(moves
            .iter()
            .map(|m| {
                if *m == tt_move {
                    return 10_000_000;
                }
                let attacker = self.values[kind_of(p.sq[m.from as usize])];
                if m.flags & F_CAPTURE != 0 {
                    // As if it didn't lose material: `select` checks that
                    // when it comes up.
                    let victim = self.values[kind_of(p.sq[victim_square(*m) as usize])];
                    let crack = if m.flags & F_CRACK != 0 { 50 } else { 0 };
                    let ch = self.cap_hist[self.cap_index(p, *m)] as i32 / self.sp.cap_order_div;
                    return 1_000_000 + victim * 16 - attacker / 8 + crack + ch;
                }
                if m.promo != 0 {
                    return 900_000 + self.values[m.promo as usize - 1];
                }
                if m.flags & F_SHIELD != 0 {
                    return 800_000 + self.values[kind_of(p.sq[m.to as usize])] * 4 - attacker / 8;
                }
                if *m == self.killers[ply][0] {
                    return 700_000;
                }
                if *m == self.killers[ply][1] {
                    return 690_000;
                }
                if ply > 0 && *m == self.counter_of(p.side, self.played[ply - 1]) {
                    return 680_000;
                }
                if m.flags & (F_RAISE | F_HAUNT) != 0 {
                    return 600_000 + self.values[m.extra as usize];
                }
                self.history[(us * MAX_SQ + m.from as usize) * MAX_SQ + m.to as usize] + self.cont_score(ply, self.ckey(p, *m))
            }));
    }

    /// Selection sort step: brings the best-ordered of moves `i..` to `i`. A
    /// capture's exchange (`capture_gain`) is only worked out when it comes up
    /// (most nodes cut off before reaching every capture); if it probably
    /// loses material, it goes back after the killers (650,000 instead of
    /// 1,000,000 + crack bonus) and the next best comes up. The order is the
    /// same as if every gain had been worked out first.
    fn select(&self, p: &Position, moves: &mut [Move], scores: &mut [i32], gains: &mut [i32], i: usize) {
        loop {
            let mut bi = i;
            for j in i + 1..moves.len() {
                if scores[j] > scores[bi] {
                    bi = j;
                }
            }
            let m = moves[bi];
            if m.flags & F_CAPTURE != 0 && gains[bi] == NO_GAIN && scores[bi] != 10_000_000 {
                let gain = self.capture_gain(p, m);
                gains[bi] = gain;
                if gain < -self.sp.order_see {
                    scores[bi] -= 350_000 + if m.flags & F_CRACK != 0 { 50 } else { 0 };
                    continue;
                }
            }
            moves.swap(i, bi);
            scores.swap(i, bi);
            gains.swap(i, bi);
            return;
        }
    }

    /// `capture_gain` of move `i`: as `select` worked it out, or now.
    #[inline]
    fn gain_of(&self, p: &Position, moves: &[Move], gains: &[i32], i: usize) -> i32 {
        if gains[i] != NO_GAIN {
            gains[i]
        } else {
            self.capture_gain(p, moves[i])
        }
    }

    /// `ckeys` entry for move `m` in `p`: the moving kind's slot and its
    /// destination, seen from the mover's side.
    #[inline]
    fn ckey(&self, p: &Position, m: Move) -> u32 {
        let k = if m.flags & F_HAUNT != 0 { self.r.haunt_kind as usize } else { kind_of(p.sq[m.from as usize]) };
        let to = if p.side == BLACK { self.flip[m.to as usize] as usize } else { m.to as usize };
        (self.kslot[k & (MAX_KINDS - 1)] as usize * self.r.nsq + to) as u32
    }

    /// Continuation-history score of a move with key `key` at `ply`.
    #[inline]
    fn cont_score(&self, ply: usize, key: u32) -> i32 {
        let stride = self.nslots * self.r.nsq;
        let mut s = 0;
        for back in 0..CONT_PLIES {
            if ply > back {
                let pk = self.ckeys[ply - 1 - back];
                if pk != NO_KEY {
                    s += self.cont[back][pk as usize * stride + key as usize] as i32;
                }
            }
        }
        s
    }

    /// Index of capture `m` (or shield break) in `cap_hist`.
    #[inline]
    fn cap_index(&self, p: &Position, m: Move) -> usize {
        let vs = if m.flags & F_CAPTURE != 0 { victim_square(m) } else { m.to };
        let victim = self.kslot[kind_of(p.sq[vs as usize])] as usize;
        self.ckey(p, m) as usize * self.nslots + victim
    }

    /// What a capture wins if both sides keep recapturing (static exchange
    /// evaluation, `Position::see`).
    #[inline]
    fn capture_gain(&self, p: &Position, m: Move) -> i32 {
        p.see(self.r, m, &self.values)
    }

    #[inline]
    fn counter_of(&self, side: usize, prev: Move) -> Move {
        if prev == Move::NONE {
            return Move::NONE;
        }
        self.counter[(side * MAX_SQ + prev.from as usize) * MAX_SQ + prev.to as usize]
    }

    fn negamax(&mut self, p: &Position, mut depth: i32, mut alpha: i32, mut beta: i32, ply: usize, is_pv: bool, was_null: bool) -> i32 {
        self.pv_len[ply] = 0;
        if self.time_up() {
            return 0;
        }
        let r = self.r;
        let root = ply == 0;
        if !root {
            if self.is_repetition(p) || p.halfmove >= 100 || p.unchanged >= 150 {
                return 0;
            }
            if (p.occupied().count_ones() as usize) <= 5 && p.checkmate_impossible(r) {
                return 0;
            }
            if let Some(s) = self.table_score(p, ply) {
                return s;
            }
            // Mate distance pruning.
            alpha = alpha.max(-MATE + ply as i32);
            beta = beta.min(MATE - ply as i32 - 1);
            if alpha >= beta {
                return alpha;
            }
            if ply >= MAX_PLY {
                return self.eval(p);
            }
        }
        let in_check = p.in_check(r, p.side);
        if in_check && depth < 1 {
            depth = 1;
        }
        if depth <= 0 {
            return self.quiesce(p, alpha, beta, ply, 0);
        }
        self.nodes += 1;
        let excluded = self.excluded[ply];
        // Transposition table.
        let (_, e) = self.tt.probe(p.tt_key(), self.age);
        let mut tt_move = Move::NONE;
        if e.key == p.tt_key() && e.bound != 0 {
            tt_move = e.mv;
            let s = from_tt(e.score as i32, ply);
            if !is_pv && e.depth as i32 >= depth && !root && excluded == Move::NONE {
                if e.bound == B_EXACT || (e.bound == B_LOWER && s >= beta) || (e.bound == B_UPPER && s <= alpha) {
                    return s;
                }
            }
        }
        let raw_eval = if in_check { -INF } else if e.key == p.tt_key() && e.bound != 0 { e.eval as i32 } else { self.eval(p) };
        let corr_slots = if in_check { [0; CORR_TABLES] } else { self.corr_slots(p, if ply > 0 { self.played[ply - 1] } else { Move::NONE }) };
        let static_eval = if in_check { -INF } else { self.corrected(raw_eval, &corr_slots) };
        let us = p.side;
        self.evals[ply] = static_eval;
        // Is our position better than two plies ago? If not, prune harder.
        let improving = !in_check && (ply < 2 || self.evals[ply - 2] == -INF || static_eval > self.evals[ply - 2]);

        if !is_pv && !in_check && !root && excluded == Move::NONE {
            // Reverse futility pruning.
            if depth <= self.sp.rfp_depth && static_eval - self.sp.rfp_margin * depth + if improving { self.sp.rfp_improving } else { 0 } >= beta && !is_mate(beta) {
                return static_eval;
            }
            // Null move: if passing still beats beta, a real move surely will.
            if !was_null && depth >= self.sp.nmp_depth && static_eval >= beta && self.has_pieces(p, us) {
                let mut child = p.clone();
                child.ep = 0;
                child.ep_victim = NO_SQ;
                child.frozen = NO_SQ;
                child.halfmove += 1;
                child.unchanged += 1;
                child.set_side(r, 1 - us);
                child.update_key(r);
                let rd = (self.sp.nmp_base + depth * self.sp.nmp_depth_mul) / 256;
                self.keys.push(p.key);
                self.played[ply] = Move::NONE;
                self.ckeys[ply] = NO_KEY;
                let s = -self.negamax(&child, depth - rd, -beta, -beta + 1, ply + 1, false, true);
                self.keys.pop();
                if self.stopped {
                    return 0;
                }
                if s >= beta {
                    return if is_mate(s) { beta } else { s };
                }
            }
        }

        // Singular extension: if every other move, searched at half depth,
        // falls well short of the hash move's score, the hash move is
        // extended. If even the others beat beta, cut off (multi-cut); if the
        // hash move beats beta without being singular, search it shallower.
        let mut se_ext = 0;
        if !root && depth >= self.sp.se_depth && (ply as i32) < 2 * self.root_depth && tt_move != Move::NONE && excluded == Move::NONE && e.key == p.tt_key() && (e.bound == B_LOWER || e.bound == B_EXACT) && e.depth as i32 >= depth - 3 {
            let tt_score = from_tt(e.score as i32, ply);
            if !is_mate(tt_score) {
                let sbeta = tt_score - self.sp.se_margin * depth / 100;
                self.excluded[ply] = tt_move;
                let s = self.negamax(p, (depth - 1) / 2, sbeta - 1, sbeta, ply, false, false);
                self.excluded[ply] = Move::NONE;
                self.pv_len[ply] = 0;
                self.evals[ply] = static_eval;
                if self.stopped {
                    return 0;
                }
                if s < sbeta {
                    se_ext = 1;
                } else if sbeta >= beta {
                    return sbeta;
                } else if tt_score >= beta {
                    se_ext = -1;
                }
            }
        }

        let mut moves = std::mem::take(&mut self.buffers[ply]);
        let (mut scores, mut gains) = std::mem::take(&mut self.order_bufs[ply]);
        let mut hash_first = !root && excluded == Move::NONE && self.hash_move_first(p, GEN_ALL, tt_move, &mut moves, &mut scores, &mut gains);
        if !hash_first {
            moves.clear();
            p.gen_pseudo(r, &mut moves, GEN_ALL);
            if excluded != Move::NONE {
                moves.retain(|m| *m != excluded);
            }
            if root && !self.root_excluded.is_empty() {
                let ex = self.root_excluded.clone();
                moves.retain(|m| !ex.contains(m));
            }
            self.order(p, &moves, tt_move, ply, &mut scores, &mut gains);
        }
        let mut best = -INF;
        let mut best_move = Move::NONE;
        let mut legal = 0;
        let orig_alpha = alpha;
        let mut quiets_tried = [Move::NONE; 32];
        let mut n_quiets = 0;
        let mut sens: Option<(u128, u128)> = None;
        let mut caps_tried = [Move::NONE; 16];
        let mut n_caps = 0;
        self.keys.push(p.key);
        let mut next = 0;
        loop {
            if next == moves.len() {
                if !hash_first {
                    break;
                }
                hash_first = false;
                self.rest_moves(p, GEN_ALL, tt_move, ply, &mut moves, &mut scores, &mut gains);
                if next == moves.len() {
                    break;
                }
            }
            let i = next;
            next += 1;
            self.select(p, &mut moves, &mut scores, &mut gains, i);
            let m = moves[i];
            // Captures that probably lose a lot, near the leaves.
            if !is_pv && !in_check && depth <= self.sp.see_capture_depth && legal > 0 && m.flags & F_CAPTURE != 0 && best > -MATE_BOUND && self.gain_of(p, &moves, &gains, i) < -self.sp.see_capture * depth {
                continue;
            }
            let quiet = !m.is_tactical() && m.flags & (F_ABILITY | F_CASTLE) == 0;
            // Quiet moves near the leaves, unless they give check. `n`: this
            // move's number among the legal moves, if it's legal.
            let n = legal + 1;
            let sp = &self.sp;
            let prune_quiet = !is_pv && !in_check && quiet && best > -MATE_BOUND && {
                // Late move pruning.
                let lmp_limit = if improving { (sp.lmp_base_imp + depth * depth * sp.lmp_mul_imp) / 100 } else { (sp.lmp_base + depth * depth * sp.lmp_mul) / 100 };
                (depth <= sp.lmp_depth && n > lmp_limit)
                    // Futility pruning: a quiet move can't lift a position
                    // this far below alpha.
                    || (depth <= sp.fut_depth && n > 1 && static_eval + sp.fut_base + sp.fut_mul * depth <= alpha && !is_mate(alpha))
                    // Moves that put a piece where it's simply lost.
                    || (depth <= sp.see_quiet_depth && n > 1 && p.see_quiet(r, m, &self.values) < -sp.see_quiet * depth * depth)
            };
            // Making a move and testing it costs about as much as a leaf node,
            // so skip it if the move is surely legal and surely gives no check;
            // for quiet moves that are searched, those answers save the tests.
            let (mut sure_legal, mut no_check) = (false, false);
            if quiet && !in_check {
                let (checks, pins) = *sens.get_or_insert_with(|| (p.attack_sensitive(r, us, true), p.attack_sensitive(r, 1 - us, false)));
                sure_legal = p.quiet_surely_legal(r, m, pins);
                no_check = !p.quiet_might_check(r, m, checks);
                if prune_quiet && sure_legal && no_check {
                    legal += 1;
                    continue;
                }
            }
            let mut child = p.clone();
            child.make(r, m);
            if !sure_legal && child.leaves_king_attacked(p, r, m) {
                continue;
            }
            legal += 1;
            let gives_check = !no_check && child.in_check(r, child.side);
            if prune_quiet && !gives_check {
                continue;
            }
            self.played[ply] = m;
            let key = self.ckey(p, m);
            self.ckeys[ply] = key;
            let check_ext = if gives_check && ply < 64 { 1 } else { 0 };
            let ext = if m == tt_move && se_ext > 0 && ply < 64 { se_ext } else if m == tt_move && se_ext < 0 { se_ext + check_ext } else { check_ext };
            let new_depth = depth - 1 + ext;
            let score;
            if legal == 1 {
                score = -self.negamax(&child, new_depth, -beta, -alpha, ply + 1, is_pv, false);
            } else {
                let mut red = 0;
                if depth >= self.sp.lmr_depth && quiet && !in_check && !gives_check && legal > if is_pv { self.sp.lmr_moves_pv } else { self.sp.lmr_moves } {
                    red = (self.sp.lmr_base_f + (depth as f32).ln() * (legal as f32).ln() / self.sp.lmr_div_f) as i32;
                    if is_pv {
                        red -= self.sp.lmr_pv;
                    }
                    red -= (self.history[(us * MAX_SQ + m.from as usize) * MAX_SQ + m.to as usize] + self.cont_score(ply, key)) / self.sp.lmr_history;
                    red = red.clamp(0, new_depth - 1);
                }
                let mut s = -self.negamax(&child, new_depth - red, -alpha - 1, -alpha, ply + 1, false, false);
                if s > alpha && red > 0 {
                    s = -self.negamax(&child, new_depth, -alpha - 1, -alpha, ply + 1, false, false);
                }
                if s > alpha && s < beta && is_pv {
                    s = -self.negamax(&child, new_depth, -beta, -alpha, ply + 1, true, false);
                }
                score = s;
            }
            if self.stopped {
                break;
            }
            if quiet && n_quiets < quiets_tried.len() {
                quiets_tried[n_quiets] = m;
                n_quiets += 1;
            }
            if m.is_capture() && n_caps < caps_tried.len() {
                caps_tried[n_caps] = m;
                n_caps += 1;
            }
            if score > best {
                best = score;
                best_move = m;
                if score > alpha {
                    alpha = score;
                    if root {
                        self.root_score = score;
                    }
                    self.pv[ply][0] = m;
                    let n = self.pv_len[ply + 1].min(MAX_PLY - 1);
                    for k in 0..n {
                        self.pv[ply][k + 1] = self.pv[ply + 1][k];
                    }
                    self.pv_len[ply] = n + 1;
                    if score >= beta {
                        // Capture history: the capture that cut off gains, the
                        // captures tried before it lose.
                        let cbonus = (depth * depth * self.sp.hist_mul).min(self.sp.hist_max);
                        for (j, c) in caps_tried[..n_caps].iter().enumerate() {
                            let b = if j + 1 == n_caps && *c == m { cbonus } else { -cbonus };
                            let ci = self.cap_index(p, *c);
                            let h = &mut self.cap_hist[ci];
                            *h += (b - *h as i32 * b.abs() / 16384) as i16;
                        }
                        if quiet {
                            if self.killers[ply][0] != m {
                                self.killers[ply][1] = self.killers[ply][0];
                                self.killers[ply][0] = m;
                            }
                            if ply > 0 {
                                let prev = self.played[ply - 1];
                                if prev != Move::NONE {
                                    self.counter[(us * MAX_SQ + prev.from as usize) * MAX_SQ + prev.to as usize] = m;
                                }
                            }
                            // The move that cut off gains; the quiet moves tried
                            // before it lose (bounded "gravity" updates).
                            let bonus = (depth * depth * self.sp.hist_mul).min(self.sp.hist_max);
                            for (j, q) in quiets_tried[..n_quiets].iter().enumerate() {
                                let b = if j + 1 == n_quiets { bonus } else { -bonus };
                                let h = &mut self.history[(us * MAX_SQ + q.from as usize) * MAX_SQ + q.to as usize];
                                *h += b - *h * b.abs() / 16384;
                                let qk = self.ckey(p, *q) as usize;
                                let stride = self.nslots * self.r.nsq;
                                for back in 0..CONT_PLIES {
                                    if ply > back {
                                        let pk = self.ckeys[ply - 1 - back];
                                        if pk != NO_KEY {
                                            let h = &mut self.cont[back][pk as usize * stride + qk];
                                            *h += (b - *h as i32 * b.abs() / 16384) as i16;
                                        }
                                    }
                                }
                            }
                        }
                        break;
                    }
                }
            }
        }
        self.keys.pop();
        self.buffers[ply] = moves;
        self.order_bufs[ply] = (scores, gains);
        if self.stopped {
            return 0;
        }
        if legal == 0 {
            if excluded != Move::NONE {
                // The excluded move was the only one: it's singular.
                return alpha;
            }
            if root && !self.root_excluded.is_empty() {
                return -INF;
            }
            return if in_check { -MATE + ply as i32 } else { 0 };
        }
        let bound = if best >= beta {
            B_LOWER
        } else if best > orig_alpha {
            B_EXACT
        } else {
            B_UPPER
        };
        // A singular-extension search (one move left out) learns nothing
        // and stores nothing.
        if excluded != Move::NONE {
            return best;
        }
        // Learn how far the search landed from the static evaluation, unless
        // a tactical best move explains it or the bound says nothing about it.
        if !in_check
            && !root
            && !is_mate(best)
            && (best_move == Move::NONE || (!best_move.is_tactical() && best_move.flags & F_ABILITY == 0))
            && !(bound == B_LOWER && best <= static_eval)
            && !(bound == B_UPPER && best >= static_eval)
        {
            self.update_corr(&corr_slots, best - static_eval, depth);
        }
        let (slot, e) = self.tt.probe(p.tt_key(), self.age);
        if e.key != p.tt_key() || depth as i8 >= e.depth - 2 || e.age != self.age || bound == B_EXACT {
            self.tt.store(
                slot,
                TTEntry {
                    key: p.tt_key(),
                    mv: best_move,
                    score: to_tt(best, ply).clamp(-INF, INF) as i16,
                    eval: raw_eval.clamp(-INF, INF) as i16,
                    depth: depth.min(127) as i8,
                    bound,
                    age: self.age,
                },
            );
        }
        best
    }

    /// The endgame tables' exact score for `p` (King and one piece against a
    /// lone King), if they cover it. A mate that would come only after the
    /// 50- or 75-move rule has made the game a draw counts as a draw.
    fn table_score(&mut self, p: &Position, ply: usize) -> Option<i32> {
        if !self.use_tables || p.occupied().count_ones() != 3 {
            return None;
        }
        let result = endgame::probe(p, self.r)?;
        self.nodes += 1;
        let in_time = |d: u16| p.halfmove + (d as u32) < 100 && p.unchanged + (d as u32) < 150;
        Some(match result {
            Probe::Win(d) if in_time(d) => MATE - ply as i32 - d as i32,
            Probe::Loss(d) if in_time(d) => -MATE + ply as i32 + d as i32,
            _ => 0,
        })
    }

    fn has_pieces(&self, p: &Position, team: usize) -> bool {
        p.squares(team).any(|s| {
            let i = &self.r.info[kind_of(p.sq[s])];
            !i.is_pawn && !i.is_king
        })
    }

    /// `qply`: plies since the main search ended. Check evasions (every move)
    /// are only searched near the start: chains of capture-with-check and
    /// evasion can otherwise grow without limit in busy army positions.
    fn quiesce(&mut self, p: &Position, mut alpha: i32, beta: i32, ply: usize, qply: usize) -> i32 {
        self.pv_len[ply] = 0;
        self.nodes += 1;
        if ply > self.seldepth {
            self.seldepth = ply;
        }
        if self.time_up() {
            return 0;
        }
        let r = self.r;
        if ply >= MAX_PLY {
            return self.eval(p);
        }
        if ply > 0 {
            if let Some(s) = self.table_score(p, ply) {
                return s;
            }
        }
        // Transposition table: any stored result is deep enough here.
        let (_, e) = self.tt.probe(p.tt_key(), self.age);
        let hit = e.key == p.tt_key() && e.bound != 0;
        let mut tt_move = Move::NONE;
        if hit {
            let s = from_tt(e.score as i32, ply);
            if e.bound == B_EXACT || (e.bound == B_LOWER && s >= beta) || (e.bound == B_UPPER && s <= alpha) {
                return s;
            }
            tt_move = e.mv;
        }
        let orig_alpha = alpha;
        let in_check = qply < Q_CHECK_PLIES && p.in_check(r, p.side);
        let raw_eval = if in_check { -INF } else if hit { e.eval as i32 } else { self.eval(p) };
        let stand = if in_check { -MATE + ply as i32 } else { self.corrected(raw_eval, &self.corr_slots(p, Move::NONE)) };
        if !in_check {
            if stand >= beta {
                return stand;
            }
            alpha = alpha.max(stand);
        }
        let mut moves = std::mem::take(&mut self.buffers[ply]);
        moves.clear();
        p.gen_pseudo(r, &mut moves, if in_check { GEN_ALL } else { GEN_TACTICAL });
        let (mut scores, mut gains) = std::mem::take(&mut self.order_bufs[ply]);
        self.order(p, &moves, tt_move, ply.min(MAX_PLY), &mut scores, &mut gains);
        let mut best = stand;
        let mut best_move = Move::NONE;
        let mut legal = 0;
        for i in 0..moves.len() {
            self.select(p, &mut moves, &mut scores, &mut gains, i);
            let m = moves[i];
            // Captures that probably lose material.
            if !in_check && m.flags & F_CAPTURE != 0 && self.gain_of(p, &moves, &gains, i) < -self.sp.q_see {
                continue;
            }
            // Delta pruning: even winning this piece can't lift us to alpha.
            if !in_check && m.promo == 0 {
                let gain = if m.flags & F_CAPTURE != 0 {
                    self.values[kind_of(p.sq[victim_square(m) as usize])]
                } else {
                    self.values[kind_of(p.sq[m.to as usize])] / 2
                };
                if stand + gain + self.sp.q_delta < alpha {
                    continue;
                }
            }
            let mut child = p.clone();
            child.make(r, m);
            if child.leaves_king_attacked(p, r, m) {
                continue;
            }
            legal += 1;
            self.ckeys[ply] = self.ckey(p, m);
            let s = -self.quiesce(&child, -beta, -alpha, ply + 1, qply + 1);
            if self.stopped {
                break;
            }
            if s > best {
                best = s;
                best_move = m;
                if s > alpha {
                    alpha = s;
                    self.pv[ply][0] = m;
                    let n = self.pv_len[ply + 1].min(MAX_PLY - 1);
                    for k in 0..n {
                        self.pv[ply][k + 1] = self.pv[ply + 1][k];
                    }
                    self.pv_len[ply] = n + 1;
                    if s >= beta {
                        break;
                    }
                }
            }
        }
        self.buffers[ply] = moves;
        self.order_bufs[ply] = (scores, gains);
        if self.stopped {
            return 0;
        }
        if in_check && legal == 0 {
            return -MATE + ply as i32;
        }
        let (slot, e) = self.tt.probe(p.tt_key(), self.age);
        if e.key != p.tt_key() || e.depth <= 0 || e.age != self.age {
            let bound = if best >= beta {
                B_LOWER
            } else if best > orig_alpha {
                B_EXACT
            } else {
                B_UPPER
            };
            self.tt.store(
                slot,
                TTEntry { key: p.tt_key(), mv: best_move, score: to_tt(best, ply).clamp(-INF, INF) as i16, eval: raw_eval.clamp(-INF, INF) as i16, depth: 0, bound, age: self.age },
            );
        }
        best
    }
}

/// Continuation history: plies back (1 = the opponent's last move; 2 was
/// worse at 6,000 nodes/move).
const CONT_PLIES: usize = 1;

/// Quiescence plies in which a side in check searches all its moves.
const Q_CHECK_PLIES: usize = 6;

/// "+1.25", "-0.40" or "#3" / "#-2" (mate in N moves), for people.
pub fn score_text(s: i32) -> String {
    if s >= MATE_BOUND {
        format!("#{}", (MATE - s + 1) / 2)
    } else if s <= -MATE_BOUND {
        format!("#-{}", (MATE + s) / 2)
    } else {
        format!("{:+.2}", s as f64 / 100.0)
    }
}

/// UCI style: "cp 125" or "mate 3".
pub fn score_uci(s: i32) -> String {
    if s >= MATE_BOUND {
        format!("mate {}", (MATE - s + 1) / 2)
    } else if s <= -MATE_BOUND {
        format!("mate -{}", (MATE + s) / 2)
    } else {
        format!("cp {}", s)
    }
}
