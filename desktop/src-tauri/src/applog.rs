//! A small in-memory log for the diagnostics report: the last few hundred events, filtered by the
//! level the user chose in Settings. It is never written to disk. Callers pass event words and
//! error text, never credentials: passwords, tokens and nonces do not reach this module.

use std::collections::VecDeque;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Level {
    Off,
    Error,
    Info,
    Debug,
}

impl Level {
    pub fn as_str(self) -> &'static str {
        match self {
            Level::Off => "off",
            Level::Error => "error",
            Level::Info => "info",
            Level::Debug => "debug",
        }
    }

    pub fn parse(s: &str) -> Option<Level> {
        Some(match s {
            "off" => Level::Off,
            "error" => Level::Error,
            "info" => Level::Info,
            "debug" => Level::Debug,
            _ => return None,
        })
    }
}

/// Lines kept; the oldest go first.
pub const CAPACITY: usize = 500;
/// Characters kept of one message.
const MAX_LINE: usize = 300;

struct Log {
    level: Level,
    lines: VecDeque<String>,
}

static LOG: Mutex<Log> = Mutex::new(Log {
    level: Level::Info,
    lines: VecDeque::new(),
});

fn log() -> std::sync::MutexGuard<'static, Log> {
    LOG.lock().unwrap_or_else(|e| e.into_inner())
}

pub fn set_level(level: Level) {
    log().level = level;
}

pub fn level() -> Level {
    log().level
}

/// Records `msg` if `at` is within the chosen level. One line: control characters become spaces.
pub fn record(at: Level, msg: &str) {
    let mut l = log();
    if at == Level::Off || at > l.level {
        return;
    }
    let clean: String = msg
        .chars()
        .map(|c| if c.is_control() { ' ' } else { c })
        .take(MAX_LINE)
        .collect();
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    if l.lines.len() == CAPACITY {
        l.lines.pop_front();
    }
    l.lines
        .push_back(format!("{secs} {} {clean}", at.as_str().to_uppercase()));
}

pub fn error(msg: &str) {
    record(Level::Error, msg);
}

pub fn info(msg: &str) {
    record(Level::Info, msg);
}

pub fn debug(msg: &str) {
    record(Level::Debug, msg);
}

pub fn lines() -> Vec<String> {
    log().lines.iter().cloned().collect()
}

pub fn clear() {
    log().lines.clear();
}
