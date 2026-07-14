<!-- NEXT_SESSION_STATUS: CLEAR -->
# NEXT_SESSION — cross-session handoff

Carryover for work **left unfinished** in a prior session. The `SessionStart`
hook (`.claude/hooks/next-session-guard.sh`) surfaces this file automatically at
the start of every session in this repo — but **only when the status marker on
line 1 reads `HANDOFF`**. When it reads `CLEAR`, there is nothing to resume and
the hook stays silent.

This is repo-local, incomplete-work carryover only. Durable project state,
architecture, and backlog live in the Obsidian wiki (`entities/rfe-backlog.md`),
not here.

## Contract (mirrored in `CLAUDE.md` §"Cross-session handoff")
- **Task finished this session** → set line 1 to `CLEAR` and reset
  `## Open handoff` to the "None" placeholder. Don't leave a resolved handoff to
  rot (that's what made the old version stale).
- **Task NOT finished** → set line 1 to `HANDOFF` and fill `## Open handoff`
  with: the goal, what's done, what's left, exact files/lines to start from, and
  how to verify. Write it so a cold session resumes with zero re-derivation.

---

## Open handoff

None. The approved Settings redesign (v2, tile-grid hub + tinted hero
sub-screens) from the prior handoff shipped this session — see commit for
details. `flutter analyze` clean, 618/618 tests pass.
