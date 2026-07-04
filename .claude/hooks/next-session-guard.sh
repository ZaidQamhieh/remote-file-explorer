#!/usr/bin/env bash
# SessionStart guard: surface NEXT_SESSION.md ONLY when it carries an unfinished
# handoff (line-1 marker reads HANDOFF). Silent otherwise, so a clean repo never
# adds noise. stdout from a SessionStart hook is injected into the session as
# context — that's the "make Claude read it before any session" guarantee.
set -euo pipefail

f="${CLAUDE_PROJECT_DIR:-.}/NEXT_SESSION.md"
[ -f "$f" ] || exit 0

# Only the first line's marker decides. CLEAR (or anything not HANDOFF) → silent.
if ! head -n1 "$f" | grep -q 'NEXT_SESSION_STATUS: HANDOFF'; then
  exit 0
fi

printf '⚠️  UNFINISHED WORK from a previous session — read NEXT_SESSION.md before starting:\n\n'
cat "$f"
