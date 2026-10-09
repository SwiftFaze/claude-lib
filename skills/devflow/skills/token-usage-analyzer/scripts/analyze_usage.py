#!/usr/bin/env python3
"""
analyze_usage.py — factual token-usage aggregator for Claude Code style
session transcripts (JSONL, one JSON object per line).

Design goal: never assume the schema silently. Print what was detected
so a human (or the calling Claude) can sanity-check before trusting the
aggregation. Field names vary across Claude Code versions and export
formats, so this script probes for several known variants and reports
which one it used.

Usage:
    python3 analyze_usage.py <path-to-transcript.jsonl> [more-files...] [--json]
"""

import sys
import json
import argparse
from collections import defaultdict


USAGE_KEYS = ("input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens")


def load_lines(path):
    records = []
    bad = 0
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                bad += 1
    if bad:
        print(f"  [warn] {bad} line(s) in {path} were not valid JSON and were skipped", file=sys.stderr)
    return records


def get_usage(record):
    """Find a usage dict wherever it lives in a record. Returns dict or None."""
    msg = record.get("message") if isinstance(record.get("message"), dict) else None
    candidates = []
    if msg and isinstance(msg.get("usage"), dict):
        candidates.append(msg["usage"])
    if isinstance(record.get("usage"), dict):
        candidates.append(record["usage"])
    for c in candidates:
        if any(k in c for k in USAGE_KEYS):
            return c
    return None


def get_model(record):
    msg = record.get("message") if isinstance(record.get("message"), dict) else None
    if msg and msg.get("model"):
        return msg["model"]
    if record.get("model"):
        return record["model"]
    return None


def get_type(record):
    return record.get("type") or record.get("role") or (record.get("message") or {}).get("role")


def is_sidechain(record):
    for key in ("isSidechain", "is_sidechain", "sidechain"):
        if key in record:
            return bool(record[key])
    return False


def find_tool_uses(record):
    """Return list of (tool_name, approx_char_len_of_input) for tool_use blocks."""
    out = []
    msg = record.get("message") if isinstance(record.get("message"), dict) else record
    content = msg.get("content") if isinstance(msg, dict) else None
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                name = block.get("name", "unknown_tool")
                length = len(json.dumps(block.get("input", "")))
                out.append((name, length))
    return out


def find_tool_results(record):
    """Return list of approx char lengths of tool_result content blocks."""
    out = []
    msg = record.get("message") if isinstance(record.get("message"), dict) else record
    content = msg.get("content") if isinstance(msg, dict) else None
    if isinstance(content, list):
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                c = block.get("content", "")
                out.append(len(json.dumps(c)))
    # some formats store the raw tool result separately
    if "toolUseResult" in record:
        out.append(len(json.dumps(record["toolUseResult"])))
    return out


def looks_like_compact(record):
    t = get_type(record)
    if t == "summary":
        return True
    text = json.dumps(record).lower()
    return "compact" in text and ("summary" in text or "context" in text)


def analyze_file(path):
    records = load_lines(path)
    result = {
        "file": path,
        "num_records": len(records),
        "usage_field_found": False,
        "model_totals": defaultdict(lambda: defaultdict(int)),
        "per_turn": [],
        "sidechain_count": 0,
        "subagent_tool_calls": [],
        "compact_events": [],
        "session_ids_seen": [],
        "top_tool_results": [],
        "top_tool_uses": [],
    }

    prev_session = None
    for idx, rec in enumerate(records):
        sid = rec.get("sessionId") or rec.get("session_id")
        if sid and sid != prev_session:
            result["session_ids_seen"].append({"index": idx, "sessionId": sid})
            prev_session = sid

        usage = get_usage(rec)
        model = get_model(rec)
        if usage:
            result["usage_field_found"] = True
            m = model or "unknown_model"
            for k in USAGE_KEYS:
                result["model_totals"][m][k] += int(usage.get(k, 0) or 0)
            result["per_turn"].append({
                "index": idx,
                "model": m,
                "usage": {k: int(usage.get(k, 0) or 0) for k in USAGE_KEYS},
            })

        if is_sidechain(rec):
            result["sidechain_count"] += 1

        for name, length in find_tool_uses(rec):
            result["top_tool_uses"].append({"index": idx, "tool": name, "input_chars": length})
            if name.lower() in ("task", "agent", "subagent"):
                result["subagent_tool_calls"].append({"index": idx, "tool": name})

        for length in find_tool_results(rec):
            result["top_tool_results"].append({"index": idx, "chars": length})

        if looks_like_compact(rec):
            result["compact_events"].append({"index": idx})

    result["top_tool_uses"].sort(key=lambda x: -x["input_chars"])
    result["top_tool_uses"] = result["top_tool_uses"][:10]
    result["top_tool_results"].sort(key=lambda x: -x["chars"])
    result["top_tool_results"] = result["top_tool_results"][:10]

    return result


def print_human(result):
    print(f"\n=== {result['file']} ===")
    print(f"Records parsed: {result['num_records']}")
    if not result["usage_field_found"]:
        print("  [!] No recognizable usage field found — schema may differ from")
        print("      what this script expects. Inspect the file manually before")
        print("      trusting any totals below (there may be none).")

    print("\n-- Token totals by model --")
    for model, totals in result["model_totals"].items():
        total = sum(totals.values())
        print(f"  {model}: {total} tokens")
        for k in USAGE_KEYS:
            if totals.get(k):
                print(f"      {k}: {totals[k]}")

    print(f"\n-- Structural events --")
    print(f"  Sidechain/fork records: {result['sidechain_count']}")
    print(f"  Subagent tool calls detected: {len(result['subagent_tool_calls'])}")
    for s in result["subagent_tool_calls"][:10]:
        print(f"      at record {s['index']}: {s['tool']}")
    print(f"  Compact-like events detected: {len(result['compact_events'])}")
    for c in result["compact_events"]:
        print(f"      at record {c['index']}")
    print(f"  Session ID changes (possible /clear or new session): {len(result['session_ids_seen'])}")
    for s in result["session_ids_seen"]:
        print(f"      at record {s['index']}: sessionId={s['sessionId']}")

    print("\n-- Largest tool_use inputs (top 10) --")
    for t in result["top_tool_uses"]:
        print(f"  record {t['index']}: {t['tool']} — ~{t['input_chars']} chars")

    print("\n-- Largest tool_result payloads (top 10) --")
    for t in result["top_tool_results"]:
        print(f"  record {t['index']}: ~{t['chars']} chars")
    print()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON instead of the human report")
    args = ap.parse_args()

    all_results = [analyze_file(f) for f in args.files]

    if args.json:
        # defaultdicts aren't JSON-serializable directly
        def clean(r):
            r = dict(r)
            r["model_totals"] = {m: dict(t) for m, t in r["model_totals"].items()}
            return r
        print(json.dumps([clean(r) for r in all_results], indent=2))
    else:
        for r in all_results:
            print_human(r)


if __name__ == "__main__":
    main()
