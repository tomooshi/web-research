# shared by deepseek scripts: key loading, POST with retry, ledger. Source, don't execute.
#
# Env:
#   DEEPSEEK_API_KEY     bearer key (else ~/.config/deepseek/api_key)
#   DEEPSEEK_BASE_URL    default https://api.deepseek.com (override for mocks/tests)
#   DEEPSEEK_RETRIES     retries on 408/429/5xx/timeout (default 2, backoff 1s, 2s)
#   DEEPSEEK_TIMEOUT     per-request seconds (default 30)
#   DEEPSEEK_LEDGER      ledger path, or "off" (default ~/.local/state/deepseek/usage.jsonl)
#   DEEPSEEK_RATE_SEARCH / DEEPSEEK_RATE_FETCH   USD per billed call (default 0.00075)

DS_BASE="${DEEPSEEK_BASE_URL:-https://api.deepseek.com}"

ds_key() {
	API_KEY="${DEEPSEEK_API_KEY:-}"
	if [ -z "$API_KEY" ] && [ -r "$HOME/.config/deepseek/api_key" ]; then
		API_KEY="$(tr -d '[:space:]' <"$HOME/.config/deepseek/api_key")"
	fi
	if [ -z "$API_KEY" ]; then
		echo "Error: no DEEPSEEK_API_KEY env var and no ~/.config/deepseek/api_key file" >&2
		exit 1
	fi
}

# ds_post ENDPOINT BODY LEDGER_QUERY     ENDPOINT: search | fetch
# Prints the response body on 200; exits 1 with a mapped message otherwise.
ds_post() {
	local ep="$1" body="$2" q="$3"
	local attempt=0 retries="${DEEPSEEK_RETRIES:-2}" response http_code body_out msg
	while :; do
		response="$(curl -s --max-time "${DEEPSEEK_TIMEOUT:-30}" -w "\n%{http_code}" \
			-H "Authorization: Bearer $API_KEY" \
			-H "Content-Type: application/json" \
			-d "$body" \
			"$DS_BASE/v1/tools/$ep")" || response=$'\n000'
		http_code="$(echo "$response" | tail -n1)"
		body_out="$(echo "$response" | sed '$d')"
		# Docs: retry 408, 429 and 5xx. Do not retry other 4xx unchanged.
		case "$http_code" in
		408 | 429 | 5?? | 000)
			if [ "$attempt" -lt "$retries" ]; then
				attempt=$((attempt + 1))
				sleep "$attempt"
				continue
			fi
			;;
		esac
		break
	done

	if [ "$http_code" != "200" ]; then
		msg="$(printf '%s' "$body_out" | python3 -c '
import json, sys
try:
    print((json.load(sys.stdin).get("error") or {}).get("message", "")[:200])
except Exception:
    print("")' 2>/dev/null)"
		case "$http_code" in
		401) echo "DeepSeek 401: API key missing or rejected (check ~/.config/deepseek/api_key)" >&2 ;;
		402) echo "DeepSeek 402: insufficient balance, top up at platform.deepseek.com" >&2 ;;
		403) echo "DeepSeek 403: fetch rejected by security policy${msg:+: $msg}" >&2 ;;
		404) echo "DeepSeek 404: no usable page content${msg:+: $msg}" >&2 ;;
		429) echo "DeepSeek 429: QPS limit (5/s per account; fetch also per-domain) after $retries retries" >&2 ;;
		000) echo "DeepSeek: request failed or timed out after $retries retries" >&2 ;;
		*) echo "DeepSeek $http_code: ${msg:-$body_out}" >&2 ;;
		esac
		exit 1
	fi

	# Ledger: billed only when search returns results / fetch returns content.
	if [ "${DEEPSEEK_LEDGER:-}" != "off" ]; then
		printf '%s' "$body_out" | EP="$ep" Q="$q" python3 -c '
import json, os, sys, datetime
try:
    d = json.load(sys.stdin)
    ep = os.environ["EP"]
    if ep == "search":
        n = len(d.get("results") or [])
        billed = n > 0
    else:
        n = len(d.get("content") or "")
        billed = n > 0
    rate = float(os.environ.get(f"DEEPSEEK_RATE_{ep.upper()}", "0.00075"))
    rec = {"ts": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "ep": ep, "usd": rate if billed else 0, "n": n, "q": os.environ["Q"][:200]}
    path = os.environ.get("DEEPSEEK_LEDGER") or os.path.join(
        os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
        "deepseek", "usage.jsonl")
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a") as f:
        f.write(json.dumps(rec) + "\n")
except Exception:
    pass' 2>/dev/null || true
	fi
	echo "$body_out"
}
