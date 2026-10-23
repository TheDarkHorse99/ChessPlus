//! A game: the rules, the moves played, and the positions they led to. Also FEN
//! (the game's dialect from `core/fen.gd`), move text and SAN (`core/notation.gd`).

use crate::defs::*;
use crate::position::*;
use std::sync::Arc;

#[derive(Clone)]
pub struct Game {
    pub rules: Arc<Rules>,
    pub start: Position,
    pub pos: Position,
    pub moves: Vec<Move>,
    /// Repetition key of every position, start first.
    pub keys: Vec<u64>,
}

impl Game {
    pub fn new(rules: Arc<Rules>, mut start: Position) -> Game {
        start.update_key(&rules);
        let keys = vec![start.key];
        Game { rules, pos: start.clone(), start, moves: Vec::new(), keys }
    }

    pub fn play(&mut self, m: Move) {
        self.pos.make(&self.rules, m);
        self.moves.push(m);
        self.keys.push(self.pos.key);
    }

    pub fn play_text(&mut self, text: &str) -> Result<Move, String> {
        let m = find_move(&self.pos, &self.rules, text).ok_or_else(|| format!("illegal or unknown move: {}", text))?;
        self.play(m);
        Ok(m)
    }

    pub fn outcome(&self) -> Outcome {
        self.pos.outcome(&self.rules, &self.keys)
    }

    /// "1-0", "0-1", "1/2-1/2" or "*".
    pub fn result_text(&self) -> &'static str {
        match self.outcome().white_score(self.pos.side) {
            None => "*",
            Some(s) if s > 0.75 => "1-0",
            Some(s) if s < 0.25 => "0-1",
            _ => "1/2-1/2",
        }
    }

    /// The game so far in SAN: "1. e4 e5 2. Nf3".
    pub fn move_list(&self) -> String {
        let mut out = Vec::new();
        let mut p = self.start.clone();
        for (i, &m) in self.moves.iter().enumerate() {
            if p.side == WHITE {
                out.push(format!("{}.", p.fullmove));
            } else if i == 0 {
                out.push(format!("{}...", p.fullmove));
            }
            out.push(san(&p, &self.rules, m));
            p.make(&self.rules, m);
        }
        out.join(" ")
    }
}

pub fn square_name(r: &Rules, s: usize) -> String {
    let f = (b'a' + r.file(s) as u8) as char;
    format!("{}{}", f, r.rank(s) + 1)
}

pub fn parse_square(r: &Rules, t: &str) -> Option<usize> {
    let mut chars = t.chars();
    let f = chars.next()?;
    if !f.is_ascii_lowercase() {
        return None;
    }
    let rank: i32 = chars.as_str().parse().ok()?;
    let x = (f as u8 - b'a') as i32;
    let y = rank - 1;
    if x < 0 || y < 0 || x >= r.w || y >= r.h {
        return None;
    }
    Some((y * r.w + x) as usize)
}

/// `Move.to_text()`: "e2-e4", "e4xd5", "e7-e8=Q", "a1!c3" (Crack Shot), "d2!=Q"
/// (Raise Dead), "@e3" (Haunt), "c1~g5" (Song of Slumber), "e4!" (Full Moon);
/// "c7xe5/d4", "a1!c3/d4" when the attacker chose the Jester on d4 to take
/// the hit.
pub fn move_text(r: &Rules, m: Move) -> String {
    if m.flags & F_HAUNT != 0 {
        return format!("@{}", square_name(r, m.to as usize));
    }
    if m.flags & F_SONG != 0 {
        return format!("{}~{}", square_name(r, m.from as usize), square_name(r, m.to as usize));
    }
    if m.flags & F_MOON != 0 {
        return format!("{}!", square_name(r, m.from as usize));
    }
    if m.flags & F_RAISE != 0 {
        return format!("{}!={}", square_name(r, m.from as usize), r.def(m.extra as usize).symbol.to_uppercase());
    }
    if m.flags & F_CRACK != 0 {
        return format!("{}!{}{}", square_name(r, m.from as usize), square_name(r, m.to as usize), decoy_text(r, m));
    }
    let mut t = format!(
        "{}{}{}",
        square_name(r, m.from as usize),
        if m.is_capture() { "x" } else { "-" },
        square_name(r, m.to as usize)
    );
    if m.promo != 0 {
        t.push('=');
        t.push_str(&r.def(m.promo as usize - 1).symbol.to_uppercase());
    }
    t + &decoy_text(r, m)
}

/// "/d4" (the Jester's square) when the attacker chose which Jester takes the
/// hit, else "" (`Move.decoy_text`).
fn decoy_text(r: &Rules, m: Move) -> String {
    if m.flags & F_CHOICE != 0 {
        format!("/{}", square_name(r, m.extra as usize))
    } else {
        String::new()
    }
}

/// Standard algebraic notation as the game writes it (`Notation.san`).
pub fn san(p: &Position, r: &Rules, m: Move) -> String {
    let mover = if m.flags & F_HAUNT != 0 { m.extra as usize } else { kind_of(p.sq[m.from as usize]) };
    let sym = r.def(mover).symbol.to_uppercase();
    let mut t = String::new();
    if m.flags & F_RAISE != 0 {
        t = format!("{}!={}", sym, r.def(m.extra as usize).symbol.to_uppercase());
        return t + &check_suffix(p, r, m);
    }
    // Text only, like the game: G@e3 (Haunt), BDc1~g5 (Song of Slumber), WWe4! (Full Moon).
    if m.flags & F_HAUNT != 0 {
        return format!("{}@{}", sym, square_name(r, m.to as usize)) + &check_suffix(p, r, m);
    }
    if m.flags & F_SONG != 0 {
        return format!("{}{}~{}", sym, square_name(r, m.from as usize), square_name(r, m.to as usize)) + &check_suffix(p, r, m);
    }
    if m.flags & F_MOON != 0 {
        return format!("{}{}!", sym, square_name(r, m.from as usize)) + &check_suffix(p, r, m);
    }
    if m.flags & F_CASTLE != 0 {
        t = if m.to > m.from { "O-O".into() } else { "O-O-O".into() };
    } else {
        if sym == "P" {
            if m.is_capture() {
                t.push((b'a' + r.file(m.from as usize) as u8) as char);
            }
        } else {
            t.push_str(&sym);
            t.push_str(&disambiguation(p, r, m, mover));
        }
        if m.is_capture() {
            t.push('x');
        }
        t.push_str(&square_name(r, m.to as usize));
        if m.promo != 0 {
            t.push('=');
            t.push_str(&r.def(m.promo as usize - 1).symbol.to_uppercase());
        }
        if m.flags & F_SHIELD != 0 {
            t.push('*');
        }
        if m.flags & F_CRACK != 0 {
            t.push('!');
        }
        // The attacker chose which Jester takes the hit: Bxe5/d4.
        t.push_str(&decoy_text(r, m));
    }
    t + &check_suffix(p, r, m)
}

fn disambiguation(p: &Position, r: &Rules, m: Move, mover: usize) -> String {
    let mut rivals: Vec<usize> = Vec::new();
    for o in p.legal_moves(r) {
        if o.to == m.to && o.from != m.from && kind_of(p.sq[o.from as usize]) == mover && !rivals.contains(&(o.from as usize)) {
            rivals.push(o.from as usize);
        }
    }
    if rivals.is_empty() {
        return String::new();
    }
    let from = m.from as usize;
    let file_clash = rivals.iter().any(|&s| r.file(s) == r.file(from));
    let rank_clash = rivals.iter().any(|&s| r.rank(s) == r.rank(from));
    let ft = ((b'a' + r.file(from) as u8) as char).to_string();
    let rt = (r.rank(from) + 1).to_string();
    if !file_clash {
        ft
    } else if !rank_clash {
        rt
    } else {
        ft + &rt
    }
}

fn check_suffix(p: &Position, r: &Rules, m: Move) -> String {
    let mut c = p.clone();
    c.make(r, m);
    if c.in_check(r, c.side) {
        if c.has_legal_move(r) {
            "+".into()
        } else {
            "#".into()
        }
    } else {
        String::new()
    }
}

/// The legal move written as `text`: move text ("e2-e4") or SAN ("e4", "Nf3+").
/// A capture written without the Jester's square when the attacker had a
/// choice of Jesters (saved before that rule, Oct 2026) finds the first, as
/// `GameState.find_move` does.
pub fn find_move(p: &Position, r: &Rules, text: &str) -> Option<Move> {
    let want = text.trim().trim_end_matches(|c| c == '+' || c == '#');
    let legal = p.legal_moves(r);
    if let Some(&m) = legal.iter().find(|&&m| move_text(r, m) == want) {
        return Some(m);
    }
    if let Some(&m) = legal.iter().find(|&&m| san(p, r, m).trim_end_matches(|c| c == '+' || c == '#') == want) {
        return Some(m);
    }
    if want.contains('/') {
        return None;
    }
    let first_choice = |name: &dyn Fn(Move) -> String| {
        legal.iter().copied().find(|&m| m.flags & F_CHOICE != 0 && name(m).split('/').next() == Some(want))
    };
    first_choice(&|m| move_text(r, m)).or_else(|| first_choice(&|m| san(p, r, m)))
}

// ---------------------------------------------------------------------------
// FEN

pub const STANDARD_FEN: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

fn piece_token(r: &Rules, c: u16) -> String {
    let sym = &r.def(kind_of(c)).symbol;
    let s = if team_of(c) == WHITE { sym.to_uppercase() } else { sym.to_lowercase() };
    let mut t = if sym.chars().count() == 1 { s } else { format!("({})", s) };
    if c & BROKEN != 0 {
        t.push('\'');
    }
    if c & GAINED != 0 {
        t.push('+');
    }
    if c & USED != 0 {
        t.push('^');
    }
    t
}

/// A piece's marks: "'" (broken shield), "+" (gained shield), "^" (ability used).
fn mark_bit(t: &str) -> Option<u16> {
    match t {
        "'" => Some(BROKEN),
        "+" => Some(GAINED),
        "^" => Some(USED),
        _ => None,
    }
}

/// Placement tokens: digits, "X", "(XY)", "'", "+" and "^".
fn tokens(row: &str) -> Vec<String> {
    let chars: Vec<char> = row.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        if c.is_ascii_digit() {
            let mut d = String::new();
            while i < chars.len() && chars[i].is_ascii_digit() {
                d.push(chars[i]);
                i += 1;
            }
            out.push(d);
            continue;
        }
        if c == '(' {
            let mut j = i;
            while j < chars.len() && chars[j] != ')' {
                j += 1;
            }
            let end = j.min(chars.len() - 1);
            out.push(chars[i..=end].iter().collect());
            i = end + 1;
            continue;
        }
        out.push(c.to_string());
        i += 1;
    }
    out
}

/// Pieces in a FEN-style list such as "Qn(PD)" -> (kind, team) pairs.
pub fn parse_piece_list(cat: &Catalog, text: &str) -> Result<Vec<(usize, usize)>, String> {
    Ok(parse_marked_list(cat, text)?.into_iter().map(|(k, t, _)| (k, t)).collect())
}

/// The same with each piece's marks as flag bits (a lost Ghost's "^" =
/// its Haunt is used).
pub fn parse_marked_list(cat: &Catalog, text: &str) -> Result<Vec<(usize, usize, u16)>, String> {
    let mut out: Vec<(usize, usize, u16)> = Vec::new();
    for t in tokens(text) {
        if let Some(bit) = mark_bit(&t) {
            if let Some(last) = out.last_mut() {
                last.2 |= bit;
            }
            continue;
        }
        if t.chars().all(|c| c.is_ascii_digit()) || t == "," {
            continue;
        }
        let letters = t.trim_start_matches('(').trim_end_matches(')');
        let k = cat.kind_by_symbol(letters).ok_or(format!("unknown piece: {}", t))?;
        let team = if letters == letters.to_uppercase() { WHITE } else { BLACK };
        out.push((k, team, 0));
    }
    Ok(out)
}

/// Placement and extras of a FEN, before the Rules exist: the board size, the
/// pieces, and the extension fields.
pub struct ParsedFen {
    pub w: i32,
    pub h: i32,
    pub pieces: Vec<(usize, usize, u16)>, // square, kind, flag bits (BROKEN/USED) and team
    pub side: usize,
    pub castling: String,
    pub ep: Option<String>,
    pub halfmove: u32,
    pub fullmove: u32,
    /// Lost pieces in order: kind, team, marks.
    pub lost: Vec<(usize, usize, u16)>,
    pub promo: Option<Vec<usize>>,
}

pub fn parse_fen_text(cat: &Catalog, text: &str) -> Result<ParsedFen, String> {
    let fields: Vec<&str> = text.split_whitespace().collect();
    if fields.is_empty() {
        return Err("FEN is empty".into());
    }
    let rows: Vec<&str> = fields[0].split('/').collect();
    let h = rows.len() as i32;
    let width_of = |row: &str| -> i32 {
        tokens(row)
            .iter()
            .map(|t| if t.chars().all(|c| c.is_ascii_digit()) { t.parse::<i32>().unwrap_or(0) } else if mark_bit(t).is_some() { 0 } else { 1 })
            .sum()
    };
    let w = width_of(rows[0]);
    let mut pieces = Vec::new();
    for (i, row) in rows.iter().enumerate() {
        let rank = h - 1 - i as i32;
        let mut file = 0;
        let mut last: Option<usize> = None;
        for t in tokens(row) {
            if t.chars().all(|c| c.is_ascii_digit()) {
                file += t.parse::<i32>().unwrap();
                continue;
            }
            if let Some(bit) = mark_bit(&t) {
                if let Some(l) = last {
                    let p: &mut (usize, usize, u16) = &mut pieces[l];
                    p.2 |= bit;
                }
                continue;
            }
            let letters = t.trim_start_matches('(').trim_end_matches(')');
            let k = cat.kind_by_symbol(letters).ok_or(format!("FEN has an unknown piece: {}", t))?;
            if file >= w {
                return Err(format!("FEN rank {} is too long", rank + 1));
            }
            let team = if letters == letters.to_uppercase() { WHITE } else { BLACK };
            pieces.push(((rank * w + file) as usize, k, if team == BLACK { BLACK_BIT } else { 0 }));
            last = Some(pieces.len() - 1);
            file += 1;
        }
        if file != w {
            return Err(format!("FEN rank {} has the wrong length", rank + 1));
        }
    }
    let mut pf = ParsedFen {
        w,
        h,
        pieces,
        side: if fields.len() > 1 && fields[1] == "b" { BLACK } else { WHITE },
        castling: fields.get(2).unwrap_or(&"-").to_string(),
        ep: fields.get(3).filter(|&&e| e != "-").map(|e| e.to_string()),
        halfmove: fields.get(4).and_then(|v| v.parse().ok()).unwrap_or(0),
        fullmove: fields.get(5).and_then(|v| v.parse().ok()).unwrap_or(1),
        lost: Vec::new(),
        promo: None,
    };
    for f in fields.iter().skip(6) {
        if let Some(v) = f.strip_prefix("lost=") {
            pf.lost = parse_marked_list(cat, v)?;
        } else if let Some(v) = f.strip_prefix("promo=") {
            pf.promo = Some(parse_piece_list(cat, v)?.into_iter().map(|(k, _)| k).collect());
        }
    }
    Ok(pf)
}

/// The standard promotion choices (queen, rook, bishop, knight) that
/// `Fen.parse` games use, for whichever of them exist.
pub fn standard_promo(cat: &Catalog) -> Vec<usize> {
    ["queen", "rook", "bishop", "knight"].iter().filter_map(|id| cat.kind_by_id(id)).collect()
}

/// Promotion choices for an army game: each piece type on the board at the
/// start except king and pawn types, most valuable first.
pub fn army_promo(cat: &Catalog, kinds_on_board: &[usize]) -> Vec<usize> {
    let mut v: Vec<usize> = Vec::new();
    for &k in kinds_on_board {
        let d = &cat.defs[k];
        if !d.is_king() && !d.is_pawn() && !v.contains(&k) {
            v.push(k);
        }
    }
    v.sort_by(|&a, &b| cat.defs[b].value.partial_cmp(&cat.defs[a].value).unwrap().then(a.cmp(&b)));
    v
}

pub fn kinds_mask(kinds: impl IntoIterator<Item = usize>) -> u64 {
    kinds.into_iter().fold(0u64, |m, k| m | (1u64 << k))
}

/// A game from a FEN. Promotion choices: the FEN's `promo=` field if it has
/// one, otherwise `promo` (None = the standard four, as `Fen.parse` games use).
pub fn game_from_fen(cat: &Arc<Catalog>, text: &str, promo: Option<Vec<usize>>) -> Result<Game, String> {
    let pf = parse_fen_text(cat, text)?;
    if (pf.w * pf.h) as usize > MAX_SQ || pf.w > 26 {
        return Err(format!("board {}x{} is too big (max {} squares)", pf.w, pf.h, MAX_SQ));
    }
    let promo = pf.promo.clone().or(promo).unwrap_or_else(|| standard_promo(cat));
    let mut present: Vec<usize> = pf.pieces.iter().map(|p| p.1).collect();
    present.extend(promo.iter().copied());
    present.extend(pf.lost.iter().map(|l| l.0));
    let rules = Arc::new(Rules::new(cat.clone(), pf.w, pf.h, promo.iter().map(|&k| k as u8).collect(), true, kinds_mask(present)));
    let r = &rules;
    let mut p = Position::empty();
    for &(s, k, flags) in &pf.pieces {
        let team = if flags & BLACK_BIT != 0 { BLACK } else { WHITE };
        let mut c = code(k, team) | (flags & (BROKEN | GAINED | USED));
        let def = r.def(k);
        if def.is_king() || def.has_castle() {
            c |= MOVED;
        } else if def.has_first_move_rule() {
            let home = if team == WHITE { 1 } else { r.h - 2 };
            if r.rank(s) != home {
                c |= MOVED;
            }
        }
        p.put(r, s, c);
    }
    // Castling rights: unmove the king and the outermost partner on that side.
    for ch in pf.castling.chars() {
        let up = ch.to_ascii_uppercase();
        if up != 'K' && up != 'Q' {
            continue;
        }
        let team = if ch.is_ascii_uppercase() { WHITE } else { BLACK };
        if p.kings[team] == 0 {
            continue;
        }
        let king = p.kings[team].trailing_zeros() as usize;
        let dir = if up == 'K' { 1 } else { -1 };
        let y = r.rank(king);
        let mut x = if dir > 0 { r.w - 1 } else { 0 };
        let mut partner = None;
        while x != r.file(king) {
            let s = (y * r.w + x) as usize;
            let c = p.sq[s];
            if c != 0 && team_of(c) == team && r.info[kind_of(c)].castle {
                partner = Some(s);
                break;
            }
            x -= dir;
        }
        if let Some(ps) = partner {
            for s in [king, ps] {
                let c = p.remove(r, s);
                p.put(r, s, c & !MOVED);
            }
        }
    }
    p.set_side(r, pf.side);
    if let Some(e) = &pf.ep {
        let s = parse_square(r, e).ok_or(format!("FEN has a bad en passant square: {}", e))?;
        p.ep = 1u128 << s;
        let forward = if pf.side == BLACK { 1 } else { -1 };
        let v = s as i32 + forward * r.w;
        p.ep_victim = if v >= 0 && (v as usize) < r.nsq { v as u8 } else { NO_SQ };
    }
    p.halfmove = pf.halfmove;
    p.fullmove = pf.fullmove;
    for &(k, team, marks) in &pf.lost {
        p.lose(r, team, code(k, team) | marks);
    }
    Ok(Game::new(rules.clone(), p))
}

/// The FEN for a position (`Fen.write`), plus ` lost=...` when pieces have been
/// lost and `with_extras` is on (the game's own reader ignores extra fields).
pub fn fen(p: &Position, r: &Rules, with_extras: bool) -> String {
    let mut rows = Vec::new();
    for rank in (0..r.h).rev() {
        let mut row = String::new();
        let mut empty = 0;
        for file in 0..r.w {
            let c = p.sq[(rank * r.w + file) as usize];
            if c == 0 {
                empty += 1;
                continue;
            }
            if empty > 0 {
                row += &empty.to_string();
                empty = 0;
            }
            row += &piece_token(r, c);
        }
        if empty > 0 {
            row += &empty.to_string();
        }
        rows.push(row);
    }
    let b = p.castling_bits(r);
    let mut castling = String::new();
    for (bit, ch) in [(0, 'K'), (1, 'Q'), (2, 'k'), (3, 'q')] {
        if b & (1 << bit) != 0 {
            castling.push(ch);
        }
    }
    if castling.is_empty() {
        castling.push('-');
    }
    let ep = if p.ep == 0 {
        "-".to_string()
    } else {
        let s = if p.side == BLACK { p.ep.trailing_zeros() as usize } else { 127 - p.ep.leading_zeros() as usize };
        square_name(r, s)
    };
    let mut out = format!(
        "{} {} {} {} {} {}",
        rows.join("/"),
        if p.side == WHITE { "w" } else { "b" },
        castling,
        ep,
        p.halfmove,
        p.fullmove
    );
    if with_extras {
        let mut lost = String::new();
        for team in 0..2 {
            for k in 0..r.info.len() {
                if k as u8 == r.haunt_kind {
                    // Ghosts in the order they were lost, "^" if Haunt is used.
                    for i in 0..p.ghost_n[team] {
                        let used = if p.ghosts[team] & (1 << i) == 0 { USED } else { 0 };
                        lost += &piece_token(r, code(k, team) | used);
                    }
                    continue;
                }
                for _ in 0..p.lost[team][k] {
                    lost += &piece_token(r, code(k, team));
                }
            }
        }
        if !lost.is_empty() {
            out += &format!(" lost={}", lost);
        }
        let promo: String = r.promo.iter().map(|&k| piece_token(r, code(k as usize, WHITE))).collect();
        out += &format!(" promo={}", if promo.is_empty() { "-".into() } else { promo });
    }
    out
}

/// The board as text, White at the bottom.
pub fn board_text(p: &Position, r: &Rules) -> String {
    let mut lines = Vec::new();
    for rank in (0..r.h).rev() {
        let mut row = format!("{:>2} ", rank + 1);
        for file in 0..r.w {
            let c = p.sq[(rank * r.w + file) as usize];
            let t = if c == 0 { ".".to_string() } else { piece_token(r, c) };
            row += &format!("{:<5}", t);
        }
        lines.push(row.trim_end().to_string());
    }
    let mut footer = "   ".to_string();
    for file in 0..r.w {
        footer += &format!("{:<5}", (b'a' + file as u8) as char);
    }
    lines.push(footer.trim_end().to_string());
    lines.join("\n")
}

pub fn outcome_name(o: Outcome) -> &'static str {
    match o {
        Outcome::None => "none",
        Outcome::Checkmate => "checkmate",
        Outcome::Stalemate => "stalemate",
        Outcome::FiftyMoves => "fifty_moves",
        Outcome::Repetition => "repetition",
        Outcome::Insufficient => "insufficient_material",
        Outcome::KingExposed => "king_exposed",
    }
}
