//! The request loop: reads frames from stdin, answers on stdout, runs each request on its own thread so a
//! long index build never blocks a query.

use crate::filter::{Compiled, Filters};
use crate::index::{Index, Limits};
use crate::recents;
use rfe_proto::{code, error_response, read_frame, write_frame, Envelope, Hello, KIND_JSON};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, Instant};

pub const NAME: &str = "rfe-indexd";

struct State {
    index: RwLock<Option<Arc<Index>>>,
    building: AtomicBool,
    cancels: Mutex<HashMap<u64, Arc<AtomicBool>>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BuildReq {
    roots: Vec<String>,
    max_entries: usize,
    max_bytes: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct QueryReq {
    #[serde(default)]
    filters: Filters,
    roots: Vec<String>,
    limit: usize,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RecentsReq {
    roots: Vec<String>,
    limit: usize,
    #[serde(default)]
    budget_ms: u64,
}

type Out<W> = Arc<Mutex<W>>;

fn send<W: Write>(out: &Out<W>, v: &Value) {
    let bytes = serde_json::to_vec(v).unwrap_or_default();
    let mut w = out.lock().unwrap();
    // A write failure means the Go agent is gone; the read loop will see EOF and exit.
    let _ = write_frame(&mut *w, KIND_JSON, &bytes).and_then(|_| w.flush());
}

/// Serves requests until the input closes. Generic over the streams so tests can drive it in memory.
pub fn serve<R: Read, W: Write + Send + 'static>(mut input: R, output: W) -> std::io::Result<()> {
    let out: Out<W> = Arc::new(Mutex::new(output));
    send(
        &out,
        &serde_json::to_value(Hello::new(NAME, env!("CARGO_PKG_VERSION"))).unwrap(),
    );
    let state = Arc::new(State {
        index: RwLock::new(None),
        building: AtomicBool::new(false),
        cancels: Mutex::new(HashMap::new()),
    });
    let mut workers: Vec<std::thread::JoinHandle<()>> = Vec::new();
    while let Some(frame) = read_frame(&mut input)? {
        if frame.kind != KIND_JSON {
            continue;
        }
        let Ok(env) = serde_json::from_slice::<Envelope>(&frame.payload) else {
            send(
                &out,
                &error_response(0, code::BAD_REQUEST, "malformed request"),
            );
            continue;
        };
        if env.op == "cancel" {
            if let Some(flag) = state.cancels.lock().unwrap().get(&env.target) {
                flag.store(true, Ordering::Relaxed);
            }
            send(&out, &json!({"id": env.id, "ok": true}));
            continue;
        }
        let cancel = Arc::new(AtomicBool::new(false));
        state
            .cancels
            .lock()
            .unwrap()
            .insert(env.id, Arc::clone(&cancel));
        let (state, out2, payload) = (Arc::clone(&state), Arc::clone(&out), frame.payload);
        workers.retain(|h| !h.is_finished());
        workers.push(std::thread::spawn(move || {
            let id = env.id;
            let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
                handle(&state, &env.op, &payload, &cancel)
            }));
            let resp = match result {
                Ok(Ok(mut v)) => {
                    v["id"] = json!(id);
                    v["ok"] = json!(true);
                    v
                }
                Ok(Err((c, m))) => error_response(id, c, &m),
                Err(_) => error_response(id, code::INTERNAL, "request panicked"),
            };
            state.cancels.lock().unwrap().remove(&id);
            send(&out2, &resp);
        }));
    }
    for h in workers {
        let _ = h.join();
    }
    Ok(())
}

type HandlerResult = Result<Value, (&'static str, String)>;

fn parse<T: for<'de> Deserialize<'de>>(payload: &[u8]) -> Result<T, (&'static str, String)> {
    serde_json::from_slice(payload)
        .map_err(|e| (code::BAD_REQUEST, format!("bad request body: {e}")))
}

fn handle(state: &State, op: &str, payload: &[u8], cancel: &AtomicBool) -> HandlerResult {
    match op {
        "ping" => Ok(json!({})),
        "index.build" => {
            let req: BuildReq = parse(payload)?;
            if state.building.swap(true, Ordering::AcqRel) {
                return Err((code::BUSY, "an index build is already running".into()));
            }
            let idx = Index::build(
                &req.roots,
                Limits {
                    max_entries: req.max_entries,
                    max_bytes: req.max_bytes,
                },
                cancel,
            );
            state.building.store(false, Ordering::Release);
            if cancel.load(Ordering::Relaxed) {
                return Err((code::CANCELED, "build canceled".into()));
            }
            let s = idx.stats;
            *state.index.write().unwrap() = Some(Arc::new(idx));
            Ok(
                json!({"entries": s.entries, "truncated": s.truncated, "buildMs": s.build_ms, "bytes": s.bytes}),
            )
        }
        "index.stats" => match state.index.read().unwrap().as_ref() {
            Some(i) => {
                let s = i.stats;
                Ok(
                    json!({"ready": true, "entries": s.entries, "truncated": s.truncated, "buildMs": s.build_ms, "bytes": s.bytes}),
                )
            }
            None => Ok(json!({"ready": false})),
        },
        "index.query" => {
            let req: QueryReq = parse(payload)?;
            let Some(idx) = state.index.read().unwrap().clone() else {
                return Ok(json!({"ready": false, "entries": [], "truncated": false}));
            };
            let (entries, truncated) =
                idx.query(&Compiled::new(req.filters), &req.roots, req.limit);
            Ok(json!({"ready": true, "entries": entries, "truncated": truncated}))
        }
        "recents.scan" => {
            let req: RecentsReq = parse(payload)?;
            let deadline =
                (req.budget_ms > 0).then(|| Instant::now() + Duration::from_millis(req.budget_ms));
            let (entries, partial) = recents::scan(&req.roots, req.limit, deadline, cancel);
            if cancel.load(Ordering::Relaxed) {
                return Err((code::CANCELED, "scan canceled".into()));
            }
            Ok(json!({"entries": entries, "partial": partial}))
        }
        other => Err((code::BAD_REQUEST, format!("unknown op {other:?}"))),
    }
}
