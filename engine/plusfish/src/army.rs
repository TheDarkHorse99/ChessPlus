//! Armies (`core/army.gd`, `core/army_setup.gd`): what each player brings, the
//! army-building rules, and a random army maker for self-play.
//!
//! Text form: the owner's back row, "/", then the row in front, files a to h,
//! using FEN letters (two-letter symbols in brackets, digits for gaps). The
//! standard set is "RNBQKBNR/PPPPPPPP". Black's army is written the same way
//! (from Black's side, files not mirrored), as the army builder stores it.

use crate::defs::*;
use crate::game::*;
use crate::position::*;
use crate::util::Rng;
use std::sync::Arc;

pub const BUDGET: f64 = 39.0;

/// Experiment (Mac, Oct 2026), not a game rule: set (by --front-row-rule=true)
/// to switch on the Front-row rule in `Army::problems`.
pub static FRONT_ROW_CATALOG: std::sync::OnceLock<Arc<Catalog>> = std::sync::OnceLock::new();

/// True if no piece of `army` could capture anything on the opponent's two
/// starting rows on move 1 (the Front-row rule): the army plays White against
/// a wall of Men on every square of those rows, and has no capture or Crack
/// Shot at all.
pub fn front_row_ok(cat: &Arc<Catalog>, army: &Army) -> bool {
    let Some(man) = cat.kind_by_id("man") else { return true };
    let wall = Army { name: String::new(), pieces: (0..8).flat_map(|f| (0..START_ROWS).map(move |r| (man, f, r))).collect(), mirror: true };
    let g = army_game(cat, army, &wall, 8, 8);
    let mut moves = Vec::new();
    g.pos.gen_pseudo(&g.rules, &mut moves, GEN_CAPTURES);
    moves.is_empty()
}
pub const START_ROWS: i32 = 2;
pub const MAX_COPIES: usize = 2;
pub const MAX_EXTRA_ROYALS: usize = 1;

#[derive(Clone, Debug, PartialEq)]
pub struct Army {
    pub name: String,
    /// (kind, file, row from the owner's edge).
    pub pieces: Vec<(usize, i32, i32)>,
    /// Played as Black, the army is turned round as a whole (files mirrored
    /// too), so it looks from Black's side as it was built (`Army.mirror_for_black`
    /// in the game). The standard set turns it off.
    pub mirror: bool,
}

impl Army {
    pub fn cost(&self, cat: &Catalog) -> f64 {
        self.pieces.iter().map(|p| cat.defs[p.0].value).sum()
    }

    pub fn count(&self, kind: usize) -> usize {
        self.pieces.iter().filter(|p| p.0 == kind).count()
    }

    pub fn at(&self, file: i32, row: i32) -> Option<usize> {
        self.pieces.iter().find(|p| p.1 == file && p.2 == row).map(|p| p.0)
    }

    /// "RNBQKBNR/PPPPPPPP".
    pub fn to_text(&self, cat: &Catalog, width: i32) -> String {
        let mut rows = Vec::new();
        for row in 0..START_ROWS {
            let mut s = String::new();
            let mut empty = 0;
            for f in 0..width {
                match self.at(f, row) {
                    None => empty += 1,
                    Some(k) => {
                        if empty > 0 {
                            s += &empty.to_string();
                            empty = 0;
                        }
                        let sym = cat.defs[k].symbol.to_uppercase();
                        if sym.chars().count() == 1 {
                            s += &sym;
                        } else {
                            s += &format!("({})", sym);
                        }
                    }
                }
            }
            if empty > 0 {
                s += &empty.to_string();
            }
            rows.push(s);
        }
        rows.join("/")
    }

    pub fn from_text(cat: &Catalog, text: &str) -> Result<Army, String> {
        let mut pieces = Vec::new();
        for (row, part) in text.split('/').enumerate() {
            let mut file = 0;
            let chars: Vec<char> = part.chars().collect();
            let mut i = 0;
            while i < chars.len() {
                let c = chars[i];
                if c.is_ascii_digit() {
                    let mut d = String::new();
                    while i < chars.len() && chars[i].is_ascii_digit() {
                        d.push(chars[i]);
                        i += 1;
                    }
                    file += d.parse::<i32>().unwrap();
                    continue;
                }
                let sym: String = if c == '(' {
                    let close = part[i..].find(')').map(|p| p + i).ok_or("missing ')' in army")?;
                    let s = chars[i + 1..close].iter().collect();
                    i = close + 1;
                    s
                } else {
                    i += 1;
                    c.to_string()
                };
                let k = cat.kind_by_symbol(&sym).ok_or(format!("unknown piece '{}' in army", sym))?;
                pieces.push((k, file, row as i32));
                file += 1;
            }
        }
        Ok(Army { name: text.to_string(), pieces, mirror: true })
    }

    /// Reads an army saved by the game's army builder (a Godot .tres file in
    /// %APPDATA%\Godot\app_userdata\<game>\armies\).
    pub fn from_tres(cat: &Catalog, text: &str) -> Result<Army, String> {
        let sections = parse_tres(text);
        let mut ext: std::collections::HashMap<String, String> = Default::default();
        for s in &sections {
            if s.kind == "ext_resource" {
                if let (Some(id), Some(path)) = (s.attrs.get("id"), s.attrs.get("path")) {
                    ext.insert(id.clone(), path.clone());
                }
            }
        }
        let mut subs: std::collections::HashMap<String, (usize, i32, i32)> = Default::default();
        for s in &sections {
            if s.kind != "sub_resource" {
                continue;
            }
            let id = match s.attrs.get("id") {
                Some(i) => i.clone(),
                None => continue,
            };
            let def_ref = match s.get("def").map(|v| parse_refs(v, "ExtResource")) {
                Some(v) if !v.is_empty() => v[0].clone(),
                _ => continue,
            };
            let path = ext.get(&def_ref).ok_or(format!("army refers to unknown resource {}", def_ref))?;
            let stem = path.rsplit('/').next().unwrap_or(path).trim_end_matches(".tres");
            let k = cat.kind_by_id(stem).ok_or(format!("army uses unknown piece {}", stem))?;
            let sq = s.get("square").map(parse_vectors).and_then(|v| v.first().copied()).unwrap_or((0, 0));
            subs.insert(id, (k, sq.0, sq.1));
        }
        let main = sections.iter().find(|s| s.kind == "resource").ok_or("no [resource] in army file")?;
        let name = main.get("army_name").map(unquote).unwrap_or_default();
        let mut pieces = Vec::new();
        if let Some(v) = main.get("pieces") {
            for id in parse_refs(v, "SubResource") {
                pieces.push(*subs.get(&id).ok_or(format!("army piece {} missing", id))?);
            }
        }
        // Saved armies store mirror_for_black only when it's off (Godot leaves
        // out values that equal the default).
        let mirror = main.get("mirror_for_black").map(|v| v.trim() == "true").unwrap_or(true);
        Ok(Army { name, pieces, mirror })
    }

    /// Everything wrong with the army (`Army.problems`). Empty = legal.
    pub fn problems(&self, cat: &Catalog, width: i32) -> Vec<String> {
        let mut found = Vec::new();
        // Experiment (Mac, Oct 2026): the Front-row rule, when it's on.
        if let Some(full) = FRONT_ROW_CATALOG.get() {
            if width == 8 && !front_row_ok(full, self) {
                found.push("Front-row rule: a piece could capture on the opponent's starting rows on move 1.".to_string());
            }
        }
        let cost = self.cost(cat);
        if cost > BUDGET + 1e-9 {
            found.push(format!("Costs {} points; the budget is {}.", cost, BUDGET));
        }
        let kings: Vec<_> = self.pieces.iter().filter(|p| cat.defs[p.0].is_king()).collect();
        if kings.is_empty() {
            found.push("Needs a king.".into());
        }
        let kf = king_files(width);
        for k in &kings {
            if k.2 != 0 || !kf.contains(&k.1) {
                found.push("The king must start in the middle of the back row.".into());
            }
        }
        let royals = self.pieces.iter().filter(|p| cat.defs[p.0].is_royal() && !cat.defs[p.0].is_king()).count();
        if royals > MAX_EXTRA_ROYALS {
            found.push(format!("Too many royal pieces: {} besides the king (the most is {}).", royals, MAX_EXTRA_ROYALS));
        }
        let mut checked = Vec::new();
        for p in &self.pieces {
            if checked.contains(&p.0) {
                continue;
            }
            checked.push(p.0);
            let d = &cat.defs[p.0];
            let limit = max_copies(d);
            let royal_only = d.is_royal() && !d.is_king();
            if let Some(l) = limit {
                if self.count(p.0) > l && !royal_only {
                    found.push(format!("Too many {}s: {} (the most is {}).", d.name.to_lowercase(), self.count(p.0), l));
                }
            }
        }
        let mut used = Vec::new();
        for p in &self.pieces {
            if p.1 < 0 || p.1 >= width || p.2 < 0 || p.2 >= START_ROWS {
                found.push(format!("A {} is outside the starting rows.", cat.defs[p.0].name.to_lowercase()));
            } else if used.contains(&(p.1, p.2)) {
                found.push("Two pieces share a square.".into());
            }
            used.push((p.1, p.2));
        }
        found
    }
}

pub fn max_copies(d: &PieceDef) -> Option<usize> {
    if d.is_king() {
        Some(1)
    } else if d.is_pawn() {
        None
    } else if d.is_royal() {
        Some(MAX_EXTRA_ROYALS.min(MAX_COPIES))
    } else {
        Some(MAX_COPIES)
    }
}

pub fn king_files(width: i32) -> Vec<i32> {
    if width % 2 == 1 {
        vec![width / 2]
    } else {
        vec![width / 2 - 1, width / 2]
    }
}

pub fn standard(cat: &Catalog) -> Army {
    let mut a = Army::from_text(cat, "RNBQKBNR/PPPPPPPP").expect("standard pieces missing");
    a.name = "Standard".into();
    a.mirror = false;
    a
}

/// An army from the command line: "standard", "random", "random:<seed>", a
/// saved .tres army file, or the text form ("RNBQKBNR/PPPPPPPP").
pub fn parse_army(cat: &Catalog, spec: &str, rng: &mut Rng) -> Result<Army, String> {
    let s = spec.trim();
    if s.eq_ignore_ascii_case("standard") {
        return Ok(standard(cat));
    }
    if s.eq_ignore_ascii_case("random") {
        return Ok(random_army(cat, rng));
    }
    if let Some(seed) = s.strip_prefix("random:") {
        let mut r = Rng::new(seed.parse().map_err(|_| "bad random seed")?);
        return Ok(random_army(cat, &mut r));
    }
    if s.ends_with(".tres") || std::path::Path::new(s).is_file() {
        let text = std::fs::read_to_string(s).map_err(|e| format!("{}: {}", s, e))?;
        let mut a = Army::from_tres(cat, &text)?;
        if a.name.is_empty() {
            a.name = s.to_string();
        }
        return Ok(a);
    }
    Army::from_text(cat, s)
}

/// A random legal army that spends most of the budget, laid out sensibly:
/// king in the middle, pawn-like pieces in front, castling pieces in corners.
pub fn random_army(cat: &Catalog, rng: &mut Rng) -> Army {
    random_army_budget(cat, rng, BUDGET)
}

/// A random legal army spending close to `total` points (at most the budget).
pub fn random_army_budget(cat: &Catalog, rng: &mut Rng, total: f64) -> Army {
    let king = cat.defs.iter().position(|d| d.is_king()).expect("no king type");
    let width = 8;
    let total = total.min(BUDGET);
    loop {
        let mut picks: Vec<usize> = Vec::new();
        let mut budget = total;
        let pawn_kinds: Vec<usize> = (0..cat.len()).filter(|&k| cat.defs[k].is_pawn() && cat.defs[k].value > 0.0 && !cat.defs[k].is_form).collect();
        let others: Vec<usize> = (0..cat.len()).filter(|&k| !cat.defs[k].is_king() && !cat.defs[k].is_pawn() && cat.defs[k].value > 0.0 && !cat.defs[k].is_form).collect();
        let pawns = if pawn_kinds.is_empty() { 0 } else { rng.range(0, 9) as usize };
        for _ in 0..pawns {
            let k = pawn_kinds[rng.below(pawn_kinds.len())];
            picks.push(k);
            budget -= cat.defs[k].value;
        }
        let mut royals = 0;
        for _ in 0..40 {
            if picks.len() >= 15 {
                break;
            }
            let options: Vec<usize> = others
                .iter()
                .copied()
                .filter(|&k| {
                    let d = &cat.defs[k];
                    d.value <= budget + 1e-9
                        && picks.iter().filter(|&&p| p == k).count() < max_copies(d).unwrap_or(99)
                        && !(d.is_royal() && royals >= MAX_EXTRA_ROYALS)
                })
                .collect();
            if options.is_empty() {
                break;
            }
            let k = options[rng.below(options.len())];
            if cat.defs[k].is_royal() {
                royals += 1;
            }
            picks.push(k);
            budget -= cat.defs[k].value;
        }
        // Top up with pawns if there's room and money.
        while picks.len() < 15 && !pawn_kinds.is_empty() && budget >= 1.0 - 1e-9 {
            let k = pawn_kinds[0];
            picks.push(k);
            budget -= cat.defs[k].value;
        }
        if budget > 1.5 + 1e-9 {
            continue;
        }
        // Lay them out.
        let mut front: Vec<usize> = Vec::new();
        let mut back: Vec<usize> = Vec::new();
        for &k in &picks {
            let d = &cat.defs[k];
            let forwardish = d.can_promote() || d.id == "berserker";
            if forwardish {
                front.push(k);
            } else {
                back.push(k);
            }
        }
        while front.len() > width as usize {
            back.push(front.pop().unwrap());
        }
        while back.len() > width as usize - 1 {
            front.push(back.pop().unwrap());
        }
        if front.len() > width as usize {
            continue;
        }
        let mut pieces = Vec::new();
        let kf = king_files(width)[rng.below(2)];
        pieces.push((king, kf, 0));
        let mut free_back: Vec<i32> = (0..width).filter(|&f| f != kf).collect();
        // Castling partners take the corners first.
        back.sort_by_key(|&k| if cat.defs[k].has_castle() { 0 } else { 1 });
        let mut rest = Vec::new();
        for &k in &back {
            if cat.defs[k].has_castle() {
                if let Some(pos) = free_back.iter().position(|&f| f == 0 || f == width - 1) {
                    let f = free_back.remove(pos);
                    pieces.push((k, f, 0));
                    continue;
                }
            }
            rest.push(k);
        }
        rng.shuffle(&mut rest);
        for k in rest {
            let i = rng.below(free_back.len());
            let f = free_back.remove(i);
            pieces.push((k, f, 0));
        }
        let mut free_front: Vec<i32> = (0..width).collect();
        rng.shuffle(&mut front);
        // Pawns spread from the middle out tend to be the most natural.
        for k in front {
            let i = rng.below(free_front.len());
            let f = free_front.remove(i);
            pieces.push((k, f, 1));
        }
        let army = Army { name: String::new(), pieces, mirror: true };
        if army.problems(cat, width).is_empty() {
            let mut a = army;
            a.name = a.to_text(cat, width);
            return a;
        }
    }
}

/// A new game between two armies (`ArmySetup.create_game`), 8x8 by default.
pub fn army_game(cat: &Arc<Catalog>, white: &Army, black: &Army, w: i32, h: i32) -> Game {
    let mut kinds: Vec<usize> = Vec::new();
    for a in [white, black] {
        for p in &a.pieces {
            kinds.push(p.0);
        }
    }
    let promo = army_promo(cat, &kinds);
    let mut present = kinds.clone();
    present.extend(promo.iter().copied());
    let rules = Arc::new(Rules::new(cat.clone(), w, h, promo.iter().map(|&k| k as u8).collect(), true, kinds_mask(present)));
    let mut p = Position::empty();
    for p0 in &white.pieces {
        p.put(&rules, (p0.2 * w + p0.1) as usize, code(p0.0, WHITE));
    }
    for p0 in &black.pieces {
        let file = if black.mirror { w - 1 - p0.1 } else { p0.1 };
        p.put(&rules, ((h - 1 - p0.2) * w + file) as usize, code(p0.0, BLACK));
    }
    Game::new(rules, p)
}
