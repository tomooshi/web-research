#!/bin/bash
set -euo pipefail

# scripts/search.sh — Exa search (POST api.exa.ai/search)
#
# Phrase the query as a *description of the answer*, not keywords
# ("blog posts where practitioners argue against lazy loading" beats
# "lazy loading criticism"). Pass the task goal with -o (Exa `objective`).
#
# Cost (exa.ai/docs/admin/pricing + live costDollars, 2026-10-18):
#   type instant $0.004 · fast/auto $0.007 · deep-lite/deep $0.012 ·
#   deep-reasoning $0.015 — base covers 10 results, +$0.001/result above 10.
#   Highlights and text inside /search did NOT change costDollars (verified
#   live 2026-10-18, 5 results). Only AI summaries bill extra ($0.001/page).
#
# Usage:
#   search.sh [options] "query"
#
# Options:
#   -n NUM       number of results, 1-100 (default 10; >10 bills extra)
#   -t TYPE      instant | fast | auto | deep-lite | deep | deep-reasoning
#                (default auto). "keyword" is no longer documented but still
#                accepted and billed as keyword (2026-10-18).
#   -c CATEGORY  company | publication | news | "personal site" |
#                "financial report" | people. Other strings are only hints
#                ("research paper" returned the same results as publication).
#   -d DOMAINS   comma-separated includeDomains
#   -a DATE      startPublishedDate (YYYY-MM-DD)
#   -b DATE      endPublishedDate (YYYY-MM-DD)
#   -o TEXT      objective: the goal this search serves — which documents
#                should rank first, which to exclude, what facts to pull
#   -h CHARS     highlights per result, max chars (default 600; 0 = Exa decides)
#   -H           no highlights
#   -x           include full page text (contents.text)
#   -j JSON      extra JSON merged into request body
#
# Examples:
#   search.sh "startups building anti-detect browsers"
#   search.sh -c publication -a 2024-01-01 "form validation usability studies"
#   search.sh -t instant "recent product updates from major AI labs"
#   search.sh -o "find the original RRF paper and its main result" "reciprocal rank fusion"
#   search.sh -x -n 5 "essays on digital gardens"      # with full text

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

NUM="" TYPE="" CATEGORY="" DOMAINS="" AFTER="" BEFORE="" TEXT="" EXTRA="" OBJ="" HL=600
while getopts ":n:t:c:d:a:b:o:h:Hxj:" opt; do
	case "$opt" in
	n) NUM="$OPTARG" ;;
	t) TYPE="$OPTARG" ;;
	c) CATEGORY="$OPTARG" ;;
	d) DOMAINS="$OPTARG" ;;
	a) AFTER="$OPTARG" ;;
	b) BEFORE="$OPTARG" ;;
	o) OBJ="$OPTARG" ;;
	h) HL="$OPTARG" ;;
	H) HL="off" ;;
	x) TEXT=1 ;;
	j) EXTRA="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
QUERY="${1:?Usage: search.sh [options] \"query\"}"

exa_key

BODY="$(QUERY="$QUERY" NUM="$NUM" TYPE="$TYPE" CATEGORY="$CATEGORY" DOMAINS="$DOMAINS" \
	AFTER="$AFTER" BEFORE="$BEFORE" TEXT="$TEXT" EXTRA="$EXTRA" OBJ="$OBJ" HL="$HL" python3 -c '
import json, os
b = {"query": os.environ["QUERY"]}
if os.environ.get("NUM"): b["numResults"] = int(os.environ["NUM"])
if os.environ.get("TYPE"): b["type"] = os.environ["TYPE"]
if os.environ.get("CATEGORY"): b["category"] = os.environ["CATEGORY"]
if os.environ.get("DOMAINS"): b["includeDomains"] = os.environ["DOMAINS"].split(",")
if os.environ.get("AFTER"): b["startPublishedDate"] = os.environ["AFTER"] + "T00:00:00.000Z"
if os.environ.get("BEFORE"): b["endPublishedDate"] = os.environ["BEFORE"] + "T23:59:59.999Z"
if os.environ.get("OBJ"): b["objective"] = os.environ["OBJ"][:4096]
contents = {}
hl = os.environ.get("HL", "600")
if hl != "off":
    contents["highlights"] = True if int(hl) <= 0 else {"maxCharacters": int(hl)}
if os.environ.get("TEXT"): contents["text"] = True
if contents: b["contents"] = contents
extra = os.environ.get("EXTRA")
if extra:
    m = json.loads(extra)
    if not isinstance(m, dict): raise SystemExit("-j must be a JSON object")
    b.update(m)
print(json.dumps(b))')"

exa_post search "$BODY" search "$QUERY"
