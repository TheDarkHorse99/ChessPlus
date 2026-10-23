//! The rules engine: positions, move generation, attack detection, making moves
//! and game outcomes. It is a straight port of the game's `core/` GDScript
//! (move_generator.gd, game_state.gd), driven entirely by the piece data, just
//! with precomputed tables and copy-make so it runs a few hundred times faster.

use crate::defs::*;
use std::sync::Arc;

pub const MAX_SQ: usize = 128;
pub const WHITE: usize = 0;
pub const BLACK: usize = 1;
pub const NO_SQ: u8 = 255;

// A square holds 0 (empty) or a piece code.
pub const PRESENT: u16 = 1 << 15;
pub const BLACK_BIT: u16 = 1 << 6;
pub const MOVED: u16 = 1 << 7;
pub const BROKEN: u16 = 1 << 8;
pub const USED: u16 = 1 << 9;
/// A shield gained by capturing (the Vampire's).
pub const GAINED: u16 = 1 << 10;
/// "No such kind" in the u8 kind fields below.
pub const NO_KIND: u8 = 255;

#[inline(always)]
pub fn kind_of(c: u16) -> usize {
    (c & 63) as usize
}
#[inline(always)]
pub fn team_of(c: u16) -> usize {
    ((c >> 6) & 1) as usize
}
#[inline(always)]
pub fn code(kind: usize, team: usize) -> u16 {
    PRESENT | kind as u16 | ((team as u16) << 6)
}

// Move flags.
pub const F_CAPTURE: u16 = 1;
pub const F_SHIELD: u16 = 2;
pub const F_EP: u16 = 4;
pub const F_CASTLE: u16 = 8;
pub const F_CRACK: u16 = 16;
pub const F_RAISE: u16 = 32;
pub const F_SKIP: u16 = 64;
/// Haunt: a lost Ghost comes back on `to` (== `from`).
pub const F_HAUNT: u16 = 128;
/// Song of Slumber: the Bard on `from` puts the enemy piece on `to` to sleep.
pub const F_SONG: u16 = 256;
/// Full Moon: the piece on `from` (== `to`) changes into its form.
pub const F_MOON: u16 = 512;
/// A capture a Jester takes instead: the Jester on `extra` swaps places with
/// the piece the capture was aimed at, and is captured.
pub const F_DECOY: u16 = 1024;
/// With F_DECOY: more than one Jester could take this hit, so the attacker
/// chose this one (Mac, Oct 2026; `Move.decoy_choice`). There's one move per
/// Jester, and the move's text names the Jester's square ("c7xe5/d4").
pub const F_CHOICE: u16 = 2048;
/// Every special-ability move.
pub const F_ABILITY: u16 = F_CRACK | F_RAISE | F_HAUNT | F_SONG | F_MOON;

pub const GEN_ALL: u8 = 0;
pub const GEN_CAPTURES: u8 = 1;
pub const GEN_TACTICAL: u8 = 2;

/// One move. `extra` depends on the kind of move: en passant -> the captured
/// piece's square; castling -> the partner's square; Raise Dead and Haunt ->
/// the kind that comes back; a Jester swap (F_DECOY) -> the Jester's square; a
/// multi-step pawn move (F_SKIP) -> its leap count, with `steps` = how many
/// steps it took (for the squares it skipped).
#[derive(Clone, Copy, Debug, PartialEq, Eq, Default, Hash)]
pub struct Move {
    pub from: u8,
    pub to: u8,
    pub flags: u16,
    /// Promotion kind + 1, or 0.
    pub promo: u8,
    pub extra: u8,
    pub steps: u8,
}

impl Move {
    pub const NONE: Move = Move { from: 0, to: 0, flags: 0, promo: 0, extra: 0, steps: 0 };
    #[inline]
    pub fn is_capture(&self) -> bool {
        self.flags & (F_CAPTURE | F_SHIELD) != 0
    }
    #[inline]
    pub fn is_null(&self) -> bool {
        self.from == self.to && self.flags & (F_RAISE | F_HAUNT | F_MOON) == 0
    }
    /// Where the moving piece ends up: `from` if it only broke a shield, shot
    /// (Crack Shot) or sang (Song of Slumber), else `to` (`Move.lands_on`).
    #[inline]
    pub fn lands_on(&self) -> u8 {
        if self.flags & (F_SHIELD | F_CRACK | F_SONG) != 0 {
            self.from
        } else {
            self.to
        }
    }
    #[inline]
    pub fn capture_square(&self) -> u8 {
        if self.flags & F_EP != 0 {
            self.extra
        } else {
            self.to
        }
    }
    /// Captures, shield breaks and promotions: the moves quiescence looks at.
    #[inline]
    pub fn is_tactical(&self) -> bool {
        self.is_capture() || self.promo != 0
    }
}

/// The square of the piece a capture really takes: the Jester's for a Jester
/// swap, else the capture square.
#[inline(always)]
pub fn victim_square(m: Move) -> u8 {
    if m.flags & F_DECOY != 0 {
        m.extra
    } else {
        m.capture_square()
    }
}

#[derive(Clone, Copy, Debug)]
pub struct KindInfo {
    pub is_king: bool,
    pub is_royal: bool,
    pub is_pawn: bool,
    pub can_promote: bool,
    pub castle: bool,
    pub shield: bool,
    pub dies: bool,
    pub ability: Ability,
    pub first_move: bool,
    pub can_capture: bool,
    pub cost: f64,
    /// The Parapet: the other side's pieces can't leap over it.
    pub blocks_jumps: bool,
    /// The Vampire: gains a shield by capturing.
    pub gains_shield: bool,
    /// The Squire: the kinds (bit mask) it protects anywhere in its move pattern.
    pub protects: u64,
    /// The Jester: takes the hit for pieces it reaches.
    pub decoy: bool,
    /// Full Moon: the kind it becomes, or NO_KIND.
    pub form: u8,
    /// The kind it started the game as (a wolf was a Werewolf); itself otherwise.
    pub base: u8,
}

#[derive(Clone, Copy, Debug)]
pub struct Ray {
    pub start: u32,
    pub len: u8,
    pub lim_moved: u8,
    pub lim_unmoved: u8,
    pub mode: Mode,
    pub hop: bool,
    pub leap: u8,
    pub leap_own: bool,
    pub is_path: bool,
    /// Each step is itself a leap (more than one square), which a Parapet stops.
    pub big: bool,
    pub dx: i8,
    pub dy: i8,
}

#[derive(Clone, Debug)]
struct Attacker {
    kind: u8,
    lim_moved: u8,
    lim_unmoved: u8,
    hop: bool,
}

#[derive(Clone, Debug)]
struct Line {
    attackers: Vec<Attacker>,
    plain_mask: u64,
    hop_mask: u64,
    has_hop: bool,
    /// The step is a leap (more than one square): a Parapet can stop it.
    big: bool,
    dx: i32,
    dy: i32,
}

#[derive(Clone, Copy, Debug)]
struct RevRay {
    line: u16,
    start: u32,
    len: u8,
}

pub struct Zobrist {
    pub piece: Vec<u64>, // [sq][kind][team]
    pub broken: Vec<u64>,
    pub used: Vec<u64>,
    pub unmoved: Vec<u64>,
    pub side: u64,
    pub castle: [u64; 16],
    pub ep: Vec<u64>,
    pub lost: Vec<u64>, // [team][kind][count 0..16]
    pub gained: Vec<u64>,
}

/// A well-mixed 64-bit value from `x` (for hash keys made on the fly).
#[inline(always)]
pub fn mix64(x: u64) -> u64 {
    let mut s = x;
    splitmix(&mut s)
}

/// Everything fixed for one game: board size, piece types, promotion choices,
/// and the precomputed move/attack tables.
pub struct Rules {
    pub cat: Arc<Catalog>,
    pub w: i32,
    pub h: i32,
    pub nsq: usize,
    pub info: Vec<KindInfo>,
    /// Promotion choices (kinds), most valuable first.
    pub promo: Vec<u8>,
    pub castle_corner: bool,
    /// Kinds in this game that nothing can leap over (Parapets); 0 = none, and
    /// then none of the leap checks run.
    pub parapets: u64,
    /// Kinds in this game that protect or take hits for others (Squires,
    /// Jesters); 0 = none.
    pub guards: u64,
    /// The Haunt kind (the Ghost), or NO_KIND.
    pub haunt_kind: u8,
    /// Kinds that can ever be on the board in this game (forms included).
    pub kinds_present: u64,
    ray_sq: Vec<u8>,
    rays: Vec<Ray>,
    ray_index: Vec<(u32, u32)>,
    unusual: [u64; 2],
    lines: [Vec<Line>; 2],
    rev_sq: Vec<u8>,
    rev: Vec<RevRay>,
    rev_index: [Vec<(u32, u32)>; 2],
    pub z: Zobrist,
}

fn splitmix(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E3779B97F4A7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
    z ^ (z >> 31)
}

impl Rules {
    /// `kinds_present`: bit mask of piece kinds that can ever be on the board in
    /// this game (on it at the start, promotion choices, lost pieces). The attack
    /// tables cover just those, like `GameState.attack_table`.
    pub fn new(cat: Arc<Catalog>, w: i32, h: i32, promo: Vec<u8>, castle_corner: bool, kinds_present: u64) -> Rules {
        assert!(w >= 1 && h >= 1 && (w * h) as usize <= MAX_SQ && w <= 26, "board too big");
        let nsq = (w * h) as usize;
        let nk = cat.len();
        let maxwh = w.max(h);
        let kind_of_id = |id: &str| cat.kind_by_id(id).map(|k| k as u8).unwrap_or(NO_KIND);
        let mut info: Vec<KindInfo> = cat
            .defs
            .iter()
            .enumerate()
            .map(|(k, d)| KindInfo {
                is_king: d.is_king(),
                is_royal: d.is_royal(),
                is_pawn: d.is_pawn(),
                can_promote: d.can_promote(),
                castle: d.has_castle(),
                shield: d.has_shield(),
                dies: d.dies_on_capture,
                ability: d.ability,
                first_move: d.has_first_move_rule(),
                can_capture: d.can_capture(),
                cost: d.value,
                blocks_jumps: d.blocks_jumps,
                gains_shield: d.shield_on_capture,
                protects: d.protects.iter().filter_map(|id| cat.kind_by_id(id)).fold(0u64, |m, p| m | 1u64 << p),
                decoy: d.decoy,
                form: if d.ability == Ability::FullMoon { d.transforms_into.as_deref().map(kind_of_id).unwrap_or(NO_KIND) } else { NO_KIND },
                base: k as u8,
            })
            .collect();
        for k in 0..nk {
            let f = info[k].form;
            if f != NO_KIND {
                info[f as usize].base = k as u8;
            }
        }
        // A piece that can change also plays as its form, and a lost form
        // comes back (Raise Dead) as what it started as.
        let mut kinds_present = kinds_present;
        for k in 0..nk {
            if kinds_present & (1u64 << k) != 0 {
                if info[k].form != NO_KIND {
                    kinds_present |= 1u64 << info[k].form;
                }
                kinds_present |= 1u64 << info[k].base;
            }
        }
        let present_with = |test: &dyn Fn(&KindInfo) -> bool| -> u64 {
            (0..nk).filter(|&k| kinds_present & (1u64 << k) != 0 && test(&info[k])).fold(0u64, |m, k| m | 1u64 << k)
        };
        let parapets = present_with(&|i| i.blocks_jumps);
        let guards = present_with(&|i| i.protects != 0 || i.decoy);
        let haunt_kind = (0..nk).find(|&k| info[k].ability == Ability::Haunt).map(|k| k as u8).unwrap_or(NO_KIND);
        let lim = |steps: i32| -> u8 { (if steps == 0 { maxwh } else { steps }).clamp(0, 255) as u8 };

        // Forward rays: for each kind, team and square.
        let mut ray_sq = Vec::new();
        let mut rays = Vec::new();
        let mut ray_index = vec![(0u32, 0u32); nk * 2 * nsq];
        let mut unusual = [0u64; 2];
        for k in 0..nk {
            let def = &cat.defs[k];
            for t in 0..2 {
                let flip = if t == WHITE { 1 } else { -1 };
                for s in 0..nsq {
                    let (fx, fy) = ((s as i32) % w, (s as i32) / w);
                    let begin = rays.len() as u32;
                    for rule in &def.rules {
                        if !rule.path.is_empty() {
                            if rule.mode != Mode::MoveOnly {
                                unusual[t] |= 1u64 << k;
                            }
                            for variant in rule.path_variants() {
                                let (mut x, mut y) = (fx, fy);
                                let start = ray_sq.len() as u32;
                                let mut ok = !variant.is_empty();
                                for &(dx, dy) in &variant {
                                    x += dx;
                                    y += dy * flip;
                                    if x < 0 || y < 0 || x >= w || y >= h {
                                        ok = false;
                                        break;
                                    }
                                    ray_sq.push((y * w + x) as u8);
                                }
                                if !ok {
                                    ray_sq.truncate(start as usize);
                                    continue;
                                }
                                rays.push(Ray {
                                    start,
                                    len: variant.len() as u8,
                                    lim_moved: 0,
                                    lim_unmoved: 0,
                                    mode: rule.mode,
                                    hop: false,
                                    leap: 0,
                                    leap_own: false,
                                    is_path: true,
                                    big: false,
                                    dx: 0,
                                    dy: 0,
                                });
                            }
                            continue;
                        }
                        if rule.leap_steps > 0 && rule.mode != Mode::MoveOnly {
                            unusual[t] |= 1u64 << k;
                        }
                        let lm = lim(rule.max_steps);
                        let lu = if rule.first_move_max_steps > 0 { lim(rule.first_move_max_steps) } else { lm };
                        let reach = lm.max(lu) as i32;
                        for &(dx, dy) in &rule.directions {
                            if dx == 0 && dy == 0 {
                                continue;
                            }
                            let (sx, sy) = (dx, dy * flip);
                            let start = ray_sq.len() as u32;
                            let (mut x, mut y) = (fx, fy);
                            let mut n = 0;
                            while n < reach {
                                x += sx;
                                y += sy;
                                if x < 0 || y < 0 || x >= w || y >= h {
                                    break;
                                }
                                ray_sq.push((y * w + x) as u8);
                                n += 1;
                            }
                            if n == 0 {
                                continue;
                            }
                            rays.push(Ray {
                                start,
                                len: n as u8,
                                lim_moved: lm,
                                lim_unmoved: lu,
                                mode: rule.mode,
                                hop: rule.captures_by_hopping,
                                leap: rule.leap_steps.clamp(0, 255) as u8,
                                leap_own: rule.leap_over_own,
                                is_path: false,
                                big: sx.abs() > 1 || sy.abs() > 1,
                                dx: sx as i8,
                                dy: sy as i8,
                            });
                        }
                    }
                    ray_index[(k * 2 + t) * nsq + s] = (begin, rays.len() as u32);
                }
            }
        }

        // Attack lines (MoveGenerator.attack_table), walked back from a target.
        let mut lines: [Vec<Line>; 2] = [Vec::new(), Vec::new()];
        let mut line_steps: [Vec<(i32, i32, i32)>; 2] = [Vec::new(), Vec::new()];
        for t in 0..2 {
            let flip = if t == WHITE { 1 } else { -1 };
            for k in 0..nk {
                if kinds_present & (1u64 << k) == 0 {
                    continue;
                }
                for rule in &cat.defs[k].rules {
                    if rule.mode == Mode::MoveOnly || rule.is_unusual() {
                        continue;
                    }
                    let lm = lim(rule.max_steps);
                    let lu = if rule.first_move_max_steps > 0 { lim(rule.first_move_max_steps) } else { lm };
                    let reach = lm.max(lu) as i32;
                    for &(dx, dy) in &rule.directions {
                        if dx == 0 && dy == 0 {
                            continue;
                        }
                        let step = (dx, dy * flip);
                        let idx = match line_steps[t].iter().position(|&(a, b, _)| (a, b) == step) {
                            Some(i) => i,
                            None => {
                                line_steps[t].push((step.0, step.1, 0));
                                lines[t].push(Line {
                                    attackers: Vec::new(),
                                    plain_mask: 0,
                                    hop_mask: 0,
                                    has_hop: false,
                                    big: step.0.abs() > 1 || step.1.abs() > 1,
                                    dx: step.0,
                                    dy: step.1,
                                });
                                lines[t].len() - 1
                            }
                        };
                        line_steps[t][idx].2 = line_steps[t][idx].2.max(reach);
                        let line = &mut lines[t][idx];
                        line.attackers.push(Attacker { kind: k as u8, lim_moved: lm, lim_unmoved: lu, hop: rule.captures_by_hopping });
                        if rule.captures_by_hopping {
                            line.hop_mask |= 1u64 << k;
                            line.has_hop = true;
                        } else {
                            line.plain_mask |= 1u64 << k;
                        }
                    }
                }
            }
        }
        let mut rev_sq = Vec::new();
        let mut rev = Vec::new();
        let mut rev_index: [Vec<(u32, u32)>; 2] = [vec![(0, 0); nsq], vec![(0, 0); nsq]];
        for t in 0..2 {
            for s in 0..nsq {
                let (tx, ty) = ((s as i32) % w, (s as i32) / w);
                let begin = rev.len() as u32;
                for (li, &(sx, sy, reach)) in line_steps[t].iter().enumerate() {
                    let start = rev_sq.len() as u32;
                    let (mut x, mut y) = (tx, ty);
                    let mut n = 0;
                    while n < reach {
                        x -= sx;
                        y -= sy;
                        if x < 0 || y < 0 || x >= w || y >= h {
                            break;
                        }
                        rev_sq.push((y * w + x) as u8);
                        n += 1;
                    }
                    if n > 0 {
                        rev.push(RevRay { line: li as u16, start, len: n as u8 });
                    }
                }
                rev_index[t][s] = (begin, rev.len() as u32);
            }
        }
        for t in 0..2 {
            unusual[t] &= kinds_present;
        }

        let mut seed = 0x5EED_C0DE_1234_5678u64;
        let mut gen = |n: usize| -> Vec<u64> { (0..n).map(|_| splitmix(&mut seed)).collect() };
        let piece = gen(nsq * MAX_KINDS * 2);
        let broken = gen(nsq);
        let used = gen(nsq);
        let unmoved = gen(nsq);
        let side = gen(1)[0];
        let castle_v = gen(16);
        let mut castle = [0u64; 16];
        castle.copy_from_slice(&castle_v);
        castle[0] = 0;
        let ep = gen(nsq);
        let mut lost = gen(2 * MAX_KINDS * 17);
        for t in 0..2 {
            for k in 0..MAX_KINDS {
                lost[(t * MAX_KINDS + k) * 17] = 0;
            }
        }
        let gained = gen(nsq);
        Rules {
            cat,
            w,
            h,
            nsq,
            info,
            promo,
            castle_corner,
            parapets,
            guards,
            haunt_kind,
            kinds_present,
            ray_sq,
            rays,
            ray_index,
            unusual,
            lines,
            rev_sq,
            rev,
            rev_index,
            z: Zobrist { piece, broken, used, unmoved, side, castle, ep, lost, gained },
        }
    }

    /// True if a leap of (dx, dy) from `from` by a piece of `team` passes over
    /// one of the other side's Parapets on board `sqa` (Mac: a Parapet only
    /// stops its opponents' jumps; `MoveGenerator._leap_blocked`). Squares passed:
    /// none for a one-square step; the squares between for a straight or
    /// diagonal leap; for a Knight-like leap, the long leg first, then the
    /// short one: (1, 2) passes (0, 1) and (0, 2). Only called in games with
    /// Parapets.
    #[cold]
    #[inline(never)]
    pub fn leap_blocked(&self, sqa: &[u16; MAX_SQ], from: usize, dx: i32, dy: i32, team: usize) -> bool {
        let (ax, ay) = (dx.abs(), dy.abs());
        if ax <= 1 && ay <= 1 {
            return false;
        }
        let (sx, sy) = (dx.signum(), dy.signum());
        let (fx, fy) = (self.file(from), self.rank(from));
        let over = |ox: i32, oy: i32| -> bool {
            let (x, y) = (fx + ox, fy + oy);
            if x < 0 || y < 0 || x >= self.w || y >= self.h {
                return false;
            }
            self.stops_jumps(sqa[(y * self.w + x) as usize], team)
        };
        if ax == ay || ax == 0 || ay == 0 {
            (1..ax.max(ay)).any(|k| over(sx * k, sy * k))
        } else if ay > ax {
            (1..=ay).any(|k| over(0, sy * k)) || (1..ax).any(|k| over(sx * k, dy))
        } else {
            (1..=ax).any(|k| over(sx * k, 0)) || (1..ay).any(|k| over(dx, sy * k))
        }
    }

    /// True if `c` is a Parapet (of either side).
    #[inline(always)]
    pub fn is_parapet(&self, c: u16) -> bool {
        c != 0 && self.parapets & (1u64 << kind_of(c)) != 0
    }

    /// True if `c` is a Parapet that `team`'s pieces can't leap over or use
    /// as a Cannon screen: one of the other side's (`MoveGenerator.stops_jumps`).
    #[inline(always)]
    pub fn stops_jumps(&self, c: u16, team: usize) -> bool {
        self.is_parapet(c) && team_of(c) != team
    }

    /// True if the piece `c` has a shield up (Shield keyword unbroken, or one
    /// gained by capturing): a capture only breaks it.
    #[inline(always)]
    pub fn shielded(&self, c: u16) -> bool {
        (self.info[kind_of(c)].shield && c & BROKEN == 0) || c & GAINED != 0
    }

    #[inline(always)]
    pub fn rays_of(&self, kind: usize, team: usize, sq: usize) -> &[Ray] {
        let (a, b) = self.ray_index[(kind * 2 + team) * self.nsq + sq];
        &self.rays[a as usize..b as usize]
    }
    #[inline(always)]
    pub fn ray_squares(&self, r: &Ray) -> &[u8] {
        &self.ray_sq[r.start as usize..r.start as usize + r.len as usize]
    }
    #[inline(always)]
    pub fn file(&self, sq: usize) -> i32 {
        sq as i32 % self.w
    }
    #[inline(always)]
    pub fn rank(&self, sq: usize) -> i32 {
        sq as i32 / self.w
    }
    #[inline(always)]
    pub fn far_rank(&self, team: usize) -> i32 {
        if team == WHITE {
            self.h - 1
        } else {
            0
        }
    }
    #[inline(always)]
    pub fn back_rank(&self, team: usize) -> i32 {
        if team == WHITE {
            0
        } else {
            self.h - 1
        }
    }
    #[inline]
    pub fn def(&self, kind: usize) -> &PieceDef {
        &self.cat.defs[kind]
    }

    #[inline(always)]
    fn piece_key(&self, sq: usize, c: u16) -> u64 {
        let k = kind_of(c);
        let mut h = self.z.piece[(sq * MAX_KINDS + k) * 2 + team_of(c)];
        if c & (BROKEN | USED | GAINED) != 0 {
            if c & BROKEN != 0 {
                h ^= self.z.broken[sq];
            }
            if c & USED != 0 {
                h ^= self.z.used[sq];
            }
            if c & GAINED != 0 {
                h ^= self.z.gained[sq];
            }
        }
        if c & MOVED == 0 && self.info[k].first_move {
            h ^= self.z.unmoved[sq];
        }
        h
    }
    #[inline(always)]
    fn lost_key(&self, team: usize, kind: usize, count: u8) -> u64 {
        self.z.lost[(team * MAX_KINDS + kind) * 17 + (count.min(16) as usize)]
    }
}

#[derive(Clone)]
pub struct Position {
    pub sq: [u16; MAX_SQ],
    pub occ: [u128; 2],
    pub kings: [u128; 2],
    pub side: usize,
    /// Squares the last move's pawn-type piece skipped (en passant targets).
    pub ep: u128,
    pub ep_victim: u8,
    pub halfmove: u32,
    pub fullmove: u32,
    /// Lost pieces per team, as counts per kind (the kind each started the
    /// game as: a lost wolf counts as a Werewolf).
    pub lost: [[u8; MAX_KINDS]; 2],
    /// The lost Ghosts (the Haunt kind) in the order they were lost, oldest
    /// in bit 0: bit set = its Haunt is unused. `ghost_n` = how many.
    pub ghosts: [u16; 2],
    pub ghost_n: [u8; 2],
    /// The piece the last move's Song of Slumber put to sleep (it can't move
    /// this turn), or NO_SQ.
    pub frozen: u8,
    /// Pieces + lost + side, kept up to date move by move.
    pub hash: u64,
    /// `hash` plus castling rights and usable en passant: same key = same
    /// position for repetition (`GameState._position_key`).
    pub key: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Outcome {
    None,
    Checkmate,
    Stalemate,
    FiftyMoves,
    Repetition,
    Insufficient,
    /// Before the first move, the side NOT to move has its king attacked (some
    /// army pairings): that side loses (the game's temporary rule).
    KingExposed,
}

impl Outcome {
    /// White's score (1, 0.5 or 0) if the game is over, with `side` to move.
    pub fn white_score(self, side: usize) -> Option<f64> {
        let side_to_move_wins = if side == WHITE { 1.0 } else { 0.0 };
        match self {
            Outcome::None => None,
            Outcome::Checkmate => Some(1.0 - side_to_move_wins),
            Outcome::KingExposed => Some(side_to_move_wins),
            _ => Some(0.5),
        }
    }
}

#[inline(always)]
fn bits(mut b: u128) -> impl Iterator<Item = usize> {
    std::iter::from_fn(move || {
        if b == 0 {
            None
        } else {
            let s = b.trailing_zeros() as usize;
            b &= b - 1;
            Some(s)
        }
    })
}

impl Position {
    pub fn empty() -> Position {
        Position {
            sq: [0; MAX_SQ],
            occ: [0; 2],
            kings: [0; 2],
            side: WHITE,
            ep: 0,
            ep_victim: NO_SQ,
            halfmove: 0,
            fullmove: 1,
            lost: [[0; MAX_KINDS]; 2],
            ghosts: [0; 2],
            ghost_n: [0; 2],
            frozen: NO_SQ,
            hash: 0,
            key: 0,
        }
    }

    /// The key for the transposition table: `key` plus the sleeping piece,
    /// which changes the moves but not the position for repetition.
    #[inline(always)]
    pub fn tt_key(&self) -> u64 {
        if self.frozen == NO_SQ {
            self.key
        } else {
            self.key ^ mix64(0xF0F0_0000 + self.frozen as u64)
        }
    }

    #[inline(always)]
    fn ghost_key(team: usize, bits: u16, n: u8) -> u64 {
        if n == 0 {
            0
        } else {
            mix64(0x6057_0000_0000 ^ (team as u64) << 32 ^ (n as u64) << 16 ^ bits as u64)
        }
    }

    fn set_ghosts(&mut self, team: usize, bits: u16, n: u8) {
        self.hash ^= Self::ghost_key(team, self.ghosts[team], self.ghost_n[team]) ^ Self::ghost_key(team, bits, n);
        self.ghosts[team] = bits;
        self.ghost_n[team] = n;
    }

    /// A piece of `team` is lost (captured, or a Ram that died): it counts as
    /// the kind it started as, and a Ghost remembers whether it can Haunt.
    pub fn lose(&mut self, r: &Rules, team: usize, c: u16) {
        let k = r.info[kind_of(c)].base;
        self.add_lost(r, team, k as usize, 1);
        if k == r.haunt_kind && self.ghost_n[team] < 16 {
            let n = self.ghost_n[team];
            let bits = self.ghosts[team] | if c & USED == 0 { 1 << n } else { 0 };
            self.set_ghosts(team, bits, n + 1);
        }
    }

    /// Takes a lost Ghost off the list: the first one (Raise Dead), or the
    /// first one that can still Haunt.
    fn take_ghost(&mut self, team: usize, haunting: bool) {
        let (bits, n) = (self.ghosts[team], self.ghost_n[team]);
        if n == 0 {
            return;
        }
        let i = if haunting { bits.trailing_zeros().min(n as u32 - 1) } else { 0 };
        let low = bits & ((1u16 << i) - 1);
        let high = ((bits as u32) >> (i + 1)) as u16;
        self.set_ghosts(team, low | high << i, n - 1);
    }

    #[inline(always)]
    pub fn put(&mut self, r: &Rules, s: usize, c: u16) {
        debug_assert!(self.sq[s] == 0);
        self.sq[s] = c;
        let t = team_of(c);
        self.occ[t] |= 1u128 << s;
        if r.info[kind_of(c)].is_king {
            self.kings[t] |= 1u128 << s;
        }
        self.hash ^= r.piece_key(s, c);
    }

    #[inline(always)]
    pub fn remove(&mut self, r: &Rules, s: usize) -> u16 {
        let c = self.sq[s];
        if c == 0 {
            return 0;
        }
        self.sq[s] = 0;
        let t = team_of(c);
        self.occ[t] &= !(1u128 << s);
        self.kings[t] &= !(1u128 << s);
        self.hash ^= r.piece_key(s, c);
        c
    }

    #[inline(always)]
    fn add_lost(&mut self, r: &Rules, team: usize, kind: usize, delta: i32) {
        let old = self.lost[team][kind];
        let new = (old as i32 + delta).clamp(0, 255) as u8;
        self.hash ^= r.lost_key(team, kind, old) ^ r.lost_key(team, kind, new);
        self.lost[team][kind] = new;
    }

    pub fn set_side(&mut self, r: &Rules, side: usize) {
        if self.side != side {
            self.hash ^= r.z.side;
            self.side = side;
        }
    }

    pub fn set_lost(&mut self, r: &Rules, team: usize, kind: usize, count: u8) {
        let d = count as i32 - self.lost[team][kind] as i32;
        self.add_lost(r, team, kind, d);
    }

    #[inline]
    pub fn occupied(&self) -> u128 {
        self.occ[0] | self.occ[1]
    }

    /// True if a piece of `by` could capture on `s` (`MoveGenerator.attacked_with`).
    pub fn attacked(&self, r: &Rules, s: usize, by: usize) -> bool {
        if r.parapets == 0 {
            self.attacked_with::<false>(r, s, by)
        } else {
            self.attacked_with::<true>(r, s, by)
        }
    }

    /// `attacked`, with the Parapet checks compiled in only when `PP`.
    #[inline(always)]
    fn attacked_with<const PP: bool>(&self, r: &Rules, s: usize, by: usize) -> bool {
        let pp = PP;
        let (a, b) = r.rev_index[by][s];
        for rr in &r.rev[a as usize..b as usize] {
            let line = &r.lines[by][rr.line as usize];
            let mut screens = 0;
            let sqs = &r.rev_sq[rr.start as usize..rr.start as usize + rr.len as usize];
            for (i, &p) in sqs.iter().enumerate() {
                // A leap from here onwards would pass over a Parapet: nothing
                // further along this line can attack.
                if pp && line.big && r.leap_blocked(&self.sq, p as usize, line.dx, line.dy, by) {
                    break;
                }
                let c = self.sq[p as usize];
                if c == 0 {
                    continue;
                }
                if team_of(c) == by {
                    let k = kind_of(c);
                    let mask = if screens == 0 { line.plain_mask } else { line.hop_mask };
                    if mask & (1u64 << k) != 0 {
                        let dist = (i + 1) as u8;
                        let hop = screens == 1;
                        for at in &line.attackers {
                            if at.kind as usize == k && at.hop == hop {
                                let limit = if c & MOVED != 0 { at.lim_moved } else { at.lim_unmoved };
                                if dist <= limit {
                                    return true;
                                }
                            }
                        }
                    }
                }
                screens += 1;
                // An opponent's Parapet can't be a Cannon's screen.
                if screens > 1 || !line.has_hop || (pp && r.stops_jumps(c, by)) {
                    break;
                }
            }
        }
        let um = r.unusual[by];
        if um != 0 {
            for from in bits(self.occ[by]) {
                let c = self.sq[from];
                let k = kind_of(c);
                if um & (1u64 << k) == 0 {
                    continue;
                }
                for ray in r.rays_of(k, by, from) {
                    if ray.mode == Mode::MoveOnly {
                        continue;
                    }
                    if ray.is_path {
                        let sqs = r.ray_squares(ray);
                        if sqs[sqs.len() - 1] as usize == s && sqs[..sqs.len() - 1].iter().all(|&p| self.sq[p as usize] == 0) {
                            return true;
                        }
                    } else if ray.leap > 0 {
                        if Self::ray_reaches(r, &self.sq, ray, from, c, by, s) {
                            return true;
                        }
                    }
                }
            }
        }
        false
    }

    /// Static exchange evaluation: the material balance for the side making
    /// capture `m` if both sides keep recapturing on that square, least
    /// valuable piece first, and each may stop when it suits. `val` gives each
    /// kind's value; kings count as huge and can't capture into an attacked
    /// square. Simplifications: a shield on the contested square ends the
    /// exchange (a Vampire that recaptures gains one); promotions after the
    /// first capture are ignored, and so are Squires and Jesters after the
    /// first capture (the first capture itself is already legal and knows
    /// which piece it really takes).
    pub fn see(&self, r: &Rules, m: Move, val: &[i32]) -> i32 {
        let victim = self.sq[if m.flags & F_DECOY != 0 { m.extra } else { m.capture_square() } as usize];
        if m.flags & F_SHIELD != 0 || victim == 0 {
            return 0;
        }
        self.see_from(r, m, val[kind_of(victim)], val)
    }

    /// The same for a quiet move: what the moving piece stands to lose on its
    /// new square (0 or less). Castling and abilities count as safe.
    pub fn see_quiet(&self, r: &Rules, m: Move, val: &[i32]) -> i32 {
        if m.flags & (F_CASTLE | F_ABILITY | F_SHIELD | F_CAPTURE) != 0 {
            return 0;
        }
        self.see_from(r, m, 0, val)
    }

    fn see_from(&self, r: &Rules, m: Move, vv: i32, val: &[i32]) -> i32 {
        if m.flags & (F_CRACK | F_EP) != 0 {
            // The Archer stays put; en passant: a pawn for a pawn, then
            // whatever happens on the landing square (rare; ignored).
            return vv;
        }
        let from = m.from as usize;
        let s = m.to as usize;
        let mut sqa = self.sq;
        let mut occ = self.occ;
        let mover = sqa[from];
        let us = team_of(mover);
        let king_val = 100_000;
        let piece_val = |c: u16| if r.info[kind_of(c)].is_king { king_val } else { val[kind_of(c)] };
        let mut gain = [0i32; 40];
        gain[0] = vv;
        if r.info[kind_of(mover)].dies {
            return vv - val[kind_of(mover)];
        }
        if m.flags & F_DECOY != 0 {
            // The piece aimed at moves to the Jester's square (still theirs).
            sqa[m.extra as usize] = sqa[s] | MOVED;
        }
        sqa[from] = 0;
        occ[us] &= !(1u128 << from);
        occ[1 - us] &= !(1u128 << s);
        let mut placed = if m.promo != 0 { code(m.promo as usize - 1, us) | MOVED } else { mover | MOVED };
        if m.promo != 0 {
            gain[0] += val[m.promo as usize - 1] - val[kind_of(mover)];
        }
        if m.flags & F_CAPTURE != 0 && r.info[kind_of(placed)].gains_shield && !r.shielded(placed) {
            placed |= GAINED;
        }
        sqa[s] = placed;
        occ[us] |= 1u128 << s;
        let mut on_sq = piece_val(placed);
        let mut side = 1 - us;
        let mut d = 0;
        loop {
            let occupant = sqa[s];
            if r.shielded(occupant) {
                break;
            }
            let a = match Self::least_attacker(r, &sqa, occ, s, side, val) {
                Some(a) => a,
                None => break,
            };
            let ac = sqa[a];
            let ak = kind_of(ac);
            if r.info[ak].is_king {
                // Only if the square isn't defended after taking.
                let mut sq2 = sqa;
                let mut occ2 = occ;
                sq2[a] = 0;
                occ2[side] &= !(1u128 << a);
                occ2[1 - side] &= !(1u128 << s);
                sq2[s] = ac;
                occ2[side] |= 1u128 << s;
                if Self::least_attacker(r, &sq2, occ2, s, 1 - side, val).is_some() {
                    break;
                }
            }
            d += 1;
            if d >= gain.len() {
                break;
            }
            gain[d] = on_sq - gain[d - 1];
            if r.info[ak].dies {
                // A Ram captures and dies: nothing is left on the square.
                gain[d] -= val[ak];
                break;
            }
            if gain[d].max(-gain[d - 1]) < 0 {
                break;
            }
            sqa[a] = 0;
            occ[side] &= !(1u128 << a);
            occ[1 - side] &= !(1u128 << s);
            sqa[s] = ac | MOVED | if r.info[ak].gains_shield { GAINED } else { 0 };
            occ[side] |= 1u128 << s;
            on_sq = piece_val(ac);
            side = 1 - side;
        }
        while d > 0 {
            gain[d - 1] = -(-gain[d - 1]).max(gain[d]);
            d -= 1;
        }
        gain[0]
    }

    /// The least valuable piece of `by` that could capture on `s`, on board
    /// `sqa` (like `attacked`, but finding the cheapest attacker).
    fn least_attacker(r: &Rules, sqa: &[u16; MAX_SQ], occ: [u128; 2], s: usize, by: usize, val: &[i32]) -> Option<usize> {
        if r.parapets == 0 {
            Self::least_attacker_with::<false>(r, sqa, occ, s, by, val)
        } else {
            Self::least_attacker_with::<true>(r, sqa, occ, s, by, val)
        }
    }

    #[inline(always)]
    fn least_attacker_with<const PP: bool>(r: &Rules, sqa: &[u16; MAX_SQ], occ: [u128; 2], s: usize, by: usize, val: &[i32]) -> Option<usize> {
        let mut best: Option<(i32, usize)> = None;
        let mut consider = |from: usize, c: u16| {
            let v = if r.info[kind_of(c)].is_king { 100_000 } else { val[kind_of(c)] };
            if best.map_or(true, |b| v < b.0) {
                best = Some((v, from));
            }
        };
        let pp = PP;
        let (a, b) = r.rev_index[by][s];
        for rr in &r.rev[a as usize..b as usize] {
            let line = &r.lines[by][rr.line as usize];
            let mut screens = 0;
            let sqs = &r.rev_sq[rr.start as usize..rr.start as usize + rr.len as usize];
            for (i, &p) in sqs.iter().enumerate() {
                if pp && line.big && r.leap_blocked(sqa, p as usize, line.dx, line.dy, by) {
                    break;
                }
                let c = sqa[p as usize];
                if c == 0 {
                    continue;
                }
                if team_of(c) == by {
                    let k = kind_of(c);
                    let mask = if screens == 0 { line.plain_mask } else { line.hop_mask };
                    if mask & (1u64 << k) != 0 {
                        let dist = (i + 1) as u8;
                        let hop = screens == 1;
                        for at in &line.attackers {
                            if at.kind as usize == k && at.hop == hop {
                                let limit = if c & MOVED != 0 { at.lim_moved } else { at.lim_unmoved };
                                if dist <= limit {
                                    consider(p as usize, c);
                                    break;
                                }
                            }
                        }
                    }
                }
                screens += 1;
                if screens > 1 || !line.has_hop || (pp && r.stops_jumps(c, by)) {
                    break;
                }
            }
        }
        let um = r.unusual[by];
        if um != 0 {
            for from in bits(occ[by]) {
                let c = sqa[from];
                let k = kind_of(c);
                if um & (1u64 << k) == 0 {
                    continue;
                }
                for ray in r.rays_of(k, by, from) {
                    if ray.mode == Mode::MoveOnly {
                        continue;
                    }
                    let sqs = r.ray_squares(ray);
                    let reaches = if ray.is_path {
                        sqs[sqs.len() - 1] as usize == s && sqs[..sqs.len() - 1].iter().all(|&p| sqa[p as usize] == 0)
                    } else if ray.leap > 0 {
                        Self::ray_reaches(r, sqa, ray, from, c, by, s)
                    } else {
                        false
                    };
                    if reaches {
                        consider(from, c);
                        break;
                    }
                }
            }
        }
        best.map(|b| b.1)
    }

    /// `_rule_reaches` for a leaping rule, on board `sqa`: can the piece `c`
    /// on `from` capture on `s` along `ray`?
    #[inline(always)]
    fn ray_reaches(r: &Rules, sqa: &[u16; MAX_SQ], ray: &Ray, from: usize, c: u16, team: usize, s: usize) -> bool {
        let sqs = r.ray_squares(ray);
        let idx = match sqs.iter().position(|&p| p as usize == s) {
            Some(i) => i,
            None => return false,
        };
        let limit = if c & MOVED != 0 { ray.lim_moved } else { ray.lim_unmoved } as usize;
        if idx < ray.leap as usize || idx + 1 > limit {
            return false;
        }
        let pp = r.parapets != 0;
        if pp && ray.big {
            for j in 0..=idx {
                let prev = if j == 0 { from } else { sqs[j - 1] as usize };
                if r.leap_blocked(sqa, prev, ray.dx as i32, ray.dy as i32, team) {
                    return false;
                }
            }
        }
        for j in 0..idx {
            let p = sqa[sqs[j] as usize];
            if j < ray.leap as usize {
                if pp && r.stops_jumps(p, team) {
                    return false;
                }
                if ray.leap_own && (p == 0 || team_of(p) != team) {
                    return false;
                }
            } else if p != 0 {
                return false;
            }
        }
        true
    }

    /// The squares the piece `c` on `from` could move or capture to by its
    /// rules as the board stands: each line up to and including the first
    /// piece it meets (`MoveGenerator.reach_squares`). The Jester's and Bard's
    /// range.
    pub fn reach(&self, r: &Rules, from: usize, c: u16) -> u128 {
        let pp = r.parapets != 0;
        let moved = c & MOVED != 0;
        let mut a = 0u128;
        for ray in r.rays_of(kind_of(c), team_of(c), from) {
            let sqs = r.ray_squares(ray);
            if ray.is_path {
                let n = sqs.len();
                if sqs[..n - 1].iter().all(|&p| self.sq[p as usize] == 0) {
                    a |= 1u128 << sqs[n - 1];
                }
                continue;
            }
            let limit = (if moved { ray.lim_moved } else { ray.lim_unmoved }).min(ray.len) as usize;
            let leap = ray.leap as usize;
            for i in 0..limit {
                if pp && ray.big {
                    let prev = if i == 0 { from } else { sqs[i - 1] as usize };
                    if r.leap_blocked(&self.sq, prev, ray.dx as i32, ray.dy as i32, team_of(c)) {
                        break;
                    }
                }
                let q = sqs[i] as usize;
                if i >= leap {
                    a |= 1u128 << q;
                }
                let o = self.sq[q];
                if o != 0 && (i >= leap || (pp && r.stops_jumps(o, team_of(c)))) {
                    break;
                }
            }
        }
        a
    }

    /// Every square in the piece's move pattern from `from`, as if nothing
    /// stood in the way (`MoveGenerator.pattern_squares`). The Squire protects
    /// Knights anywhere in it, even with pieces in between (Mac, Oct 2026).
    pub fn pattern(&self, r: &Rules, from: usize, c: u16) -> u128 {
        let moved = c & MOVED != 0;
        let mut a = 0u128;
        for ray in r.rays_of(kind_of(c), team_of(c), from) {
            let sqs = r.ray_squares(ray);
            if ray.is_path {
                a |= 1u128 << sqs[sqs.len() - 1];
                continue;
            }
            let limit = (if moved { ray.lim_moved } else { ray.lim_unmoved }).min(ray.len) as usize;
            for &q in sqs.iter().take(limit).skip(ray.leap as usize) {
                a |= 1u128 << q;
            }
        }
        a
    }

    pub fn in_check(&self, r: &Rules, team: usize) -> bool {
        for k in bits(self.kings[team]) {
            if self.attacked(r, k, 1 - team) {
                return true;
            }
        }
        false
    }

    /// For the search: the squares where a quiet move (no capture,
    /// shield break, promotion, ability or castling; `quiet_might_check`,
    /// `quiet_surely_legal`) could change whether `by` attacks the other
    /// side's king, as `attacked` sees it: for each attack line towards that
    /// king along which one of `by`'s kinds attacks, the squares `attacked`
    /// walks (up to and including the piece that ends the walk); and for each
    /// of `by`'s leaping or path pieces whose capture pattern reaches the
    /// king, its square and the squares on its way. `by_moves`: the move is
    /// `by`'s (it may itself attack along any line); if not, only lines with
    /// an attacker of `by` on them count, and the move mustn't be a Parapet's
    /// (it could stop or free `by`'s leaps; the caller checks). With a
    /// piece of the side to move asleep, every square when `by` is that side
    /// (the sleeping piece may be attacking the king already).
    pub fn attack_sensitive(&self, r: &Rules, by: usize, by_moves: bool) -> u128 {
        if self.frozen != NO_SQ && by == self.side {
            return u128::MAX;
        }
        let pp = r.parapets != 0;
        let mut kinds = 0u64;
        for s in bits(self.occ[by]) {
            kinds |= 1u64 << kind_of(self.sq[s]);
        }
        let mut sens = 0u128;
        for king in bits(self.kings[1 - by]) {
            let (a, b) = r.rev_index[by][king];
            for rr in &r.rev[a as usize..b as usize] {
                let line = &r.lines[by][rr.line as usize];
                if (line.plain_mask | line.hop_mask) & kinds == 0 {
                    continue;
                }
                let hops = line.hop_mask & kinds != 0;
                let mut screens = 0;
                let mut walk = 0u128;
                let mut walking = true;
                // If the move isn't `by`'s, the line only matters with one of
                // `by`'s attackers on it.
                let mut attacker = by_moves;
                for &p in &r.rev_sq[rr.start as usize..rr.start as usize + rr.len as usize] {
                    if pp && line.big && r.leap_blocked(&self.sq, p as usize, line.dx, line.dy, by) {
                        break;
                    }
                    if walking {
                        walk |= 1u128 << p;
                    }
                    let c = self.sq[p as usize];
                    if c == 0 {
                        continue;
                    }
                    if team_of(c) == by && (line.plain_mask | line.hop_mask) & (1u64 << kind_of(c)) != 0 {
                        attacker = true;
                    }
                    if walking {
                        screens += 1;
                        if screens > 1 || !hops || (pp && r.stops_jumps(c, by)) {
                            walking = false;
                        }
                    }
                    if !walking && attacker {
                        break;
                    }
                }
                if attacker {
                    sens |= walk;
                }
            }
            if r.unusual[by] & kinds != 0 {
                for from in bits(self.occ[by]) {
                    let k = kind_of(self.sq[from]);
                    if r.unusual[by] & (1u64 << k) == 0 {
                        continue;
                    }
                    for ray in r.rays_of(k, by, from) {
                        if ray.mode == Mode::MoveOnly || !(ray.is_path || ray.leap > 0) {
                            continue;
                        }
                        let sqs = r.ray_squares(ray);
                        if let Some(idx) = sqs.iter().position(|&q| q as usize == king) {
                            if !ray.is_path || idx + 1 == sqs.len() {
                                sens |= 1u128 << from;
                                for &q in &sqs[..=idx] {
                                    sens |= 1u128 << q;
                                }
                            }
                        }
                    }
                }
            }
        }
        sens
    }

    /// Is quiet move `m` (as in `attack_sensitive`) surely legal? Yes if the
    /// side to move isn't in check, it isn't a king or Parapet move and it
    /// neither leaves nor lands on a square of `sens` =
    /// `attack_sensitive(r, 1 - side, false)`.
    #[inline]
    pub fn quiet_surely_legal(&self, r: &Rules, m: Move, sens: u128) -> bool {
        let info = &r.info[kind_of(self.sq[m.from as usize])];
        !info.is_king && !info.blocks_jumps && sens & (1u128 << m.from | 1u128 << m.to) == 0
    }

    /// Could quiet move `m` (as in `attack_sensitive`) give check? False only
    /// if it surely doesn't: it neither leaves nor lands on a square of `sens`
    /// = `attack_sensitive(r, side, true)`, and if the piece leaps or follows a
    /// path, no such capture pattern from its new square reaches the king.
    #[inline]
    pub fn quiet_might_check(&self, r: &Rules, m: Move, sens: u128) -> bool {
        if sens & (1u128 << m.from | 1u128 << m.to) != 0 {
            return true;
        }
        let us = self.side;
        let k = kind_of(self.sq[m.from as usize]);
        if r.unusual[us] & (1u64 << k) != 0 {
            let kings = self.kings[1 - us];
            for ray in r.rays_of(k, us, m.to as usize) {
                if ray.mode != Mode::MoveOnly && (ray.is_path || ray.leap > 0) && r.ray_squares(ray).iter().any(|&q| kings & (1u128 << q) != 0) {
                    return true;
                }
            }
        }
        false
    }

    #[inline(always)]
    fn push(&self, r: &Rules, kind: usize, us: usize, m: Move, out: &mut Vec<Move>) {
        if r.info[kind].can_promote && m.flags & F_SHIELD == 0 && !r.promo.is_empty() && r.rank(m.to as usize) == r.far_rank(us) {
            for &p in &r.promo {
                let mut pm = m;
                pm.promo = p + 1;
                out.push(pm);
            }
        } else {
            out.push(m);
        }
    }

    #[inline(always)]
    fn hit(&self, r: &Rules, from: usize, to: usize, target: u16) -> Move {
        let flags = if r.shielded(target) { F_SHIELD } else { F_CAPTURE };
        Move { from: from as u8, to: to as u8, flags, promo: 0, extra: 0, steps: 0 }
    }

    /// Every move by the movement rules, not checking whether it leaves the king
    /// in check (`MoveGenerator.pseudo_legal_moves`). `mode`: GEN_ALL, or
    /// GEN_CAPTURES (captures, shield breaks, Crack Shots), or GEN_TACTICAL
    /// (those plus quiet promotions).
    pub fn gen_pseudo(&self, r: &Rules, out: &mut Vec<Move>, mode: u8) {
        self.gen_some(r, out, mode, self.occ[self.side], true);
    }

    /// Is `m` one of the moves `gen_pseudo` gives in `mode`? For a move from
    /// elsewhere (the hash table), so that it can be played before generating
    /// all the moves. `buf`: scratch space.
    pub fn is_pseudo_legal(&self, r: &Rules, m: Move, mode: u8, buf: &mut Vec<Move>) -> bool {
        let from = m.from as usize;
        if from >= r.nsq {
            return false;
        }
        if m.flags & F_HAUNT != 0 {
            return mode == GEN_ALL && m == Move { from: m.from, to: m.from, flags: F_HAUNT, promo: 0, extra: r.haunt_kind, steps: 0 } && self.ghosts[self.side] != 0 && self.sq[from] == 0;
        }
        if self.occ[self.side] & (1u128 << from) == 0 {
            return false;
        }
        buf.clear();
        self.gen_some(r, buf, mode, 1u128 << from, false);
        buf.contains(&m)
    }

    /// `gen_pseudo` for the side to move's pieces on `pieces`, and Haunts if
    /// `haunts`.
    #[inline(always)]
    fn gen_some(&self, r: &Rules, out: &mut Vec<Move>, mode: u8, pieces: u128, haunts: bool) {
        let us = self.side;
        let tactical_only = mode != GEN_ALL;
        let far = r.far_rank(us);
        let pp = r.parapets != 0;
        let first = out.len();
        for from in bits(pieces) {
            // A piece put to sleep by Song of Slumber can't move this turn.
            if from == self.frozen as usize {
                continue;
            }
            let c = self.sq[from];
            let k = kind_of(c);
            let info = r.info[k];
            let promo_quiet = mode == GEN_TACTICAL && info.can_promote && !r.promo.is_empty();
            let first_new = out.len();
            let moved = c & MOVED != 0;
            for ray in r.rays_of(k, us, from) {
                let sqs = r.ray_squares(ray);
                if ray.is_path {
                    let n = sqs.len();
                    if !sqs[..n - 1].iter().all(|&p| self.sq[p as usize] == 0) {
                        continue;
                    }
                    let to = sqs[n - 1] as usize;
                    let t = self.sq[to];
                    if t == 0 {
                        if ray.mode != Mode::CaptureOnly && (!tactical_only || (promo_quiet && r.rank(to) == far)) {
                            self.push(r, k, us, Move { from: from as u8, to: to as u8, ..Move::NONE }, out);
                        }
                    } else if team_of(t) != us && ray.mode != Mode::MoveOnly {
                        self.push(r, k, us, self.hit(r, from, to, t), out);
                    }
                    continue;
                }
                let limit = (if moved { ray.lim_moved } else { ray.lim_unmoved }).min(ray.len) as usize;
                let leap = ray.leap as usize;
                let can_ep = info.is_pawn && ray.mode != Mode::MoveOnly && self.ep != 0;
                let quiet_ok = ray.mode != Mode::CaptureOnly && !tactical_only;
                let quiet_promo = ray.mode != Mode::CaptureOnly && promo_quiet;
                let check_leaps = pp && ray.big;
                for i in 0..limit {
                    if check_leaps {
                        let prev = if i == 0 { from } else { sqs[i - 1] as usize };
                        if r.leap_blocked(&self.sq, prev, ray.dx as i32, ray.dy as i32, us) {
                            break;
                        }
                    }
                    let to = sqs[i] as usize;
                    if i < leap {
                        // Leapt squares: nothing leaps an opponent's Parapet, and
                        // the Rogue can only leap one of its own pieces.
                        let o = self.sq[to];
                        if pp && r.stops_jumps(o, us) {
                            break;
                        }
                        if ray.leap_own && (o == 0 || team_of(o) != us) {
                            break;
                        }
                        continue;
                    }
                    let t = self.sq[to];
                    if t == 0 {
                        if can_ep && self.ep & (1u128 << to) != 0 && self.ep_victim != NO_SQ {
                            let v = self.sq[self.ep_victim as usize];
                            if v != 0 && team_of(v) != us && r.info[kind_of(v)].is_pawn {
                                let m = Move { from: from as u8, to: to as u8, flags: F_CAPTURE | F_EP, promo: 0, extra: self.ep_victim, steps: 0 };
                                self.push(r, k, us, m, out);
                                continue;
                            }
                        }
                        if quiet_ok || (quiet_promo && r.rank(to) == far) {
                            let mut m = Move { from: from as u8, to: to as u8, ..Move::NONE };
                            if info.is_pawn && i > leap {
                                m.flags = F_SKIP;
                                m.steps = (i + 1) as u8;
                                m.extra = leap as u8;
                            }
                            self.push(r, k, us, m, out);
                        }
                        continue;
                    }
                    if ray.hop {
                        // An opponent's Parapet can't be a Cannon's screen.
                        if ray.mode != Mode::MoveOnly && !(pp && r.stops_jumps(t, us)) {
                            for j in i + 1..limit {
                                let s2 = sqs[j] as usize;
                                let t2 = self.sq[s2];
                                if t2 == 0 {
                                    continue;
                                }
                                if team_of(t2) != us {
                                    self.push(r, k, us, self.hit(r, from, s2, t2), out);
                                }
                                break;
                            }
                        }
                    } else if team_of(t) != us && ray.mode != Mode::MoveOnly {
                        self.push(r, k, us, self.hit(r, from, to, t), out);
                    }
                    break;
                }
            }
            if !tactical_only && info.is_king && !moved {
                self.gen_castling(r, from, out);
            }
            if c & USED == 0 {
                match info.ability {
                    Ability::CrackShot => {
                        let end = out.len();
                        for i in first_new..end {
                            let m = out[i];
                            if m.is_capture() && m.promo == 0 {
                                let mut shot = m;
                                shot.flags |= F_CRACK;
                                shot.flags &= !F_SKIP;
                                out.push(shot);
                            }
                        }
                    }
                    Ability::RaiseDead if !tactical_only => {
                        for kk in 0..r.info.len() {
                            if self.lost[us][kk] > 0 && !r.info[kk].is_pawn && r.info[kk].ability != Ability::RaiseDead {
                                out.push(Move { from: from as u8, to: from as u8, flags: F_RAISE, promo: 0, extra: kk as u8, steps: 0 });
                            }
                        }
                    }
                    Ability::SongOfSlumber if !tactical_only => {
                        // Any enemy piece it could reach, except a king.
                        for s in bits(self.reach(r, from, c) & self.occ[1 - us]) {
                            if !r.info[kind_of(self.sq[s])].is_king {
                                out.push(Move { from: from as u8, to: s as u8, flags: F_SONG, ..Move::NONE });
                            }
                        }
                    }
                    Ability::FullMoon if !tactical_only && info.form != NO_KIND => {
                        out.push(Move { from: from as u8, to: from as u8, flags: F_MOON, ..Move::NONE });
                    }
                    _ => {}
                }
            }
        }
        // Haunt: a lost Ghost that hasn't used it can come back onto any empty
        // square.
        if haunts && !tactical_only && self.ghosts[us] != 0 {
            let empty = !self.occupied();
            for s in 0..r.nsq {
                if empty & (1u128 << s) != 0 {
                    out.push(Move { from: s as u8, to: s as u8, flags: F_HAUNT, promo: 0, extra: r.haunt_kind, steps: 0 });
                }
            }
        }
        if r.guards != 0 {
            self.apply_guards(r, out, first);
        }
    }

    /// The enemy's Squires and Jesters change the side to move's captures
    /// (`MoveGenerator._apply_guards`): a protected piece (a Knight anywhere
    /// in a Squire's move pattern, even through pieces) can't be captured,
    /// and a capture of a piece a Jester could reach (not a pawn type, king
    /// or Jester) becomes a swap in which the Jester is captured instead. If
    /// more than one Jester could take the hit, the attacker chooses which
    /// (Mac, Oct 2026): the capture becomes one move per Jester (F_CHOICE).
    fn apply_guards(&self, r: &Rules, out: &mut Vec<Move>, first: usize) {
        let them = 1 - self.side;
        let mut protected = 0u128;
        let mut jesters: Vec<(usize, u128)> = Vec::new();
        for s in bits(self.occ[them]) {
            let c = self.sq[s];
            let info = &r.info[kind_of(c)];
            if info.protects == 0 && !info.decoy {
                continue;
            }
            if info.protects != 0 {
                for q in bits(self.pattern(r, s, c) & self.occ[them]) {
                    if info.protects & (1u64 << kind_of(self.sq[q])) != 0 {
                        protected |= 1u128 << q;
                    }
                }
            }
            if info.decoy {
                jesters.push((s, self.reach(r, s, c)));
            }
        }
        if protected == 0 && jesters.is_empty() {
            return;
        }
        let mut kept = first;
        // The other Jesters' versions of captures two or more could take:
        // added at the end, since the list is compacted in place.
        let mut choices: Vec<Move> = Vec::new();
        for i in first..out.len() {
            let mut m = out[i];
            if m.flags & F_CAPTURE != 0 {
                let cs = m.capture_square() as usize;
                if protected & (1u128 << cs) != 0 {
                    continue;
                }
                let ti = &r.info[kind_of(self.sq[cs])];
                if !ti.is_pawn && !ti.is_king && !ti.decoy {
                    let mut reaching = jesters.iter().filter(|j| j.1 & (1u128 << cs) != 0).map(|j| j.0);
                    if let Some(js) = reaching.next() {
                        m.flags |= F_DECOY;
                        m.extra = js as u8;
                        for other in reaching {
                            m.flags |= F_CHOICE;
                            choices.push(Move { flags: m.flags, extra: other as u8, ..m });
                        }
                    }
                }
            }
            out[kept] = m;
            kept += 1;
        }
        out.truncate(kept);
        out.extend(choices);
    }

    fn gen_castling(&self, r: &Rules, king: usize, out: &mut Vec<Move>) {
        let us = self.side;
        let them = 1 - us;
        let (kx, ky) = (r.file(king), r.rank(king));
        let mut checked = false;
        for dir in [-1i32, 1] {
            let mut x = kx + dir;
            let mut partner = None;
            while x >= 0 && x < r.w {
                let s = (ky * r.w + x) as usize;
                if self.sq[s] != 0 {
                    partner = Some(s);
                    break;
                }
                x += dir;
            }
            let p = match partner {
                Some(p) => p,
                None => continue,
            };
            if (r.file(p) - kx).abs() < 3 {
                continue;
            }
            let pc = self.sq[p];
            if team_of(pc) != us || !r.info[kind_of(pc)].castle || pc & MOVED != 0 {
                continue;
            }
            if r.castle_corner {
                let px = r.file(p);
                if r.rank(p) != r.back_rank(us) || (px != 0 && px != r.w - 1) {
                    continue;
                }
            }
            if !checked {
                if self.attacked(r, king, them) {
                    return;
                }
                checked = true;
            }
            let crossed = (king as i32 + dir) as usize;
            if self.attacked(r, crossed, them) {
                continue;
            }
            out.push(Move { from: king as u8, to: (king as i32 + 2 * dir) as u8, flags: F_CASTLE, promo: 0, extra: p as u8, steps: 0 });
        }
    }

    /// Plays a move (`GameState.make_move`). The position must be a copy if you
    /// want the old one back: there's no undo (copying is cheap).
    pub fn make(&mut self, r: &Rules, m: Move) {
        self.frozen = NO_SQ;
        if m.flags & (F_HAUNT | F_RAISE | F_SONG | F_MOON) != 0 {
            self.make_ability(r, m);
            return;
        }
        let us = self.side;
        let them = 1 - us;
        let from = m.from as usize;
        let to = m.to as usize;
        let mut c = self.sq[from];
        let k = kind_of(c);
        if m.is_capture() || r.info[k].is_pawn {
            self.halfmove = 0;
        } else {
            self.halfmove += 1;
        }
        if m.flags & F_CRACK != 0 {
            self.remove(r, from);
            c |= USED;
            self.put(r, from, c);
        }
        self.ep = 0;
        self.ep_victim = NO_SQ;
        if m.flags & F_SHIELD != 0 {
            // A gained shield (Vampire) goes first; otherwise the Shield breaks.
            let t = self.remove(r, to);
            self.put(r, to, if t & GAINED != 0 { t & !GAINED } else { t | BROKEN });
            if r.info[k].dies {
                self.remove(r, from);
                self.lose(r, us, c);
            }
            self.next_turn(r);
            return;
        }
        let cs = m.capture_square() as usize;
        if m.flags & F_DECOY != 0 {
            // The Jester takes the hit: the piece aimed at moves to the
            // Jester's square and the Jester stands where it was.
            let js = m.extra as usize;
            let jc = self.remove(r, js);
            let tc = self.remove(r, cs);
            self.put(r, js, tc | MOVED);
            self.put(r, cs, jc);
        }
        if m.flags & F_CRACK != 0 {
            let t = self.remove(r, cs);
            self.lose(r, them, t);
            self.next_turn(r);
            return;
        }
        // A Vampire gains a shield by capturing (if it hasn't one).
        if m.flags & F_CAPTURE != 0 && r.info[k].gains_shield && !r.shielded(c) {
            c |= GAINED;
        }
        self.remove(r, from);
        if m.flags & F_CAPTURE != 0 {
            let t = self.remove(r, cs);
            self.lose(r, them, t);
        }
        if m.promo != 0 {
            self.put(r, to, code(m.promo as usize - 1, us) | MOVED);
        } else {
            self.put(r, to, c | MOVED);
        }
        if m.flags & F_CASTLE != 0 {
            let pf = m.extra as usize;
            let pc = self.remove(r, pf);
            let dir = if to > from { 1 } else { -1 };
            self.put(r, (from as i32 + dir) as usize, pc | MOVED);
        }
        if m.flags & F_CAPTURE != 0 && r.info[k].dies {
            self.remove(r, to);
            self.lose(r, us, c);
        }
        if m.flags & F_SKIP != 0 {
            let n = m.steps as i32;
            let (dx, dy) = ((r.file(to) - r.file(from)) / n, (r.rank(to) - r.rank(from)) / n);
            for j in m.extra as i32..n - 1 {
                let x = r.file(from) + dx * (j + 1);
                let y = r.rank(from) + dy * (j + 1);
                self.ep |= 1u128 << (y * r.w + x);
            }
            if self.ep != 0 {
                self.ep_victim = to as u8;
            }
        }
        self.next_turn(r);
    }

    /// Raise Dead, Haunt, Song of Slumber and Full Moon: none of them moves a
    /// piece across the board or captures.
    #[cold]
    #[inline(never)]
    fn make_ability(&mut self, r: &Rules, m: Move) {
        let us = self.side;
        let from = m.from as usize;
        let to = m.to as usize;
        self.ep = 0;
        self.ep_victim = NO_SQ;
        if m.flags & F_HAUNT != 0 {
            // A lost Ghost comes back, its Haunt used.
            let g = m.extra as usize;
            if r.info[g].is_pawn {
                self.halfmove = 0;
            } else {
                self.halfmove += 1;
            }
            self.add_lost(r, us, g, -1);
            self.take_ghost(us, true);
            self.put(r, to, code(g, us) | MOVED | USED);
            self.next_turn(r);
            return;
        }
        let c = self.remove(r, from) | USED;
        let k = kind_of(c);
        if r.info[k].is_pawn {
            self.halfmove = 0;
        } else {
            self.halfmove += 1;
        }
        if m.flags & F_RAISE != 0 {
            // The Necromancer leaves; a fresh copy of the lost piece takes its square.
            let raised = m.extra as usize;
            self.add_lost(r, us, raised, -1);
            if raised as u8 == r.haunt_kind {
                self.take_ghost(us, false);
            }
            self.put(r, from, code(raised, us) | MOVED);
        } else if m.flags & F_MOON != 0 {
            // The Werewolf becomes the wolf where it stands.
            self.put(r, from, (c & !63) | r.info[k].form as u16);
        } else {
            // Song of Slumber: nothing moves; the target can't move next turn.
            self.put(r, from, c);
            self.frozen = m.to;
        }
        self.next_turn(r);
    }

    fn next_turn(&mut self, r: &Rules) {
        if self.side == BLACK {
            self.fullmove += 1;
        }
        self.side = 1 - self.side;
        self.hash ^= r.z.side;
        self.update_key(r);
    }

    /// Recomputes `key`: the running hash plus castling rights (as FEN writes
    /// them) and en passant, if a legal en passant capture exists.
    pub fn update_key(&mut self, r: &Rules) {
        let mut key = self.hash ^ r.z.castle[self.castling_bits(r) as usize];
        if self.ep != 0 {
            let mut moves = Vec::with_capacity(32);
            self.gen_pseudo(r, &mut moves, GEN_CAPTURES);
            for m in moves {
                // Same test as the game: a legal move whose capture square isn't
                // where it lands (en passant). Making it clears en passant, so
                // this never recurses more than once.
                if m.capture_square() != m.to && self.is_legal(r, m) {
                    key = key.wrapping_add(r.z.ep[m.to as usize]);
                }
            }
        }
        self.key = key;
    }

    /// Castling rights as 4 bits (white K, white Q, black K, black Q), worked out
    /// like `Fen._castling_text`.
    pub fn castling_bits(&self, r: &Rules) -> u8 {
        let mut b = 0u8;
        for team in 0..2 {
            let ks = self.kings[team];
            if ks == 0 {
                continue;
            }
            let king = ks.trailing_zeros() as usize;
            if self.sq[king] & MOVED != 0 {
                continue;
            }
            for (bit, dir) in [(0u8, 1i32), (1u8, -1i32)] {
                let mut x = r.file(king) + dir;
                let y = r.rank(king);
                while x >= 0 && x < r.w {
                    let p = self.sq[(y * r.w + x) as usize];
                    if p != 0 && team_of(p) == team && r.info[kind_of(p)].castle && p & MOVED == 0 {
                        b |= 1 << (team as u8 * 2 + bit);
                        break;
                    }
                    x += dir;
                }
            }
        }
        b
    }

    pub fn legal_moves(&self, r: &Rules) -> Vec<Move> {
        let mut pseudo = Vec::with_capacity(64);
        self.gen_pseudo(r, &mut pseudo, GEN_ALL);
        pseudo.retain(|&m| self.is_legal(r, m));
        pseudo
    }

    #[inline]
    pub fn is_legal(&self, r: &Rules, m: Move) -> bool {
        let mut child = self.clone();
        child.make(r, m);
        !child.leaves_king_attacked(self, r, m)
    }

    /// After `m` was played from `before`: is one of the mover's kings attacked?
    /// Like `MoveGenerator.legal_moves`, it checks the squares the kings stood
    /// on before the move (moved along if the king itself moved), so a king
    /// brought back by Raise Dead doesn't count yet.
    #[inline]
    pub fn leaves_king_attacked(&self, before: &Position, r: &Rules, m: Move) -> bool {
        let us = before.side;
        let mut ks = before.kings[us];
        let from_bit = 1u128 << m.from;
        if ks & from_bit != 0 {
            ks &= !from_bit;
            ks |= 1u128 << m.lands_on();
        }
        if m.flags & F_SONG != 0 {
            // A piece put to sleep can't capture next turn, so its attacks
            // don't count: it's lifted off the board while looking.
            let mut lifted = self.clone();
            lifted.remove(r, m.to as usize);
            return bits(ks).any(|k| lifted.attacked(r, k, 1 - us));
        }
        for k in bits(ks) {
            if self.attacked(r, k, 1 - us) {
                return true;
            }
        }
        false
    }

    pub fn has_legal_move(&self, r: &Rules) -> bool {
        let mut pseudo = Vec::with_capacity(64);
        self.gen_pseudo(r, &mut pseudo, GEN_ALL);
        pseudo.into_iter().any(|m| self.is_legal(r, m))
    }

    /// Kinds of lost pieces Raise Dead could bring back for `team`.
    pub fn raisable(&self, r: &Rules, team: usize) -> bool {
        (0..r.info.len()).any(|k| self.lost[team][k] > 0 && !r.info[k].is_pawn && r.info[k].ability != Ability::RaiseDead)
    }

    /// `GameState._checkmate_impossible`.
    pub fn checkmate_impossible(&self, r: &Rules) -> bool {
        for team in 0..2 {
            // A Ghost that can still come back changes everything.
            if self.ghosts[team] != 0 {
                return false;
            }
            if self.raisable(r, team) {
                for s in bits(self.occ[team]) {
                    let c = self.sq[s];
                    if c & USED == 0 && r.info[kind_of(c)].ability == Ability::RaiseDead {
                        return false;
                    }
                }
            }
        }
        let mut others: Vec<usize> = Vec::new();
        let mut colors = [false; 2];
        let mut non_capturers = 0;
        for s in bits(self.occupied()) {
            let k = kind_of(self.sq[s]);
            let info = &r.info[k];
            if info.is_king {
                continue;
            }
            if info.is_pawn {
                return false;
            }
            if !info.can_capture {
                non_capturers += 1;
                continue;
            }
            others.push(k);
            colors[((r.file(s) + r.rank(s)) % 2) as usize] = true;
        }
        if others.is_empty() {
            return true;
        }
        if non_capturers > 0 {
            return false;
        }
        if others.len() == 1 && r.def(others[0]).is_distant_leaper() {
            return true;
        }
        for &k in &others {
            if !r.def(k).stays_on_one_color() {
                return false;
            }
        }
        colors[0] != colors[1]
    }

    /// How the game stands (`GameState.outcome`). `keys`: the repetition key of
    /// every position so far, oldest first, ending with this one.
    pub fn outcome(&self, r: &Rules, keys: &[u64]) -> Outcome {
        if keys.len() <= 1 && self.in_check(r, 1 - self.side) {
            return Outcome::KingExposed;
        }
        if !self.has_legal_move(r) {
            return if self.in_check(r, self.side) { Outcome::Checkmate } else { Outcome::Stalemate };
        }
        if self.checkmate_impossible(r) {
            return Outcome::Insufficient;
        }
        if self.halfmove >= 100 {
            return Outcome::FiftyMoves;
        }
        if repetitions(keys, self.halfmove as usize) >= 3 {
            return Outcome::Repetition;
        }
        Outcome::None
    }

    pub fn count(&self, team: usize, kind: usize) -> u32 {
        bits(self.occ[team]).filter(|&s| kind_of(self.sq[s]) == kind).count() as u32
    }

    pub fn squares(&self, team: usize) -> impl Iterator<Item = usize> {
        bits(self.occ[team])
    }
}

/// How many times the last key occurs among the last `window` + 1 keys.
pub fn repetitions(keys: &[u64], window: usize) -> usize {
    let n = keys.len();
    if n == 0 {
        return 0;
    }
    let cur = keys[n - 1];
    let mut count = 1;
    for i in 1..=window.min(n - 1) {
        if keys[n - 1 - i] == cur {
            count += 1;
        }
    }
    count
}

pub fn perft(pos: &Position, r: &Rules, depth: u32) -> u64 {
    let mut moves = Vec::with_capacity(64);
    pos.gen_pseudo(r, &mut moves, GEN_ALL);
    let mut total = 0;
    for m in moves {
        let mut child = pos.clone();
        child.make(r, m);
        if child.leaves_king_attacked(pos, r, m) {
            continue;
        }
        total += if depth <= 1 { 1 } else { perft(&child, r, depth - 1) };
    }
    total
}
