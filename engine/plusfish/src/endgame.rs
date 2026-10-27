//! Endgame tables: exact results for a King and one other piece against a lone
//! King, for every piece type, worked out in advance by `plusfish endgames`
//! and built into the engine (`tables/kxk.bin`).
//!
//! A table gives, for every position, how many plies the lone King's side has
//! left before it is mated (or that it isn't mated: a draw). Only positions with
//! the lone King's side to move are stored, and only half the board (every
//! piece moves the same way mirrored left to right); with the other side to
//! move, `probe` looks one move ahead. Search uses `probe` to score these
//! endings exactly, so Plusfish knows which ones are draws and mates in the
//! fewest moves (before, it drew some King + Vampire against King endings by
//! the 50-move rule).
//!
//! Each table carries a fingerprint of its piece's rules (and the King's), so
//! after a piece changes, its table is simply not used until `plusfish
//! endgames` is run again (see HOW_TO.md).

use crate::defs::*;
use crate::position::*;
use std::sync::OnceLock;

/// The tables, built in (written by `plusfish endgames`).
pub const DATA: &[u8] = include_bytes!("../tables/kxk.bin");

const MAGIC: &[u8; 4] = b"PFEG";
/// Bump when the file layout or the meaning of a table changes.
const VERSION: u8 = 1;

/// Which version of a piece a table is for.
pub const ST_PLAIN: usize = 0;
pub const ST_BROKEN: usize = 1;
pub const ST_GAINED: usize = 2;
pub const ST_CAN_TURN: usize = 3;
pub const STATES: usize = 4;
pub const NO_TABLE: u16 = u16::MAX;

const F_ALL_DRAW: u8 = 1;
const F_FULL_BOARD: u8 = 2;

/// One table's header in `DATA`.
#[derive(Clone, Debug)]
pub struct Entry {
    pub id: String,
    pub state: usize,
    pub piece_fp: u64,
    pub king_fp: u64,
    flags: u8,
    /// Bits per stored value, and how many different values there are.
    nbits: u8,
    dim: usize,
    /// The longest win, in plies (for the summary).
    pub max_plies: u16,
    offset: usize,
    len: usize,
}

impl Entry {
    pub fn all_draw(&self) -> bool {
        self.flags & F_ALL_DRAW != 0
    }
}

/// What a table says about a position, for the side to move.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Probe {
    Draw,
    /// Mates in this many plies.
    Win(u16),
    /// Is mated in this many plies (0 = already mated).
    Loss(u16),
}

// ---------------------------------------------------------------------------
// Fingerprints

fn fnv(text: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in text.bytes() {
        h ^= b as u64;
        h = h.wrapping_mul(0x100000001b3);
    }
    h
}

/// Everything about a piece that changes how it moves or what happens to it
/// (not its name, letter or price), and the same for the form it turns into.
pub fn fingerprint(cat: &Catalog, kind: usize) -> u64 {
    let d = &cat.defs[kind];
    let mut text = format!(
        "{:?}|{}|{}|{:?}|{}|{}|{}|{:?}|{}",
        d.rules, d.types, d.keywords, d.ability, d.dies_on_capture, d.blocks_jumps, d.shield_on_capture, d.protects, d.decoy
    );
    if let Some(form) = d.transforms_into.as_ref().and_then(|id| cat.kind_by_id(id)) {
        text += &format!("|{:x}", fingerprint(cat, form));
    }
    fnv(&text)
}

/// The kinds that get tables: not Kings, not pawn types, nothing that promotes
/// (its table would depend on each game's promotion choices).
pub fn has_tables(d: &PieceDef) -> bool {
    !d.is_king() && !d.is_pawn() && !d.can_promote()
}

/// The table version (`ST_...`) for a piece with code `c`.
pub fn state_of(d: &PieceDef, c: u16) -> usize {
    if d.has_shield() {
        if c & BROKEN != 0 {
            ST_BROKEN
        } else {
            ST_PLAIN
        }
    } else if d.shield_on_capture {
        if c & GAINED != 0 {
            ST_GAINED
        } else {
            ST_PLAIN
        }
    } else if d.ability == Ability::FullMoon && c & USED == 0 {
        ST_CAN_TURN
    } else {
        ST_PLAIN
    }
}

/// The versions of a piece that get tables.
pub fn states_for(d: &PieceDef) -> Vec<usize> {
    if d.has_shield() {
        vec![ST_BROKEN, ST_PLAIN]
    } else if d.shield_on_capture {
        vec![ST_PLAIN, ST_GAINED]
    } else if d.ability == Ability::FullMoon {
        vec![ST_PLAIN, ST_CAN_TURN]
    } else {
        vec![ST_PLAIN]
    }
}

/// The piece code a table is worked out with (White's piece, moved, its
/// ability used unless it's a Werewolf that can still turn).
pub fn code_for(cat: &Catalog, kind: usize, state: usize) -> u16 {
    let d = &cat.defs[kind];
    let mut c = code(kind, WHITE) | MOVED;
    if d.ability != Ability::None && state != ST_CAN_TURN {
        c |= USED;
    }
    match state {
        ST_BROKEN => c | BROKEN,
        ST_GAINED => c | GAINED,
        _ => c,
    }
}

// ---------------------------------------------------------------------------
// Reading the built-in tables

fn read_u16(b: &[u8], at: &mut usize) -> u16 {
    let v = u16::from_le_bytes([b[*at], b[*at + 1]]);
    *at += 2;
    v
}
fn read_u32(b: &[u8], at: &mut usize) -> u32 {
    let v = u32::from_le_bytes(b[*at..*at + 4].try_into().unwrap());
    *at += 4;
    v
}
fn read_u64(b: &[u8], at: &mut usize) -> u64 {
    let v = u64::from_le_bytes(b[*at..*at + 8].try_into().unwrap());
    *at += 8;
    v
}

/// The table headers in `data` (empty if it isn't a table file of this version).
pub fn entries(data: &[u8]) -> Vec<Entry> {
    if data.len() < 7 || &data[0..4] != MAGIC || data[4] != VERSION {
        return Vec::new();
    }
    let mut at = 5;
    let n = read_u16(data, &mut at) as usize;
    let mut out = Vec::with_capacity(n);
    for _ in 0..n {
        let id_len = data[at] as usize;
        at += 1;
        let id = String::from_utf8_lossy(&data[at..at + id_len]).to_string();
        at += id_len;
        let state = data[at] as usize;
        let flags = data[at + 1];
        let nbits = data[at + 2];
        let dim = data[at + 3] as usize;
        at += 4;
        let max_plies = read_u16(data, &mut at);
        let piece_fp = read_u64(data, &mut at);
        let king_fp = read_u64(data, &mut at);
        let offset = read_u32(data, &mut at) as usize;
        let len = read_u32(data, &mut at) as usize;
        out.push(Entry { id, state, piece_fp, king_fp, flags, nbits, dim, max_plies, offset, len });
    }
    out
}

fn builtin() -> &'static [Entry] {
    static E: OnceLock<Vec<Entry>> = OnceLock::new();
    E.get_or_init(|| entries(DATA))
}

/// For each kind in `cat`: the built-in table for each version (`NO_TABLE` =
/// none, or the piece's rules have changed since the tables were made).
pub fn index_for(cat: &Catalog) -> Vec<[u16; STATES]> {
    let king = (0..cat.len()).find(|&k| cat.defs[k].is_king() && !cat.defs[k].is_form);
    let king_fp = king.map(|k| fingerprint(cat, k));
    let es = builtin();
    (0..cat.len())
        .map(|k| {
            let mut slots = [NO_TABLE; STATES];
            if !has_tables(&cat.defs[k]) || king_fp.is_none() {
                return slots;
            }
            let fp = fingerprint(cat, k);
            for (i, e) in es.iter().enumerate() {
                if e.piece_fp == fp && Some(e.king_fp) == king_fp && e.state < STATES {
                    slots[e.state] = i as u16;
                }
            }
            slots
        })
        .collect()
}

/// A table's values, unpacked the first time it's needed.
fn values(i: usize) -> &'static [u8] {
    static T: OnceLock<Vec<OnceLock<Vec<u8>>>> = OnceLock::new();
    let cells = T.get_or_init(|| (0..builtin().len()).map(|_| OnceLock::new()).collect());
    cells[i].get_or_init(|| {
        let e = &builtin()[i];
        let wk = if e.flags & F_FULL_BOARD != 0 { 64 } else { 32 };
        decode(&DATA[e.offset..e.offset + e.len], wk * 64 * 64, e.nbits, e.dim)
    })
}

fn stored_index(wk: usize, x: usize, bk: usize, full: bool) -> usize {
    let w = if full { wk } else { (wk / 8) * 4 + wk % 8 };
    (w * 64 + x) * 64 + bk
}

/// The exact result for `p` if it's a King and one piece against a lone King
/// with a table for that piece (8x8 boards; nothing that could still come back
/// from the Graveyard; no castling).
pub fn probe(p: &Position, r: &Rules) -> Option<Probe> {
    if r.w != 8 || r.h != 8 || r.endgames.is_empty() {
        return None;
    }
    let occ = p.occupied();
    if occ.count_ones() != 3 || p.kings[0].count_ones() != 1 || p.kings[1].count_ones() != 1 {
        return None;
    }
    let xs = (occ & !(p.kings[0] | p.kings[1])).trailing_zeros() as usize;
    let c = p.sq[xs];
    let kind = kind_of(c);
    let strong = team_of(c);
    if p.ghosts[0] != 0 || p.ghosts[1] != 0 || p.frozen != NO_SQ || p.castling_bits(r) != 0 {
        return None;
    }
    let info = &r.info[kind];
    match info.ability {
        Ability::Haunt if c & USED == 0 => return None,
        Ability::RaiseDead if c & USED == 0 && p.raisable(r, strong) => return None,
        Ability::FullMoon if c & USED == 0 && c & MOVED == 0 => return None,
        _ => {}
    }
    if info.first_move && c & MOVED == 0 {
        return None;
    }
    let ti = r.endgames[kind][state_of(r.def(kind), c)];
    if ti == NO_TABLE {
        return None;
    }
    let e = &builtin()[ti as usize];
    if e.all_draw() {
        return Some(Probe::Draw);
    }
    if p.side == strong {
        // One move ahead: the best result among the strong side's moves.
        let moves = p.legal_moves(r);
        let mut best: Option<u16> = None;
        for m in moves {
            let mut child = p.clone();
            child.make(r, m);
            match probe(&child, r)? {
                Probe::Loss(d) => best = Some(best.map_or(d + 1, |b| b.min(d + 1))),
                _ => {}
            }
        }
        return Some(best.map_or(Probe::Draw, Probe::Win));
    }
    let mut wk = p.kings[strong].trailing_zeros() as usize;
    let mut bk = p.kings[1 - strong].trailing_zeros() as usize;
    let mut x = xs;
    if strong == BLACK {
        // Turned round: Black's piece is looked up as White's.
        wk ^= 56;
        bk ^= 56;
        x ^= 56;
    }
    let full = e.flags & F_FULL_BOARD != 0;
    if !full && wk % 8 >= 4 {
        wk ^= 7;
        bk ^= 7;
        x ^= 7;
    }
    let v = values(ti as usize)[stored_index(wk, x, bk, full)];
    Some(if v == 0 { Probe::Draw } else { Probe::Loss(2 * (v as u16 - 1)) })
}

// ---------------------------------------------------------------------------
// Packing: an adaptive binary range coder (as in LZMA), each value predicted
// from the ones already unpacked beside it (the lone King one square to the
// left, one square down, and the piece one square back).

const PROB_BITS: u32 = 11;
const PROB_ONE: u16 = 1 << PROB_BITS;
const MOVE_BITS: u32 = 5;
const TOP: u32 = 1 << 24;

/// Values 0..dim, coded bit by bit (a tree of `1 << nbits` nodes) with
/// probabilities kept per context.
struct Model {
    dim: usize,
    nodes: usize,
    probs: Vec<u16>,
}

impl Model {
    fn new(nbits: u8, dim: usize) -> Model {
        let nodes = 1usize << nbits;
        Model { dim, nodes, probs: vec![PROB_ONE / 2; dim * dim * CTX_BACK.max(1) * nodes] }
    }
    /// The context for entry `i` of `vals` (already known entries only).
    fn context(&self, vals: &[u8], i: usize) -> usize {
        let bk = i % 64;
        let left = if bk % 8 > 0 { vals[i - 1] } else { 0 } as usize;
        let down = if bk >= 8 { vals[i - 8] } else { 0 } as usize;
        // The piece one square back: only whether it matches `left`, or its value.
        let back = if (i / 64) % 64 > 0 { vals[i - 64] as usize } else { 0 };
        let b = match CTX_BACK {
            0 | 1 => 0,
            2 => (back == left) as usize,
            _ => back.min(CTX_BACK - 1),
        };
        ((left * self.dim + down) * CTX_BACK.max(1) + b) * self.nodes
    }
}

/// How the value one piece-square back adds to the context (see `Model::context`).
const CTX_BACK: usize = 2;

struct Encoder {
    low: u64,
    range: u32,
    cache: u8,
    cache_size: u64,
    out: Vec<u8>,
}

impl Encoder {
    fn new() -> Encoder {
        Encoder { low: 0, range: u32::MAX, cache: 0, cache_size: 1, out: Vec::new() }
    }
    fn shift_low(&mut self) {
        if (self.low as u32) < 0xFF00_0000 || (self.low >> 32) != 0 {
            let carry = (self.low >> 32) as u8;
            let mut temp = self.cache;
            loop {
                self.out.push(temp.wrapping_add(carry));
                temp = 0xFF;
                self.cache_size -= 1;
                if self.cache_size == 0 {
                    break;
                }
            }
            self.cache = ((self.low >> 24) & 0xFF) as u8;
        }
        self.cache_size += 1;
        self.low = (self.low & 0x00FF_FFFF) << 8;
    }
    fn bit(&mut self, prob: &mut u16, bit: u32) {
        let bound = (self.range >> PROB_BITS) * *prob as u32;
        if bit == 0 {
            self.range = bound;
            *prob += (PROB_ONE - *prob) >> MOVE_BITS;
        } else {
            self.low += bound as u64;
            self.range -= bound;
            *prob -= *prob >> MOVE_BITS;
        }
        while self.range < TOP {
            self.range <<= 8;
            self.shift_low();
        }
    }
    fn finish(mut self) -> Vec<u8> {
        for _ in 0..5 {
            self.shift_low();
        }
        self.out
    }
}

struct Decoder<'a> {
    data: &'a [u8],
    at: usize,
    range: u32,
    code: u32,
}

impl<'a> Decoder<'a> {
    fn new(data: &'a [u8]) -> Decoder<'a> {
        let mut d = Decoder { data, at: 0, range: u32::MAX, code: 0 };
        for _ in 0..5 {
            d.code = (d.code << 8) | d.next() as u32;
        }
        d
    }
    fn next(&mut self) -> u8 {
        let b = self.data.get(self.at).copied().unwrap_or(0);
        self.at += 1;
        b
    }
    fn bit(&mut self, prob: &mut u16) -> u32 {
        let bound = (self.range >> PROB_BITS) * *prob as u32;
        let bit = if self.code < bound {
            self.range = bound;
            *prob += (PROB_ONE - *prob) >> MOVE_BITS;
            0
        } else {
            self.code -= bound;
            self.range -= bound;
            *prob -= *prob >> MOVE_BITS;
            1
        };
        while self.range < TOP {
            self.range <<= 8;
            self.code = (self.code << 8) | self.next() as u32;
        }
        bit
    }
}

pub fn encode(vals: &[u8], nbits: u8, dim: usize) -> Vec<u8> {
    let mut m = Model::new(nbits, dim);
    let mut enc = Encoder::new();
    for i in 0..vals.len() {
        let ctx = m.context(vals, i);
        let v = vals[i] as u32;
        let mut node = 1usize;
        for b in (0..nbits).rev() {
            let bit = (v >> b) & 1;
            enc.bit(&mut m.probs[ctx + node], bit);
            node = (node << 1) | bit as usize;
        }
    }
    enc.finish()
}

pub fn decode(data: &[u8], n: usize, nbits: u8, dim: usize) -> Vec<u8> {
    let mut m = Model::new(nbits, dim);
    let mut dec = Decoder::new(data);
    let mut vals = vec![0u8; n];
    for i in 0..n {
        let ctx = m.context(&vals, i);
        let mut node = 1usize;
        for _ in 0..nbits {
            let bit = dec.bit(&mut m.probs[ctx + node]);
            node = (node << 1) | bit as usize;
        }
        vals[i] = (node - (1 << nbits)) as u8;
    }
    vals
}

// ---------------------------------------------------------------------------
// Making the tables (`plusfish endgames`)

#[cfg(not(target_arch = "wasm32"))]
pub use make::*;

#[cfg(not(target_arch = "wasm32"))]
mod make {
    use super::*;
    use crate::game::kinds_mask;
    use std::collections::HashMap;
    use std::sync::Arc;

    const UNK: u8 = 0;
    const WIN: u8 = 1;
    const LOSS: u8 = 2;
    const DRAW: u8 = 3;
    const BAD: u8 = 255;
    const N: usize = 2 * 64 * 64 * 64;
    const EXT: u32 = 1 << 31;

    /// A solved table: for every (side, white king, piece, black king), win/loss
    /// for the side to move and the plies to mate.
    pub struct Solved {
        pub state: Vec<u8>,
        pub dist: Vec<u16>,
    }

    fn idx(side: usize, wk: usize, x: usize, bk: usize) -> usize {
        ((side * 64 + wk) * 64 + x) * 64 + bk
    }

    /// Works out one table with Plusfish's own move rules: every position's
    /// moves first, then distances to mate outwards from the mates. `done`:
    /// tables this one's positions can turn into (a broken shield, the wolf).
    pub fn solve(r: &Rules, king: usize, kind: usize, state: usize, done: &HashMap<(usize, usize), Solved>, threads: usize) -> Solved {
        let cat = &*r.cat;
        let xcode = code_for(cat, kind, state);
        let chunk = N / threads + 1;
        let parts: Vec<(Vec<u8>, Vec<u32>, Vec<u32>)> = std::thread::scope(|s| {
            let hs: Vec<_> = (0..threads)
                .map(|t| {
                    s.spawn(move || {
                        let (mut init, mut start, mut kids) = (Vec::new(), Vec::new(), Vec::new());
                        for i in t * chunk..((t + 1) * chunk).min(N) {
                            start.push(kids.len() as u32);
                            let (side, wk, x, bk) = (i / 262144, (i / 4096) % 64, (i / 64) % 64, i % 64);
                            if wk == x || wk == bk || x == bk {
                                init.push(BAD);
                                continue;
                            }
                            let mut p = Position::empty();
                            p.put(r, wk, code(king, WHITE) | MOVED);
                            p.put(r, bk, code(king, BLACK) | MOVED);
                            p.put(r, x, xcode);
                            p.set_side(r, side);
                            p.update_key(r);
                            if p.in_check(r, 1 - side) {
                                init.push(BAD);
                                continue;
                            }
                            match p.outcome(r, &[p.key]) {
                                Outcome::Checkmate => {
                                    init.push(LOSS);
                                    continue;
                                }
                                Outcome::None => {}
                                _ => {
                                    init.push(DRAW);
                                    continue;
                                }
                            }
                            for m in p.legal_moves(r) {
                                let mut c = p.clone();
                                c.make(r, m);
                                let (mut cwk, mut cbk, mut cx) = (NO_SQ as usize, NO_SQ as usize, NO_SQ as usize);
                                for s in 0..64 {
                                    if c.sq[s] == 0 {
                                        continue;
                                    }
                                    if c.kings[WHITE] >> s & 1 == 1 {
                                        cwk = s;
                                    } else if c.kings[BLACK] >> s & 1 == 1 {
                                        cbk = s;
                                    } else {
                                        cx = s;
                                    }
                                }
                                if cx == NO_SQ as usize {
                                    // The piece was taken: King against King.
                                    kids.push(EXT | (DRAW as u32) << 16);
                                    continue;
                                }
                                let cc = c.sq[cx];
                                let key = (kind_of(cc), state_of(r.def(kind_of(cc)), cc));
                                let ci = idx(c.side, cwk, cx, cbk);
                                if key == (kind, state) {
                                    kids.push(ci as u32);
                                } else {
                                    let t = done.get(&key).unwrap_or_else(|| panic!("table for {} needs {:?} first", cat.defs[kind].id, key));
                                    kids.push(EXT | (t.state[ci] as u32) << 16 | t.dist[ci] as u32);
                                }
                            }
                            init.push(UNK);
                        }
                        (init, start, kids)
                    })
                })
                .collect();
            hs.into_iter().map(|h| h.join().unwrap()).collect()
        });
        let mut state_v = Vec::with_capacity(N);
        let mut start = Vec::with_capacity(N + 1);
        let mut kids: Vec<u32> = Vec::new();
        for (a, b, c) in parts {
            let off = kids.len() as u32;
            state_v.extend(a);
            start.extend(b.into_iter().map(|x| x + off));
            kids.extend(c);
        }
        start.push(kids.len() as u32);
        let mut dist = vec![0u16; N];
        // Outwards from the mates: at step i, a position is won in i if some move
        // leads to a loss in i - 1, lost in i if every move leads to a win in
        // fewer. Results from other tables can be any distance, so it keeps going
        // a while after a quiet step.
        let mut quiet = 0;
        for i in 1..u16::MAX {
            let mut changed = Vec::new();
            for p in 0..N {
                if state_v[p] != UNK {
                    continue;
                }
                let (mut win, mut all_win) = (false, true);
                for &k in &kids[start[p] as usize..start[p + 1] as usize] {
                    let (st, d) = if k & EXT != 0 { (((k >> 16) & 0xff) as u8, (k & 0xffff) as u16) } else { (state_v[k as usize], dist[k as usize]) };
                    let known = st != UNK && d < i;
                    if known && st == LOSS {
                        win = true;
                        break;
                    }
                    if !(known && st == WIN) {
                        all_win = false;
                    }
                }
                if win {
                    changed.push((p, WIN));
                } else if all_win {
                    changed.push((p, LOSS));
                }
            }
            if changed.is_empty() {
                quiet += 1;
                if quiet > 300 {
                    break;
                }
                continue;
            }
            quiet = 0;
            for (p, s) in changed {
                state_v[p] = s;
                dist[p] = i;
            }
        }
        for s in state_v.iter_mut() {
            if *s == UNK {
                *s = DRAW;
            }
        }
        Solved { state: state_v, dist }
    }

    /// One line of the summary per table.
    pub struct Summary {
        pub id: String,
        pub state: usize,
        pub win_share: f64,
        pub max_plies: u16,
        pub bytes: usize,
    }

    /// Every table for the pieces in `cat`, as the file `DATA` is read from.
    pub fn make_all(cat: &Arc<Catalog>, threads: usize, mut progress: impl FnMut(&Summary)) -> Vec<u8> {
        let all: Vec<usize> = (0..cat.len()).collect();
        let r = Rules::new(cat.clone(), 8, 8, Vec::new(), true, kinds_mask(all));
        let king = (0..cat.len()).find(|&k| cat.defs[k].is_king() && !cat.defs[k].is_form).expect("no King in the pieces");
        let king_fp = fingerprint(cat, king);
        let mut jobs: Vec<(usize, usize)> = Vec::new();
        for k in 0..cat.len() {
            if has_tables(&cat.defs[k]) {
                for s in states_for(&cat.defs[k]) {
                    jobs.push((k, s));
                }
            }
        }
        // Tables a piece can turn into come first: forms (the wolf), broken shields.
        jobs.sort_by_key(|&(k, s)| (s == ST_CAN_TURN, cat.defs[k].has_shield() && s == ST_PLAIN, !cat.defs[k].is_form, cat.defs[k].id.clone()));
        let mut done: HashMap<(usize, usize), Solved> = HashMap::new();
        let mut headers: Vec<(String, usize, u8, u8, u8, u16, u64, Vec<u8>)> = Vec::new();
        for &(k, s) in &jobs {
            let t = solve(&r, king, k, s, &done, threads);
            // The lone King's side (Black) to move.
            let mut vals = vec![0u8; 64 * 64 * 64];
            let mut symmetric = true;
            let mut max_plies = 0u16;
            let mut wins = (0usize, 0usize);
            for wk in 0..64 {
                for x in 0..64 {
                    for bk in 0..64 {
                        let i = idx(BLACK, wk, x, bk);
                        if t.state[i] == LOSS {
                            assert!(t.dist[i] % 2 == 0, "a loss in an odd number of plies");
                            vals[(wk * 64 + x) * 64 + bk] = (t.dist[i] / 2 + 1) as u8;
                        }
                        let j = idx(WHITE, wk, x, bk);
                        if t.state[j] != BAD {
                            wins.1 += 1;
                            if t.state[j] == WIN {
                                wins.0 += 1;
                                max_plies = max_plies.max(t.dist[j]);
                            }
                        }
                        let m = idx(BLACK, wk ^ 7, x ^ 7, bk ^ 7);
                        if t.state[i] != t.state[m] || (t.state[i] == LOSS && t.dist[i] != t.dist[m]) {
                            symmetric = false;
                        }
                    }
                }
            }
            let stored: Vec<u8> = if symmetric {
                (0..32 * 64 * 64).map(|i| {
                    let (w, rest) = (i / 4096, i % 4096);
                    vals[((w / 4) * 8 + w % 4) * 4096 + rest]
                }).collect()
            } else {
                vals.clone()
            };
            let maxv = stored.iter().copied().max().unwrap_or(0);
            let nbits = (8 - maxv.leading_zeros()).max(1) as u8;
            let all_draw = maxv == 0;
            let dim = maxv as usize + 1;
            let packed = if all_draw { Vec::new() } else { encode(&stored, nbits, dim) };
            assert!(all_draw || decode(&packed, stored.len(), nbits, dim) == stored, "packing {} doesn't round-trip", cat.defs[k].id);
            let flags = (if all_draw { F_ALL_DRAW } else { 0 }) | (if symmetric { 0 } else { F_FULL_BOARD });
            let sum = Summary { id: cat.defs[k].id.clone(), state: s, win_share: wins.0 as f64 / wins.1.max(1) as f64, max_plies, bytes: packed.len() };
            progress(&sum);
            headers.push((cat.defs[k].id.clone(), s, flags, nbits, dim as u8, max_plies, fingerprint(cat, k), packed));
            done.insert((k, s), t);
        }
        // Tables with the same values (a Rook and a Ram) share their data.
        let mut out = Vec::new();
        out.extend_from_slice(MAGIC);
        out.push(VERSION);
        out.extend_from_slice(&(headers.len() as u16).to_le_bytes());
        let head_len: usize = headers.iter().map(|h| 1 + h.0.len() + 4 + 2 + 8 + 8 + 4 + 4).sum();
        let mut data_at = out.len() + head_len;
        let mut blobs: Vec<Vec<u8>> = Vec::new();
        let mut placed: HashMap<Vec<u8>, usize> = HashMap::new();
        for (id, s, flags, nbits, dim, max_plies, fp, packed) in &headers {
            out.push(id.len() as u8);
            out.extend_from_slice(id.as_bytes());
            out.extend_from_slice(&[*s as u8, *flags, *nbits, *dim]);
            out.extend_from_slice(&max_plies.to_le_bytes());
            out.extend_from_slice(&fp.to_le_bytes());
            out.extend_from_slice(&king_fp.to_le_bytes());
            let at = if packed.is_empty() {
                0
            } else if let Some(&at) = placed.get(packed) {
                at
            } else {
                let at = data_at;
                data_at += packed.len();
                placed.insert(packed.clone(), at);
                blobs.push(packed.clone());
                at
            };
            out.extend_from_slice(&(at as u32).to_le_bytes());
            out.extend_from_slice(&(packed.len() as u32).to_le_bytes());
        }
        for b in blobs {
            out.extend_from_slice(&b);
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::eval::{EvalTables, Params, BUILTIN_PARAMS};
    use crate::game::kinds_mask;
    use crate::search::{Limits, Searcher, MATE};
    use std::sync::Arc;

    fn catalog() -> Arc<Catalog> {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../data/pieces");
        Arc::new(Catalog::load_dir(&dir).unwrap())
    }

    fn rules(cat: &Arc<Catalog>) -> Rules {
        Rules::new(cat.clone(), 8, 8, Vec::new(), true, kinds_mask(0..cat.len()))
    }

    /// King + piece v King with these squares (`strong` owns the piece).
    fn position(r: &Rules, kind: usize, state: usize, strong: usize, kings: (usize, usize), x: usize, side: usize) -> Option<Position> {
        let king = (0..r.cat.len()).find(|&k| r.cat.defs[k].is_king() && !r.cat.defs[k].is_form).unwrap();
        let (sk, wk) = kings;
        if sk == wk || sk == x || wk == x {
            return None;
        }
        let mut p = Position::empty();
        p.put(r, sk, code(king, strong) | MOVED);
        p.put(r, wk, code(king, 1 - strong) | MOVED);
        let c = code_for(&r.cat, kind, state);
        p.put(r, x, (c & !(1 << 6)) | ((strong as u16) << 6));
        p.set_side(r, side);
        p.update_key(r);
        if p.in_check(r, 1 - side) {
            return None;
        }
        Some(p)
    }

    #[test]
    fn packing_round_trips() {
        let mut vals = vec![0u8; 3 * 4096];
        let mut seed = 12345u64;
        for (i, v) in vals.iter_mut().enumerate() {
            seed = seed.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            *v = if i % 7 == 0 { 0 } else { ((seed >> 40) % 30) as u8 };
        }
        let packed = encode(&vals, 5, 30);
        assert_eq!(decode(&packed, vals.len(), 5, 30), vals);
    }

    #[test]
    fn the_built_in_tables_fit_these_pieces() {
        let cat = catalog();
        let index = index_for(&cat);
        for k in 0..cat.len() {
            if has_tables(&cat.defs[k]) {
                for s in states_for(&cat.defs[k]) {
                    assert_ne!(index[k][s], NO_TABLE, "no table for {} state {} (run plusfish endgames)", cat.defs[k].id, s);
                }
            }
        }
    }

    #[test]
    fn a_changed_piece_loses_its_table() {
        let mut cat = (*catalog()).clone();
        let rook = cat.kind_by_id("rook").unwrap();
        assert_ne!(index_for(&cat)[rook][ST_PLAIN], NO_TABLE);
        cat.defs[rook].rules[0].max_steps = 3;
        assert_eq!(index_for(&cat)[rook][ST_PLAIN], NO_TABLE);
    }

    #[test]
    fn known_longest_mates() {
        // King + Queen and King + Rook against King: mate in 10 and in 16 at most.
        let es = entries(DATA);
        let longest = |id: &str| es.iter().find(|e| e.id == id && e.state == ST_PLAIN).unwrap().max_plies;
        assert_eq!((longest("queen") + 1) / 2, 10);
        assert_eq!((longest("rook") + 1) / 2, 16);
    }

    /// Every lone-King-to-move position agrees with its moves: mated now = loss
    /// in 0; otherwise a loss in 1 + the longest of the wins its moves lead to,
    /// and a draw if any move escapes. Checks the tables against the engine's
    /// own move rules (and the one-move-ahead lookup for the other side).
    #[test]
    fn tables_agree_with_the_moves() {
        let cat = catalog();
        let r = rules(&cat);
        for id in ["rook", "vampire", "galleon", "paladin", "werewolf", "cavalry"] {
            let k = cat.kind_by_id(id).unwrap();
            for s in states_for(&cat.defs[k]) {
                let mut checked = 0;
                for i in (0..64 * 64 * 64).step_by(if id == "rook" { 1 } else { 7 }) {
                    let (sk, x, wk) = (i / 4096, (i / 64) % 64, i % 64);
                    let Some(p) = position(&r, k, s, WHITE, (sk, wk), x, BLACK) else { continue };
                    let got = probe(&p, &r).unwrap();
                    let moves = p.legal_moves(&r);
                    let want = if moves.is_empty() {
                        if p.in_check(&r, BLACK) { Probe::Loss(0) } else { Probe::Draw }
                    } else {
                        let mut worst: Option<u16> = Some(0);
                        for m in moves {
                            let mut c = p.clone();
                            c.make(&r, m);
                            let v = if c.occupied().count_ones() == 2 { Probe::Draw } else { probe(&c, &r).unwrap() };
                            worst = match (worst, v) {
                                (Some(w), Probe::Win(d)) => Some(w.max(d + 1)),
                                _ => None,
                            };
                        }
                        worst.map_or(Probe::Draw, Probe::Loss)
                    };
                    assert_eq!(got, want, "{} state {}: {}", id, s, crate::game::fen(&p, &r, false));
                    checked += 1;
                }
                assert!(checked > 10_000);
            }
        }
    }

    /// The same position with colours swapped (board turned round) has the
    /// same result.
    #[test]
    fn black_pieces_use_the_same_tables() {
        let cat = catalog();
        let r = rules(&cat);
        let k = cat.kind_by_id("vampire").unwrap();
        for i in (0..64 * 64 * 64).step_by(13) {
            let (sk, x, wk) = (i / 4096, (i / 64) % 64, i % 64);
            for side in 0..2 {
                let a = position(&r, k, ST_PLAIN, WHITE, (sk, wk), x, side);
                let b = position(&r, k, ST_PLAIN, BLACK, (sk ^ 56, wk ^ 56), x ^ 56, 1 - side);
                if let (Some(a), Some(b)) = (a, b) {
                    assert_eq!(probe(&a, &r), probe(&b, &r));
                }
            }
        }
    }

    /// Search without the tables never finds a quicker mate than they say, and
    /// never a mate where they say draw.
    #[test]
    fn search_agrees_with_the_tables() {
        let cat = catalog();
        let r = rules(&cat);
        let et = EvalTables::new(&r);
        let mut params = Params::defaults(&cat);
        params.load_over(&cat, BUILTIN_PARAMS);
        let mut s = Searcher::new(&r, &et, &params, 16);
        s.use_tables = false;
        let mut mates = 0;
        for id in ["queen", "vampire", "jester", "ghost"] {
            let k = cat.kind_by_id(id).unwrap();
            for i in (0..64 * 64 * 64).step_by(997) {
                let (sk, x, wk) = (i / 4096, (i / 64) % 64, i % 64);
                for side in 0..2 {
                    let Some(p) = position(&r, k, ST_PLAIN, WHITE, (sk, wk), x, side) else { continue };
                    let t = probe(&p, &r).unwrap();
                    let rep = s.search(&p, &[], Limits { depth: Some(7), nodes: None, movetime_ms: None, soft_ms: None }, 1, |_| {});
                    let score = rep.lines[0].score;
                    if score.abs() > MATE - 100 {
                        let d = (MATE - score.abs()) as u16;
                        let fen = crate::game::fen(&p, &r, false);
                        match t {
                            Probe::Win(td) => assert!(score > 0 && d >= td, "{}: search mate {} vs table {:?}", fen, score, t),
                            Probe::Loss(td) => assert!(score < 0 && d >= td, "{}: search mate {} vs table {:?}", fen, score, t),
                            Probe::Draw => panic!("{}: search found a mate ({}) in a table draw", fen, score),
                        }
                        mates += 1;
                    }
                }
            }
        }
        assert!(mates > 20, "only {} mates found", mates);
    }
}
