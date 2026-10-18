---
name: exa-search
description: "Neural/semantic web search via the Exa API (api.exa.ai) — retrieval by meaning (custom-trained embeddings over Exa's own crawl), not keywords. THE engine for conceptual queries ('essays arguing X', 'companies building Y'), publication/company/people category search, query-relevant highlights (free inside search), similarity expansion (find-similar.sh — deprecated by Exa but still working), and cheap page extraction (contents.sh, $0.001/page, 4x cheaper than Kagi extract, maxAgeHours freshness control). Use when the query describes what the answer looks like rather than what words it contains, when expanding from a known-good source, or for 'papers about', 'startups similar to', 'personal sites discussing'. Prefer kagi-search for operator-precision (site:/filetype:), news workflows, X/Twitter; marginalia-search for indie/old-web; deepseek-search for the cheapest search/fetch. Optional engine: needs EXA_API_KEY or ~/.config/exa/api_key (free tier $10 credits/month); when not configured, skip it and do not ask the operator for a key."
---

# Exa Search (neural)

Exa runs its own crawler, its own index, and retrieval by **custom-trained transformer embeddings** served from its own vector database. Verified live 2026-09-01/02; **API surface re-audited 2026-10-18** against `exa.ai/docs/exa-spec.yaml` (v2.0.0, the documented source of truth) and live calls.

Docs moved to `exa.ai/docs` (index: `exa.ai/docs/llms.txt`; every page has a `.md` variant).

## Setup

> **Optional engine.** On a machine without a Exa key, the scripts print `exa: not configured` and exit 3. Skip Exa and use another engine (`../web-research/SKILL.md` → *If an engine is not configured*). Do not ask the operator for a key unless they asked to set up Exa.

Script paths below (`./scripts/...`) are relative to this skill's directory.

Create a key at https://dashboard.exa.ai (free tier: **$10 credits/month**, reset on the 1st; balance shown there). The scripts read `EXA_API_KEY`, else `~/.config/exa/api_key`:

```bash
mkdir -p ~/.config/exa
printf '%s' 'YOUR_KEY' > ~/.config/exa/api_key
chmod 600 ~/.config/exa/api_key
```

Requires `bash`, `curl`, `python3` (stdlib only).

Auth header `x-api-key` still works; the docs now show `Authorization: Bearer`.

## The habits that matter

1. **Phrase queries as a description of the answer, not keywords.** ✅ "blog posts where practitioners argue against lazy loading images" — ❌ "lazy loading criticism".
2. **Pass the goal with `-o`** (`objective`, ≤4096 chars). Exa's own guidance for agents: "Goal for this search turn; say which documents should rank first, which should be excluded, and what specific facts or figures to pull from them."
3. **Read highlights, not full text.** `search.sh` asks for highlights by default (Exa's recommended baseline). Exa reports that 500 chars of highlights match the SimpleQA accuracy of 8,000 chars of page text.
4. **Add hard constraints only when a violating result is useless** (domains, dates). Change `-t` last: a different mode cannot repair an underspecified query.

## Usage

```bash
./scripts/search.sh "essays on why personal websites matter"           # highlights, 600 chars
./scripts/search.sh -o "prefer official docs; pull the default k value" "reciprocal rank fusion"
./scripts/search.sh -c publication -a 2024-01-01 "form validation usability"
./scripts/search.sh -t instant "recent product updates from major AI labs"  # $0.004
./scripts/search.sh -d "nngroup.com,baymard.com" "checkout flow research"
./scripts/search.sh -x -n 5 "digital garden essays"       # + full text (no extra cost observed)
./scripts/search.sh -H "query"                            # no highlights
./scripts/search.sh -h 0 "query"                          # highlights sized by Exa

./scripts/find-similar.sh https://lawsofux.com/           # DEPRECATED endpoint, still works
./scripts/find-similar.sh -e -n 10 https://seirdy.one/    # exclude source domain

./scripts/contents.sh URL1 URL2                           # $0.001/page, cache when available
./scripts/contents.sh -l URL                              # fresh fetch (maxAgeHours=0)
./scripts/contents.sh -a 168 URL                          # refetch if cache is older than 7 days
./scripts/contents.sh -s URL                              # + AI summary (+$0.001/page)
```

### Search types (`-t`)

| Type | Price | Use |
|---|---|---|
| `instant` | **$0.004** | lowest latency; loops, autocomplete-like use |
| `fast` | $0.007 | interactive |
| `auto` (default) | $0.007 | balanced, recommended |
| `deep-lite` | $0.012 | ~4 s synthesis |
| `deep` | $0.012 | 4-15 s multi-step research with synthesis |
| `deep-reasoning` | $0.015 | 12-40 s, harder research |

`neural` and `keyword` are **no longer in the spec**. `-t keyword` is still accepted and billed as `keyword` (live 2026-10-18), so it may still help exact-string lookups, but it can disappear without notice. For exact strings, prefer Kagi.

### Categories (`-c`)

Documented: `company`, `publication`, `news`, `personal site`, `financial report`, `people`. Other strings are accepted only as **hints**. `"research paper"` returned the same results as `publication` (live 2026-10-18). `github`, `tweet`, `pdf` and `linkedin profile` are no longer listed. `company` and `people` reject date filters (HTTP 400); `people` also rejects `excludeDomains`.

## Response shape

```json
{
  "requestId": "...", "resolvedSearchType": "", "searchTime": 4655.2,
  "costDollars": {"total": 0.007, "search": {"neural": 0.007}},
  "results": [{"id": "...", "url": "...", "title": "...",
               "publishedDate": "2026-04-17T...", "author": "...",
               "highlights": ["..."],
               "text": "(only with -x)",
               "entities": [{"type": "publication", "properties": {"year": 2020, "citationCount": 8, "authors": [...]}}]}]
}
```

- `costDollars.total` is the authoritative per-request cost — the ledger records it directly.
- `resolvedSearchType` now comes back as an empty string. Do not rely on it.
- `entities` appears on some results (publications carry year, venue, citation count, authors).
- `highlights.maxCharacters` is a **soft** limit: a 600-char request returned a 1,264-char highlight.
- `/contents` responses include `statuses[]` with `source: cached | crawled` and per-URL errors.

## Freshness: maxAgeHours (livecrawl is deprecated)

`livecrawl` is deprecated: the spec says it "does not guarantee freshly fetched content". Use `maxAgeHours` (`contents.sh -a HOURS`, `-l` = 0):

| `maxAgeHours` | Behavior |
|---|---|
| omitted | cache when available, live fetch otherwise |
| `N` (1-720) | cache only if younger than N hours, else fetch fresh |
| `0` | always fetch fresh |
| `-1` | cache only |

Verified 2026-10-18: without it, `api-docs.deepseek.com/guides/search` (a new page) came back as a *different* cached page (the docs index, "Your First API Call") with `status: success`, `source: cached` and the requested URL. With `maxAgeHours: 0` or `168`, it came back `source: crawled` with the correct page, still $0.001. `web-research/scripts/fetch-page.sh` now sends `maxAgeHours=168` and also keeps a slug-word stale check.

Verified win (2026-09-01): `/contents` served seirdy.one (151K chars) from cache where Kagi's live crawler returned "No data from crawlers".

## Pricing (exa.ai/docs/admin/pricing + live costDollars, 2026-10-18)

| Endpoint | Cost |
|---|---|
| `/search` `instant` | **$0.004** base (≤10 results) |
| `/search` `fast` / `auto` | **$0.007** base (≤10 results) |
| `/search` deep types | $0.012-0.015 |
| results above 10 | +$0.001/result |
| highlights / text inside `/search` | **no extra charge observed** (5 results, live) |
| AI page summaries | +$0.001/page, any endpoint |
| `/findSimilar` (deprecated) | **$0.004** observed (was $0.007) |
| `/contents` | **$0.001/page per content type** (text, highlights, summary each) |
| `/answer` | $0.005 (not wrapped; our agents synthesize) |

Not wrapped but available: `/monitors` (scheduled searches, $0.015), `/agent/runs` (async research, $0.012-$1.00), `/batches` (async batch of API requests), Snapshot (`snapshotAsOf`, paid tiers only).

Ledger: `${XDG_STATE_HOME:-~/.local/state}/exa/usage.jsonl` (override path with `EXA_LEDGER=/path`, disable with `EXA_LEDGER=off`); `../web-research/scripts/search-cost.sh` summarizes spend for every engine (in pi, the bundled `search-cost` extension also shows it in the footer and `/search-cost`).

## When Exa vs the others

| Task | Engine |
|---|---|
| Conceptual/descriptive query | **Exa** (this is the paradigm) |
| "More like this URL" | **Exa find-similar** while it works; fallback: fetch the page, describe it in one sentence, `search.sh` that description |
| Publications / companies / people | **Exa** categories |
| Cheap bulk extraction of known URLs | **Exa contents** ($0.001, keeps links and code) → DeepSeek fetch ($0.00075, flat text) → Kagi extract ($0.004) for X/Twitter |
| Exact match, operators, `site:` precision | **Kagi** |
| News/freshness workflows | **Kagi** `-w news` (Exa `-c news` is the second option) |
| Indie/old web, anti-SEO | **Marginalia** |
| Multi-engine corroboration | **web-research** `../web-research/scripts/meta-search.sh -e all` |

## Errors and limits

- 400 → bad body, or a filter the category does not support (`company`/`people` + dates)
- 401 → key rejected (check `~/.config/exa/api_key`)
- 402 → out of credits (free tier resets monthly; top up at dashboard)
- 429 → rate limit: **10 QPS** for search/answer on free and pay-as-you-go (up to 25 QPS on request); **5 QPS** for deep types. Limits apply per team, across keys.
- `/contents` partial failures come back in `statuses[]` with HTTP 200 — check per URL.
