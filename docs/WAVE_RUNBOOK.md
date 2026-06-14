# Wave Runbook — how to scope, dispatch, and ship a wave

> Purpose: make orchestration **mechanical instead of re-reasoned each time**, and stop
> dispatched sub-agents from re-reading the whole repo cold. Pair this with
> `docs/architecture.md` (the code map) and the root `CLAUDE.md` (constraints + policy).

## When to dispatch sub-agents at all

- **Small/medium diff (one feature, < ~5 files):** do it inline. A sub-agent re-reads
  context cold — that costs more tokens than it saves here.
- **Large wave with disjoint file ownership:** dispatch parallel agents, **one per
  non-overlapping file set**, each in its own git worktree, merge clean. This is the
  only case worth the cold-start cost.
- Never dispatch a separate review/fix agent for a small diff — review inline.

## Wave lifecycle (the mechanical loop)

1. **Scope** — list the exact files each unit of work will touch (from the code map).
   Confirm the sets are disjoint before dispatching in parallel.
2. **Brief** — give each agent the template below. Do **not** make it discover the repo.
3. **Build** — agent edits only its named files; OpenAPI change ships in the same commit.
4. **Gate** — `lefthook run pre-commit` is automatic on commit (format/analyze/vet);
   `lefthook run pre-push` runs affected tests on push. Trust CI for the full green.
5. **Commit** — one `feat:` commit, then a separate `fix:` commit for review fixes.
6. **Push** — let CI confirm the full suite green; don't re-run it locally.
7. **Release (if shipping)** — `./release.sh X.Y.Z+N` (build number MUST increase) or tag
   `v*` for the CD job. Update `HANDOFF.md` build-state + this repo's memory.

---

## Sub-agent brief template (copy, fill the « » slots, delete the rest)

```
You are implementing one slice of a wave in the Remote File Explorer repo
(~/Storage/Projects/remote-file-explorer). Work fully autonomously.

ORIENT (read these, in order — do NOT fan-out grep the repo):
  1. CLAUDE.md                — hard constraints + token-discipline policy
  2. docs/architecture.md     — code map; find your files there
  3. «only the 1–3 files you will edit, listed below»

YOUR SLICE (edit ONLY these files — they are disjoint from other agents):
  - «app/lib/features/.../foo.dart»     — «what to change»
  - «agent/internal/.../bar.go»         — «what to change»
  - protocol/openapi.yaml               — «if the API changes, in the SAME commit»

HARD CONSTRAINTS (from CLAUDE.md — do not violate):
  - Riverpod stays 2.6.1 (Notifier API). Impeller is OFF — Skia-safe widgets only.
  - All network/content access goes through the pinned AgentClient. No raw dio.
  - All explorer state changes go through ExplorerNotifier. Use shared formatSize/formatDate.
  - Any agent API change edits protocol/openapi.yaml in the same commit.

DONE = lefthook pre-commit passes (it runs format/analyze/vet on commit) and the
test files for your slice pass. Do NOT run the full suite — CI does that. Do NOT
re-read a file you just edited to verify.

DELIVER: a `feat:` commit on your worktree branch + a one-paragraph summary of what
changed and any contract edits.
```

> Keep the brief short. The whole point is the agent reads ~3 files (CLAUDE.md, the
> code map, its own targets) instead of re-deriving the repo — that is the re-read tax
> this runbook exists to kill.
