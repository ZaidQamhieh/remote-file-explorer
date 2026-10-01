# Sidecar protocol (version 1)

The Go agent runs hot components as child processes (`rfe-indexd`, later `rfe-thumbd`). The agent stays the
security boundary: it authenticates devices, decides roots and jails, and re-checks everything a sidecar returns.
A sidecar never decides access. This file is the contract both sides follow; the REST contract stays in
`openapi.yaml`.

## Transport

The agent starts the sidecar and talks to it over the child's **stdin and stdout**. There are no ports or sockets,
so it behaves the same on Linux, macOS and Windows, and the child ends when the agent does (stdin closes).
**stderr is for logs only**; the agent copies it into its own log with a `sidecar <name>:` prefix. stdout carries
frames and nothing else.

## Frames

```
u32 big-endian length | u8 kind | payload        (length counts the kind byte and the payload)
```

| kind | payload |
|---|---|
| 0 | one JSON message |
| 1 | raw bytes belonging to the JSON frame just before it (that message sets `"body": true`) |

A sender writes a JSON frame and its body under one lock, so a receiver always sees them back to back. A frame
longer than 160 MiB, or of length 0, is a protocol error: the receiver closes the connection and the agent
restarts the sidecar.

## Handshake

The sidecar's first frame is a hello. The agent waits up to 5 seconds, requires `kind == "hello"`, `proto == 1`
and the expected `name`, and otherwise kills the process.

```json
{"kind":"hello","proto":1,"name":"rfe-indexd","version":"0.1.0"}
```

## Requests and responses

The agent sends `{"id": <u64>, "op": "<name>", ...fields}`. Ids are unique per connection. Requests run
concurrently and responses may arrive in any order, matched by `id`.

Success: `{"id":N,"ok":true, ...fields}`. Failure: `{"id":N,"ok":false,"code":"...","message":"..."}`.

| code | meaning |
|---|---|
| `BAD_REQUEST` | malformed or unknown request |
| `NOT_SUPPORTED` | the input is not something this sidecar can process (maps to the Go `ErrNotSupported`) |
| `TOO_LARGE` | input over a limit |
| `BUSY` | an exclusive operation is already running |
| `CANCELED` | the request was canceled |
| `INTERNAL` | the sidecar failed (including a panic); the agent falls back to its own code |

**Cancel:** `{"id":M,"op":"cancel","target":N}` asks the sidecar to stop request N early; it answers N with
`CANCELED` (or its normal result if it already finished) and answers the cancel itself with `ok`.

**Ping:** `{"op":"ping"}` answers `{"ok":true}`; the agent uses it for health checks.

## rfe-indexd operations

Paths are absolute, UTF-8, and use the platform separator. Entries whose names are not valid UTF-8 are skipped.

- `index.build` `{roots:[string], maxEntries, maxBytes}` walks the roots in parallel (rooted, no-follow directory
  handles), swaps in the new snapshot, and answers `{entries, truncated, buildMs, bytes}`. One build at a time
  (`BUSY` otherwise). Queries keep using the old snapshot until the swap.
- `index.stats` answers `{ready, entries, truncated, buildMs, bytes}`.
- `index.query` `{filters, roots:[string], limit}` answers `{ready, entries:[Entry], truncated}`. `ready:false`
  means no snapshot yet; the agent walks live instead. `filters` is
  `{glob, needle, types, exts, minSize, maxSize, modAfterNs, modBeforeNs}` already validated by the agent
  (lowercase glob in Go `path.Match` syntax, or a lowercase substring). Results come in depth-first, name-sorted
  order, the order Go's `fs.WalkDir` yields. `truncated` is true when `limit` was reached or the index itself was
  cut by its budget.
- `recents.scan` `{roots:[string], limit, budgetMs}` answers `{entries:[Entry], partial}` with the newest files
  (not directories) first. `partial` is true when `budgetMs` cut the scan short.

Walk rules match the Go agent: hidden directories (leading `.`), `node_modules`, and on Linux `/proc /sys /dev
/sysroot` are pruned (never the root itself); hidden files are kept; symlinks are listed but never followed, and a
link whose target is a directory inside the root reports `isDir: true`.

**Entry**:
`{path, size, mtimeNs, ctimeNs, mode, isDir, isSymlink, symlinkTarget?}` where `mode` holds Go `fs.FileMode` bits
and `ctimeNs` follows the Go agent's per-OS "created" rule. The agent derives the MIME type, the mode string and
the timestamps from these fields.

## What the agent must do with every response

1. Re-check each returned `path` is absolute, clean (`filepath.Clean(p) == p`) and under one of the roots it
   asked for; drop anything else.
2. Treat any error, malformed JSON, protocol violation or timeout as "sidecar unavailable" and use its own
   implementation.
3. Never pass user input to a sidecar unvalidated (globs, category names and limits are validated in Go first).
