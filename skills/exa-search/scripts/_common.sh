# shared by exa scripts: key loading, request, ledger. Source, don't execute.

exa_key() {
	API_KEY="${EXA_API_KEY:-}"
	if [ -z "$API_KEY" ] && [ -r "$HOME/.config/exa/api_key" ]; then
		API_KEY="$(cat "$HOME/.config/exa/api_key")"
	fi
	if [ -z "$API_KEY" ]; then
		# exit 3 = not configured (web-research treats it as "skip this engine")
		echo "exa: not configured on this machine (no EXA_API_KEY or ~/.config/exa/api_key). Skip this engine and use another one; do not ask the operator for a key unless they asked to set up Exa." >&2
		exit 3
	fi
}

# exa_post ENDPOINT BODY LEDGER_EP LEDGER_QUERY
exa_post() {
	local endpoint="$1" body="$2" ep="$3" q="$4"
	local response http_code body_out
	response="$(curl -s -w "\n%{http_code}" \
		-H "x-api-key: $API_KEY" \
		-H "Content-Type: application/json" \
		-d "$body" \
		"https://api.exa.ai/$endpoint")"
	http_code="$(echo "$response" | tail -n1)"
	body_out="$(echo "$response" | sed '$d')"
	if [ "$http_code" != "200" ]; then
		echo "Exa API $http_code: $body_out" >&2
		exit 1
	fi
	# Ledger: Exa reports its own cost in the response (costDollars.total).
	if [ "${EXA_LEDGER:-}" != "off" ]; then
		local ledger="${EXA_LEDGER:-${XDG_STATE_HOME:-$HOME/.local/state}/exa/usage.jsonl}"
		mkdir -p "$(dirname "$ledger")" 2>/dev/null || true
		printf '%s' "$body_out" | EP="$ep" Q="$q" LEDGER="$ledger" python3 -c '
import json, os, sys, datetime
try:
    d = json.load(sys.stdin)
    usd = (d.get("costDollars") or {}).get("total", 0)
    rec = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "ep": os.environ["EP"], "usd": usd, "q": os.environ["Q"][:200]}
    with open(os.environ["LEDGER"], "a") as f:
        f.write(json.dumps(rec) + "\n")
except Exception:
    pass' 2>/dev/null || true
	fi
	# Exa 3.0 (2026-10-19): /search may return `warnings` (request fields with no
	# effect) and `notices` (how results were produced, written for the model,
	# e.g. RESTRICTIONS_RELAXED when a site: operator matched nothing). Both stay
	# in the JSON; one line each also goes to stderr so they are not missed.
	printf '%s' "$body_out" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit
for kind in ("warnings", "notices"):
    for w in d.get(kind) or []:
        print("exa", kind[:-1], str(w.get("code", "?")) + ":", w.get("message", ""), file=sys.stderr)' || true
	echo "$body_out"
}
