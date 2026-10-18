#!/bin/bash
set -euo pipefail

# scripts/search.sh — DeepSeek Search API (POST api.deepseek.com/v1/tools/search)
#
# DeepSeek's in-house index. Each result carries a query-focused `summary`
# (600-800 chars, written for a model), `rerank_score` (0-3, >=1.5 = high
# quality), `authority` (0-4, >=3 = highly authoritative, -1 = unknown) and
# `date` (RFC 3339 or null).
#
# Cost: $0.00075/search, billed only when `results` is non-empty. `count`
#       does not change the price. Failed and empty searches are free.
# Limits: 5 QPS per account. Query is 1-128 Unicode characters.
#
# Usage:
#   search.sh [options] "query"
#
# Options:
#   -c COUNT     results, 1-50 (default 10)
#   -o QUESTION  the user's original question (ori_question, <=128 chars,
#                truncated) — helps query understanding
#   -x           need_content: include full page content in `content`
#   -L IP        localization: an IP address to localize results
#
# Query operators (inline, from the docs):
#   site:a.com  site:a.com OR site:b.org  -site:x.com  -term  "exact phrase"
#   -"exact phrase"  lang:zh,en  after:2025  after:2025-01-01  before:2026-06-01
#
# Examples:
#   search.sh "deepseek v4 release"
#   search.sh -c 20 "rank fusion site:arxiv.org after:2024"
#   search.sh "大模型 推理 优化 lang:zh"
#   search.sh -o "Is RRF better than score fusion?" "reciprocal rank fusion evaluation"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

COUNT="" ORIQ="" CONTENT="" LOC=""
while getopts ":c:o:xL:" opt; do
	case "$opt" in
	c) COUNT="$OPTARG" ;;
	o) ORIQ="$OPTARG" ;;
	x) CONTENT=1 ;;
	L) LOC="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
QUERY="${1:?Usage: search.sh [options] \"query\"}"

BODY="$(QUERY="$QUERY" COUNT="$COUNT" ORIQ="$ORIQ" CONTENT="$CONTENT" LOC="$LOC" python3 -c '
import json, os, sys
q = os.environ["QUERY"]
if not q.strip():
    raise SystemExit("query is all whitespace")
if len(q) > 128:
    raise SystemExit(f"query is {len(q)} chars; DeepSeek allows 128. Shorten it (start wide, then narrow).")
b = {"query": q}
if os.environ.get("COUNT"):
    c = int(os.environ["COUNT"])
    if not 1 <= c <= 50:
        raise SystemExit("-c must be 1-50")
    b["count"] = c
oq = os.environ.get("ORIQ", "").strip()
if oq:
    if len(oq) > 128:
        print("warning: -o truncated to 128 chars", file=sys.stderr)
    b["ori_question"] = oq[:128]
if os.environ.get("CONTENT"): b["need_content"] = True
if os.environ.get("LOC"): b["localization"] = os.environ["LOC"]
print(json.dumps(b, ensure_ascii=False))')" || exit 2

ds_key
ds_post search "$BODY" "$QUERY"
