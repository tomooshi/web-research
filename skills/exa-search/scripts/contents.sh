#!/bin/bash
set -euo pipefail

# scripts/contents.sh — Exa page contents (POST api.exa.ai/contents)
# $0.001/page per content type — 4x cheaper than Kagi extract; often succeeds
# where Kagi's crawler fails. Serves from Exa's cache unless told otherwise;
# check statuses[].source (cached | crawled).
#
# Usage:
#   contents.sh URL [URL ...]
#   contents.sh -s URL          # + AI summary (+$0.001/page)
#   contents.sh -l URL          # fresh fetch (maxAgeHours=0)
#   contents.sh -a 168 URL      # use cache only if younger than 168 h
#
# `livecrawl` is deprecated (exa-spec.yaml, 2026-10-18: "does not guarantee
# freshly fetched content"); this script uses `maxAgeHours` instead.
# maxAgeHours=0 returned source "crawled" and the current page where the
# cache served a stale one (verified 2026-10-18).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/_common.sh"

SUMMARY="" MAXAGE=""
while getopts ":sla:" opt; do
	case "$opt" in
	s) SUMMARY=1 ;;
	l) MAXAGE=0 ;;
	a) MAXAGE="$OPTARG" ;;
	\?) echo "Unknown option: -$OPTARG" >&2; exit 2 ;;
	:) echo "Option -$OPTARG requires an argument" >&2; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
[ $# -ge 1 ] || { echo "Usage: contents.sh [-s] [-l | -a HOURS] URL [URL ...]" >&2; exit 2; }

exa_key

BODY="$(SUMMARY="$SUMMARY" MAXAGE="$MAXAGE" python3 -c '
import json, os, sys
b = {"urls": sys.argv[1:], "text": True}
if os.environ.get("SUMMARY"): b["summary"] = True
if os.environ.get("MAXAGE", "") != "": b["maxAgeHours"] = int(os.environ["MAXAGE"])
print(json.dumps(b))' "$@")"

exa_post contents "$BODY" contents "$1"
