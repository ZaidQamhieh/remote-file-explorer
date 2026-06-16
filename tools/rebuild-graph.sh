#!/usr/bin/env bash
# Rebuild the Remote File Explorer architecture knowledge graph.
# Reads graphify's cached extraction (no LLM cost) unless code changed since
# the last `graphify` run, regenerates graph.json + GRAPH_REPORT.md + HTML +
# the Obsidian mirror. Tune behavior in tools/build_arch_graph.py CONFIG block.
set -euo pipefail
cd "$(dirname "$0")/.."

PY=$(cat graphify-out/.graphify_python 2>/dev/null || true)
if [ -z "${PY}" ] || [ ! -x "${PY}" ]; then
  PY=$(head -1 "$(command -v graphify)" | tr -d '#!')
  mkdir -p graphify-out && printf '%s' "$PY" > graphify-out/.graphify_python
fi

OBSIDIAN_DIR="$HOME/Documents/Obsidian Vault/Claude/graphify-remote-file-explorer"

"$PY" tools/build_arch_graph.py
graphify export html >/dev/null
# graphify's obsidian export APPENDS and never removes deleted nodes, so stale
# notes accumulate. Wipe the (dedicated, fully regenerable) mirror first.
rm -rf "$OBSIDIAN_DIR"
graphify export obsidian --dir "$OBSIDIAN_DIR" >/dev/null
echo "✓ graph.html + Obsidian mirror refreshed ($(find "$OBSIDIAN_DIR" -name '*.md' | wc -l | tr -d ' ') notes)"
