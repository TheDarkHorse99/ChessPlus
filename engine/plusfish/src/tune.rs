//! Fitting things to game results:
//!   - Texel tuning: the evaluation weights that best predict how self-play
//!     games ended from the positions in them.
//!   - Piece-value regressions for the balance report: how much each extra
//!     piece of a type (at the start, or on the board mid-game) shifts the
//!     odds of winning, with standard errors.

use crate::eval::*;
use crate::selfplay::Sample;

fn sigmoid(x: f64) -> f64 {
    1.0 / (1.0 + (-x).exp())
}

/// Win probability from a centipawn score (White's view), Texel-style.
fn win_prob(cp: f64, k: f64) -> f64 {
    1.0 / (1.0 + 10f64.powf(-k * cp / 400.0))
}

fn predict(s: &Sample, w: &[[f32; 2]]) -> f64 {
    let mut mg = 0.0f64;
    let mut eg = 0.0f64;
    for &(f, v) in &s.feats {
        let ww = w[f as usize];
        mg += ww[0] as f64 * v as f64;
        eg += ww[1] as f64 * v as f64;
    }
    mg * s.phase as f64 + eg * (1.0 - s.phase as f64)
}

pub fn mse(samples: &[Sample], w: &[[f32; 2]], k: f64) -> f64 {
    samples.iter().map(|s| (s.result as f64 - win_prob(predict(s, w), k)).powi(2)).sum::<f64>() / samples.len().max(1) as f64
}

pub fn best_k(samples: &[Sample], w: &[[f32; 2]]) -> f64 {
    let (mut lo, mut hi) = (0.05f64, 3.0f64);
    for _ in 0..40 {
        let a = lo + (hi - lo) / 3.0;
        let b = hi - (hi - lo) / 3.0;
        if mse(samples, w, a) < mse(samples, w, b) {
            hi = b;
        } else {
            lo = a;
        }
    }
    (lo + hi) / 2.0
}

/// Adam on mean squared error, with an L2 pull towards the starting weights
/// so rarely-seen features stay sensible. `frozen` features keep their values.
pub fn texel(all: &[Sample], start: &Params, frozen: &[bool], epochs: usize, lambda: f64, log: &mut dyn FnMut(usize, f64)) -> (Params, f64) {
    // Shuffle: samples come game by game, and batches drawn from just a few
    // games (which share a result) give gradients that are mostly noise.
    let mut order: Vec<usize> = (0..all.len()).collect();
    crate::util::Rng::new(12345).shuffle(&mut order);
    let shuffled: Vec<Sample> = order.iter().map(|&i| all[i].clone()).collect();
    let samples = &shuffled[..];
    let k = best_k(samples, &start.w);
    let n = NFEAT;
    let mut w: Vec<[f64; 2]> = start.w.iter().map(|x| [x[0] as f64, x[1] as f64]).collect();
    let w0 = w.clone();
    let mut m = vec![[0.0f64; 2]; n];
    let mut v = vec![[0.0f64; 2]; n];
    let (b1, b2, eps) = (0.9, 0.999, 1e-8);
    let ln10 = std::f64::consts::LN_10;
    let mut t = 0;
    let batch = 4096.min(samples.len().max(1));
    for epoch in 0..epochs {
        // Big steps first (material weights are hundreds of centipawns), then settle.
        let lr = (12.0 * 0.88f64.powi(epoch as i32)).max(0.5);
        for chunk in samples.chunks(batch) {
            let mut g = vec![[0.0f64; 2]; n];
            for s in chunk {
                let mut mg = 0.0;
                let mut eg = 0.0;
                for &(f, x) in &s.feats {
                    mg += w[f as usize][0] * x as f64;
                    eg += w[f as usize][1] * x as f64;
                }
                let ph = s.phase as f64;
                let e = mg * ph + eg * (1.0 - ph);
                let p = win_prob(e, k);
                // d/dE of (r - p)^2
                let d = -2.0 * (s.result as f64 - p) * p * (1.0 - p) * k * ln10 / 400.0;
                for &(f, x) in &s.feats {
                    g[f as usize][0] += d * x as f64 * ph;
                    g[f as usize][1] += d * x as f64 * (1.0 - ph);
                }
            }
            t += 1;
            let scale = 1.0 / chunk.len() as f64;
            for i in 0..n {
                if frozen[i] {
                    continue;
                }
                for j in 0..2 {
                    let gr = g[i][j] * scale + lambda * (w[i][j] - w0[i][j]);
                    m[i][j] = b1 * m[i][j] + (1.0 - b1) * gr;
                    v[i][j] = b2 * v[i][j] + (1.0 - b2) * gr * gr;
                    let mh = m[i][j] / (1.0 - f64::powi(b1, t));
                    let vh = v[i][j] / (1.0 - f64::powi(b2, t));
                    w[i][j] -= lr * mh / (vh.sqrt() + eps);
                }
            }
        }
        let wf: Vec<[f32; 2]> = w.iter().map(|x| [x[0] as f32, x[1] as f32]).collect();
        if std::env::var("PLUSFISH_DEBUG").is_ok() {
            eprintln!("    f56 w={:?} m={:?} v={:?} frozen={}", w[56], m[56], v[56], frozen[56]);
        }
        log(epoch, mse(samples, &wf, k));
    }
    let mut out = start.clone();
    out.w = w.iter().map(|x| [x[0] as f32, x[1] as f32]).collect();
    for i in 0..n {
        if !frozen[i] {
            out.tuned[i] = true;
        }
    }
    (out, k)
}

/// Texel tuning as a logistic regression, solved with Newton's method (the
/// problem is convex, so it can't get stuck the way gradient descent can).
/// Each feature gets a middlegame and an endgame column (value x phase,
/// value x (1 - phase)). A ridge penalty pulls weights towards their starting
/// values (so rarely-seen features stay sensible), and at the end the weights
/// are rescaled so material matches army costs on average: centipawns stay
/// "hundredths of an army point".
/// `k`: the logistic scale (as in `win_prob`); None = the best fit for the
/// starting weights.
pub fn texel_newton(samples: &[Sample], start: &Params, frozen: &[bool], cost_cp: &[(usize, f64)], ridge: f64, iters: usize, threads: usize, k: Option<f64>, log: &mut dyn FnMut(usize, f64)) -> Params {
    let k0 = k.unwrap_or_else(|| best_k(samples, &start.w));
    let to_logit = k0 * std::f64::consts::LN_10 / 400.0;
    let mut col_of = vec![usize::MAX; NFEAT];
    let mut cols = 0;
    for i in 0..NFEAT {
        if !frozen[i] {
            col_of[i] = cols;
            cols += 2;
        }
    }
    let mut beta0 = vec![0.0f64; cols];
    for i in 0..NFEAT {
        if col_of[i] != usize::MAX {
            beta0[col_of[i]] = start.w[i][0] as f64 * to_logit;
            beta0[col_of[i] + 1] = start.w[i][1] as f64 * to_logit;
        }
    }
    let mut beta = beta0.clone();
    // The fixed part of each sample's score (frozen features).
    let offsets: Vec<f64> = samples
        .iter()
        .map(|s| {
            let mut o = 0.0;
            for &(f, x) in &s.feats {
                if frozen[f as usize] {
                    let w = start.w[f as usize];
                    o += (w[0] as f64 * s.phase as f64 + w[1] as f64 * (1.0 - s.phase as f64)) * x as f64;
                }
            }
            o * to_logit
        })
        .collect();
    let n = samples.len().max(1) as f64;
    let threads = threads.max(1);
    for it in 0..iters {
        let chunk = ((samples.len() + threads - 1) / threads).max(1);
        let parts: Vec<(Vec<f64>, Vec<f64>, f64)> = std::thread::scope(|scope| {
            let handles: Vec<_> = samples
                .chunks(chunk)
                .zip(offsets.chunks(chunk))
                .map(|(ss, oo)| {
                    let beta = &beta;
                    let col_of = &col_of;
                    scope.spawn(move || {
                        let mut g = vec![0.0f64; cols];
                        let mut h = vec![0.0f64; cols * cols];
                        let mut loss = 0.0;
                        let mut row: Vec<(usize, f64)> = Vec::with_capacity(96);
                        for (s, &o) in ss.iter().zip(oo) {
                            row.clear();
                            let ph = s.phase as f64;
                            for &(f, x) in &s.feats {
                                let c = col_of[f as usize];
                                if c != usize::MAX {
                                    row.push((c, x as f64 * ph));
                                    row.push((c + 1, x as f64 * (1.0 - ph)));
                                }
                            }
                            let z: f64 = o + row.iter().map(|&(c, v)| beta[c] * v).sum::<f64>();
                            let mu = sigmoid(z);
                            let y = s.result as f64;
                            loss -= y * mu.max(1e-12).ln() + (1.0 - y) * (1.0 - mu).max(1e-12).ln();
                            let wgt = mu * (1.0 - mu);
                            for &(c, v) in &row {
                                g[c] += (y - mu) * v;
                                let hr = &mut h[c * cols..(c + 1) * cols];
                                for &(c2, v2) in &row {
                                    hr[c2] += wgt * v * v2;
                                }
                            }
                        }
                        (g, h, loss)
                    })
                })
                .collect();
            handles.into_iter().map(|h| h.join().unwrap()).collect()
        });
        let mut g = vec![0.0f64; cols];
        let mut h = vec![0.0f64; cols * cols];
        let mut loss = 0.0;
        for (pg, ph, pl) in parts {
            for i in 0..cols {
                g[i] += pg[i];
            }
            for i in 0..cols * cols {
                h[i] += ph[i];
            }
            loss += pl;
        }
        // Ridge towards the starting weights, scaled to the data size.
        let lam = ridge * n;
        let mut hm: Vec<Vec<f64>> = (0..cols).map(|i| h[i * cols..(i + 1) * cols].to_vec()).collect();
        for i in 0..cols {
            g[i] -= lam * (beta[i] - beta0[i]);
            hm[i][i] += lam + 1e-9;
        }
        let step = solve(&hm, &g);
        let mut biggest = 0.0f64;
        for i in 0..cols {
            beta[i] += step[i];
            biggest = biggest.max(step[i].abs());
        }
        log(it, loss / n);
        if biggest < 1e-6 {
            break;
        }
    }
    // Back to centipawns, anchored to the army costs.
    let mut num = 0.0;
    let mut den = 0.0;
    for &(f, cp) in cost_cp {
        let c = col_of[f];
        if c != usize::MAX {
            let b = (beta[c] + beta[c + 1]) / 2.0;
            num += b * cp;
            den += b * b;
        }
    }
    let scale = if den > 0.0 { num / den } else { 1.0 / to_logit };
    let mut w: Vec<[f32; 2]> = start.w.clone();
    let ratio = (scale * to_logit) as f32;
    for i in 0..NFEAT {
        let c = col_of[i];
        if c != usize::MAX {
            w[i] = [(beta[c] * scale) as f32, (beta[c + 1] * scale) as f32];
        } else {
            // Frozen features were in centipawns already; put them on the new scale.
            w[i] = [start.w[i][0] * ratio, start.w[i][1] * ratio];
        }
    }
    let mut out = start.clone();
    out.w = w;
    for i in 0..NFEAT {
        if !frozen[i] {
            out.tuned[i] = true;
        }
    }
    out
}

/// Logistic regression (results can be 0, 0.5 or 1) by Newton's method with a
/// small ridge penalty. Returns coefficients and their standard errors.
/// `x` rows are dense; the last column should be 1 for an intercept if wanted.
pub fn logistic(x: &[Vec<f64>], y: &[f64], ridge: f64) -> (Vec<f64>, Vec<f64>) {
    let (beta, se, _) = logistic_cov(x, y, ridge);
    (beta, se)
}

/// `logistic`, also returning the full covariance matrix of the coefficients.
pub fn logistic_cov(x: &[Vec<f64>], y: &[f64], ridge: f64) -> (Vec<f64>, Vec<f64>, Vec<Vec<f64>>) {
    let p = x.first().map(|r| r.len()).unwrap_or(0);
    let mut beta = vec![0.0; p];
    for _ in 0..50 {
        let mut grad = vec![0.0; p];
        let mut hess = vec![vec![0.0; p]; p];
        for (row, &yi) in x.iter().zip(y) {
            let z: f64 = row.iter().zip(&beta).map(|(a, b)| a * b).sum();
            let mu = sigmoid(z);
            let wgt = mu * (1.0 - mu);
            for i in 0..p {
                if row[i] == 0.0 {
                    continue;
                }
                grad[i] += (yi - mu) * row[i];
                for j in 0..p {
                    hess[i][j] += wgt * row[i] * row[j];
                }
            }
        }
        for i in 0..p {
            grad[i] -= ridge * beta[i];
            hess[i][i] += ridge;
        }
        let step = solve(&hess, &grad);
        let mut biggest = 0.0f64;
        for i in 0..p {
            beta[i] += step[i];
            biggest = biggest.max(step[i].abs());
        }
        if biggest < 1e-9 {
            break;
        }
    }
    // Standard errors from the inverse Hessian, scaled for over/under-dispersion
    // (draws make the 0/0.5/1 results less spread out than pure win/loss).
    let mut hess = vec![vec![0.0; p]; p];
    let mut pearson = 0.0;
    for (row, &yi) in x.iter().zip(y) {
        let z: f64 = row.iter().zip(&beta).map(|(a, b)| a * b).sum();
        let mu = sigmoid(z);
        let wgt = (mu * (1.0 - mu)).max(1e-9);
        pearson += (yi - mu).powi(2) / wgt;
        for i in 0..p {
            for j in 0..p {
                hess[i][j] += wgt * row[i] * row[j];
            }
        }
    }
    for i in 0..p {
        hess[i][i] += ridge;
    }
    let dispersion = pearson / (x.len() as f64 - p as f64).max(1.0);
    let inv = invert(&hess);
    let se = (0..p).map(|i| (inv[i][i] * dispersion).max(0.0).sqrt()).collect();
    let cov = inv.iter().map(|r| r.iter().map(|v| v * dispersion).collect()).collect();
    (beta, se, cov)
}

/// Solves a x = b (Gaussian elimination with partial pivoting).
pub fn solve(a: &[Vec<f64>], b: &[f64]) -> Vec<f64> {
    let n = b.len();
    let mut m: Vec<Vec<f64>> = a.iter().zip(b).map(|(r, &bi)| {
        let mut r = r.clone();
        r.push(bi);
        r
    }).collect();
    for c in 0..n {
        let piv = (c..n).max_by(|&i, &j| m[i][c].abs().partial_cmp(&m[j][c].abs()).unwrap()).unwrap();
        m.swap(c, piv);
        let d = m[c][c];
        if d.abs() < 1e-12 {
            continue;
        }
        for j in c..=n {
            m[c][j] /= d;
        }
        for i in 0..n {
            if i != c {
                let f = m[i][c];
                if f != 0.0 {
                    for j in c..=n {
                        m[i][j] -= f * m[c][j];
                    }
                }
            }
        }
    }
    (0..n).map(|i| m[i][n]).collect()
}

pub fn invert(a: &[Vec<f64>]) -> Vec<Vec<f64>> {
    let n = a.len();
    let mut out = vec![vec![0.0; n]; n];
    for c in 0..n {
        let mut e = vec![0.0; n];
        e[c] = 1.0;
        let col = solve(a, &e);
        for r in 0..n {
            out[r][c] = col[r];
        }
    }
    out
}
