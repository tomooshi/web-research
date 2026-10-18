#!/bin/bash
# scripts/doctor.sh — check that the web-research skills are ready to use.
#
# Checks required tools, the five skill folders, API keys for each engine,
# engine selection (~/.config/web-research/config), and the optional
# extraction extras used by fetch-page.sh. Makes NO network calls unless
# --live is given. Never prints key values.
#
# Every engine is optional: a missing key only removes that engine.
#
# Usage:
#   doctor.sh           # offline checks only (free)
#   doctor.sh --live    # + one real query per usable engine
#                       #   (kagi ~$0.012, exa ~$0.007, deepseek ~$0.00075,
#                       #    marginalia 1 quota)
#
# Exit status: 0 if the required tools exist and at least one engine is
# usable, else 1.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_ROOT="${SEARCH_SKILLS_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
PY="${FETCH_PYTHON:-python3}"
LIVE=""
[ "${1:-}" = "--live" ] && LIVE=1

FAIL=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
off() { printf '  \033[2m–\033[0m %s\n' "$1"; }  # optional, not set up: not a problem
warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=1; }

echo "Required tools"
for t in bash curl python3; do
	if command -v "$t" >/dev/null 2>&1; then ok "$t"; else bad "$t not found"; fi
done
command -v python3 >/dev/null 2>&1 || { echo; echo "Not ready — install python3."; exit 1; }

echo "Skills (in $SKILLS_ROOT)"
if [ -f "$SKILLS_ROOT/web-research/SKILL.md" ]; then ok "web-research"; else bad "web-research missing (set SEARCH_SKILLS_DIR?)"; fi
for s in kagi-search marginalia-search exa-search deepseek-search; do
	if [ -f "$SKILLS_ROOT/$s/SKILL.md" ]; then ok "$s"; else off "$s not installed (optional; skipped)"; fi
done

echo "API keys and engine selection"
STATUS="$(SEARCH_SKILLS_DIR="$SKILLS_ROOT" python3 "$SCRIPT_DIR/_engines.py" status --json)" || { bad "engine config: $STATUS"; STATUS=""; }
USABLE=""
if [ -n "$STATUS" ]; then
	while IFS=$'\t' read -r level msg; do
		case "$level" in
		ok) ok "$msg" ;;
		off) off "$msg" ;;
		warn) warn "$msg" ;;
		info) echo "    $msg" ;;
		esac
	done < <(printf '%s' "$STATUS" | python3 -c '
import json, sys
d = json.load(sys.stdin)
signup = {"kagi": "https://kagi.com/api", "exa": "https://dashboard.exa.ai",
          "deepseek": "https://platform.deepseek.com",
          "marginalia": "https://about.marginalia-search.com/article/api/"}
for name, r in d["engines"].items():
    if r["usable"]:
        if r.get("public"):
            print("off\t" + f"{name}: no personal key, uses the shared public key (rate-limited; optional free key: {signup[name]})")
        else:
            src = r["key"]
            print("ok\t" + f"{name} ({src})")
    elif r["reason"] == "not configured":
        print("off\t" + f"{name}: not configured (optional; key from {signup[name]})")
    else:
        why = r["reason"]
        print("off\t" + f"{name}: {why} (optional)")
print("info\t" + "default fan-out: " + (", ".join(d["default"]) or "none"))
print("info\t" + "fetch ladder: " + " -> ".join(d["ladder"]))
cfg = d["config"] if d["config_present"] else d["config"] + " (absent: every engine with a key is used)"
print("info\t" + "config: " + cfg)')
	USABLE="$(printf '%s' "$STATUS" | python3 -c 'import json,sys; print(",".join(n for n,r in json.load(sys.stdin)["engines"].items() if r["usable"]))')"
	[ -n "$USABLE" ] || bad "no usable search engine — add at least one API key (see README → API keys)"
fi

echo "Optional fetch-page.sh extras (free fallback rungs)"
if "$PY" -c "import bs4" 2>/dev/null; then
	ok "beautifulsoup4 ($PY) — enables curl / playwright / camoufox / wayback rungs"
else
	warn "beautifulsoup4 missing for $PY — local rungs disabled (pip install beautifulsoup4, or set FETCH_PYTHON)"
fi
if "$PY" -c "import playwright" 2>/dev/null; then
	ok "playwright ($PY)"
else
	warn "playwright missing — JS-rendered page rung disabled (pip install playwright && playwright install chromium)"
fi
CF="${CAMOUFOX_PYTHON:-}"
if [ -z "$CF" ]; then
	if [ -x "$HOME/.venvs/camoufox/bin/python" ]; then CF="$HOME/.venvs/camoufox/bin/python"; else CF="$PY"; fi
fi
if "$CF" -c "import camoufox" 2>/dev/null; then
	ok "camoufox ($CF)"
else
	warn "camoufox missing — anti-detect rung disabled (optional; see README)"
fi

has() { case ",$USABLE," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

if [ -n "$LIVE" ]; then
	echo "Live checks"
	TMPE="$(mktemp)"
	if has kagi; then
		if bash "$SKILLS_ROOT/kagi-search/scripts/search-v1.sh" -l 1 "kagi search api" >/dev/null 2>"$TMPE"; then
			ok "kagi search"
		else bad "kagi search: $(head -c 200 "$TMPE")"; fi
	fi
	if has exa; then
		if bash "$SKILLS_ROOT/exa-search/scripts/search.sh" -t instant -n 1 "exa neural search api" >/dev/null 2>"$TMPE"; then
			ok "exa search"
		else bad "exa search: $(head -c 200 "$TMPE")"; fi
	fi
	if has deepseek; then
		if bash "$SKILLS_ROOT/deepseek-search/scripts/search.sh" -c 1 "deepseek api" >/dev/null 2>"$TMPE"; then
			ok "deepseek search"
		else bad "deepseek search: $(head -c 200 "$TMPE")"; fi
	fi
	if has marginalia; then
		if bash "$SKILLS_ROOT/marginalia-search/scripts/search.sh" -c 1 "linear b" >/dev/null 2>"$TMPE"; then
			ok "marginalia search ($(grep -o 'quota: .*' "$TMPE" || echo 'no ledger'))"
		else bad "marginalia search: $(grep -v quota "$TMPE" | head -c 200)"; fi
	fi
	rm -f "$TMPE"
fi

echo
if [ "$FAIL" = 0 ]; then
	echo "Ready. Usable engines: ${USABLE//,/, }. Engines marked – are optional and are skipped without errors."
else
	echo "Not ready — fix the ✗ items above."
fi
exit "$FAIL"
