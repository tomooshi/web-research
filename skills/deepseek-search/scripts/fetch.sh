#!/bin/bash
set -euo pipefail

# scripts/fetch.sh — DeepSeek Fetch API (POST api.deepseek.com/v1/tools/fetch)
#
# One URL -> {"title", "content"} with content as Markdown.
# Cost: $0.00075/fetch, billed only when content comes back. 403 (security
# policy) and 404 (no usable content) are free. 5 QPS per account plus a
# per-domain QPS limit (both answer 429; the script retries twice).
#
# Output quirk (verified live 2026-10-18): `content` backslash-escapes almost
# every punctuation mark (\# \. \- \( \/ ...), which breaks headings and
# tables. This script removes those escapes. Use -r for the raw response.
# The content also has no links and no code fences.
#
# Usage:
#   fetch.sh [-r] URL

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

RAW=""
if [ "${1:-}" = "-r" ]; then RAW=1; shift; fi
URL="${1:?Usage: fetch.sh [-r] URL}"
case "$URL" in
http://* | https://*) ;;
*) echo "Error: URL must start with http:// or https://" >&2; exit 2 ;;
esac

BODY="$(URL="$URL" python3 -c 'import json, os; print(json.dumps({"url": os.environ["URL"]}))')"

ds_key
OUT="$(ds_post fetch "$BODY" "$URL")" || exit 1
if [ -n "$RAW" ]; then
	printf '%s\n' "$OUT"
	exit 0
fi
printf '%s' "$OUT" | python3 -c '
import json, re, sys
d = json.load(sys.stdin)
# CommonMark backslash escapes -> plain characters (\\ -> \ as well).
d["content"] = re.sub(r"\\([!-/:-@\[-`{-~])", r"\1", d.get("content") or "")
print(json.dumps(d, ensure_ascii=False))'
