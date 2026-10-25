//! Piece definitions, read straight from the game's `data/pieces/*.tres` files,
//! so the engine always plays by the same rules as the game.
//!
//! Field names and defaults mirror `core/move_rule.gd` and `core/piece_def.gd`.

use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

pub const T_KING: u8 = 1;
pub const T_ROYAL: u8 = 2;
pub const T_PAWN: u8 = 4;

pub const KW_JUMP: u8 = 1;
pub const KW_CASTLE: u8 = 2;
pub const KW_PROMOTE: u8 = 4;
pub const KW_SHIELD: u8 = 8;
/// Wall (Oct 2026): the opponent's pieces can't jump over it (`blocks_jumps`).
pub const KW_WALL: u8 = 16;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode {
    MoveOrCapture,
    MoveOnly,
    CaptureOnly,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Ability {
    None,
    CrackShot,
    RaiseDead,
    /// The Ghost: used after it has been lost, to come back onto any empty square.
    Haunt,
    /// The Bard: one enemy piece it could reach (not a king) can't move next turn.
    SongOfSlumber,
    /// The Werewolf: it turns into its `transforms_into` form for good.
    FullMoon,
}

impl Ability {
    /// The game's `PieceDef.Ability` number.
    pub fn from_code(n: i32) -> Ability {
        match n {
            1 => Ability::CrackShot,
            2 => Ability::RaiseDead,
            3 => Ability::Haunt,
            4 => Ability::SongOfSlumber,
            5 => Ability::FullMoon,
            _ => Ability::None,
        }
    }
}

#[derive(Clone, Debug)]
pub struct MoveRule {
    pub directions: Vec<(i32, i32)>,
    pub max_steps: i32,
    pub first_move_max_steps: i32,
    pub mode: Mode,
    pub captures_by_hopping: bool,
    pub leap_steps: i32,
    pub leap_over_own: bool,
    pub path: Vec<(i32, i32)>,
    pub mirror_files: bool,
    pub mirror_ranks: bool,
}

impl Default for MoveRule {
    fn default() -> Self {
        MoveRule {
            directions: Vec::new(),
            max_steps: 1,
            first_move_max_steps: 0,
            mode: Mode::MoveOrCapture,
            captures_by_hopping: false,
            leap_steps: 0,
            leap_over_own: false,
            path: Vec::new(),
            mirror_files: false,
            mirror_ranks: false,
        }
    }
}

impl MoveRule {
    /// Leaping and bent-path rules can't be found by walking straight lines back
    /// from a square (`MoveRule.is_unusual`).
    pub fn is_unusual(&self) -> bool {
        self.leap_steps > 0 || !self.path.is_empty()
    }

    /// Every version of `path` with its mirror images, each listed once.
    pub fn path_variants(&self) -> Vec<Vec<(i32, i32)>> {
        let mut variants: Vec<Vec<(i32, i32)>> = Vec::new();
        let fx: &[i32] = if self.mirror_files { &[1, -1] } else { &[1] };
        let fy: &[i32] = if self.mirror_ranks { &[1, -1] } else { &[1] };
        for &x in fx {
            for &y in fy {
                let steps: Vec<(i32, i32)> = self.path.iter().map(|&(a, b)| (a * x, b * y)).collect();
                if !variants.contains(&steps) {
                    variants.push(steps);
                }
            }
        }
        variants
    }
}

#[derive(Clone, Debug)]
pub struct PieceDef {
    pub id: String,
    pub name: String,
    pub symbol: String,
    /// Army cost in points.
    pub value: f64,
    pub rules: Vec<MoveRule>,
    pub types: u8,
    pub keywords: u8,
    pub ability: Ability,
    pub dies_on_capture: bool,
    /// The Parapet: the opponent's pieces can't leap over it, and their Cannons
    /// can't use it as a screen (its own side's can, Mac).
    pub blocks_jumps: bool,
    /// The Vampire: it gains a shield whenever it captures (if it hasn't one).
    pub shield_on_capture: bool,
    /// The Squire: these piece types (ids), on squares it could reach, can't be captured.
    pub protects: Vec<String>,
    /// The Jester: captures of its side's pieces it could reach hit it instead.
    pub decoy: bool,
    /// Full Moon: the id of the piece type it becomes.
    pub transforms_into: Option<String>,
    /// A form some other piece changes into (the Werewolf's wolf): never bought
    /// for an army. Worked out by the catalog.
    pub is_form: bool,
}

impl PieceDef {
    /// A piece with no rules or tags yet, for readers to fill in.
    pub fn blank() -> PieceDef {
        PieceDef {
            id: String::new(),
            name: String::new(),
            symbol: String::new(),
            value: 0.0,
            rules: Vec::new(),
            types: 0,
            keywords: 0,
            ability: Ability::None,
            dies_on_capture: false,
            blocks_jumps: false,
            shield_on_capture: false,
            protects: Vec::new(),
            decoy: false,
            transforms_into: None,
            is_form: false,
        }
    }

    pub fn is_king(&self) -> bool {
        self.types & T_KING != 0
    }
    pub fn is_royal(&self) -> bool {
        self.types & T_ROYAL != 0
    }
    pub fn is_pawn(&self) -> bool {
        self.types & T_PAWN != 0
    }
    pub fn has_castle(&self) -> bool {
        self.keywords & KW_CASTLE != 0
    }
    pub fn has_shield(&self) -> bool {
        self.keywords & KW_SHIELD != 0
    }
    pub fn can_promote(&self) -> bool {
        self.is_pawn() || self.keywords & KW_PROMOTE != 0
    }
    pub fn has_first_move_rule(&self) -> bool {
        self.rules.iter().any(|r| r.first_move_max_steps > 0)
    }
    pub fn can_capture(&self) -> bool {
        self.rules.iter().any(|r| r.mode != Mode::MoveOnly)
    }

    /// Every move is a single jump of 3+ squares (|x| + |y|), like a knight
    /// (`GameState._is_distant_leaper`).
    pub fn is_distant_leaper(&self) -> bool {
        for r in &self.rules {
            if r.is_unusual() || r.max_steps != 1 || r.first_move_max_steps > 1 {
                return false;
            }
            for &(x, y) in &r.directions {
                if x.abs() + y.abs() < 3 {
                    return false;
                }
            }
        }
        true
    }

    /// Every move keeps the piece on one square colour (`_stays_on_one_color`).
    pub fn stays_on_one_color(&self) -> bool {
        for r in &self.rules {
            if !r.path.is_empty() {
                for v in r.path_variants() {
                    let (x, y) = v.iter().fold((0, 0), |a, s| (a.0 + s.0, a.1 + s.1));
                    if (x + y) % 2 != 0 {
                        return false;
                    }
                }
                continue;
            }
            for &(x, y) in &r.directions {
                if (x + y) % 2 != 0 {
                    return false;
                }
            }
        }
        true
    }
}

/// Every piece type the engine knows about. A piece's "kind" is its index here.
#[derive(Clone, Debug)]
pub struct Catalog {
    pub defs: Vec<PieceDef>,
}

pub const MAX_KINDS: usize = 64;

fn tres_files(dir: &Path) -> Result<Vec<PathBuf>, String> {
    let mut files: Vec<PathBuf> = fs::read_dir(dir)
        .map_err(|e| format!("can't read piece folder {}: {}", dir.display(), e))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().map(|x| x == "tres").unwrap_or(false))
        .collect();
    files.sort();
    Ok(files)
}

impl Catalog {
    /// Every piece in the folder, then the forms pieces change into
    /// (`forms/`, e.g. the Werewolf's wolf), last so the other pieces keep
    /// their kind numbers.
    pub fn load_dir(dir: &Path) -> Result<Catalog, String> {
        let mut files = tres_files(dir)?;
        let forms = dir.join("forms");
        if forms.is_dir() {
            files.extend(tres_files(&forms)?);
        }
        let mut defs = Vec::new();
        for f in files {
            let text = fs::read_to_string(&f).map_err(|e| format!("{}: {}", f.display(), e))?;
            let mut def = parse_piece_tres(&text).map_err(|e| format!("{}: {}", f.display(), e))?;
            if def.id.is_empty() {
                def.id = f.file_stem().unwrap().to_string_lossy().to_string();
            }
            defs.push(def);
        }
        if defs.is_empty() {
            return Err(format!("no .tres piece files in {}", dir.display()));
        }
        Catalog::new(defs)
    }

    /// Checks the pieces and marks the forms that pieces change into.
    pub fn new(mut defs: Vec<PieceDef>) -> Result<Catalog, String> {
        if defs.is_empty() || defs.len() > MAX_KINDS {
            return Err(format!("need 1 to {} piece types (got {})", MAX_KINDS, defs.len()));
        }
        let mut seen = HashMap::new();
        for d in &defs {
            if let Some(other) = seen.insert(d.symbol.to_uppercase(), d.id.clone()) {
                return Err(format!("pieces {} and {} share the symbol {}", other, d.id, d.symbol));
            }
        }
        let forms: Vec<String> = defs.iter().filter_map(|d| d.transforms_into.clone()).collect();
        for f in &forms {
            match defs.iter_mut().find(|d| d.id.to_lowercase() == f.to_lowercase()) {
                Some(d) => d.is_form = true,
                None => return Err(format!("unknown form {}", f)),
            }
        }
        Ok(Catalog { defs })
    }

    pub fn kind_by_symbol(&self, sym: &str) -> Option<usize> {
        let s = sym.to_uppercase();
        self.defs.iter().position(|d| d.symbol.to_uppercase() == s)
    }

    pub fn kind_by_id(&self, id: &str) -> Option<usize> {
        let s = id.to_lowercase();
        self.defs.iter().position(|d| d.id.to_lowercase() == s)
    }

    pub fn len(&self) -> usize {
        self.defs.len()
    }
}

/// Finds the game's piece folder: `--pieces`, then $CHESSPLUS_PIECES, then a
/// few likely spots next to the engine and the current folder.
pub fn find_pieces_dir(explicit: Option<&str>) -> Result<PathBuf, String> {
    if let Some(p) = explicit {
        return Ok(PathBuf::from(p));
    }
    if let Ok(p) = std::env::var("CHESSPLUS_PIECES") {
        return Ok(PathBuf::from(p));
    }
    let mut roots: Vec<PathBuf> = vec![PathBuf::from(".")];
    if let Ok(exe) = std::env::current_exe() {
        let mut d = exe.parent().map(|p| p.to_path_buf());
        while let Some(dir) = d {
            roots.push(dir.clone());
            d = dir.parent().map(|p| p.to_path_buf());
        }
    }
    let candidates = ["data/pieces", "ChessPlus/data/pieces", "src/ChessPlus/data/pieces", "../ChessPlus/data/pieces"];
    for r in &roots {
        for c in &candidates {
            let p = r.join(c);
            if p.join("king.tres").exists() {
                return Ok(p);
            }
        }
    }
    Err("can't find the ChessPlus piece folder (data/pieces). Pass --pieces <dir> or set CHESSPLUS_PIECES.".into())
}

// ---------------------------------------------------------------------------
// A small reader for Godot's text resource format (.tres).

/// One `[section]` of a .tres file: its header attributes and its `key = value` lines.
#[derive(Debug, Default, Clone)]
pub struct TresSection {
    pub kind: String,
    pub attrs: HashMap<String, String>,
    pub props: Vec<(String, String)>,
}

impl TresSection {
    pub fn get(&self, key: &str) -> Option<&str> {
        self.props.iter().find(|(k, _)| k == key).map(|(_, v)| v.as_str())
    }
}

pub fn parse_tres(text: &str) -> Vec<TresSection> {
    let chars: Vec<char> = text.chars().collect();
    let mut sections: Vec<TresSection> = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        // Start of a line.
        while i < chars.len() && (chars[i] == ' ' || chars[i] == '\t' || chars[i] == '\r') {
            i += 1;
        }
        if i >= chars.len() {
            break;
        }
        if chars[i] == '\n' {
            i += 1;
            continue;
        }
        if chars[i] == ';' {
            while i < chars.len() && chars[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if chars[i] == '[' {
            let start = i + 1;
            let mut in_str = false;
            while i < chars.len() && (in_str || chars[i] != ']') {
                if chars[i] == '"' {
                    in_str = !in_str;
                }
                i += 1;
            }
            let header: String = chars[start..i.min(chars.len())].iter().collect();
            i += 1;
            sections.push(parse_header(&header));
            continue;
        }
        // key = value (a quoted value may run over several lines).
        let ks = i;
        while i < chars.len() && chars[i] != '=' && chars[i] != '\n' {
            i += 1;
        }
        let key: String = chars[ks..i].iter().collect::<String>().trim().to_string();
        if i >= chars.len() || chars[i] == '\n' {
            continue;
        }
        i += 1;
        let vs = i;
        let mut in_str = false;
        let mut depth = 0i32;
        while i < chars.len() {
            let c = chars[i];
            if in_str {
                if c == '\\' {
                    i += 2;
                    continue;
                }
                if c == '"' {
                    in_str = false;
                }
            } else if c == '"' {
                in_str = true;
            } else if c == '(' || c == '[' || c == '{' {
                depth += 1;
            } else if c == ')' || c == ']' || c == '}' {
                depth -= 1;
            } else if c == '\n' && depth <= 0 {
                break;
            }
            i += 1;
        }
        let value: String = chars[vs..i.min(chars.len())].iter().collect::<String>().trim().to_string();
        if let Some(s) = sections.last_mut() {
            s.props.push((key, value));
        }
    }
    sections
}

fn parse_header(h: &str) -> TresSection {
    let mut s = TresSection::default();
    let h = h.trim();
    let (kind, rest) = match h.find(' ') {
        Some(p) => (&h[..p], &h[p + 1..]),
        None => (h, ""),
    };
    s.kind = kind.to_string();
    let chars: Vec<char> = rest.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        while i < chars.len() && chars[i] == ' ' {
            i += 1;
        }
        let ks = i;
        while i < chars.len() && chars[i] != '=' {
            i += 1;
        }
        let key: String = chars[ks..i].iter().collect();
        i += 1;
        let mut val = String::new();
        if i < chars.len() && chars[i] == '"' {
            i += 1;
            while i < chars.len() && chars[i] != '"' {
                val.push(chars[i]);
                i += 1;
            }
            i += 1;
        } else {
            while i < chars.len() && chars[i] != ' ' {
                val.push(chars[i]);
                i += 1;
            }
        }
        if !key.trim().is_empty() {
            s.attrs.insert(key.trim().to_string(), val);
        }
    }
    s
}

/// All `Vector2i(a, b)` pairs in a value, in order.
pub fn parse_vectors(v: &str) -> Vec<(i32, i32)> {
    let mut out = Vec::new();
    let mut rest = v;
    while let Some(p) = rest.find("Vector2i(") {
        rest = &rest[p + 9..];
        if let Some(e) = rest.find(')') {
            let nums: Vec<i32> = rest[..e].split(',').filter_map(|n| n.trim().parse().ok()).collect();
            if nums.len() == 2 {
                out.push((nums[0], nums[1]));
            }
            rest = &rest[e..];
        }
    }
    out
}

/// The ids inside every `Name("id")` call in a value, e.g. SubResource("Resource_x").
pub fn parse_refs(v: &str, call: &str) -> Vec<String> {
    let mut out = Vec::new();
    let pat = format!("{}(\"", call);
    let mut rest = v;
    while let Some(p) = rest.find(&pat) {
        rest = &rest[p + pat.len()..];
        if let Some(e) = rest.find('"') {
            out.push(rest[..e].to_string());
            rest = &rest[e..];
        }
    }
    out
}

pub fn unquote(v: &str) -> String {
    let v = v.trim();
    if v.len() >= 2 && v.starts_with('"') && v.ends_with('"') {
        v[1..v.len() - 1].replace("\\\"", "\"").replace("\\n", "\n")
    } else {
        v.to_string()
    }
}

/// The quoted strings in a value such as `Array[String](["knight"])`.
pub fn parse_strings(v: &str) -> Vec<String> {
    v.split('"').skip(1).step_by(2).map(|t| t.to_string()).collect()
}

fn parse_int(v: &str) -> i32 {
    v.trim().parse::<f64>().map(|f| f as i32).unwrap_or(0)
}

fn parse_bool(v: &str) -> bool {
    v.trim() == "true"
}

fn parse_rule(s: &TresSection) -> MoveRule {
    let mut r = MoveRule::default();
    for (k, v) in &s.props {
        match k.as_str() {
            "directions" => r.directions = parse_vectors(v),
            "max_steps" => r.max_steps = parse_int(v),
            "first_move_max_steps" => r.first_move_max_steps = parse_int(v),
            "mode" => {
                r.mode = match parse_int(v) {
                    1 => Mode::MoveOnly,
                    2 => Mode::CaptureOnly,
                    _ => Mode::MoveOrCapture,
                }
            }
            "captures_by_hopping" => r.captures_by_hopping = parse_bool(v),
            "leap_steps" => r.leap_steps = parse_int(v),
            "leap_over" => r.leap_over_own = parse_int(v) == 1,
            "path" => r.path = parse_vectors(v),
            "mirror_files" => r.mirror_files = parse_bool(v),
            "mirror_ranks" => r.mirror_ranks = parse_bool(v),
            _ => {}
        }
    }
    r
}

pub fn parse_piece_tres(text: &str) -> Result<PieceDef, String> {
    let sections = parse_tres(text);
    let mut subs: HashMap<String, MoveRule> = HashMap::new();
    for s in &sections {
        if s.kind == "sub_resource" {
            if let Some(id) = s.attrs.get("id") {
                subs.insert(id.clone(), parse_rule(s));
            }
        }
    }
    // External resources by id. The Werewolf's form is one; its file name is its id.
    let mut ext: HashMap<String, String> = HashMap::new();
    for s in &sections {
        if s.kind == "ext_resource" {
            if let (Some(id), Some(path)) = (s.attrs.get("id"), s.attrs.get("path")) {
                ext.insert(id.clone(), path.clone());
            }
        }
    }
    let main = sections.iter().find(|s| s.kind == "resource").ok_or("no [resource] section")?;
    let mut def = PieceDef::blank();
    for (k, v) in &main.props {
        match k.as_str() {
            "id" => def.id = unquote(v),
            "display_name" => def.name = unquote(v),
            "symbol" => def.symbol = unquote(v),
            "value" => def.value = v.trim().parse().unwrap_or(0.0),
            "types" => def.types = parse_int(v) as u8,
            "keywords" => {
                def.keywords = parse_int(v) as u8;
                if def.keywords & KW_WALL != 0 {
                    def.blocks_jumps = true;
                }
            }
            "ability" => def.ability = Ability::from_code(parse_int(v)),
            "dies_on_capture" => def.dies_on_capture = parse_bool(v),
            "blocks_jumps" => def.blocks_jumps = parse_bool(v),
            "shield_on_capture" => def.shield_on_capture = parse_bool(v),
            "decoy" => def.decoy = parse_bool(v),
            "protects" => def.protects = parse_strings(v),
            "transforms_into" => {
                let path = parse_refs(v, "ExtResource").first().and_then(|id| ext.get(id)).cloned().ok_or("transforms_into: missing resource")?;
                let stem = path.rsplit('/').next().unwrap_or(&path).trim_end_matches(".tres").to_string();
                def.transforms_into = Some(stem);
            }
            "move_rules" => {
                for id in parse_refs(v, "SubResource") {
                    def.rules.push(subs.get(&id).cloned().ok_or(format!("missing move rule {}", id))?);
                }
            }
            _ => {}
        }
    }
    if def.symbol.is_empty() {
        return Err("piece has no symbol".into());
    }
    if def.name.is_empty() {
        def.name = def.id.clone();
    }
    Ok(def)
}
