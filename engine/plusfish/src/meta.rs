//! `plusfish meta`: grows a pool of armies that look strong in the eval bar
//! at the start of the game (turn 0), against each other. Each round a new
//! army is hill-climbed from a random one against the whole pool, then:
//!   - it joins the pool if it differs enough from every member (and if that
//!     makes the pool too big, the member with the lowest average is dropped);
//!   - if it's close to a member, it replaces that member when it does better
//!     against the rest of the pool;
//!   - otherwise it's thrown away.
//! The run stops once the pool stays the same for a few rounds in a row.
//! Scores are Plusfish's own judgement, so re-run it whenever the engine gets
//! better; `start-check --pool` then shows how well those scores match games.

use plusfish_core::army::*;
use plusfish_core::defs::*;
use plusfish_core::eval::*;
use plusfish_core::search::*;
use plusfish_core::selfplay::{play_game, start_is_broken, PlayConfig};
use plusfish_core::util::{Args, Rng};
use std::collections::HashMap;
use std::io::Write;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

pub const HELP: &str = "\
meta: grow a pool of armies that look strong at the start (turn 0) in the eval
bar, against each other. Each round hill-climbs a new army against the pool:
it joins if its piece list differs from every member's by at least --min-diff
pieces (dropping the member with the lowest average once there are
more than --max), replaces a similar member if it does better against the rest,
or is thrown away. Stops after --stable rounds in a row without a change.
  --pool <file>      starting pool (pool.txt format); armies that break the
                     army rules are left out. Standard is always added.
  --out <file>       where the pool is written after every round (meta_pool.txt)
  --max N            pool size (default 10)       --rounds N (default 40)
  --stable N         rounds without a change before stopping (default 4)
  --min-diff N       pieces that must differ to count as new (default 3;
                     layout is ignored: same pieces, other squares = similar)
  --nodes N          nodes per start score, as the eval bar (default 20000)
  --climb-nodes N    nodes per score while climbing (default 8000)
  --patience N       climbing stops after N batches without a gain (default 5)
  --threads N        default 16   --seed N
  --name X           new armies are called X <round> (default Meta)
Scores are the advantage in centipawns, both colours averaged so White's
first move cancels; a pairing that starts with a king attacked counts as
unusable (the candidate is rejected).
";

struct Cfg {
    nodes: u64,
    climb_nodes: u64,
    threads: usize,
    min_diff: usize,
    patience: usize,
}

/// White's score of the starting position, from a node-limited search,
/// capped so a forced win doesn't swamp the averages. None = broken start.
struct Scorer<'a> {
    cat: &'a Arc<Catalog>,
    params: &'a Params,
    cache: Mutex<HashMap<(String, String, u64), Option<i32>>>,
    /// A start with Black's king attacked counts as White's win (+1500), as
    /// the game's temporary rule says, instead of an unusable pairing (None).
    exposed_wins: bool,
}

impl<'a> Scorer<'a> {
    fn start_score(&self, w: &Army, b: &Army, nodes: u64) -> Option<i32> {
        let key = (w.to_text(self.cat, 8), b.to_text(self.cat, 8), nodes);
        if let Some(&v) = self.cache.lock().unwrap().get(&key) {
            return v;
        }
        let g = army_game(self.cat, w, b, 8, 8);
        let v = if self.exposed_wins && g.pos.in_check(&g.rules, plusfish_core::position::BLACK) {
            Some(1500)
        } else if start_is_broken(&g) && !self.exposed_wins {
            None
        } else {
            let et = EvalTables::new(&g.rules);
            let mut s = Searcher::new(&g.rules, &et, self.params, 4);
            let lim = Limits { nodes: Some(nodes), ..Default::default() };
            let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], lim, 1, |_| {});
            Some(rep.lines.first().map(|l| l.score).unwrap_or(0).clamp(-1500, 1500))
        };
        self.cache.lock().unwrap().insert(key, v);
        v
    }

    /// a's advantage over b (centipawns), each playing White once.
    fn advantage(&self, a: &Army, b: &Army, nodes: u64) -> Option<f64> {
        let x = self.start_score(a, b, nodes)?;
        let y = self.start_score(b, a, nodes)?;
        Some((x - y) as f64 / 2.0)
    }

    /// Scores many pairings at once on `threads` threads.
    fn many(&self, pairs: &[(&Army, &Army)], nodes: u64, threads: usize) -> Vec<Option<f64>> {
        let out: Vec<Mutex<Option<f64>>> = pairs.iter().map(|_| Mutex::new(None)).collect();
        // Each pairing is two searches; spread the single searches.
        let jobs: Vec<(usize, bool)> = (0..pairs.len()).flat_map(|i| [(i, true), (i, false)]).collect();
        let next = AtomicUsize::new(0);
        std::thread::scope(|scope| {
            for _ in 0..threads.max(1) {
                scope.spawn(|| loop {
                    let j = next.fetch_add(1, Ordering::SeqCst);
                    if j >= jobs.len() {
                        break;
                    }
                    let (i, a_white) = jobs[j];
                    let (a, b) = pairs[i];
                    if a_white {
                        self.start_score(a, b, nodes);
                    } else {
                        self.start_score(b, a, nodes);
                    }
                });
            }
        });
        for (i, &(a, b)) in pairs.iter().enumerate() {
            *out[i].lock().unwrap() = self.advantage(a, b, nodes);
        }
        out.into_iter().map(|m| m.into_inner().unwrap()).collect()
    }

    /// Mean advantage of `a` over every army in `pool` (None if any pairing is broken).
    fn mean_vs(&self, a: &Army, pool: &[Army], nodes: u64, threads: usize) -> Option<f64> {
        if pool.is_empty() {
            return Some(0.0);
        }
        let pairs: Vec<(&Army, &Army)> = pool.iter().map(|p| (a, p)).collect();
        let v = self.many(&pairs, nodes, threads);
        let mut sum = 0.0;
        for x in v {
            sum += x?;
        }
        Some(sum / pool.len() as f64)
    }
}

fn buyable(cat: &Catalog) -> Vec<usize> {
    (0..cat.len()).filter(|&k| !cat.defs[k].is_king() && !cat.defs[k].is_form && cat.defs[k].value > 0.0).collect()
}

fn empty_squares(a: &Army) -> Vec<(i32, i32)> {
    let mut v = Vec::new();
    for row in 0..START_ROWS {
        for f in 0..8 {
            if a.at(f, row).is_none() {
                v.push((f, row));
            }
        }
    }
    v
}

/// One random change: swap a piece's type, move one, swap two squares, add,
/// remove, or trade one piece for one or two others (from plusfish-army-pool).
fn mutate_once(cat: &Catalog, a: &mut Army, rng: &mut Rng) {
    let kinds = buyable(cat);
    let non_king: Vec<usize> = (0..a.pieces.len()).filter(|&i| !cat.defs[a.pieces[i].0].is_king()).collect();
    let pick = |rng: &mut Rng, v: &Vec<usize>| -> Option<usize> { if v.is_empty() { None } else { Some(v[rng.below(v.len())]) } };
    match rng.below(7) {
        0 | 1 => {
            if let Some(i) = pick(rng, &non_king) {
                a.pieces[i].0 = kinds[rng.below(kinds.len())];
            }
        }
        2 => {
            let i = rng.below(a.pieces.len());
            let free = empty_squares(a);
            let kf = king_files(8);
            let free: Vec<(i32, i32)> = if cat.defs[a.pieces[i].0].is_king() { free.into_iter().filter(|s| s.1 == 0 && kf.contains(&s.0)).collect() } else { free };
            if !free.is_empty() {
                let s = free[rng.below(free.len())];
                a.pieces[i].1 = s.0;
                a.pieces[i].2 = s.1;
            }
        }
        3 => {
            if a.pieces.len() >= 2 {
                let i = rng.below(a.pieces.len());
                let j = rng.below(a.pieces.len());
                let (fi, ri) = (a.pieces[i].1, a.pieces[i].2);
                a.pieces[i].1 = a.pieces[j].1;
                a.pieces[i].2 = a.pieces[j].2;
                a.pieces[j].1 = fi;
                a.pieces[j].2 = ri;
            }
        }
        4 => {
            let free = empty_squares(a);
            if !free.is_empty() {
                let s = free[rng.below(free.len())];
                a.pieces.push((kinds[rng.below(kinds.len())], s.0, s.1));
            }
        }
        5 => {
            if let Some(i) = pick(rng, &non_king) {
                a.pieces.remove(i);
            }
        }
        _ => {
            if let Some(i) = pick(rng, &non_king) {
                let sq = (a.pieces[i].1, a.pieces[i].2);
                a.pieces.remove(i);
                a.pieces.push((kinds[rng.below(kinds.len())], sq.0, sq.1));
                if rng.below(2) == 0 {
                    let free = empty_squares(a);
                    if !free.is_empty() {
                        let s = free[rng.below(free.len())];
                        a.pieces.push((kinds[rng.below(kinds.len())], s.0, s.1));
                    }
                }
            }
        }
    }
}

/// A legal army 1 to 3 changes away from `parent`, costing at least 36.
fn mutate(cat: &Catalog, parent: &Army, rng: &mut Rng) -> Option<Army> {
    for _ in 0..500 {
        let mut a = parent.clone();
        for _ in 0..1 + rng.below(3) {
            mutate_once(cat, &mut a, rng);
        }
        a.pieces.sort_by_key(|p| (p.2, p.1));
        a.mirror = true;
        if a.pieces == parent.pieces || a.cost(cat) < 36.0 - 1e-9 || !a.problems(cat, 8).is_empty() {
            continue;
        }
        a.name = a.to_text(cat, 8);
        return Some(a);
    }
    None
}

/// How many pieces would have to change to turn one army's piece list into
/// the other's (layout ignored): half the summed differences in counts, rounded up.
pub fn pieces_apart(a: &Army, b: &Army) -> usize {
    let mut kinds: Vec<usize> = a.pieces.iter().chain(&b.pieces).map(|p| p.0).collect();
    kinds.sort();
    kinds.dedup();
    let total: usize = kinds.iter().map(|&k| (a.count(k) as i64 - b.count(k) as i64).unsigned_abs() as usize).sum();
    (total + 1) / 2
}

/// On how many of the 16 starting squares two armies differ (the closer of
/// the army as built and its mirror image, which plays the same).
pub fn squares_apart(a: &Army, b: &Army) -> usize {
    let diff = |flip: bool| {
        let mut n = 0;
        for row in 0..START_ROWS {
            for f in 0..8 {
                let fb = if flip { 7 - f } else { f };
                if a.at(f, row) != b.at(fb, row) {
                    n += 1;
                }
            }
        }
        n
    };
    diff(false).min(diff(true))
}

fn pieces_text(cat: &Catalog, a: &Army) -> String {
    let mut counts: Vec<(usize, usize)> = Vec::new();
    for p in &a.pieces {
        if cat.defs[p.0].is_king() {
            continue;
        }
        match counts.iter_mut().find(|c| c.0 == p.0) {
            Some(c) => c.1 += 1,
            None => counts.push((p.0, 1)),
        }
    }
    counts.sort_by(|x, y| cat.defs[y.0].value.partial_cmp(&cat.defs[x.0].value).unwrap().then(x.0.cmp(&y.0)));
    counts.iter().map(|&(k, n)| if n > 1 { format!("{} {}", n, cat.defs[k].name) } else { cat.defs[k].name.clone() }).collect::<Vec<_>>().join(", ")
}

struct Member {
    army: Army,
    name: String,
    born: usize,
}

/// Each member's mean advantage over the others, at the eval-bar budget.
fn standings(sc: &Scorer, pool: &[Member], cfg: &Cfg) -> Vec<f64> {
    let n = pool.len();
    let mut pairs = Vec::new();
    for i in 0..n {
        for j in i + 1..n {
            pairs.push((&pool[i].army, &pool[j].army));
        }
    }
    let v = sc.many(&pairs, cfg.nodes, cfg.threads);
    let mut sum = vec![0.0; n];
    let mut k = 0;
    for i in 0..n {
        for j in i + 1..n {
            let x = v[k].unwrap_or(0.0);
            sum[i] += x;
            sum[j] -= x;
            k += 1;
        }
    }
    sum.iter().map(|s| s / (n.max(2) - 1) as f64).collect()
}

/// Hill-climbs from `start` against `pool`: each batch tries one mutant per
/// thread and keeps the best if it beats the current army.
fn climb(cat: &Arc<Catalog>, sc: &Scorer, start: Army, pool: &[Army], cfg: &Cfg, rng: &mut Rng, log: &mut dyn FnMut(String)) -> (Army, f64) {
    let mut cur = start;
    let mut cur_score = sc.mean_vs(&cur, pool, cfg.climb_nodes, cfg.threads).unwrap_or(-1e9);
    let mut fails = 0;
    let mut batch = 0;
    while fails < cfg.patience && batch < 200 {
        batch += 1;
        let mutants: Vec<Army> = (0..cfg.threads.max(4)).filter_map(|_| mutate(cat, &cur, rng)).collect();
        // Score all mutants against the pool in one go.
        let mut pairs = Vec::new();
        for m in &mutants {
            for p in pool {
                pairs.push((m, p));
            }
        }
        let v = sc.many(&pairs, cfg.climb_nodes, cfg.threads);
        let mut best: Option<(usize, f64)> = None;
        for (i, _) in mutants.iter().enumerate() {
            let part = &v[i * pool.len()..(i + 1) * pool.len()];
            if part.iter().any(|x| x.is_none()) {
                continue;
            }
            let s = part.iter().map(|x| x.unwrap()).sum::<f64>() / pool.len().max(1) as f64;
            if best.map(|b| s > b.1).unwrap_or(true) {
                best = Some((i, s));
            }
        }
        match best {
            Some((i, s)) if s > cur_score + 0.5 => {
                cur = mutants[i].clone();
                cur_score = s;
                fails = 0;
            }
            _ => fails += 1,
        }
    }
    log(format!("  climbed {} batches to {:+.0} cp (at {} nodes): {}", batch, cur_score, cfg.climb_nodes, cur.to_text(cat, 8)));
    (cur, cur_score)
}

fn read_pool(cat: &Catalog, path: &str, log: &mut dyn FnMut(String)) -> Vec<(Army, String)> {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {}", path, e));
    let mut out = Vec::new();
    for l in text.lines().map(|l| l.trim()).filter(|l| !l.is_empty() && !l.starts_with('#')) {
        let mut f = l.split('|');
        let spec = f.next().unwrap().trim();
        let name = f.next().unwrap_or(spec).trim().to_string();
        match Army::from_text(cat, spec) {
            Ok(a) => {
                let p = a.problems(cat, 8);
                if p.is_empty() {
                    out.push((a, name));
                } else {
                    log(format!("left out {} ({}): {}", name, spec, p.join(" ")));
                }
            }
            Err(e) => log(format!("left out {}: {}", spec, e)),
        }
    }
    out
}

fn write_pool(cat: &Catalog, path: &str, pool: &[Member], score: &[f64], round: usize, cfg: &Cfg) {
    let mut s = String::new();
    s += "# Chess Plus army pool grown by `plusfish meta` (armies that look strongest at turn 0 in Plusfish's eval bar, against each other).\n";
    s += &format!("# After round {}. Score = mean advantage over the rest of the pool at the start, {} nodes, both colours averaged (centipawns).\n", round, cfg.nodes);
    s += "# army | name | cost | score | pieces\n";
    let mut order: Vec<usize> = (0..pool.len()).collect();
    order.sort_by(|&a, &b| score[b].partial_cmp(&score[a]).unwrap());
    for i in order {
        let m = &pool[i];
        s += &format!("{} | {} | {} | {:+.0} | {}\n", m.army.to_text(cat, 8), m.name, m.army.cost(cat), score[i], pieces_text(cat, &m.army));
    }
    std::fs::write(path, s).unwrap_or_else(|e| panic!("{}: {}", path, e));
}

pub fn run(cat: &Arc<Catalog>, params: &Params, args: &Args) {
    if args.get("wide").is_some() {
        return run_wide(cat, params, args);
    }
    let cfg = Cfg {
        nodes: args.num("nodes", 20_000),
        climb_nodes: args.num("climb-nodes", 8_000),
        threads: args.num("threads", 16),
        min_diff: args.num("min-diff", 3),
        patience: args.num("patience", 5),
    };
    let max: usize = args.num("max", 10);
    let rounds: usize = args.num("rounds", 40);
    let stable: usize = args.num("stable", 4);
    let out = args.get("out").unwrap_or("meta_pool.txt").to_string();
    let prefix = args.get("name").unwrap_or("Meta").to_string();
    let mut rng = Rng::new(args.num("seed", 1u64));
    let logf = Mutex::new(std::fs::File::create(format!("{}.log", out.trim_end_matches(".txt"))).ok());
    let mut log = |s: String| {
        println!("{}", s);
        if let Some(f) = logf.lock().unwrap().as_mut() {
            writeln!(f, "{}", s).ok();
        }
    };
    let sc = Scorer { cat, params, cache: Mutex::new(HashMap::new()), exposed_wins: false };

    let mut pool: Vec<Member> = vec![Member { army: standard(cat), name: "Standard".into(), born: 0 }];
    if let Some(p) = args.get("pool") {
        for (a, n) in read_pool(cat, p, &mut log) {
            pool.push(Member { army: a, name: n, born: 0 });
        }
    }
    // Members that start with a king attacked against another can't share a pool.
    let mut i = 1;
    while i < pool.len() {
        if (0..i).any(|j| start_is_broken(&army_game(cat, &pool[i].army, &pool[j].army, 8, 8)) || start_is_broken(&army_game(cat, &pool[j].army, &pool[i].army, 8, 8))) {
            log(format!("left out {}: a king is attacked at the start against another member", pool[i].name));
            pool.remove(i);
        } else {
            i += 1;
        }
    }
    let mut score = standings(&sc, &pool, &cfg);
    while pool.len() > max {
        let worst = (0..pool.len()).min_by(|&a, &b| score[a].partial_cmp(&score[b]).unwrap()).unwrap();
        log(format!("starting pool over {}: drops {} ({:+.0})", max, pool[worst].name, score[worst]));
        pool.remove(worst);
        score = standings(&sc, &pool, &cfg);
    }
    log(format!("starting pool: {}", pool.iter().zip(&score).map(|(m, s)| format!("{} {:+.0}", m.name, s)).collect::<Vec<_>>().join(", ")));
    write_pool(cat, &out, &pool, &score, 0, &cfg);

    let mut quiet = 0;
    for round in 1..=rounds {
        let t0 = std::time::Instant::now();
        // Even rounds refine a member against the others (the result usually
        // stays close to it and competes to replace it); odd rounds explore
        // from a random army.
        let refine = round % 2 == 0 && pool.len() >= 2;
        let pick = rng.below(pool.len());
        let others: Vec<Army> = (0..pool.len()).filter(|&i| !(refine && i == pick)).map(|i| pool[i].army.clone()).collect();
        let start = if refine {
            let m = &pool[pick];
            log(format!("round {}: refining {}: {}", round, m.name, m.army.to_text(cat, 8)));
            m.army.clone()
        } else {
            let a = loop {
                let a = random_army(cat, &mut rng);
                if a.cost(cat) >= 36.0 && sc.mean_vs(&a, &others, cfg.climb_nodes, cfg.threads).is_some() {
                    break a;
                }
            };
            log(format!("round {}: climbing from {}", round, a.to_text(cat, 8)));
            a
        };
        let (cand, _) = climb(cat, &sc, start, &others, &cfg, &mut rng, &mut log);
        let cand_score = match sc.mean_vs(&cand, &others, cfg.nodes, cfg.threads) {
            Some(s) => s,
            None => {
                log("  a king is attacked at the start against a member at the eval-bar budget: thrown away".into());
                quiet += 1;
                continue;
            }
        };
        // Nearest member by piece list, then by layout.
        let (near, apart) = (0..pool.len()).map(|i| (i, pieces_apart(&cand, &pool[i].army))).min_by_key(|&(i, d)| (d, squares_apart(&cand, &pool[i].army))).unwrap();
        let name = format!("{} {}", prefix, round);
        let mut changed = false;
        if apart >= cfg.min_diff {
            pool.push(Member { army: cand.clone(), name: name.clone(), born: round });
            score = standings(&sc, &pool, &cfg);
            log(format!("  {:+.0} cp vs the pool at {} nodes, {} pieces from the nearest ({}): joins as {}", cand_score, cfg.nodes, apart, pool[near].name, name));
            changed = true;
            while pool.len() > max {
                let worst = (0..pool.len()).min_by(|&a, &b| score[a].partial_cmp(&score[b]).unwrap()).unwrap();
                log(format!("  pool over {}: drops {} ({:+.0})", max, pool[worst].name, score[worst]));
                if pool[worst].born == round {
                    changed = false;
                }
                pool.remove(worst);
                score = standings(&sc, &pool, &cfg);
            }
        } else {
            // Close to a member: compare the two against the rest of the pool.
            let rest: Vec<Army> = (0..pool.len()).filter(|&i| i != near).map(|i| pool[i].army.clone()).collect();
            let c = sc.mean_vs(&cand, &rest, cfg.nodes, cfg.threads);
            let m = sc.mean_vs(&pool[near].army, &rest, cfg.nodes, cfg.threads).unwrap_or(-1e9);
            match c {
                Some(c) if c > m + 1.0 => {
                    log(format!("  only {} pieces from {}, and better against the rest ({:+.0} vs {:+.0}): replaces it as {}", apart, pool[near].name, c, m, name));
                    pool[near] = Member { army: cand.clone(), name: name.clone(), born: round };
                    score = standings(&sc, &pool, &cfg);
                    changed = true;
                }
                _ => log(format!("  only {} pieces from {}, and not better against the rest ({:+.0} vs {:+.0}): thrown away", apart, pool[near].name, c.unwrap_or(f64::NAN), m)),
            }
        }
        quiet = if changed { 0 } else { quiet + 1 };
        write_pool(cat, &out, &pool, &score, round, &cfg);
        log(format!(
            "  pool after round {} ({:.0}s): {}",
            round,
            t0.elapsed().as_secs_f64(),
            pool.iter().zip(&score).map(|(m, s)| format!("{} {:+.0}", m.name, s)).collect::<Vec<_>>().join(", ")
        ));
        if quiet >= stable && pool.len() >= max.min(3) {
            log(format!("stable: no change for {} rounds", quiet));
            break;
        }
    }
    log(format!("wrote {}", out));
}

// --- climb-fixed: hill-climb one army with some squares pinned ----------------

pub const FIXED_HELP: &str = "\
climb-fixed: hill-climb one army against a pool, with some squares pinned.
  --pool <file>      the armies to beat (pool.txt format; Standard is added)
  --keep <list>      pieces that must stay, as SYMBOL@square on the builder's
                     rows 1-2 (e.g. C@e1,K@d1)
  --empty <list>     squares that must stay empty (e.g. e2)
  --restarts N       climbs from random armies (default 4); every pool member
                     is also used as a start, with the pinned squares forced
  --nodes N          nodes for the final scores (default 20000)
  --climb-nodes N    nodes while climbing (default 8000)
  --patience N       batches without a gain before a climb stops (default 6)
  --threads N        default 16   --seed N   --out <file> (fixed_climb.txt)
Scores follow the game's rules, including Mac's temporary one: if Black's king
is attacked before White's first move, White wins at once (scored +1500, the
cap). Each result is reported with and without those instant wins.
";

/// The pinned squares: pieces that must stay put and squares that must stay empty.
struct Pins {
    keep: Vec<(usize, i32, i32)>,
    empty: Vec<(i32, i32)>,
}

fn builder_square(t: &str) -> (i32, i32) {
    let b = t.trim().as_bytes();
    assert!(b.len() == 2 && (b'a'..=b'h').contains(&b[0]) && (b'1'..=b'2').contains(&b[1]), "bad square {}", t);
    ((b[0] - b'a') as i32, (b[1] - b'1') as i32)
}

impl Pins {
    fn parse(cat: &Catalog, keep: &str, empty: &str) -> Pins {
        let keep = keep
            .split(',')
            .filter(|s| !s.trim().is_empty())
            .map(|s| {
                let (sym, sq) = s.split_once('@').unwrap_or_else(|| panic!("bad --keep entry {}", s));
                let k = cat.kind_by_symbol(sym.trim()).unwrap_or_else(|| panic!("unknown piece {}", sym));
                let (f, r) = builder_square(sq);
                (k, f, r)
            })
            .collect();
        let empty = empty.split(',').filter(|s| !s.trim().is_empty()).map(builder_square).collect();
        Pins { keep, empty }
    }

    fn obeyed_by(&self, a: &Army) -> bool {
        self.keep.iter().all(|&(k, f, r)| a.at(f, r) == Some(k)) && self.empty.iter().all(|&(f, r)| a.at(f, r).is_none())
    }

    /// `a` with the pins forced on it (anything in the way, and any other king,
    /// removed), then random pieces removed until it's legal. None if that fails.
    fn force(&self, cat: &Catalog, a: &Army, rng: &mut Rng) -> Option<Army> {
        let mut a = a.clone();
        let pins_king = self.keep.iter().any(|p| cat.defs[p.0].is_king());
        a.pieces.retain(|p| {
            !self.keep.iter().any(|q| (q.1, q.2) == (p.1, p.2)) && !self.empty.contains(&(p.1, p.2)) && !(pins_king && cat.defs[p.0].is_king())
        });
        for &(k, f, r) in &self.keep {
            a.pieces.push((k, f, r));
        }
        for _ in 0..40 {
            if a.problems(cat, 8).is_empty() {
                a.pieces.sort_by_key(|p| (p.2, p.1));
                a.mirror = true;
                a.name = a.to_text(cat, 8);
                return Some(a);
            }
            let free: Vec<usize> = (0..a.pieces.len()).filter(|&i| !self.keep.iter().any(|q| (q.1, q.2) == (a.pieces[i].1, a.pieces[i].2))).collect();
            if free.is_empty() {
                return None;
            }
            a.pieces.remove(free[rng.below(free.len())]);
        }
        None
    }

    fn mutate(&self, cat: &Catalog, parent: &Army, rng: &mut Rng) -> Option<Army> {
        for _ in 0..300 {
            if let Some(m) = mutate(cat, parent, rng) {
                if self.obeyed_by(&m) {
                    return Some(m);
                }
            }
        }
        None
    }
}

impl<'a> Scorer<'a> {
    /// White's score of the start under the game's rules: an instant win (+1500)
    /// if Black's king is attacked before White moves; otherwise a search (White
    /// may start in check, which is just a check).
    fn rule_score(&self, w: &Army, b: &Army, nodes: u64) -> i32 {
        let key = (format!("rule:{}", w.to_text(self.cat, 8)), b.to_text(self.cat, 8), nodes);
        if let Some(&v) = self.cache.lock().unwrap().get(&key) {
            return v.unwrap();
        }
        let g = army_game(self.cat, w, b, 8, 8);
        let v = if g.pos.in_check(&g.rules, plusfish_core::position::BLACK) {
            1500
        } else {
            let et = EvalTables::new(&g.rules);
            let mut s = Searcher::new(&g.rules, &et, self.params, 4);
            let lim = Limits { nodes: Some(nodes), ..Default::default() };
            let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], lim, 1, |_| {});
            rep.lines.first().map(|l| l.score).unwrap_or(0).clamp(-1500, 1500)
        };
        self.cache.lock().unwrap().insert(key, Some(v));
        v
    }

    /// rule_score for many (white, black) starts at once.
    fn many_rule(&self, starts: &[(&Army, &Army)], nodes: u64, threads: usize) -> Vec<i32> {
        let next = AtomicUsize::new(0);
        std::thread::scope(|scope| {
            for _ in 0..threads.max(1) {
                scope.spawn(|| loop {
                    let j = next.fetch_add(1, Ordering::SeqCst);
                    if j >= starts.len() {
                        break;
                    }
                    self.rule_score(starts[j].0, starts[j].1, nodes);
                });
            }
        });
        starts.iter().map(|&(w, b)| self.rule_score(w, b, nodes)).collect()
    }
}

/// For each army in `armies`: the score of each start against each pool member,
/// [as White, as Black (White's view)] per member.
fn fixed_scores(sc: &Scorer, armies: &[Army], pool: &[Army], nodes: u64, threads: usize) -> Vec<Vec<[i32; 2]>> {
    let mut starts = Vec::new();
    for a in armies {
        for p in pool {
            starts.push((a, p));
            starts.push((p, a));
        }
    }
    let v = sc.many_rule(&starts, nodes, threads);
    (0..armies.len())
        .map(|i| (0..pool.len()).map(|j| [v[(i * pool.len() + j) * 2], v[(i * pool.len() + j) * 2 + 1]]).collect())
        .collect()
}

/// Mean advantage over the pool (both colours averaged), counting instant wins.
fn fixed_mean(s: &[[i32; 2]]) -> f64 {
    s.iter().map(|x| (x[0] - x[1]) as f64 / 2.0).sum::<f64>() / s.len().max(1) as f64
}

pub fn run_fixed(cat: &Arc<Catalog>, params: &Params, args: &Args) {
    let threads: usize = args.num("threads", 16);
    let nodes: u64 = args.num("nodes", 20_000);
    let climb_nodes: u64 = args.num("climb-nodes", 8_000);
    let patience: usize = args.num("patience", 6);
    let restarts: usize = args.num("restarts", 4);
    let out = args.get("out").unwrap_or("fixed_climb.txt").to_string();
    let mut rng = Rng::new(args.num("seed", 1u64));
    let pins = Pins::parse(cat, args.get("keep").unwrap_or(""), args.get("empty").unwrap_or(""));
    let logf = Mutex::new(std::fs::File::create(format!("{}.log", out.trim_end_matches(".txt"))).ok());
    let log = |s: String| {
        println!("{}", s);
        if let Some(f) = logf.lock().unwrap().as_mut() {
            writeln!(f, "{}", s).ok();
        }
    };
    let sc = Scorer { cat, params, cache: Mutex::new(HashMap::new()), exposed_wins: false };
    let mut pool: Vec<(Army, String)> = vec![(standard(cat), "Standard".into())];
    if let Some(p) = args.get("pool") {
        let mut l = |s: String| log(s);
        pool.extend(read_pool(cat, p, &mut l));
    }
    let pool_armies: Vec<Army> = pool.iter().map(|p| p.0.clone()).collect();

    // Starts: every pool member with the pins forced, plus random armies.
    let mut starts: Vec<(Army, String)> = Vec::new();
    for (a, n) in &pool {
        if let Some(f) = pins.force(cat, a, &mut rng) {
            starts.push((f, format!("from {}", n)));
        }
    }
    let mut tries = 0;
    while starts.len() < pool.len() + restarts && tries < 1000 {
        tries += 1;
        if let Some(f) = pins.force(cat, &random_army(cat, &mut rng), &mut rng) {
            starts.push((f, "from random".into()));
        }
    }
    log(format!("{} climbs; pinned: {} kept, {} empty; pool of {}", starts.len(), pins.keep.len(), pins.empty.len(), pool.len()));

    let mut results: Vec<(Army, String)> = Vec::new();
    for (si, (start, label)) in starts.iter().enumerate() {
        let mut cur = start.clone();
        let mut cur_score = fixed_mean(&fixed_scores(&sc, &[cur.clone()], &pool_armies, climb_nodes, threads)[0]);
        let (mut fails, mut batch) = (0, 0);
        while fails < patience && batch < 200 {
            batch += 1;
            let mutants: Vec<Army> = (0..threads.max(4)).filter_map(|_| pins.mutate(cat, &cur, &mut rng)).collect();
            let scores = fixed_scores(&sc, &mutants, &pool_armies, climb_nodes, threads);
            let best = scores.iter().map(|s| fixed_mean(s)).enumerate().max_by(|a, b| a.1.partial_cmp(&b.1).unwrap());
            match best {
                Some((i, s)) if s > cur_score + 0.5 => {
                    cur = mutants[i].clone();
                    cur_score = s;
                    fails = 0;
                }
                _ => fails += 1,
            }
        }
        log(format!("climb {}/{} ({}): {} batches -> {:+.0} cp at {} nodes: {}", si + 1, starts.len(), label, batch, cur_score, climb_nodes, cur.to_text(cat, 8)));
        results.push((cur, label.clone()));
    }

    // Final scores at the eval bar's budget, best first.
    let armies: Vec<Army> = results.iter().map(|r| r.0.clone()).collect();
    let finals = fixed_scores(&sc, &armies, &pool_armies, nodes, threads);
    let mut order: Vec<usize> = (0..armies.len()).collect();
    order.sort_by(|&a, &b| fixed_mean(&finals[b]).partial_cmp(&fixed_mean(&finals[a])).unwrap());
    let mut s = String::new();
    s += &format!("# climb-fixed against {} armies, {} nodes. Score = mean advantage (cp, both colours averaged); \"instant\" = Black's king attacked at the start (White wins at once).\n", pool.len(), nodes);
    s += "# army | start | cost | score | score without instant-win pairings | instant wins as White | pieces\n";
    for &i in &order {
        let f = &finals[i];
        let instant = f.iter().filter(|x| x[0] == 1500).count();
        let fair: Vec<[i32; 2]> = f.iter().filter(|x| x[0] != 1500 && x[1] != 1500).cloned().collect();
        s += &format!("{} | {} | {} | {:+.0} | {:+.0} ({} pairings) | {}/{} | {}\n", armies[i].to_text(cat, 8), results[i].1, armies[i].cost(cat), fixed_mean(f), fixed_mean(&fair), fair.len(), instant, pool.len(), pieces_text(cat, &armies[i]));
    }
    let best = order[0];
    s += "\n# Best army against each pool member (White's view, cp):\n# member | best as White | best as Black\n";
    for (j, (_, n)) in pool.iter().enumerate() {
        let f = finals[best][j];
        let w = if f[0] == 1500 { "instant win".to_string() } else { format!("{:+}", f[0]) };
        s += &format!("{} | {} | {:+}\n", n, w, f[1]);
    }
    std::fs::write(&out, &s).unwrap_or_else(|e| panic!("{}: {}", out, e));
    log(s);
}

// --- meta --wide: many cheap eval climbs, then games decide --------------------

pub const WIDE_HELP: &str = "\
meta --wide N: grow the pool by searching wide and deciding with games.
Each round:
  1. N climbers (--wide, default 38) hill-climb at once, each from a random
     army (--refine of them start from pool members instead, default 4), using
     Plusfish's turn-0 eval as a quick guide: --mutants tries per step (default
     6), --climb-nodes per score (default 3000), --patience steps without a
     gain before stopping (default 4).
  2. The finishers are re-scored at --nodes (default 20000, as the eval bar)
     and the best --shortlist (default 3) different ones go on.
  3. With --game-climb, the best of them is polished with games: each step
     takes the --gc-mutants (default 4) best of 12 tweaks by eval and plays
     each, and the current army, --gc-games games per colour (default 4)
     against every member on the same openings; the best is kept if it scores
     at least --gc-margin (default 0.03) more. Stops after --gc-patience steps
     without a gain (default 3) or --gc-steps (default 10).
  4. Games decide: each shortlisted army plays --games games (default 40, half
     with each colour) against every member at --game-nodes per move (default
     6000). If its piece list is at least --min-diff pieces (default 3) from
     every member's, it joins and, past --max members (default 10), the member
     with the lowest game score against the others is dropped (it can be the
     newcomer). If it's close to a member, it replaces that member when its
     game score against the rest beats the member's by --replace-margin
     (default 0.02).
Stops after --stable rounds without a change (default 3) or --rounds (default 8).
Every member pair plays --games games once (kept for later rounds).
  --king-exposed win|reject   a start with Black's king attacked: an instant
                     win for White, as in the game now (default), or reject
                     such armies (the old meta behaviour)
  --pool <file> --out <file> --threads N (default 16) --seed N --name X
  --split-colours    experiment (Mac, Oct 2026): grow a White pool and a Black
                     pool side by side instead of one pool. A White army is
                     judged only by its eval and games as White against the
                     Black pool, and the other way round; each round does
                     steps 1-4 once for each colour. Both pools start from
                     --pool plus Standard. Writes <out>_white.txt and
                     <out>_black.txt (pool format).
  --phase N          with --split-colours: grow one colour at a time, N rounds
                     each, against the other pool frozen (White first), so each
                     side settles against a fixed target instead of chasing a
                     moving one (default 0: both colours every round).
";

struct WideCfg {
    threads: usize,
    nodes: u64,
    climb_nodes: u64,
    mutants: usize,
    patience: usize,
    wide: usize,
    refine: usize,
    shortlist: usize,
    min_diff: usize,
    games: usize,
    play: PlayConfig,
    game_climb: bool,
    gc_games: usize,
    gc_mutants: usize,
    gc_margin: f64,
    gc_patience: usize,
    gc_steps: usize,
    replace_margin: f64,
    max: usize,
}

/// A hill climb on one thread: each step tries `mutants` tweaks and keeps the
/// best if it beats the current army's mean advantage over `pool`.
fn climb_one(cat: &Catalog, sc: &Scorer, start: Army, pool: &[Army], nodes: u64, mutants: usize, patience: usize, rng: &mut Rng) -> (Army, f64) {
    let score = |a: &Army| -> Option<f64> {
        let mut sum = 0.0;
        for p in pool {
            sum += sc.advantage(a, p, nodes)?;
        }
        Some(sum / pool.len().max(1) as f64)
    };
    let mut cur = start;
    let mut cur_score = score(&cur).unwrap_or(-1e9);
    let (mut fails, mut steps) = (0, 0);
    while fails < patience && steps < 100 {
        steps += 1;
        let mut best: Option<(Army, f64)> = None;
        for _ in 0..mutants {
            if let Some(m) = mutate(cat, &cur, rng) {
                if let Some(s) = score(&m) {
                    if best.as_ref().map(|b| s > b.1).unwrap_or(true) {
                        best = Some((m, s));
                    }
                }
            }
        }
        match best {
            Some((m, s)) if s > cur_score + 0.5 => {
                cur = m;
                cur_score = s;
                fails = 0;
            }
            _ => fails += 1,
        }
    }
    (cur, cur_score)
}

/// Game results between armies, kept by army text: (a, b) -> a's points and
/// games played, stored once per pair.
struct GameBook<'a> {
    cat: &'a Arc<Catalog>,
    params: &'a Params,
    play: PlayConfig,
    threads: usize,
    table: HashMap<(String, String), (f64, usize)>,
}

impl<'a> GameBook<'a> {
    /// Plays `n` games (alternating colours, A White first) for each pair, all
    /// in parallel; pair i's game k uses seed `seed + i * 1000 + k`, so equal
    /// `seed`s give the same openings. Returns A's points per pair.
    fn play(&self, pairs: &[(&Army, &Army)], n: usize, seed: u64) -> Vec<f64> {
        let jobs: Vec<(usize, usize)> = (0..pairs.len()).flat_map(|i| (0..n).map(move |k| (i, k))).collect();
        let points: Vec<Mutex<f64>> = pairs.iter().map(|_| Mutex::new(0.0)).collect();
        let next = AtomicUsize::new(0);
        std::thread::scope(|scope| {
            for _ in 0..self.threads.max(1) {
                scope.spawn(|| loop {
                    let j = next.fetch_add(1, Ordering::SeqCst);
                    if j >= jobs.len() {
                        break;
                    }
                    let (i, k) = jobs[j];
                    let (a, b) = pairs[i];
                    let a_white = k % 2 == 0;
                    let (w, bl) = if a_white { (a, b) } else { (b, a) };
                    let rec = play_game(self.cat, w, bl, self.params, self.params, true, &self.play, seed + i as u64 * 1000 + k as u64);
                    let a_points = if a_white { rec.result as f64 } else { 1.0 - rec.result as f64 };
                    *points[i].lock().unwrap() += a_points;
                });
            }
        });
        points.into_iter().map(|m| m.into_inner().unwrap()).collect()
    }

    fn key(&self, a: &Army, b: &Army) -> ((String, String), bool) {
        let (x, y) = (a.to_text(self.cat, 8), b.to_text(self.cat, 8));
        if x <= y { ((x, y), false) } else { ((y, x), true) }
    }

    fn record(&mut self, a: &Army, b: &Army, a_points: f64, n: usize) {
        let (k, flipped) = self.key(a, b);
        let e = self.table.entry(k).or_insert((0.0, 0));
        e.0 += if flipped { n as f64 - a_points } else { a_points };
        e.1 += n;
    }

    /// a's mean score against b (None if they haven't played).
    fn score(&self, a: &Army, b: &Army) -> Option<f64> {
        let (k, flipped) = self.key(a, b);
        self.table.get(&k).filter(|e| e.1 > 0).map(|e| if flipped { 1.0 - e.0 / e.1 as f64 } else { e.0 / e.1 as f64 })
    }

    /// Plays whatever games are missing so every pair in `armies` has `n`.
    fn fill(&mut self, armies: &[&Army], n: usize, seed: u64) {
        let mut todo: Vec<(&Army, &Army, usize)> = Vec::new();
        for i in 0..armies.len() {
            for j in i + 1..armies.len() {
                let (k, _) = self.key(armies[i], armies[j]);
                let have = self.table.get(&k).map(|e| e.1).unwrap_or(0);
                if have < n {
                    todo.push((armies[i], armies[j], n - have));
                }
            }
        }
        if todo.is_empty() {
            return;
        }
        // Pairs needing the same number of games are played together.
        let mut counts: Vec<usize> = todo.iter().map(|t| t.2).collect();
        counts.sort();
        counts.dedup();
        for c in counts {
            let pairs: Vec<(&Army, &Army)> = todo.iter().filter(|t| t.2 == c).map(|t| (t.0, t.1)).collect();
            let pts = self.play(&pairs, c, seed);
            for (p, x) in pairs.iter().zip(pts) {
                self.record(p.0, p.1, x, c);
            }
        }
    }

    /// Mean score of `a` against `others` (pairs not played count as 0.5).
    fn mean(&self, a: &Army, others: &[&Army]) -> f64 {
        if others.is_empty() {
            return 0.5;
        }
        others.iter().map(|o| self.score(a, o).unwrap_or(0.5)).sum::<f64>() / others.len() as f64
    }
}

fn elo_of(s: f64) -> f64 {
    let s = s.clamp(0.001, 0.999);
    400.0 * (s / (1.0 - s)).log10()
}

/// Polishes `start` with games against `pool` (see WIDE_HELP step 3).
fn game_climb(cat: &Arc<Catalog>, sc: &Scorer, book: &GameBook, start: Army, pool: &[&Army], cfg: &WideCfg, rng: &mut Rng, seed: u64, log: &dyn Fn(String)) -> Army {
    let pool_owned: Vec<Army> = pool.iter().map(|a| (*a).clone()).collect();
    let mut cur = start;
    let mut fails = 0;
    for step in 0..cfg.gc_steps {
        if fails >= cfg.gc_patience {
            break;
        }
        // The eval picks which tweaks are worth playing.
        let mut tweaks: Vec<(Army, f64)> = (0..12)
            .filter_map(|_| mutate(cat, &cur, rng))
            .filter_map(|m| {
                let s = pool_owned.iter().map(|p| sc.advantage(&m, p, cfg.climb_nodes)).collect::<Option<Vec<f64>>>()?;
                Some((m, s.iter().sum::<f64>()))
            })
            .collect();
        tweaks.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        tweaks.dedup_by(|a, b| a.0.pieces == b.0.pieces);
        let mut armies = vec![cur.clone()];
        armies.extend(tweaks.into_iter().take(cfg.gc_mutants).map(|t| t.0));
        // Everyone plays the same openings against each member.
        let n = cfg.gc_games * 2;
        let mut pairs = Vec::new();
        for a in &armies {
            for p in pool {
                pairs.push((a, *p));
            }
        }
        let mut pts = vec![0.0; armies.len()];
        // Same seed per member slot for every army: play army by army.
        for (ai, chunk) in pairs.chunks(pool.len()).enumerate() {
            let v = book.play(chunk, n, seed + step as u64 * 100_000);
            pts[ai] = v.iter().sum::<f64>() / (n * pool.len()) as f64;
        }
        let best = (1..armies.len()).max_by(|&a, &b| pts[a].partial_cmp(&pts[b]).unwrap());
        match best {
            Some(i) if pts[i] >= pts[0] + cfg.gc_margin => {
                log(format!("    game climb step {}: {:.1}% -> {:.1}% with {}", step + 1, 100.0 * pts[0], 100.0 * pts[i], armies[i].to_text(cat, 8)));
                cur = armies[i].clone();
                fails = 0;
            }
            _ => {
                log(format!("    game climb step {}: no tweak beat {:.1}% (best {:.1}%)", step + 1, 100.0 * pts[0], best.map(|i| 100.0 * pts[i]).unwrap_or(0.0)));
                fails += 1;
            }
        }
    }
    cur
}

fn wide_cfg(args: &Args) -> WideCfg {
    let mut play = PlayConfig::default();
    play.nodes = args.num("game-nodes", 6_000);
    play.random_plies = args.num("random-plies", 6);
    WideCfg {
        threads: args.num("threads", 16),
        nodes: args.num("nodes", 20_000),
        climb_nodes: args.num("climb-nodes", 3_000),
        mutants: args.num("mutants", 6),
        patience: args.num("patience", 4),
        wide: args.num("wide", 38),
        refine: args.num("refine", 4),
        shortlist: args.num("shortlist", 3),
        min_diff: args.num("min-diff", 3),
        games: args.num("games", 40),
        play,
        game_climb: args.flag("game-climb"),
        gc_games: args.num("gc-games", 4),
        gc_mutants: args.num("gc-mutants", 4),
        gc_margin: args.get("gc-margin").map(|s| s.parse().unwrap()).unwrap_or(0.03),
        gc_patience: args.num("gc-patience", 3),
        gc_steps: args.num("gc-steps", 10),
        replace_margin: args.get("replace-margin").map(|s| s.parse().unwrap()).unwrap_or(0.02),
        max: args.num("max", 10),
    }
}

pub fn run_wide(cat: &Arc<Catalog>, params: &Params, args: &Args) {
    if args.flag("split-colours") {
        return run_split(cat, params, args);
    }
    let cfg = wide_cfg(args);
    let rounds: usize = args.num("rounds", 8);
    let stable: usize = args.num("stable", 3);
    let exposed_wins = args.get("king-exposed").unwrap_or("win") != "reject";
    let out = args.get("out").unwrap_or("meta_pool.txt").to_string();
    let prefix = args.get("name").unwrap_or("Wide").to_string();
    let seed: u64 = args.num("seed", 1u64);
    let mut rng = Rng::new(seed);
    let logf = Mutex::new(std::fs::File::create(format!("{}.log", out.trim_end_matches(".txt"))).ok());
    let log = |s: String| {
        println!("{}", s);
        if let Some(f) = logf.lock().unwrap().as_mut() {
            writeln!(f, "{}", s).ok();
            f.flush().ok();
        }
    };
    let sc = Scorer { cat, params, cache: Mutex::new(HashMap::new()), exposed_wins };
    let mut book = GameBook { cat, params, play: cfg.play.clone(), threads: cfg.threads, table: HashMap::new() };

    let mut pool: Vec<Member> = vec![Member { army: standard(cat), name: "Standard".into(), born: 0 }];
    if let Some(p) = args.get("pool") {
        let mut l = |s: String| log(s);
        for (a, n) in read_pool(cat, p, &mut l) {
            pool.push(Member { army: a, name: n, born: 0 });
        }
    }
    if !exposed_wins {
        let mut i = 1;
        while i < pool.len() {
            if (0..i).any(|j| start_is_broken(&army_game(cat, &pool[i].army, &pool[j].army, 8, 8)) || start_is_broken(&army_game(cat, &pool[j].army, &pool[i].army, 8, 8))) {
                log(format!("left out {}: a king is attacked at the start against another member", pool[i].name));
                pool.remove(i);
            } else {
                i += 1;
            }
        }
    }
    log(format!(
        "wide meta: {} climbers a round ({} from members), {} tries a step at {} nodes; shortlist {}; games {} per pair at {} nodes; game climb {}; king exposed at the start = {}",
        cfg.wide, cfg.refine, cfg.mutants, cfg.climb_nodes, cfg.shortlist, cfg.games, cfg.play.nodes, if cfg.game_climb { "on" } else { "off" }, if exposed_wins { "instant win" } else { "rejected" }
    ));
    let t0 = std::time::Instant::now();
    {
        let members: Vec<&Army> = pool.iter().map(|m| &m.army).collect();
        book.fill(&members, cfg.games, seed * 7_919);
    }
    let standings = |pool: &[Member], book: &GameBook| -> Vec<f64> {
        (0..pool.len())
            .map(|i| {
                let others: Vec<&Army> = (0..pool.len()).filter(|&j| j != i).map(|j| &pool[j].army).collect();
                book.mean(&pool[i].army, &others)
            })
            .collect()
    };
    let eval_scores = |pool: &[Member]| -> Vec<f64> {
        let armies: Vec<Army> = pool.iter().map(|m| m.army.clone()).collect();
        (0..armies.len())
            .map(|i| {
                let others: Vec<Army> = (0..armies.len()).filter(|&j| j != i).map(|j| armies[j].clone()).collect();
                sc.mean_vs(&armies[i], &others, cfg.nodes, cfg.threads).unwrap_or(f64::NAN)
            })
            .collect()
    };
    let write = |pool: &[Member], book: &GameBook, round: usize| {
        let g = standings(pool, book);
        let e = eval_scores(pool);
        let mut s = String::new();
        s += "# Chess Plus army pool grown by `plusfish meta --wide` (wide eval-guided climbs; games decide who stays).\n";
        s += &format!("# After round {}. Games = mean score against the rest of the pool ({} games per pair, {} nodes per move); eval = mean turn-0 advantage at {} nodes (cp).\n", round, cfg.games, cfg.play.nodes, cfg.nodes);
        s += "# army | name | cost | games (Elo) | eval | pieces\n";
        let mut order: Vec<usize> = (0..pool.len()).collect();
        order.sort_by(|&a, &b| g[b].partial_cmp(&g[a]).unwrap());
        for i in order {
            let m = &pool[i];
            s += &format!("{} | {} | {} | {:.1}% ({:+.0}) | {:+.0} | {}\n", m.army.to_text(cat, 8), m.name, m.army.cost(cat), 100.0 * g[i], elo_of(g[i]), e[i], pieces_text(cat, &m.army));
        }
        std::fs::write(&out, s).unwrap_or_else(|e| panic!("{}: {}", out, e));
        let parts: Vec<String> = pool.iter().zip(&g).map(|(m, x)| format!("{} {:+.0}", m.name, elo_of(*x))).collect();
        log(format!("  pool (game Elo): {}", parts.join(", ")));
    };
    log(format!("starting pool played out ({:.0}s)", t0.elapsed().as_secs_f64()));
    write(&pool, &book, 0);

    let mut quiet = 0;
    for round in 1..=rounds {
        let t0 = std::time::Instant::now();
        let members: Vec<Army> = pool.iter().map(|m| m.army.clone()).collect();
        // 1. Climb wide.
        let mut starts: Vec<Army> = Vec::new();
        for _ in 0..cfg.refine.min(pool.len()) {
            starts.push(pool[rng.below(pool.len())].army.clone());
        }
        while starts.len() < cfg.wide {
            let a = random_army(cat, &mut rng);
            if a.cost(cat) >= 36.0 {
                starts.push(a);
            }
        }
        let finished: Vec<Mutex<Option<(Army, f64)>>> = starts.iter().map(|_| Mutex::new(None)).collect();
        let next = AtomicUsize::new(0);
        let round_seed = rng.below(1 << 30) as u64;
        std::thread::scope(|scope| {
            for _ in 0..cfg.threads.max(1) {
                scope.spawn(|| loop {
                    let i = next.fetch_add(1, Ordering::SeqCst);
                    if i >= starts.len() {
                        break;
                    }
                    let mut r = Rng::new(round_seed * 1_000 + i as u64 + 1);
                    let res = climb_one(cat, &sc, starts[i].clone(), &members, cfg.climb_nodes, cfg.mutants, cfg.patience, &mut r);
                    *finished[i].lock().unwrap() = Some(res);
                });
            }
        });
        let mut climbed: Vec<Army> = finished.into_iter().filter_map(|m| m.into_inner().unwrap()).map(|r| r.0).collect();
        climbed.sort_by_key(|a| a.to_text(cat, 8));
        climbed.dedup_by(|a, b| a.pieces == b.pieces);
        // 2. Shortlist at the eval bar's budget.
        let mut pairs = Vec::new();
        for c in &climbed {
            for m in &members {
                pairs.push((c, m));
            }
        }
        let adv = sc.many(&pairs, cfg.nodes, cfg.threads);
        let mut ranked: Vec<(usize, f64)> = (0..climbed.len())
            .filter_map(|i| {
                let part = &adv[i * members.len()..(i + 1) * members.len()];
                let v: Option<Vec<f64>> = part.iter().cloned().collect();
                v.map(|v| (i, v.iter().sum::<f64>() / members.len() as f64))
            })
            .collect();
        ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        let mut shortlist: Vec<Army> = Vec::new();
        for &(i, _) in &ranked {
            if shortlist.len() >= cfg.shortlist {
                break;
            }
            if shortlist.iter().all(|s| pieces_apart(s, &climbed[i]) > 0 || squares_apart(s, &climbed[i]) > 0) {
                shortlist.push(climbed[i].clone());
            }
        }
        log(format!(
            "round {}: {} climbs ({:.0}s); best by eval: {}",
            round,
            climbed.len(),
            t0.elapsed().as_secs_f64(),
            ranked.iter().take(cfg.shortlist).map(|&(i, s)| format!("{:+.0} {}", s, climbed[i].to_text(cat, 8))).collect::<Vec<_>>().join(", ")
        ));
        // 3. Game climb on the best.
        if cfg.game_climb && !shortlist.is_empty() {
            let refs: Vec<&Army> = members.iter().collect();
            let polished = game_climb(cat, &sc, &book, shortlist[0].clone(), &refs, &cfg, &mut rng, round_seed * 31 + 7, &log);
            if polished.pieces != shortlist[0].pieces {
                shortlist.insert(0, polished);
                shortlist.truncate(cfg.shortlist);
            }
        }
        // 4. Games decide.
        let mut changed = false;
        for (ci, cand) in shortlist.iter().enumerate() {
            {
                let refs: Vec<&Army> = pool.iter().map(|m| &m.army).collect();
                let mut all = refs.clone();
                all.push(cand);
                book.fill(&all, cfg.games, round_seed * 7 + ci as u64 * 13 + 3);
            }
            let refs: Vec<&Army> = pool.iter().map(|m| &m.army).collect();
            let cand_score = book.mean(cand, &refs);
            let (near, apart) = (0..pool.len()).map(|i| (i, pieces_apart(cand, &pool[i].army))).min_by_key(|&(i, d)| (d, squares_apart(cand, &pool[i].army))).unwrap();
            let name = format!("{} {}{}", prefix, round, ["a", "b", "c", "d", "e", "f"].get(ci).unwrap_or(&""));
            if apart >= cfg.min_diff {
                pool.push(Member { army: cand.clone(), name: name.clone(), born: round });
                log(format!("  {} scores {:.1}% ({:+.0} Elo) against the pool in games, {} pieces from the nearest ({}): joins as {}", cand.to_text(cat, 8), 100.0 * cand_score, elo_of(cand_score), apart, pool[near].name, name));
                let mut joined = true;
                while pool.len() > cfg.max {
                    let g = standings(&pool, &book);
                    let worst = (0..pool.len()).min_by(|&a, &b| g[a].partial_cmp(&g[b]).unwrap()).unwrap();
                    log(format!("  pool over {}: drops {} ({:.1}%)", cfg.max, pool[worst].name, 100.0 * g[worst]));
                    if pool[worst].name == name {
                        joined = false;
                    }
                    pool.remove(worst);
                }
                changed |= joined;
            } else {
                let rest: Vec<&Army> = (0..pool.len()).filter(|&i| i != near).map(|i| &pool[i].army).collect();
                let c = book.mean(cand, &rest);
                let m = book.mean(&pool[near].army, &rest);
                if c > m + cfg.replace_margin {
                    log(format!("  {} is only {} pieces from {} and scores better against the rest in games ({:.1}% vs {:.1}%): replaces it as {}", cand.to_text(cat, 8), apart, pool[near].name, 100.0 * c, 100.0 * m, name));
                    pool[near] = Member { army: cand.clone(), name, born: round };
                    changed = true;
                } else {
                    log(format!("  {} is only {} pieces from {} and doesn't score better against the rest in games ({:.1}% vs {:.1}%): thrown away", cand.to_text(cat, 8), apart, pool[near].name, 100.0 * c, 100.0 * m));
                }
            }
        }
        log(format!("  round {} took {:.0}s", round, t0.elapsed().as_secs_f64()));
        write(&pool, &book, round);
        quiet = if changed { 0 } else { quiet + 1 };
        if quiet >= stable {
            log(format!("stable: no change for {} rounds", quiet));
            break;
        }
    }
    log(format!("wrote {}", out));
}

// --- meta --wide --split-colours: a White pool and a Black pool ----------------

/// `a`'s turn-0 score (cp, from its own side) playing `white` (true) or Black
/// against `o`. None = a broken start.
fn side_score(sc: &Scorer, a: &Army, white: bool, o: &Army, nodes: u64) -> Option<f64> {
    if white {
        sc.start_score(a, o, nodes).map(|v| v as f64)
    } else {
        sc.start_score(o, a, nodes).map(|v| -(v as f64))
    }
}

/// `a`'s mean turn-0 score as that colour against every army in `opp`.
fn side_mean(sc: &Scorer, a: &Army, white: bool, opp: &[Army], nodes: u64) -> Option<f64> {
    let mut sum = 0.0;
    for o in opp {
        sum += side_score(sc, a, white, o, nodes)?;
    }
    Some(sum / opp.len().max(1) as f64)
}

/// Works out (and caches) the turn-0 score of every (White, Black) pairing
/// in `jobs`, on `threads` threads.
fn warm(sc: &Scorer, jobs: &[(&Army, &Army)], nodes: u64, threads: usize) {
    let next = AtomicUsize::new(0);
    std::thread::scope(|scope| {
        for _ in 0..threads.max(1) {
            scope.spawn(|| loop {
                let j = next.fetch_add(1, Ordering::SeqCst);
                if j >= jobs.len() {
                    break;
                }
                sc.start_score(jobs[j].0, jobs[j].1, nodes);
            });
        }
    });
}

/// The (White, Black) pairings for `armies` playing `white` against `opp`.
fn side_pairs<'b>(armies: &'b [Army], white: bool, opp: &'b [Army]) -> Vec<(&'b Army, &'b Army)> {
    let mut v = Vec::new();
    for a in armies {
        for o in opp {
            v.push(if white { (a, o) } else { (o, a) });
        }
    }
    v
}

/// A hill climb for one colour (as climb_one, judged only as that colour).
fn climb_side(cat: &Catalog, sc: &Scorer, start: Army, white: bool, opp: &[Army], nodes: u64, mutants: usize, patience: usize, rng: &mut Rng) -> (Army, f64) {
    let mut cur = start;
    let mut cur_score = side_mean(sc, &cur, white, opp, nodes).unwrap_or(-1e9);
    let (mut fails, mut steps) = (0, 0);
    while fails < patience && steps < 100 {
        steps += 1;
        let mut best: Option<(Army, f64)> = None;
        for _ in 0..mutants {
            if let Some(m) = mutate(cat, &cur, rng) {
                if let Some(s) = side_mean(sc, &m, white, opp, nodes) {
                    if best.as_ref().map(|b| s > b.1).unwrap_or(true) {
                        best = Some((m, s));
                    }
                }
            }
        }
        match best {
            Some((m, s)) if s > cur_score + 0.5 => {
                cur = m;
                cur_score = s;
                fails = 0;
            }
            _ => fails += 1,
        }
    }
    (cur, cur_score)
}

/// Game results with fixed colours: (White army, Black army) -> White's
/// points and games played.
struct ColourBook<'a> {
    cat: &'a Arc<Catalog>,
    params: &'a Params,
    play: PlayConfig,
    threads: usize,
    table: HashMap<(String, String), (f64, usize)>,
}

impl<'a> ColourBook<'a> {
    /// Plays `n` games for each (White, Black) pair, all in parallel; pair i's
    /// game k uses seed `seed + i * 1000 + k`. Returns White's points per pair.
    fn play(&self, pairs: &[(&Army, &Army)], n: usize, seed: u64) -> Vec<f64> {
        let jobs: Vec<(usize, usize)> = (0..pairs.len()).flat_map(|i| (0..n).map(move |k| (i, k))).collect();
        let points: Vec<Mutex<f64>> = pairs.iter().map(|_| Mutex::new(0.0)).collect();
        let next = AtomicUsize::new(0);
        std::thread::scope(|scope| {
            for _ in 0..self.threads.max(1) {
                scope.spawn(|| loop {
                    let j = next.fetch_add(1, Ordering::SeqCst);
                    if j >= jobs.len() {
                        break;
                    }
                    let (i, k) = jobs[j];
                    let (w, bl) = pairs[i];
                    let rec = play_game(self.cat, w, bl, self.params, self.params, true, &self.play, seed + i as u64 * 1000 + k as u64);
                    *points[i].lock().unwrap() += rec.result as f64;
                });
            }
        });
        points.into_iter().map(|m| m.into_inner().unwrap()).collect()
    }

    fn key(&self, w: &Army, b: &Army) -> (String, String) {
        (w.to_text(self.cat, 8), b.to_text(self.cat, 8))
    }

    /// White's mean score when `w` plays `b` (None if they haven't played).
    fn white_score(&self, w: &Army, b: &Army) -> Option<f64> {
        self.table.get(&self.key(w, b)).filter(|e| e.1 > 0).map(|e| e.0 / e.1 as f64)
    }

    /// Plays whatever games are missing so every White army has `n` games
    /// against every Black army.
    fn fill(&mut self, whites: &[&Army], blacks: &[&Army], n: usize, seed: u64) {
        let mut todo: Vec<(&Army, &Army, usize)> = Vec::new();
        for w in whites {
            for b in blacks {
                let have = self.table.get(&self.key(w, b)).map(|e| e.1).unwrap_or(0);
                if have < n {
                    todo.push((*w, *b, n - have));
                }
            }
        }
        let mut counts: Vec<usize> = todo.iter().map(|t| t.2).collect();
        counts.sort();
        counts.dedup();
        for c in counts {
            let pairs: Vec<(&Army, &Army)> = todo.iter().filter(|t| t.2 == c).map(|t| (t.0, t.1)).collect();
            let pts = self.play(&pairs, c, seed);
            for (p, x) in pairs.iter().zip(pts) {
                let k = self.key(p.0, p.1);
                let e = self.table.entry(k).or_insert((0.0, 0));
                e.0 += x;
                e.1 += c;
            }
        }
    }

    /// `a`'s mean score playing `white` (or Black) against `opp` (pairs not
    /// played count as 0.5).
    fn mean(&self, a: &Army, white: bool, opp: &[&Army]) -> f64 {
        if opp.is_empty() {
            return 0.5;
        }
        opp.iter()
            .map(|o| if white { self.white_score(a, o) } else { self.white_score(o, a).map(|s| 1.0 - s) }.unwrap_or(0.5))
            .sum::<f64>()
            / opp.len() as f64
    }
}

/// Polishes `start` for one colour with games against `opp` (as game_climb).
fn game_climb_side(cat: &Arc<Catalog>, sc: &Scorer, book: &ColourBook, start: Army, white: bool, opp: &[Army], cfg: &WideCfg, rng: &mut Rng, seed: u64, log: &dyn Fn(String)) -> Army {
    let mut cur = start;
    let mut fails = 0;
    for step in 0..cfg.gc_steps {
        if fails >= cfg.gc_patience {
            break;
        }
        let mut tweaks: Vec<(Army, f64)> = (0..12)
            .filter_map(|_| mutate(cat, &cur, rng))
            .filter_map(|m| side_mean(sc, &m, white, opp, cfg.climb_nodes).map(|s| (m, s)))
            .collect();
        tweaks.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
        tweaks.dedup_by(|a, b| a.0.pieces == b.0.pieces);
        let mut armies = vec![cur.clone()];
        armies.extend(tweaks.into_iter().take(cfg.gc_mutants).map(|t| t.0));
        let n = cfg.gc_games * 2;
        let mut pts = vec![0.0; armies.len()];
        for (ai, a) in armies.iter().enumerate() {
            let pairs: Vec<(&Army, &Army)> = opp.iter().map(|o| if white { (a, o) } else { (o, a) }).collect();
            let v = book.play(&pairs, n, seed + step as u64 * 100_000);
            let white_pts: f64 = v.iter().sum();
            let total = (n * opp.len()) as f64;
            pts[ai] = if white { white_pts / total } else { 1.0 - white_pts / total };
        }
        let best = (1..armies.len()).max_by(|&a, &b| pts[a].partial_cmp(&pts[b]).unwrap());
        match best {
            Some(i) if pts[i] >= pts[0] + cfg.gc_margin => {
                log(format!("    game climb step {}: {:.1}% -> {:.1}% with {}", step + 1, 100.0 * pts[0], 100.0 * pts[i], armies[i].to_text(cat, 8)));
                cur = armies[i].clone();
                fails = 0;
            }
            _ => {
                log(format!("    game climb step {}: no tweak beat {:.1}% (best {:.1}%)", step + 1, 100.0 * pts[0], best.map(|i| 100.0 * pts[i]).unwrap_or(0.0)));
                fails += 1;
            }
        }
    }
    cur
}

fn side_name(white: bool) -> &'static str {
    if white { "White" } else { "Black" }
}

/// Each member's game score as its colour against the other pool.
fn split_standings(book: &ColourBook, own: &[Member], white: bool, opp: &[Member]) -> Vec<f64> {
    let refs: Vec<&Army> = opp.iter().map(|m| &m.army).collect();
    own.iter().map(|m| book.mean(&m.army, white, &refs)).collect()
}

fn write_split(cat: &Catalog, sc: &Scorer, book: &ColourBook, path: &str, own: &[Member], white: bool, opp: &[Member], round: usize, cfg: &WideCfg) -> String {
    let g = split_standings(book, own, white, opp);
    let own_armies: Vec<Army> = own.iter().map(|m| m.army.clone()).collect();
    let opp_armies: Vec<Army> = opp.iter().map(|m| m.army.clone()).collect();
    warm(sc, &side_pairs(&own_armies, white, &opp_armies), cfg.nodes, cfg.threads);
    let mut s = String::new();
    s += &format!("# Chess Plus {} armies grown by `plusfish meta --wide --split-colours` (judged only as {} against the {} pool).\n", side_name(white), side_name(white), side_name(!white));
    s += &format!("# After round {}. Games = mean score as {} against the {} pool ({} games per pair, {} nodes per move); eval = mean turn-0 advantage as {} at {} nodes (cp).\n", round, side_name(white), side_name(!white), cfg.games, cfg.play.nodes, side_name(white), cfg.nodes);
    s += "# army | name | cost | games (Elo) | eval | pieces\n";
    let mut order: Vec<usize> = (0..own.len()).collect();
    order.sort_by(|&a, &b| g[b].partial_cmp(&g[a]).unwrap());
    for i in order {
        let m = &own[i];
        let e = side_mean(sc, &m.army, white, &opp_armies, cfg.nodes).unwrap_or(f64::NAN);
        s += &format!("{} | {} | {} | {:.1}% ({:+.0}) | {:+.0} | {}\n", m.army.to_text(cat, 8), m.name, m.army.cost(cat), 100.0 * g[i], elo_of(g[i]), e, pieces_text(cat, &m.army));
    }
    std::fs::write(path, &s).unwrap_or_else(|e| panic!("{}: {}", path, e));
    own.iter().zip(&g).map(|(m, x)| format!("{} {:+.0}", m.name, elo_of(*x))).collect::<Vec<_>>().join(", ")
}

pub fn run_split(cat: &Arc<Catalog>, params: &Params, args: &Args) {
    let cfg = wide_cfg(args);
    let rounds: usize = args.num("rounds", 8);
    let stable: usize = args.num("stable", 3);
    let phase: usize = args.num("phase", 0);
    let exposed_wins = args.get("king-exposed").unwrap_or("win") != "reject";
    let out = args.get("out").unwrap_or("meta_pool.txt").to_string();
    let stem = out.trim_end_matches(".txt").to_string();
    let paths = [format!("{}_white.txt", stem), format!("{}_black.txt", stem)];
    let prefix = args.get("name").unwrap_or("Wide").to_string();
    let seed: u64 = args.num("seed", 1u64);
    let mut rng = Rng::new(seed);
    let logf = Mutex::new(std::fs::File::create(format!("{}.log", stem)).ok());
    let log = |s: String| {
        println!("{}", s);
        if let Some(f) = logf.lock().unwrap().as_mut() {
            writeln!(f, "{}", s).ok();
            f.flush().ok();
        }
    };
    let sc = Scorer { cat, params, cache: Mutex::new(HashMap::new()), exposed_wins };
    let mut book = ColourBook { cat, params, play: cfg.play.clone(), threads: cfg.threads, table: HashMap::new() };

    // Both pools start from the same armies: Standard plus --pool.
    let mut start: Vec<(Army, String)> = vec![(standard(cat), "Standard".into())];
    if let Some(p) = args.get("pool") {
        let mut l = |s: String| log(s);
        start.extend(read_pool(cat, p, &mut l));
    }
    if !exposed_wins {
        let mut i = 1;
        while i < start.len() {
            if (0..i).any(|j| start_is_broken(&army_game(cat, &start[i].0, &start[j].0, 8, 8)) || start_is_broken(&army_game(cat, &start[j].0, &start[i].0, 8, 8))) {
                log(format!("left out {}: a king is attacked at the start against another member", start[i].1));
                start.remove(i);
            } else {
                i += 1;
            }
        }
    }
    // pools[0] = White armies, pools[1] = Black armies.
    let mut pools: [Vec<Member>; 2] = [
        start.iter().map(|(a, n)| Member { army: a.clone(), name: n.clone(), born: 0 }).collect(),
        start.iter().map(|(a, n)| Member { army: a.clone(), name: n.clone(), born: 0 }).collect(),
    ];
    log(format!(
        "split-colours wide meta: {} climbers a colour a round ({} from members), {} tries a step at {} nodes; shortlist {}; games {} per pair at {} nodes, fixed colours; game climb {}; king exposed at the start = {}; {}",
        cfg.wide, cfg.refine, cfg.mutants, cfg.climb_nodes, cfg.shortlist, cfg.games, cfg.play.nodes, if cfg.game_climb { "on" } else { "off" }, if exposed_wins { "instant win" } else { "rejected" },
        if phase > 0 { format!("phases of {} rounds, one colour at a time against the other pool frozen", phase) } else { "both colours every round".to_string() }
    ));
    let t0 = std::time::Instant::now();
    {
        let w: Vec<&Army> = pools[0].iter().map(|m| &m.army).collect();
        let b: Vec<&Army> = pools[1].iter().map(|m| &m.army).collect();
        book.fill(&w, &b, cfg.games, seed * 7_919);
    }
    log(format!("starting pools played out ({:.0}s)", t0.elapsed().as_secs_f64()));
    for side in 0..2 {
        let line = write_split(cat, &sc, &book, &paths[side], &pools[side], side == 0, &pools[1 - side], 0, &cfg);
        log(format!("  {} pool (game Elo): {}", side_name(side == 0), line));
    }

    let mut quiet = 0;
    for round in 1..=rounds {
        let mut changed = false;
        // --phase: only one colour grows this round; the other pool stays as it is.
        let sides: Vec<usize> = if phase > 0 { vec![((round - 1) / phase) % 2] } else { vec![0, 1] };
        for side in sides {
            let white = side == 0;
            let t0 = std::time::Instant::now();
            let opp: Vec<Army> = pools[1 - side].iter().map(|m| m.army.clone()).collect();
            // 1. Climb wide, judged as this colour against the other pool.
            let mut starts: Vec<Army> = Vec::new();
            for _ in 0..cfg.refine.min(pools[side].len()) {
                starts.push(pools[side][rng.below(pools[side].len())].army.clone());
            }
            while starts.len() < cfg.wide {
                let a = random_army(cat, &mut rng);
                if a.cost(cat) >= 36.0 {
                    starts.push(a);
                }
            }
            let finished: Vec<Mutex<Option<(Army, f64)>>> = starts.iter().map(|_| Mutex::new(None)).collect();
            let next = AtomicUsize::new(0);
            let round_seed = rng.below(1 << 30) as u64;
            std::thread::scope(|scope| {
                for _ in 0..cfg.threads.max(1) {
                    scope.spawn(|| loop {
                        let i = next.fetch_add(1, Ordering::SeqCst);
                        if i >= starts.len() {
                            break;
                        }
                        let mut r = Rng::new(round_seed * 1_000 + i as u64 + 1);
                        let res = climb_side(cat, &sc, starts[i].clone(), white, &opp, cfg.climb_nodes, cfg.mutants, cfg.patience, &mut r);
                        *finished[i].lock().unwrap() = Some(res);
                    });
                }
            });
            let mut climbed: Vec<Army> = finished.into_iter().filter_map(|m| m.into_inner().unwrap()).map(|r| r.0).collect();
            climbed.sort_by_key(|a| a.to_text(cat, 8));
            climbed.dedup_by(|a, b| a.pieces == b.pieces);
            // 2. Shortlist at the eval bar's budget.
            warm(&sc, &side_pairs(&climbed, white, &opp), cfg.nodes, cfg.threads);
            let mut ranked: Vec<(usize, f64)> = (0..climbed.len()).filter_map(|i| side_mean(&sc, &climbed[i], white, &opp, cfg.nodes).map(|s| (i, s))).collect();
            ranked.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
            let mut shortlist: Vec<Army> = Vec::new();
            for &(i, _) in &ranked {
                if shortlist.len() >= cfg.shortlist {
                    break;
                }
                if shortlist.iter().all(|s| pieces_apart(s, &climbed[i]) > 0 || squares_apart(s, &climbed[i]) > 0) {
                    shortlist.push(climbed[i].clone());
                }
            }
            log(format!(
                "round {} {}: {} climbs ({:.0}s); best by eval: {}",
                round,
                side_name(white),
                climbed.len(),
                t0.elapsed().as_secs_f64(),
                ranked.iter().take(cfg.shortlist).map(|&(i, s)| format!("{:+.0} {}", s, climbed[i].to_text(cat, 8))).collect::<Vec<_>>().join(", ")
            ));
            // 3. Game climb on the best.
            if cfg.game_climb && !shortlist.is_empty() {
                let polished = game_climb_side(cat, &sc, &book, shortlist[0].clone(), white, &opp, &cfg, &mut rng, round_seed * 31 + 7, &log);
                if polished.pieces != shortlist[0].pieces {
                    shortlist.insert(0, polished);
                    shortlist.truncate(cfg.shortlist);
                }
            }
            // 4. Games decide, against the other pool with fixed colours.
            for (ci, cand) in shortlist.iter().enumerate() {
                {
                    let opp_refs: Vec<&Army> = pools[1 - side].iter().map(|m| &m.army).collect();
                    let me = [cand];
                    if white {
                        book.fill(&me, &opp_refs, cfg.games, round_seed * 7 + ci as u64 * 13 + 3);
                    } else {
                        book.fill(&opp_refs, &me, cfg.games, round_seed * 7 + ci as u64 * 13 + 3);
                    }
                }
                let (cand_score, near, apart, near_score) = {
                    let opp_refs: Vec<&Army> = pools[1 - side].iter().map(|m| &m.army).collect();
                    let cand_score = book.mean(cand, white, &opp_refs);
                    let (near, apart) = (0..pools[side].len()).map(|i| (i, pieces_apart(cand, &pools[side][i].army))).min_by_key(|&(i, d)| (d, squares_apart(cand, &pools[side][i].army))).unwrap();
                    (cand_score, near, apart, book.mean(&pools[side][near].army, white, &opp_refs))
                };
                let near_name = pools[side][near].name.clone();
                let name = format!("{} {}{}{}", prefix, if white { "W" } else { "B" }, round, ["a", "b", "c", "d", "e", "f"].get(ci).unwrap_or(&""));
                if apart >= cfg.min_diff {
                    log(format!("  {} {} scores {:.1}% ({:+.0} Elo) as {} against the {} pool, {} pieces from the nearest ({}): joins as {}", side_name(white), cand.to_text(cat, 8), 100.0 * cand_score, elo_of(cand_score), side_name(white), side_name(!white), apart, near_name, name));
                    pools[side].push(Member { army: cand.clone(), name: name.clone(), born: round });
                    let mut joined = true;
                    while pools[side].len() > cfg.max {
                        let g = split_standings(&book, &pools[side], white, &pools[1 - side]);
                        let worst = (0..pools[side].len()).min_by(|&a, &b| g[a].partial_cmp(&g[b]).unwrap()).unwrap();
                        log(format!("  {} pool over {}: drops {} ({:.1}%)", side_name(white), cfg.max, pools[side][worst].name, 100.0 * g[worst]));
                        if pools[side][worst].name == name {
                            joined = false;
                        }
                        pools[side].remove(worst);
                    }
                    changed |= joined;
                } else {
                    let m = near_score;
                    if cand_score > m + cfg.replace_margin {
                        log(format!("  {} {} is only {} pieces from {} and scores better against the {} pool ({:.1}% vs {:.1}%): replaces it as {}", side_name(white), cand.to_text(cat, 8), apart, near_name, side_name(!white), 100.0 * cand_score, 100.0 * m, name));
                        pools[side][near] = Member { army: cand.clone(), name, born: round };
                        changed = true;
                    } else {
                        log(format!("  {} {} is only {} pieces from {} and doesn't score better against the {} pool ({:.1}% vs {:.1}%): thrown away", side_name(white), cand.to_text(cat, 8), apart, near_name, side_name(!white), 100.0 * cand_score, 100.0 * m));
                    }
                }
            }
            log(format!("  round {} {} took {:.0}s", round, side_name(white), t0.elapsed().as_secs_f64()));
        }
        // Every White army has played every Black army before the pools are written.
        {
            let w: Vec<&Army> = pools[0].iter().map(|m| &m.army).collect();
            let b: Vec<&Army> = pools[1].iter().map(|m| &m.army).collect();
            book.fill(&w, &b, cfg.games, seed * 7_919 + round as u64);
        }
        for side in 0..2 {
            let line = write_split(cat, &sc, &book, &paths[side], &pools[side], side == 0, &pools[1 - side], round, &cfg);
            log(format!("  {} pool (game Elo): {}", side_name(side == 0), line));
        }
        quiet = if changed { 0 } else { quiet + 1 };
        if quiet >= stable {
            log(format!("stable: no change for {} rounds", quiet));
            break;
        }
    }
    log(format!("wrote {} and {}", paths[0], paths[1]));
}
