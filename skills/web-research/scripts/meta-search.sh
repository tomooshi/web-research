#!/bin/bash
set -uo pipefail

# scripts/meta-search.sh — parallel fan-out to Kagi, Marginalia, Exa and
# DeepSeek, fused into one ranked list.
#
# Runs engines concurrently, canonicalizes URLs (arXiv IDs, DOIs, tracking
# params, mobile hosts), dedupes, and fuses ranks with Reciprocal Rank Fusion
# (Cormack et al., SIGIR 2009, k=60). With k=60 and <=50 results per engine,
# any multi-engine hit outranks any single-engine hit, so cross-engine
# agreement still sorts first. Agreement across retrieval mechanisms is the
# strongest relevance vote this stack can produce.
#
# Cost per call: kagi $0.012 · exa $0.007 auto / $0.004 instant (highlights included) ·
#                deepseek $0.00075 (only if non-empty) · marginalia 1 quota.
# Tolerates engines failing — you get whatever succeeded.
#
# Usage:
#   meta-search.sh [options] "query"
#
# Options:
#   -c COUNT    results per engine (default 10; deepseek caps at 50)
#   -e ENGINES  comma list or alias (resolved by scripts/_engines.py):
#                 default = configured default, else kagi,marginalia
#                           (filled from usable engines up to two)
#                 both    = same as default (old name)
#                 all     = every usable engine
#                 cheap   = marginalia,deepseek (loops: free + $0.00075)
#               or any subset, e.g. kagi,deepseek. An engine without a key,
#               not installed, or disabled in ~/.config/web-research/config
#               reports "skipped: <reason>". Run scripts/engines.sh to see
#               what this machine has.
#   -w WORKFLOW kagi workflow: search|news|images|videos|podcasts (kagi side only)
#   -o GOAL     the user's question or task goal: sent as deepseek ori_question
#               (truncated to 128 chars) and exa objective (4096 chars)
#   -s CHARS    snippet cap (default 500; 0 = no cap)
#   -i          exa type instant: $0.004 instead of $0.007 (lower latency)
#
# Output (JSON):
#   {
#     "query": "...",
#     "engines": {"kagi": "ok", "deepseek": "skipped: ...", "exa": "error: ..."},
#     "cost": {"kagi": 0.012, "deepseek": 0.00075, "marginalia": "1 quota"},
#     "overlap": 2,                       // results found by 2+ engines
#     "results": [
#       {"url", "title", "snippet",
#        "sources": ["kagi","deepseek"],  // multi-engine hits sort first
#        "rank": {"kagi": 1, "deepseek": 3},
#        "score": 0.0323,                 // RRF: sum of 1/(60+rank)
#        "published": "2026-06-01...",    // first date any engine reported
#        "variants": [...],               // other URLs merged into this one
#        "kagi_type": "search",           // kagi result group
#        "paywalled": true, "ai_generated": true,   // kagi props, if true
#        "marginalia_quality": 3.05,      // lower = better
#        "deepseek_rerank": 2.4,          // 0-3, >=1.5 = high quality
#        "authority": 3,                  // deepseek 0-4, >=3 = authoritative
#        "site_name": "..."}
#     ]
#   }

# Engine skills are siblings of this skill (skills/<name>/scripts). Override
# with SEARCH_SKILLS_DIR if you installed them somewhere else.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${SEARCH_SKILLS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
KAGI_SCRIPTS="$SKILLS_ROOT/kagi-search/scripts"
MARG_SCRIPTS="$SKILLS_ROOT/marginalia-search/scripts"
EXA_SCRIPTS="$SKILLS_ROOT/exa-search/scripts"
DS_SCRIPTS="$SKILLS_ROOT/deepseek-search/scripts"

COUNT=10
ENGINE="default"
WORKFLOW=""
ORIQ=""
SNIP=500
EXA_TYPE=""

while getopts ":c:e:w:o:s:i" opt; do
	case "$opt" in
	c) COUNT="$OPTARG" ;;
	e) ENGINE="$OPTARG" ;;
	w) WORKFLOW="$OPTARG" ;;
	o) ORIQ="$OPTARG" ;;
	s) SNIP="$OPTARG" ;;
	i) EXA_TYPE=instant ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))

QUERY="${1:?Usage: meta-search.sh [options] \"query\"}"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# Resolve -e against what this machine can use (keys, installs, config).
# _engines.py also rejects unknown engine names (exit 2).
RESOLVED="$(python3 "$SCRIPT_DIR/_engines.py" resolve "$ENGINE")" || exit 2
RUN="$(printf '%s' "$RESOLVED" | TMPD="$TMPD" python3 -c '
import json, os, sys
r = json.load(sys.stdin)
files = {"kagi": "kagi", "marginalia": "marg", "exa": "exa", "deepseek": "ds"}
for e, why in r["skip"].items():  # reported as "skipped: <why>"
    with open(os.path.join(os.environ["TMPD"], files[e] + ".skip"), "w") as f:
        f.write(why)
print(",".join(r["run"]))')"
[ -n "$RUN" ] || echo "meta-search: no usable engine for -e '$ENGINE' (see scripts/engines.sh)" >&2

wants() { case ",$RUN," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

PIDS=()
if wants kagi; then
	KARGS=(-l "$COUNT")
	[ -n "$WORKFLOW" ] && KARGS+=(-w "$WORKFLOW")
	bash "$KAGI_SCRIPTS/search-v1.sh" "${KARGS[@]}" "$QUERY" \
		>"$TMPD/kagi.json" 2>"$TMPD/kagi.err" &
	PIDS+=($!)
fi
if wants marginalia; then
	bash "$MARG_SCRIPTS/search.sh" -c "$COUNT" "$QUERY" \
		>"$TMPD/marg.json" 2>"$TMPD/marg.err" &
	PIDS+=($!)
fi
if wants exa; then
	# Highlights are free inside /search (live costDollars, 2026-10-18).
	EARGS=(-n "$COUNT" -h "$((SNIP > 0 ? SNIP : 0))")
	[ -n "$EXA_TYPE" ] && EARGS+=(-t "$EXA_TYPE")
	[ -n "$ORIQ" ] && EARGS+=(-o "$ORIQ")
	bash "$EXA_SCRIPTS/search.sh" "${EARGS[@]}" "$QUERY" \
		>"$TMPD/exa.json" 2>"$TMPD/exa.err" &
	PIDS+=($!)
fi
if wants deepseek; then
	QLEN="$(printf '%s' "$QUERY" | python3 -c 'import sys; print(len(sys.stdin.read()))')"
	if [ "$QLEN" -gt 128 ]; then
		echo "query is $QLEN chars, DeepSeek allows 128" >"$TMPD/ds.skip"
	else
		DARGS=(-c "$((COUNT > 50 ? 50 : COUNT))")
		[ -n "$ORIQ" ] && DARGS+=(-o "$ORIQ")
		bash "$DS_SCRIPTS/search.sh" "${DARGS[@]}" "$QUERY" \
			>"$TMPD/ds.json" 2>"$TMPD/ds.err" &
		PIDS+=($!)
	fi
fi
[ "${#PIDS[@]}" -gt 0 ] && { wait "${PIDS[@]}" 2>/dev/null || true; }

# Surface the marginalia quota line (its stderr) so the agent sees it.
# (Redirect order matters: >&2 first, then silence grep's own errors.)
grep -h 'marginalia quota' "$TMPD/marg.err" >&2 2>/dev/null || true

QUERY="$QUERY" TMPD="$TMPD" SNIP="$SNIP" python3 <<'PY'
import html, json, os, re, sys
from urllib.parse import parse_qsl, unquote, urlencode, urlsplit

tmpd = os.environ["TMPD"]
SNIP = int(os.environ.get("SNIP") or 0)
RRF_K = 60

TRACKING = re.compile(
    r"^(utm_.*|fbclid|gclid|dclid|msclkid|mc_cid|mc_eid|igshid|ref_src|_hsenc|_hsmi|spm)$")
ARXIV = re.compile(r"^/(?:abs|pdf|html)/([a-z\-]+/\d{7}|\d{4}\.\d{4,5})(?:v\d+)?(?:\.pdf)?$", re.I)
ARXIV_HOSTS = ("arxiv.org", "export.arxiv.org", "ar5iv.labs.arxiv.org", "ar5iv.org")
DOI = re.compile(r"(10\.\d{4,9}/[^\s?#]+)")
DOI_PATH = re.compile(r"/doi/(?:(?:abs|full|pdf|epdf|book)/)?(10\.\d{4,9}/[^\s?#]+)", re.I)
# A leading lang-region path segment (learn.microsoft.com/el-gr/...): same doc.
# Language codes are whitelisted so that /ab-cd/ user or org names do not match.
LOCALE = re.compile(
    r"^/((?:en|de|fr|es|it|pt|ja|ko|zh|ru|pl|nl|sv|da|fi|nb|cs|tr|el|id|th|vi|ar|he|hu|ro|uk|bg|hr|sk|sl|ms|hi)"
    r"-[a-z]{2})(?=/)", re.I)
DOI_HOSTS = ("doi.org", "dx.doi.org", "dl.acm.org", "onlinelibrary.wiley.com",
             "link.springer.com", "journals.plos.org", "pubs.acs.org")


def canon(url):
    """Canonical key for cross-engine dedupe. Same document -> same key."""
    s = urlsplit(url.strip())
    host = s.netloc.lower().split("@")[-1]
    host = re.sub(r":(80|443)$", "", host)
    host = host[4:] if host.startswith("www.") else host
    host = host[2:] if host.startswith("m.") else host
    host = host.replace(".m.wikipedia.org", ".wikipedia.org")
    path = unquote(s.path)
    if host in ARXIV_HOSTS:
        m = ARXIV.match(path.rstrip("/"))
        if m:
            return f"arxiv:{m.group(1).lower()}"
    # DOI: known publisher hosts anywhere in the path; any host (incl. library
    # proxies such as dl-acm-org.ezproxy...) when the path has /doi/10.x
    m = DOI.search(path) if host in DOI_HOSTS else DOI_PATH.search(path)
    if m:
        return "doi:" + re.sub(r"(/(abs|full|pdf|epdf))+$", "", m.group(1).lower()).rstrip("/")
    path = LOCALE.sub("", path)
    path = re.sub(r"/(index\.html?|index\.php)$", "", path).rstrip("/")
    params = sorted((k, v) for k, v in parse_qsl(s.query, keep_blank_values=True)
                    if not TRACKING.match(k.lower()))
    q = f"?{unquote(urlencode(params))}" if params else ""
    return f"{host}{path}{q}"


def clean(text):
    text = html.unescape(re.sub(r"<[^>]+>", "", text or ""))
    text = re.sub(r"\s+", " ", text).strip()
    if SNIP and len(text) > SNIP:
        text = text[:SNIP].rsplit(" ", 1)[0] + " …"
    return text


def load(name):
    skip = os.path.join(tmpd, f"{name}.skip")
    if os.path.exists(skip):
        with open(skip) as f:
            return None, f"skipped: {f.read().strip()}"
    path = os.path.join(tmpd, f"{name}.json")
    errp = os.path.join(tmpd, f"{name}.err")
    if not os.path.exists(path) and not os.path.exists(errp):
        return None, "not requested"
    try:
        with open(path) as f:
            raw = f.read()
        if not raw.strip():
            raise ValueError("empty response")
        return json.loads(raw), "ok"
    except Exception as e:
        err = ""
        try:
            with open(errp) as f:
                err = " ".join(l.strip() for l in f if "marginalia quota" not in l).strip()
        except OSError:
            pass
        return None, f"error: {(err or str(e))[:300]}"


merged = {}   # canon key -> record
order = []

def add(url, title, snippet, source, rank, published=None, **extra):
    key = canon(url)
    if key not in merged:
        merged[key] = {"url": url, "title": title or "", "snippet": "",
                       "sources": [], "rank": {}, "score": 0.0}
        order.append(key)
    rec = merged[key]
    if source not in rec["sources"]:  # a repeat inside one engine is not agreement
        rec["sources"].append(source)
        rec["rank"][source] = rank
        rec["score"] += 1.0 / (RRF_K + rank)
    if url != rec["url"] and url not in rec.setdefault("variants", []):
        rec["variants"].append(url)
        # Prefer an English locale copy as the representative URL.
        lm_new, lm_old = LOCALE.match(urlsplit(url).path), LOCALE.match(urlsplit(rec["url"]).path)
        if lm_new and lm_old and lm_new.group(1).lower().startswith("en") \
                and not lm_old.group(1).lower().startswith("en"):
            rec["variants"].remove(url)
            rec["variants"].append(rec["url"])
            rec["url"] = url
    snippet = clean(snippet)
    if len(snippet) > len(rec["snippet"]):  # the longer snippet wins
        rec["snippet"] = snippet
    if not rec["title"] and title:
        rec["title"] = title
    if published and not rec.get("published"):
        rec["published"] = published
    for k, v in extra.items():
        if v is not None and v is not False:
            rec.setdefault(k, v)


engines, cost = {}, {}

def status_for(label, fname):
    data, st = load(fname)
    if st != "not requested":
        engines[label] = st
    return data

kagi = status_for("kagi", "kagi")
if kagi:
    cost["kagi"] = 0.012
    rank = 0
    for group, items in (kagi.get("data") or {}).items():
        if group == "related_search" or not isinstance(items, list):
            continue  # related_search holds relative URLs, not results
        for item in items:
            url = item.get("url")
            if not url or not url.startswith("http"):
                continue
            rank += 1
            props = item.get("props") or {}
            add(url, clean(item.get("title")), item.get("snippet"), "kagi", rank,
                published=item.get("time"), kagi_type=group,
                paywalled=props.get("paywalled"), ai_generated=props.get("ai_generated"))

marg = status_for("marginalia", "marg")
if marg:
    cost["marginalia"] = "1 quota"
    for i, item in enumerate(marg.get("results") or [], 1):
        add(item["url"], item.get("title"), item.get("description"), "marginalia", i,
            marginalia_quality=item.get("quality"))

exa = status_for("exa", "exa")
if exa:
    cost["exa"] = (exa.get("costDollars") or {}).get("total", 0.007)
    for i, item in enumerate(exa.get("results") or [], 1):
        snippet = " ... ".join(item.get("highlights") or []) or item.get("text")
        add(item["url"], item.get("title"), snippet, "exa", i,
            published=item.get("publishedDate"))

ds = status_for("deepseek", "ds")
if ds:
    rows = ds.get("results") or []
    cost["deepseek"] = 0.00075 if rows else 0
    for i, item in enumerate(rows, 1):
        # DeepSeek returns passages: URLs carry synthetic fragments (#1, #9, #h).
        add(item["url"].split("#", 1)[0], item.get("title"), item.get("summary") or item.get("snippet"),
            "deepseek", i, published=item.get("date"),
            deepseek_rerank=item.get("rerank_score"),
            authority=item.get("authority") if item.get("authority", -1) >= 0 else None,
            site_name=item.get("site_name"))

for rec in merged.values():
    rec["score"] = round(rec["score"], 4)

results = sorted((merged[k] for k in order),
                 key=lambda r: (-r["score"], -len(r["sources"])))
overlap = sum(1 for r in results if len(r["sources"]) > 1)

print(json.dumps({
    "query": os.environ["QUERY"],
    "engines": engines,
    "cost": cost,
    "overlap": overlap,
    "results": results,
}, ensure_ascii=False))

# Fail only if no engine returned a result set.
if not any(v == "ok" for v in engines.values()):
    sys.exit(1)
PY
