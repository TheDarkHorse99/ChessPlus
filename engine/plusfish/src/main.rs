
use plusfish_core::army::*;
use plusfish_core::defs::*;
use plusfish_core::eval::*;
use plusfish_core::game::*;
use plusfish_core::position::*;
use plusfish_core::search::*;
use plusfish_core::selfplay::*;
use plusfish_core::{api, html, report, tune, uci, verify};
use std::io::Write;
use std::sync::{Arc, Mutex};
use plusfish_core::util::{Args, Rng};

mod drift;
mod ematch;
mod meta;
mod spsa;
mod startcheck;

const HELP: &str = "\
Plusfish - an analysis and balancing engine for Chess Plus

Usage: plusfish <command> [options]

Analysis
  analyse   Search a position and show the best lines.
              --fen \"<fen>\"            or   --white <army> --black <army>
              --moves \"e2-e4 e7-e5\"    moves to play first (move text or SAN)
              --depth N | --time SEC | --nodes N   (default: 5 seconds)
              --multipv K              show the K best moves
              --threads N              search threads (default 1)  --hash MB (default 128)
  eval      Static evaluation with its biggest terms (same position options).
  uci       Run the UCI-style protocol on stdin/stdout (for GUIs and scripts).
  army      Check an army and show its cost and problems: plusfish army <army>

Balancing
  match     Play two armies against each other, both colours.
              --white <army> --black <army>   (the \"A\" and \"B\" armies)
              --games N (default 100)  --nodes N per move (default 20000)
              --params-b <file>        give side B a different evaluation
              --armies random          A/B test: random army pairs, played both ways
              --out games.jsonl        save the games
  enginematch Two engine programs play each other (to test engine changes);
              see plusfish enginematch --help
  spsa      Tune the search constants by SPSA self-play; see plusfish spsa --help
  start-check How well starting-position scores predict which army wins;
              see plusfish start-check --help
  drift     Play random army pairs with the top move every turn and log how
              far the score drifts from the start's; see plusfish drift --help
  meta      Grow a pool of armies that look strongest at turn 0 against each
              other (eval bar); see plusfish meta --help (--wide: search
              wide, games decide)
  climb-fixed Hill-climb one army with some squares pinned;
              see plusfish climb-fixed --help
  tournament  Round robin between armies, with Elo ratings.
              --armies \"<a>;<b>;<c>\"  or a folder of saved .tres armies
              --games N per pairing (default 20)  --nodes N
  selfplay  Random-army games for the balance report / tuning.
              --games N  --nodes N  --out games.jsonl
              --budget-spread P   each side's budget is 39 minus up to P points
                                  (default 6; needed to measure piece values)
  values    Balance report from saved games: plusfish values games.jsonl
              --html report.html       also write a web page
  tune      Fit the evaluation to saved games: plusfish tune games.jsonl --out params.txt
              --only mat,mob   tune just these features   --freeze open   all but these
              --skip N         ignore the first N plies (default 8)

Checking the rules against the game
  perft         --fen \"<fen>\" --depth N [--divide]
  perft-suite   standard-chess positions with known counts
  trace-games / trace-check   cross-check against the game's GDScript engine

Armies: \"standard\", \"random\", \"random:<seed>\", a saved .tres army file, or text
like \"RNBQKBNR/PPPPPPPP\" (back row / front row, files a-h, two-letter symbols
in brackets: \"R(CV)B(W)KB(CV)R/PPPPPPPP\").

Common options: --threads N (games at once; default: all cores)  --pieces <ChessPlus/data/pieces>
                --quiet-first-move=true (experiment: no captures or abilities on either side's first move)
                --white-quiet-first=true (experiment: no captures or abilities on White's first move unless in check)
                --params <file> (evaluation weights; \"none\" = from army costs)
";

fn die(msg: &str) -> ! {
    eprintln!("error: {}", msg);
    std::process::exit(1)
}

fn load_catalog(args: &Args) -> Arc<Catalog> {
    let dir = find_pieces_dir(args.get("pieces")).unwrap_or_else(|e| die(&e));
    Arc::new(Catalog::load_dir(&dir).unwrap_or_else(|e| die(&e)))
}


fn load_params(cat: &Catalog, spec: Option<&str>) -> Params {
    let mut p = Params::defaults(cat);
    match spec {
        Some("none") => {}
        Some(path) => p.load_over(cat, &std::fs::read_to_string(path).unwrap_or_else(|e| die(&format!("{}: {}", path, e)))),
        None => p.load_over(cat, BUILTIN_PARAMS),
    }
    p
}

fn threads(args: &Args) -> usize {
    args.num("threads", std::thread::available_parallelism().map(|n| n.get()).unwrap_or(4))
}

fn build_game(cat: &Arc<Catalog>, args: &Args) -> Game {
    let mut rng = Rng::from_time();
    let mut g = if let Some(f) = args.get("fen") {
        game_from_fen(cat, f, None).unwrap_or_else(|e| die(&e))
    } else {
        let w = parse_army(cat, args.get("white").unwrap_or("standard"), &mut rng).unwrap_or_else(|e| die(&e));
        let b = parse_army(cat, args.get("black").unwrap_or("standard"), &mut rng).unwrap_or_else(|e| die(&e));
        for (side, a) in [("White", &w), ("Black", &b)] {
            let probs = a.problems(cat, 8);
            if !probs.is_empty() {
                eprintln!("note: {}'s army breaks the army rules: {}", side, probs.join(" "));
            }
        }
        let g = army_game(cat, &w, &b, 8, 8);
        if start_is_broken(&g) {
            eprintln!("note: a king starts in check here. The game allows this, and White can even capture Black's king.");
        }
        g
    };
    if let Some(ms) = args.get("moves") {
        for m in ms.split_whitespace() {
            g.play_text(m).unwrap_or_else(|e| die(&e));
        }
    }
    g
}

/// A principal variation in SAN with move numbers.
fn pv_san(g: &Game, pv: &[Move]) -> String {
    let r = &g.rules;
    let mut p = g.pos.clone();
    let mut parts = Vec::new();
    for (i, &m) in pv.iter().enumerate() {
        if p.side == WHITE {
            parts.push(format!("{}.", p.fullmove));
        } else if i == 0 {
            parts.push(format!("{}...", p.fullmove));
        }
        parts.push(san(&p, r, m));
        p.make(r, m);
    }
    parts.join(" ")
}

fn main() {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    let args = Args::parse(&raw);
    if args.flag("quiet-first-move") {
        QUIET_FIRST_MOVE.store(true, std::sync::atomic::Ordering::Relaxed);
        eprintln!("note: quiet first move (experiment): no captures or abilities on either side's first move");
    }
    if args.flag("white-quiet-first") {
        WHITE_QUIET_FIRST.store(true, std::sync::atomic::Ordering::Relaxed);
        eprintln!("note: White-only quiet first move (experiment): no captures or abilities on White's first move unless in check");
    }
    let cmd = args.words.first().map(|s| s.as_str()).unwrap_or("help");
    if cmd == "enginematch" && args.flag("help") {
        print!("{}", ematch::HELP);
        return;
    }
    if cmd == "meta" && args.flag("help") {
        print!("{}
{}", meta::HELP, meta::WIDE_HELP);
        return;
    }
    if cmd == "climb-fixed" && args.flag("help") {
        print!("{}", meta::FIXED_HELP);
        return;
    }
    if cmd == "spsa" && args.flag("help") {
        print!("{}", spsa::HELP);
        return;
    }
    if cmd == "start-check" && args.flag("help") {
        print!("{}", startcheck::HELP);
        return;
    }
    if cmd == "help" || args.flag("help") {
        print!("{}", HELP);
        return;
    }
    if cmd == "evalgame" {
        run_evalgame();
        return;
    }
    let cat = load_catalog(&args);
    match cmd {
        "perft" => {
            let fen = args.get("fen").unwrap_or(STANDARD_FEN);
            let depth: u32 = args.num("depth", 4);
            let g = game_from_fen(&cat, fen, None).unwrap_or_else(|e| die(&e));
            let t = std::time::Instant::now();
            if args.flag("divide") {
                let mut total = 0;
                for m in g.pos.legal_moves(&g.rules) {
                    let mut c = g.pos.clone();
                    c.make(&g.rules, m);
                    let n = if depth > 1 { perft(&c, &g.rules, depth - 1) } else { 1 };
                    println!("{}: {}", move_text(&g.rules, m), n);
                    total += n;
                }
                println!("total {}", total);
            } else {
                let n = perft(&g.pos, &g.rules, depth);
                let s = t.elapsed().as_secs_f64();
                println!("perft {} = {}  ({:.2}s, {:.1}M nodes/s)", depth, n, s, n as f64 / s / 1e6);
            }
        }
        "enginematch" => {
            let dir = find_pieces_dir(args.get("pieces")).unwrap_or_else(|e| die(&e));
            ematch::run(&cat, &args, &dir.to_string_lossy());
        }
        "spsa" => {
            spsa::run(&cat, &args, &load_params(&cat, args.get("params")));
        }
        "meta" => {
            meta::run(&cat, &load_params(&cat, args.get("params")), &args);
        }
        "climb-fixed" => {
            meta::run_fixed(&cat, &load_params(&cat, args.get("params")), &args);
        }
        "drift" => {
            if args.flag("help") {
                print!("{}", drift::HELP);
                return;
            }
            drift::run(&cat, &load_params(&cat, args.get("params")), &args);
        }
        "start-check" => {
            let dir = find_pieces_dir(args.get("pieces")).unwrap_or_else(|e| die(&e));
            startcheck::run(&cat, &args, &dir.to_string_lossy());
        }
        "bench" => {
            // Fixed positions (random armies, some moves in) searched to a fixed
            // depth: the node total is a fingerprint of the search, nps its speed.
            let depth: i32 = args.num("depth", 9);
            let count: usize = args.num("count", 24);
            let params = load_params(&cat, args.get("params"));
            let mut total_nodes = 0u64;
            let mut total_ms = 0u64;
            for i in 0..count {
                let mut rng = Rng::new(9000 + i as u64);
                let (w, b) = random_pair(&cat, &mut rng, (BUDGET, BUDGET));
                let mut g = army_game(&cat, &w, &b, 8, 8);
                let r = g.rules.clone();
                let et = EvalTables::new(&r);
                {
                    let mut s = Searcher::new(&r, &et, &params, 4);
                    for _ in 0..(i * 3) % 40 {
                        if g.outcome() != Outcome::None {
                            break;
                        }
                        let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], Limits { depth: None, nodes: Some(1500), movetime_ms: None, soft_ms: None }, 1, |_| {});
                        g.play(rep.lines[0].pv.first().copied().unwrap_or_else(|| g.pos.legal_moves(&r)[0]));
                    }
                }
                if g.outcome() != Outcome::None {
                    continue;
                }
                let mut s = Searcher::new(&r, &et, &params, 16);
                let t = std::time::Instant::now();
                let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], Limits { depth: Some(depth), nodes: None, movetime_ms: None, soft_ms: None }, 1, |_| {});
                let ms = t.elapsed().as_millis() as u64;
                total_nodes += rep.nodes;
                total_ms += ms;
                if args.flag("verbose") {
                    println!("{:>2} {:>9} nodes {:>6} ms  {}  {}", i, rep.nodes, ms, score_text(rep.lines[0].score), fen(&g.pos, &r, true));
                }
            }
            println!("bench: {} nodes  {} ms  {} nps", total_nodes, total_ms, total_nodes * 1000 / total_ms.max(1));
        }
        "speed" => {
            // Times the basic operations on positions from the bench games.
            let params = load_params(&cat, args.get("params"));
            let mut sets: Vec<(Arc<Rules>, Vec<Position>)> = Vec::new();
            for i in 0..24usize {
                let mut rng = Rng::new(9000 + i as u64);
                let (w, b) = random_pair(&cat, &mut rng, (BUDGET, BUDGET));
                let mut g = army_game(&cat, &w, &b, 8, 8);
                let r = g.rules.clone();
                let et = EvalTables::new(&r);
                let mut s = Searcher::new(&r, &et, &params, 4);
                let mut list = Vec::new();
                for _ in 0..40 {
                    if g.outcome() != Outcome::None {
                        break;
                    }
                    for m in g.pos.legal_moves(&r) {
                        let mut c = g.pos.clone();
                        c.make(&r, m);
                        list.push(c);
                    }
                    let rep = s.search(&g.pos, &g.keys[..g.keys.len() - 1], Limits { depth: None, nodes: Some(1500), movetime_ms: None, soft_ms: None }, 1, |_| {});
                    g.play(rep.lines[0].pv.first().copied().unwrap_or_else(|| g.pos.legal_moves(&r)[0]));
                }
                sets.push((r.clone(), list));
            }
            let n: usize = sets.iter().map(|s| s.1.len()).sum();
            let time = |name: &str, f: &mut dyn FnMut(&Rules, &EvalTables, &Position) -> u64| {
                let mut sink = 0u64;
                let t = std::time::Instant::now();
                for (r, list) in &sets {
                    let et = EvalTables::new(r);
                    for p in list {
                        sink = sink.wrapping_add(f(r, &et, p));
                    }
                }
                let ns = t.elapsed().as_nanos() as f64 / n as f64;
                println!("{:<28} {:>8.0} ns  ({})", name, ns, sink % 7);
            };
            println!("{} positions", n);
            time("evaluate", &mut |r, et, p| evaluate(p, r, et, &params) as u64);
            time("gen_pseudo (all)", &mut |r, _, p| {
                let mut v = Vec::with_capacity(128);
                p.gen_pseudo(r, &mut v, GEN_ALL);
                v.len() as u64
            });
            time("gen_pseudo (tactical)", &mut |r, _, p| {
                let mut v = Vec::with_capacity(128);
                p.gen_pseudo(r, &mut v, GEN_TACTICAL);
                v.len() as u64
            });
            time("in_check", &mut |r, _, p| p.in_check(r, p.side) as u64);
            time("all moves: clone+make", &mut |r, _, p| {
                let mut v = Vec::with_capacity(128);
                p.gen_pseudo(r, &mut v, GEN_ALL);
                let mut k = 0;
                for &m in &v {
                    let mut c = p.clone();
                    c.make(r, m);
                    k ^= c.key;
                }
                k
            });
            time("all moves: +legality", &mut |r, _, p| {
                let mut v = Vec::with_capacity(128);
                p.gen_pseudo(r, &mut v, GEN_ALL);
                let mut k = 0;
                for &m in &v {
                    let mut c = p.clone();
                    c.make(r, m);
                    k += c.leaves_king_attacked(p, r, m) as u64;
                }
                k
            });
            time("all moves: +gives check", &mut |r, _, p| {
                let mut v = Vec::with_capacity(128);
                p.gen_pseudo(r, &mut v, GEN_ALL);
                let mut k = 0;
                for &m in &v {
                    let mut c = p.clone();
                    c.make(r, m);
                    k += c.leaves_king_attacked(p, r, m) as u64 + c.in_check(r, c.side) as u64;
                }
                k
            });
        }
        "see-check" => {
            // Compares the static exchange evaluation with a brute-force
            // search of the legal captures on the same square.
            fn exch(p: &Position, r: &Rules, s: usize, val: &[i32]) -> i32 {
                let mut best = 0;
                for m in p.legal_moves(r) {
                    if m.to as usize != s || m.flags & F_CAPTURE == 0 || m.flags & (F_CRACK | F_EP) != 0 {
                        continue;
                    }
                    let k = kind_of(p.sq[m.from as usize]);
                    let mut gain = val[kind_of(p.sq[s])];
                    if m.promo != 0 {
                        gain += val[m.promo as usize - 1] - val[k];
                    }
                    let mut c = p.clone();
                    c.make(r, m);
                    let sub = if r.info[k].dies { gain -= val[k]; 0 } else { exch(&c, r, s, val) };
                    best = best.max(gain - sub);
                }
                best
            }
            let params = load_params(&cat, args.get("params"));
            let (mut n, mut same, mut sign_same) = (0, 0, 0);
            let mut shown = 0;
            for i in 0..args.num("count", 200usize) {
                let mut rng = Rng::new(5000 + i as u64);
                let (w, b) = random_pair(&cat, &mut rng, (BUDGET, BUDGET));
                let mut g = army_game(&cat, &w, &b, 8, 8);
                let r = g.rules.clone();
                let val: Vec<i32> = (0..r.info.len()).map(|k| piece_value(&params, k)).collect();
                for _ in 0..80 {
                    if g.outcome() != Outcome::None {
                        break;
                    }
                    let legal = g.pos.legal_moves(&r);
                    for &m in &legal {
                        if m.flags & F_CAPTURE == 0 || m.flags & (F_CRACK | F_EP) != 0 {
                            continue;
                        }
                        let k = kind_of(g.pos.sq[m.from as usize]);
                        let mut gain = val[kind_of(g.pos.sq[m.to as usize])];
                        if m.promo != 0 {
                            gain += val[m.promo as usize - 1] - val[k];
                        }
                        let mut c = g.pos.clone();
                        c.make(&r, m);
                        let brute = if r.info[k].dies { gain - val[k] } else { gain - exch(&c, &r, m.to as usize, &val) };
                        let see = g.pos.see(&r, m, &val);
                        n += 1;
                        if see == brute {
                            same += 1;
                        }
                        if (see >= 0) == (brute >= 0) {
                            sign_same += 1;
                        } else if shown < args.num("show", 5) {
                            shown += 1;
                            println!("{}  {}  see {} brute {}", fen(&g.pos, &r, true), move_text(&r, m), see, brute);
                        }
                    }
                    g.play(legal[rng.below(legal.len())]);
                }
            }
            println!("{} captures: same value {:.1}%, same sign {:.1}%", n, same as f64 * 100.0 / n as f64, sign_same as f64 * 100.0 / n as f64);
        }
        "perft-suite" => {
            if !verify::run_perft_suite(&cat) {
                std::process::exit(1);
            }
        }
        "trace-games" => {
            let favor: Vec<usize> = args
                .get("favor")
                .map(|list| list.split(',').map(|id| cat.kind_by_id(id.trim()).unwrap_or_else(|| die(&format!("unknown piece {}", id)))).collect())
                .unwrap_or_default();
            let text = verify::write_trace_games(&cat, args.num("count", 50), args.num("seed", 1), args.num("plies", 300), &favor);
            print!("{}", text);
        }
        "trace-check" => {
            let games = std::fs::read_to_string(&args.words[1]).unwrap_or_else(|e| die(&e.to_string()));
            let trace = std::fs::read_to_string(&args.words[2]).unwrap_or_else(|e| die(&e.to_string()));
            let (n, bad) = verify::check_trace(&cat, &games, &trace, args.num("report", 10));
            println!("{} positions checked, {} mismatches", n, bad);
            if bad > 0 {
                std::process::exit(1);
            }
        }
        "army" => {
            let spec = args.words.get(1).map(|s| s.as_str()).unwrap_or("standard");
            let mut rng = Rng::from_time();
            let a = parse_army(&cat, spec, &mut rng).unwrap_or_else(|e| die(&e));
            println!("{}  ({} points)", a.to_text(&cat, 8), a.cost(&cat));
            let mut list: Vec<String> = Vec::new();
            for k in 0..cat.len() {
                let n = a.count(k);
                if n > 0 {
                    list.push(format!("{} x{} ({})", cat.defs[k].name, n, cat.defs[k].value * n as f64));
                }
            }
            println!("{}", list.join(", "));
            let probs = a.problems(&cat, 8);
            if probs.is_empty() {
                println!("legal army");
            } else {
                for p in probs {
                    println!("problem: {}", p);
                }
            }
        }
        "pairing-check" => {
            // How often two random legal armies start with a king attacked.
            let n: usize = args.num("count", 10000);
            let mut rng = Rng::new(args.num("seed", 3));
            let (mut white_checked, mut black_capturable) = (0, 0);
            for _ in 0..n {
                let w = random_army(&cat, &mut rng);
                let b = random_army(&cat, &mut rng);
                let g = army_game(&cat, &w, &b, 8, 8);
                if g.pos.in_check(&g.rules, BLACK) {
                    black_capturable += 1;
                }
                if g.pos.in_check(&g.rules, WHITE) {
                    white_checked += 1;
                }
            }
            println!("{} random pairings: Black's king capturable on move 1 in {} ({:.1}%), White starts in check in {} ({:.1}%)",
                n, black_capturable, 100.0 * black_capturable as f64 / n as f64, white_checked, 100.0 * white_checked as f64 / n as f64);
        }
        "analyse" | "analyze" => {
            let g = build_game(&cat, &args);
            let params = load_params(&cat, args.get("params"));
            let r = &*g.rules;
            let et = EvalTables::new(r);
            println!("{}\n", board_text(&g.pos, r));
            println!("FEN {}", fen(&g.pos, r, true));
            println!("{} to move. Static eval {} (side to move)", if g.pos.side == WHITE { "White" } else { "Black" }, score_text(evaluate(&g.pos, r, &et, &params)));
            let out = g.outcome();
            if out != Outcome::None {
                println!("Game over: {} ({})", outcome_name(out), g.result_text());
                return;
            }
            let limits = Limits {
                depth: args.get("depth").and_then(|v| v.parse().ok()),
                nodes: args.get("nodes").and_then(|v| v.parse().ok()),
                movetime_ms: args.get("time").and_then(|v| v.parse::<f64>().ok()).map(|s| (s * 1000.0) as u64).or(
                    if args.get("depth").is_none() && args.get("nodes").is_none() { Some(5000) } else { None },
                ),
                soft_ms: None,
            };
            let multipv: usize = args.num("multipv", 1);
            let mut s = Searcher::new(r, &et, &params, args.num("hash", 128));
            let white_pov = g.pos.side == WHITE;
            println!("\nScores are from White's point of view, in pawns (+ = White better).");
            println!("{:>5} {:>8} {:>10} {:>7}  line", "depth", "score", "nodes", "time");
            let search_threads: usize = args.num("threads", 1);
            let rep = s.search_threads(&g.pos, &g.keys[..g.keys.len() - 1], limits, multipv, search_threads, |rep| {
                for (i, l) in rep.lines.iter().enumerate() {
                    let sc = if white_pov { l.score } else { -l.score };
                    println!(
                        "{:>5} {:>8} {:>10} {:>6.1}s  {}{}",
                        if i == 0 { rep.depth.to_string() } else { String::new() },
                        score_text(sc),
                        if i == 0 { rep.nodes.to_string() } else { String::new() },
                        rep.ms as f64 / 1000.0,
                        if multipv > 1 { format!("[{}] ", i + 1) } else { String::new() },
                        pv_san(&g, &l.pv)
                    );
                }
                std::io::stdout().flush().ok();
            });
            if let Some(l) = rep.lines.first() {
                if let Some(&m) = l.pv.first() {
                    let sc = if white_pov { l.score } else { -l.score };
                    println!(
                        "\nBest move: {} ({})  eval {}  [{} nodes, {:.0}k nodes/s]",
                        san(&g.pos, r, m),
                        move_text(r, m),
                        score_text(sc),
                        rep.nodes,
                        rep.nodes as f64 / (rep.ms.max(1) as f64)
                    );
                }
            }
        }
        "eval" => {
            let g = build_game(&cat, &args);
            let params = load_params(&cat, args.get("params"));
            let et = EvalTables::new(&g.rules);
            println!("{}\n", board_text(&g.pos, &g.rules));
            println!("{}", uci::eval_breakdown(&g, &et, &params));
            let e = evaluate(&g.pos, &g.rules, &et, &params);
            let white = if g.pos.side == WHITE { e } else { -e };
            println!("total {} (White's view)", score_text(white));
        }
        "uci" => {
            let params = Arc::new(load_params(&cat, args.get("params")));
            uci::run(cat.clone(), params);
        }
        "match" => {
            let mut rng = Rng::from_time();
            let a = parse_army(&cat, args.get("white").unwrap_or("standard"), &mut rng).unwrap_or_else(|e| die(&e));
            let b = parse_army(&cat, args.get("black").unwrap_or("standard"), &mut rng).unwrap_or_else(|e| die(&e));
            let pa = load_params(&cat, args.get("params"));
            let pb = match args.get("params-b") {
                Some(f) => load_params(&cat, Some(f)),
                None => pa.clone(),
            };
            let games: usize = args.num("games", 100);
            let cfg = PlayConfig { nodes: args.num("nodes", 20_000), random_plies: args.num("random-plies", 6), ..Default::default() };
            let g0 = army_game(&cat, &a, &b, 8, 8);
            if start_is_broken(&g0) {
                eprintln!("warning: a king starts in check in this pairing (White could capture Black's king).");
            }
            println!("A: {}  ({} points)\nB: {}  ({} points)", a.to_text(&cat, 8), a.cost(&cat), b.to_text(&cat, 8), b.cost(&cat));
            println!("{} games, {} nodes per move, {} threads, A and B swap colours each game", games, cfg.nodes, threads(&args));
            let tally = Mutex::new([0f64; 3]);
            let progress = |rec: &GameRecord, n: usize| {
                let a_score = if rec.a_is_white { rec.result } else { 1.0 - rec.result };
                let mut t = tally.lock().unwrap();
                t[if a_score == 1.0 { 0 } else if a_score == 0.5 { 1 } else { 2 }] += 1.0;
                if n % 10 == 0 || n == games {
                    let (s, elo, m) = elo_summary(t[0], t[1], t[2]);
                    eprintln!("  {}/{}: A +{} ={} -{}  score {:.1}%  Elo {:+.0} ±{:.0}", n, games, t[0], t[1], t[2], s * 100.0, elo, m);
                }
            };
            let random_armies = args.get("armies") == Some("random");
            let seed: u64 = args.num("seed", 1);
            let pair = |i: usize, _rng: &mut Rng| -> (Army, Army, bool) {
                let (w, bl) = if random_armies {
                    // A/B test of evaluations: the same random armies twice, colours swapped.
                    let mut prng = Rng::new(seed * 104729 + (i / 2) as u64);
                    random_pair(&cat, &mut prng, (BUDGET, BUDGET))
                } else {
                    (a.clone(), b.clone())
                };
                if i % 2 == 0 {
                    (w, bl, true)
                } else if random_armies {
                    (w, bl, false)
                } else {
                    (bl, w, false)
                }
            };
            let recs = run_games(&cat, games, threads(&args), &pa, &pb, &cfg, args.num("seed", 1), &pair, &progress);
            let t = tally.into_inner().unwrap();
            let (s, elo, m) = elo_summary(t[0], t[1], t[2]);
            let white_score = recs.iter().map(|r| r.result as f64).sum::<f64>() / recs.len().max(1) as f64;
            let mut reasons: std::collections::BTreeMap<&str, usize> = Default::default();
            for rc in &recs {
                *reasons.entry(rc.reason.as_str()).or_insert(0) += 1;
            }
            println!("\nResult for A: +{} ={} -{}  score {:.1}%  => A is {:+.0} ±{:.0} Elo vs B (95%)", t[0], t[1], t[2], s * 100.0, elo, m);
            println!("White scored {:.1}% across all games", white_score * 100.0);
            println!("Endings: {:?}", reasons);
            println!("Average length: {:.0} plies", recs.iter().map(|r| r.plies).sum::<usize>() as f64 / recs.len().max(1) as f64);
            if let Some(path) = args.get("out") {
                save_games(&cat, &recs, path);
            }
        }
        "tournament" => {
            // Round robin between armies: every pair plays both colours.
            let spec = args.get("armies").unwrap_or_else(|| die("--armies \"a;b;c\" or a folder of saved armies"));
            let mut rng = Rng::new(args.num("seed", 5));
            let mut armies: Vec<Army> = Vec::new();
            let path = std::path::Path::new(spec);
            if path.is_dir() {
                let mut files: Vec<_> = std::fs::read_dir(path).unwrap().filter_map(|e| e.ok().map(|e| e.path())).filter(|p| p.extension().map(|x| x == "tres").unwrap_or(false)).collect();
                files.sort();
                for f in files {
                    armies.push(parse_army(&cat, &f.to_string_lossy(), &mut rng).unwrap_or_else(|e| die(&e)));
                }
            } else {
                for part in spec.split(';').filter(|p| !p.trim().is_empty()) {
                    let mut a = parse_army(&cat, part, &mut rng).unwrap_or_else(|e| die(&e));
                    if a.name.starts_with("random") || a.name.is_empty() || a.name == part.trim() {
                        a.name = a.to_text(&cat, 8);
                    }
                    armies.push(a);
                }
            }
            if armies.len() < 2 {
                die("need at least two armies");
            }
            for a in &armies {
                let p = a.problems(&cat, 8);
                println!("{:<40} {:>5} pts  {}", a.name, a.cost(&cat), if p.is_empty() { "legal".into() } else { p.join(" ") });
            }
            let per_pair: usize = args.num("games", 20);
            let mut pairs: Vec<(usize, usize)> = Vec::new();
            for i in 0..armies.len() {
                for j in 0..armies.len() {
                    if i != j {
                        for _ in 0..(per_pair / 2).max(1) {
                            pairs.push((i, j));
                        }
                    }
                }
            }
            let params = load_params(&cat, args.get("params"));
            let cfg = PlayConfig { nodes: args.num("nodes", 20_000), random_plies: args.num("random-plies", 6), ..Default::default() };
            let total = pairs.len();
            eprintln!("{} armies, {} games ({} per pairing), {} nodes per move", armies.len(), total, (per_pair / 2).max(1) * 2, cfg.nodes);
            let pair_fn = |i: usize, _rng: &mut Rng| -> (Army, Army, bool) {
                let (w, b) = pairs[i];
                (armies[w].clone(), armies[b].clone(), true)
            };
            let progress = |_rec: &GameRecord, n: usize| {
                if n % 20 == 0 || n == total {
                    eprintln!("  {}/{}", n, total);
                }
            };
            let recs = run_games(&cat, total, threads(&args), &params, &params, &cfg, args.num("seed", 5), &pair_fn, &progress);
            // Ratings: result ~ rating(white army) - rating(black army) + white edge.
            let na = armies.len();
            let mut x = Vec::new();
            let mut y = Vec::new();
            let mut score = vec![(0.0f64, 0usize); na];
            for (g, rec) in recs.iter().enumerate() {
                let (w, b) = pairs[g];
                let mut row = vec![0.0; na];
                row[w] += 1.0;
                row[b] -= 1.0;
                row.push(1.0);
                x.push(row);
                y.push(rec.result as f64);
                score[w].0 += rec.result as f64;
                score[w].1 += 1;
                score[b].0 += 1.0 - rec.result as f64;
                score[b].1 += 1;
            }
            let (beta, _, cov) = tune::logistic_cov(&x, &y, 0.05);
            // Uncertainty of each rating relative to the field average.
            let se: Vec<f64> = (0..na)
                .map(|i| {
                    let c: Vec<f64> = (0..na).map(|j| if i == j { 1.0 } else { 0.0 } - 1.0 / na as f64).collect();
                    let mut v = 0.0;
                    for a in 0..na {
                        for b in 0..na {
                            v += c[a] * cov[a][b] * c[b];
                        }
                    }
                    v.max(0.0).sqrt()
                })
                .collect();
            let mean = beta[..na].iter().sum::<f64>() / na as f64;
            let elo = 400.0 / std::f64::consts::LN_10;
            let mut order: Vec<usize> = (0..na).collect();
            order.sort_by(|&a, &b| beta[b].partial_cmp(&beta[a]).unwrap());
            println!("\n{:<4} {:<40} {:>6} {:>8} {:>7}", "rank", "army", "Elo", "+-95%", "score");
            for (rank, &i) in order.iter().enumerate() {
                println!(
                    "{:<4} {:<40} {:>+6.0} {:>8.0} {:>6.1}%",
                    rank + 1,
                    armies[i].name,
                    (beta[i] - mean) * elo,
                    1.96 * se[i] * elo,
                    100.0 * score[i].0 / score[i].1.max(1) as f64
                );
            }
            println!("White's first-move edge: {:+.0} Elo", beta[na] * elo);
        }
        "selfplay" => {
            let games: usize = args.num("games", 1000);
            let params = load_params(&cat, args.get("params"));
            let cfg = PlayConfig { nodes: args.num("nodes", 8_000), random_plies: args.num("random-plies", 4), tt_mb: 4, ..Default::default() };
            let spread: f64 = args.num("budget-spread", 6.0);
            let out = args.get("out").unwrap_or("games.jsonl").to_string();
            let file = Mutex::new(std::fs::File::create(&out).unwrap_or_else(|e| die(&e.to_string())));
            let start = std::time::Instant::now();
            eprintln!("{} games, {} nodes per move, {} threads -> {}", games, cfg.nodes, threads(&args), out);
            let pair = |i: usize, rng: &mut Rng| -> (Army, Army, bool) {
                // Pairs of games: the same two armies, colours swapped.
                let mut prng = Rng::new(args.num("seed", 7u64) * 7919 + (i / 2) as u64);
                let budgets = (BUDGET - prng.float() * spread, BUDGET - prng.float() * spread);
                let (w, b) = random_pair(&cat, &mut prng, budgets);
                let _ = rng;
                if i % 2 == 0 {
                    (w, b, true)
                } else {
                    (b, w, true)
                }
            };
            let progress = |rec: &GameRecord, n: usize| {
                let mut moves = Vec::new();
                let g = army_game(&cat, &rec.white, &rec.black, 8, 8);
                for &m in &rec.moves {
                    moves.push(move_text(&g.rules, m));
                }
                let line = report::game_line(&cat, rec, &moves);
                let mut f = file.lock().unwrap();
                writeln!(f, "{}", line).ok();
                if n % 50 == 0 || n == games {
                    let el = start.elapsed().as_secs_f64();
                    eprintln!("  {}/{} games  ({:.1} games/s, ~{:.0}s left)", n, games, n as f64 / el, (games - n) as f64 / (n as f64 / el));
                }
            };
            let empty = Params::defaults(&cat);
            let _ = empty;
            run_games(&cat, games, threads(&args), &params, &params, &cfg, args.num("seed", 7), &pair, &progress);
        }
        "values" => {
            let path = args.words.get(1).unwrap_or_else(|| die("usage: plusfish values games.jsonl"));
            let text = std::fs::read_to_string(path).unwrap_or_else(|e| die(&e.to_string()));
            let games = report::read_games(&cat, &text);
            eprintln!("{} games read; extracting positions...", games.len());
            let samples = report::samples_from_games(&cat, &games, 8, 2, threads(&args));
            eprintln!("{} quiet positions; fitting...", samples.len());
            let rep = report::value_report(&cat, &games, &samples);
            print!("{}", report::print_report(&cat, &rep));
            if let Some(h) = args.get("html") {
                std::fs::write(h, html::html_report(&cat, &rep)).unwrap_or_else(|e| die(&e.to_string()));
                eprintln!("wrote {}", h);
            }
        }
        "tune" => {
            let path = args.words.get(1).unwrap_or_else(|| die("usage: plusfish tune games.jsonl --out params.txt"));
            let text = std::fs::read_to_string(path).unwrap_or_else(|e| die(&e.to_string()));
            let samples = if args.flag("drift") {
                // Positions from drift games, labelled by the later scores.
                drift::samples(&cat, &args, path)
            } else {
                let games = report::read_games(&cat, &text);
                report::samples_from_games(&cat, &games, args.num("skip", 8), 1, threads(&args))
            };
            eprintln!("{} quiet positions", samples.len());
            let start = load_params(&cat, args.get("params"));
            let mut frozen = vec![false; NFEAT];
            let mut seen = vec![false; NFEAT];
            for s in &samples {
                for &(f, _) in &s.feats {
                    seen[f as usize] = true;
                }
            }
            for k in 0..cat.len() {
                if cat.defs[k].is_king() {
                    frozen[k * PER_KIND + FE_MAT] = true;
                }
            }
            for i in 0..NFEAT {
                if !seen[i] {
                    frozen[i] = true;
                }
            }
            // --only mat,shield: tune just the features whose names start so.
            if let Some(only) = args.get("only") {
                let prefixes: Vec<&str> = only.split(',').collect();
                for i in 0..NFEAT {
                    let name = feature_name(&cat, i);
                    if !prefixes.iter().any(|p| name.starts_with(p)) {
                        frozen[i] = true;
                    }
                }
            }
            // --freeze open: keep the features whose names start so as they are.
            if let Some(fz) = args.get("freeze") {
                let prefixes: Vec<&str> = fz.split(',').collect();
                for i in 0..NFEAT {
                    if prefixes.iter().any(|p| feature_name(&cat, i).starts_with(p)) {
                        frozen[i] = true;
                    }
                }
            }
            let cost_cp: Vec<(usize, f64)> = (0..cat.len())
                .filter(|&k| !cat.defs[k].is_king() && seen[k * PER_KIND + FE_MAT])
                .map(|k| (k * PER_KIND + FE_MAT, cat.defs[k].value * 100.0))
                .collect();
            // Drift labels are win chances worked out from scores on a
            // logistic scale of --k cp: fit on that scale, so the weights
            // come out in the same centipawns as the rest of the evaluation.
            let texel_k = if args.flag("drift") { Some(400.0 / args.num("k", 720.0)) } else { None };
            let tuned = tune::texel_newton(&samples, &start, &frozen, &cost_cp, args.num("ridge", 2e-4), args.num("iters", 12), threads(&args), texel_k, &mut |i, loss| {
                eprintln!("  iteration {:>2}: log loss {:.5}", i + 1, loss)
            });
            let k = tune::best_k(&samples, &tuned.w);
            let k_start = tune::best_k(&samples, &start.w);
            eprintln!("squared error before {:.5}, after {:.5}", tune::mse(&samples, &start.w, k_start), tune::mse(&samples, &tuned.w, k));
            let out = args.get("out").unwrap_or("params.txt");
            // Weights the games never touched keep their values from --params
            // (left out, they'd fall back to the defaults when loaded).
            let keep: Vec<bool> = (0..NFEAT).map(|i| seen[i] || start.tuned[i]).collect();
            std::fs::write(out, tuned.save(&cat, &keep)).unwrap_or_else(|e| die(&e.to_string()));
            eprintln!("K = {:.3}; wrote {}", k, out);
        }
        _ => {
            print!("{}", HELP);
            std::process::exit(1);
        }
    }
}

fn save_games(cat: &Arc<Catalog>, recs: &[GameRecord], path: &str) {
    let mut f = std::fs::File::create(path).unwrap_or_else(|e| die(&e.to_string()));
    for rec in recs {
        let g = army_game(cat, &rec.white, &rec.black, 8, 8);
        let moves: Vec<String> = rec.moves.iter().map(|&m| move_text(&g.rules, m)).collect();
        writeln!(f, "{}", report::game_line(cat, rec, &moves)).ok();
    }
}

/// The game's interface (desktop): one JSON request per line on stdin, reply
/// lines on stdout as each position is done (see api.rs).
fn run_evalgame() {
    use std::io::BufRead;
    let stdin = std::io::stdin();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        if line.trim().is_empty() {
            continue;
        }
        let mut out = std::io::stdout();
        let res = api::eval_request(&line, &mut |reply| {
            writeln!(out, "{}", reply).ok();
            out.flush().ok();
        });
        if let Err(e) = res {
            writeln!(out, "{{\"error\":{}}}", plusfish_core::json::quote(&e)).ok();
        }
        writeln!(out, "{{\"done\":true}}").ok();
        out.flush().ok();
    }
}
