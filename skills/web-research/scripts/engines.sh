#!/bin/bash
# scripts/engines.sh — show which search engines this machine can use.
#
# Reports, per engine: skill installed, enabled, part of the default fan-out,
# and where its key comes from (env var or file). Never prints key values.
#
# Usage:
#   engines.sh           human-readable table
#   engines.sh --json    machine-readable
#
# Select engines (optional; without it every engine with a key is used):
#   ~/.config/web-research/config
#     engines = kagi, exa          # allowed engines
#     default = kagi, exa          # what a plain meta-search.sh call runs
#     ladder  = exa, kagi, curl, playwright, camoufox, wayback
#   or env WEB_RESEARCH_ENGINES / WEB_RESEARCH_DEFAULT / WEB_RESEARCH_LADDER

exec python3 "$(dirname "${BASH_SOURCE[0]}")/_engines.py" status "${1:-}"
