//! Plusfish: an analysis and balancing engine for Chess Plus.

pub mod army;
pub mod defs;
pub mod endgame;
pub mod eval;
pub mod game;
pub mod html;
pub mod json;
pub mod position;
pub mod report;
pub mod search;
pub mod selfplay;
pub mod tune;
pub mod uci;
pub mod util;
pub mod verify;
pub mod api;

#[cfg(target_arch = "wasm32")]
mod wasm;
