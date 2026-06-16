#!/usr/bin/env python
"""Build a pruned *architecture* knowledge graph for Remote File Explorer.

Why this exists: raw graphify emits one node per code symbol (every getter,
field, test helper), so the full graph is ~3k nodes and ~60% degree-<=1 leaves.
That's great for "find any symbol" but a hairball for "understand the system".
This script rebuilds from graphify's cached extraction and keeps only the
architecturally meaningful nodes, then regenerates the report + HTML + Obsidian
mirror.

Run it after code changes:

    PY=$(cat graphify-out/.graphify_python)
    "$PY" tools/build_arch_graph.py

Tunables live in the CONFIG block below — edit those, not the logic.
Extraction is read from graphify's cache, so re-running costs ~no LLM tokens.
"""
from __future__ import annotations
import json, re, sys
from collections import Counter
from pathlib import Path

from graphify.detect import detect
from graphify.extract import collect_files, extract
from graphify.cache import check_semantic_cache
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.analyze import god_nodes, surprising_connections, suggest_questions
from graphify.report import generate
from graphify.export import to_json

# ─────────────────────────── CONFIG (edit me) ───────────────────────────
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "graphify-out"
OBSIDIAN_DIR = Path.home() / "Documents/Obsidian Vault/Claude/graphify-remote-file-explorer"

# Path fragments whose files are excluded entirely: build noise, generated
# code, platform boilerplate, and this tooling dir itself (not app architecture).
EXCLUDE_PATH = (
    "/.cxx/", "/build/", "/.dart_tool/", "/Pods/",
    "/ios/", "/android/", "/macos/", "/linux/", "/windows/", "/web/",
    "/tools/",
)

# Keep test files out of the architecture view? (they're still in the full graph)
DROP_TESTS = True

# Code nodes with degree <= this are pruned as leaves. Concept/doc/rationale
# nodes are always kept (they carry the design narrative). Raise to keep more.
MIN_CODE_DEGREE = 2

# How much CODE detail belongs in the second brain. Concept/document/rationale
# nodes (the design narrative) are ALWAYS kept — this only governs code symbols:
#   "all"    - every symbol (a full code map; noisy, not a second brain)
#   "public" - architectural nouns (exported types/classes) always, plus
#              exported functions/methods only when well-connected (god nodes);
#              internal helpers (orNone, shortID, accessors) are dropped
#   "types"  - only top-level types/classes — the most abstract view
# A second brain wants "public": you navigate it for "what are the parts and
# how do they connect", not to look up a one-line helper.
CODE_DETAIL = "public"

# In "public" mode, an exported function/method is kept only at/above this
# degree (types are always kept). Filters API trivia, keeps the connective spine.
PUBLIC_FUNC_MIN_DEGREE = 3

# Communities smaller than this are dropped — for an architecture overview,
# 1-3 node islands are noise, not modules. Set to 1 to keep everything.
MIN_COMMUNITY_SIZE = 4

# Louvain resolution. <1.0 = fewer, larger communities (less fragmentation).
CLUSTER_RESOLUTION = 0.9

# Generic AST symbols that become phantom hubs — never architecture.
GENERIC_LABELS = {
    "T", "File", "Time", "Writer", "Reader", "Entry", "Ops", "DB", "Row",
    "Context", "Request", "Response", "ResponseWriter", "ResponseRecorder",
    "HandlerFunc", "Error", "error", "build", "copyWith", "createState",
    "AsyncSnapshot", "PageController", "IconButton", "FilterChip",
    "FilledButton", "CancelToken", "PreferredSizeWidget",
    # language keywords / builtins / bare types AST mints as reference targets
    "return", "typedef", "static const", "var", "final", "const",
    "String", "List", "Map", "Set", "bool", "int", "double", "void",
    "Future", "Stream", "Widget", "DateTime", "Exception", "Object",
    "Host", "Dio",
}

# Label patterns that mark a node as an import/keyword/accessor artifact, not
# a real symbol. These plus source_file=None are the AST's phantom targets.
JUNK_LABEL_RE = re.compile(
    r"^(package:|dart:|\.{1,2}/)"          # import paths
    r"|\.(dart|go|ya?ml|json)$"            # bare filename references
    r"|^\w+ (get|set)$"                    # "String get", "bool set"
)

# Map a source path to a friendly module tag for auto-labeling communities.
# First matching rule wins; falls back to the immediate parent directory.
MODULE_RULES = [
    (r"agent/internal/fsops", "Agent: FS Ops"),
    (r"agent/internal/server", "Agent: HTTP Server"),
    (r"agent/internal/store", "Agent: Store/DB"),
    (r"agent/internal/(\w+)", lambda m: f"Agent: {m.group(1).title()}"),
    (r"agent/cmd", "Agent: CLI"),
    (r"app/lib/features/(\w+)", lambda m: m.group(1).replace("_", " ").title()),
    (r"app/lib/core/(\w+)", lambda m: f"Core: {m.group(1).title()}"),
    (r"protocol/", "API Contract"),
    (r"docs/", "Design Docs"),
]
# ─────────────────────────────────────────────────────────────────────────


def is_test(path: str) -> bool:
    p = path.lower()
    return "/test/" in p or p.endswith(("_test.go", "_test.dart")) or "/test_" in p


def module_tag(path: str) -> str:
    for pat, name in MODULE_RULES:
        m = re.search(pat, path)
        if m:
            return name(m) if callable(name) else name
    parent = Path(path).parent.name
    return parent or "misc"


def keep_node(n: dict) -> bool:
    sf = n.get("source_file")
    if not sf:                       # phantom: external/builtin reference target
        return False
    if any(x in sf for x in EXCLUDE_PATH):
        return False
    if DROP_TESTS and is_test(sf):
        return False
    label = str(n.get("label", ""))
    if label in GENERIC_LABELS:
        return False
    if len(label) == 1:              # single-letter type params (T, K, V)
        return False
    if JUNK_LABEL_RE.search(label):  # imports / bare filenames / accessors
        return False
    return True


NARRATIVE_TYPES = ("concept", "document", "rationale")


def is_type_node(label: str) -> bool:
    """A top-level type/class — the architectural nouns. No call parens and
    an uppercase initial (Go types `Ops`/`Entry`, Dart classes `AgentClient`)."""
    label = label.strip().lstrip("._")
    return bool(label) and "(" not in label and label[:1].isupper()


def is_exported(label: str) -> bool:
    """Go exported (uppercase initial, incl. `.Method()`) or Dart public
    (not `_`-prefixed). Internal helpers like orNone()/_buildBody are not."""
    name = label.strip().lstrip(".")
    if name.startswith("_"):
        return False          # Dart private
    return name[:1].isupper() if name else False


def keep_code_node(n: dict, degree: int) -> bool:
    """Second-brain code filter (see CODE_DETAIL). Narrative nodes bypass this."""
    label = str(n.get("label", ""))
    if CODE_DETAIL == "all":
        return True
    if CODE_DETAIL == "types":
        return is_type_node(label)
    # "public": types always; exported functions only when well-connected.
    if is_type_node(label):
        return True
    if is_exported(label):
        return degree >= PUBLIC_FUNC_MIN_DEGREE
    return False              # internal/unexported helper → drop


def load_extraction() -> dict:
    """Rebuild merged extraction from graphify's caches (no LLM cost)."""
    det = detect(ROOT)
    (OUT / ".graphify_detect.json").write_text(json.dumps(det, ensure_ascii=False), "utf-8")

    code_files: list[Path] = []
    for f in det.get("files", {}).get("code", []):
        fp = Path(f)
        code_files.extend(collect_files(fp) if fp.is_dir() else [fp])
    ast = extract(code_files, cache_root=ROOT)

    docs = [d for d in det["files"].get("document", []) if not any(x in d for x in EXCLUDE_PATH)]
    cn, ce, ch, _ = check_semantic_cache(docs)

    seen = {n["id"] for n in ast["nodes"]}
    nodes = list(ast["nodes"]) + [n for n in cn if n["id"] not in seen]
    return {
        "nodes": nodes,
        "edges": ast["edges"] + ce,
        "hyperedges": ch,
        "input_tokens": 0,
        "output_tokens": 0,
    }, det


def main() -> None:
    extraction, detection = load_extraction()
    raw_n = len(extraction["nodes"])

    # 1. Drop excluded files / tests / generic hubs at the node level.
    kept_ids = {n["id"] for n in extraction["nodes"] if keep_node(n)}
    nodes = [n for n in extraction["nodes"] if n["id"] in kept_ids]
    edges = [e for e in extraction["edges"] if e["source"] in kept_ids and e["target"] in kept_ids]

    # 2. Second-brain code filter: keep the design narrative (concept/doc/
    #    rationale) wholesale; for code, keep architectural nouns + connective
    #    public API and drop helper trivia (CODE_DETAIL), then prune any code
    #    left as a leaf. Degree is measured on the stage-1 graph.
    deg: Counter = Counter()
    for e in edges:
        deg[e["source"]] += 1
        deg[e["target"]] += 1
    final_ids = set()
    for n in nodes:
        if n.get("file_type") in NARRATIVE_TYPES:
            final_ids.add(n["id"])
        elif keep_code_node(n, deg[n["id"]]) and deg[n["id"]] >= MIN_CODE_DEGREE:
            final_ids.add(n["id"])
    nodes = [n for n in nodes if n["id"] in final_ids]
    edges = [e for e in edges if e["source"] in final_ids and e["target"] in final_ids]
    hyper = [h for h in extraction.get("hyperedges", [])
             if all(x in final_ids for x in h.get("nodes", []))]

    pruned = {"nodes": nodes, "edges": edges, "hyperedges": hyper,
              "input_tokens": 0, "output_tokens": 0}

    # 3. Build + cluster, then drop micro-communities (noise islands) and
    #    re-cluster the survivors so the community structure is meaningful.
    G = build_from_json(pruned)
    communities = cluster(G, resolution=CLUSTER_RESOLUTION)
    if MIN_COMMUNITY_SIZE > 1:
        keep = {nid for members in communities.values()
                if len(members) >= MIN_COMMUNITY_SIZE for nid in members}
        nodes = [n for n in nodes if n["id"] in keep]
        edges = [e for e in edges if e["source"] in keep and e["target"] in keep]
        hyper = [h for h in hyper if all(x in keep for x in h.get("nodes", []))]
        pruned = {"nodes": nodes, "edges": edges, "hyperedges": hyper,
                  "input_tokens": 0, "output_tokens": 0}
        G = build_from_json(pruned)
        communities = cluster(G, resolution=CLUSTER_RESOLUTION)
    cohesion = score_all(G, communities)
    by_id = {n["id"]: n for n in nodes}
    fdeg = dict(G.degree())

    def shorten(label: str, n: int = 34) -> str:
        label = re.sub(r"\s*\(.*?\)\s*$", "", label).strip()  # drop trailing "(...)"
        return label if len(label) <= n else label[: n - 1] + "…"

    def label_for(member_ids: list[str]) -> str:
        members = [by_id[i] for i in member_ids if i in by_id]
        # A community that is mostly design narrative is named by its most
        # central concept (theme), not by a source directory — that's what
        # makes the map read like a second brain rather than a folder tree.
        narrative = [m for m in members if m.get("file_type") in NARRATIVE_TYPES]
        if members and len(narrative) >= len(members) / 2:
            best = max(narrative, key=lambda m: fdeg.get(m["id"], 0))
            return shorten(best.get("label", "")) or "Concepts"
        tags = Counter(module_tag(m.get("source_file") or "") for m in members)
        return tags.most_common(1)[0][0] if tags else "misc"

    labels = {cid: label_for(members) for cid, members in communities.items()}

    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    questions = suggest_questions(G, communities, labels)
    report = generate(G, communities, cohesion, labels, gods, surprises,
                      detection, {"input": 0, "output": 0}, ".",
                      suggested_questions=questions)
    (OUT / "GRAPH_REPORT.md").write_text(report, "utf-8")
    # force=True: the node drop is the whole point here, so the anti-clobber
    # guard (which assumes shrinkage = data loss) must be overridden.
    to_json(G, communities, str(OUT / "graph.json"), force=True, community_labels=labels)
    (OUT / ".graphify_labels.json").write_text(
        json.dumps({str(k): v for k, v in labels.items()}, ensure_ascii=False), "utf-8")

    print(f"Raw extraction:     {raw_n} nodes")
    print(f"Architecture graph: {G.number_of_nodes()} nodes, "
          f"{G.number_of_edges()} edges, {len(communities)} communities")
    print(f"Wrote: {OUT/'graph.json'}, GRAPH_REPORT.md, .graphify_labels.json")


if __name__ == "__main__":
    main()
