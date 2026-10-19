---
name: exa-search
description: "Neural/semantic web search with the Exa API: retrieval by meaning over Exa's own index, not keywords. The engine for conceptual queries ('essays arguing X', 'companies building Y'), publication/company/people search, products and local businesses, and 'more like this URL' (find-similar.sh). Returns query-relevant highlights at no extra cost; `lite` type $0.004, `auto` $0.007. contents.sh extracts known URLs as markdown for $0.001/page with freshness control. Use when the query describes what the answer looks like rather than which words it contains, or to expand from a known-good source. Prefer kagi-search for site:/filetype: precision, news and X/Twitter; marginalia-search for the indie/old web; deepseek-search for the cheapest search. Optional engine: needs EXA_API_KEY or ~/.config/exa/api_key; when not configured, skip it and do not ask the operator for a key."
---

# Exa Search (neural)

Exa runs its own crawler, its own index, and retrieval by **custom-trained transformer embeddings** served from its own vector database. Verified live 2026-09-01/02; **API surface re-audited 2026-10-18 and for Exa 3.0 on 2026-10-19** against `exa.ai/docs/exa-spec.yaml` (v2.0.0, the documented source of truth) and live calls.

Docs moved to `exa.ai/docs` (index: `exa.ai/docs/llms.txt`; every page has a `.md` variant; changes in `exa.ai/docs/changelog.md`).

**Exa 3.0 (2026-10-19)**, as it affects these scripts:

- New `lite` type ($0.004, ~0.5 s, cached pages only, limited fields). `instant`, `fast` and `deep-reasoning` are **legacy**: they still work at their old prices.
- New `warnings` and `notices` arrays in `/search` responses. The scripts print them to stderr; `meta-search.sh` passes notices on.
- A larger embedding model and a bigger index (ecommerce listings, local businesses, news, sports, weather, flights, events, podcasts). No new API fields or categories came with it.
- "Dynamic Highlights is generally available", says the blog. **The API still requires the beta header**: `highlights.dynamic: true` without `Exa-Beta: dynamic-highlights-2026-08-28` returns HTTP 400 (verified 2026-10-19).

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
5. **Read the notices.** A `RESTRICTIONS_RELAXED` notice means no page matched your `site:` operator or quoted phrase, so the results come from a search without it. Do not present those results as matching the restriction.

## Usage

```bash
./scripts/search.sh "essays on why personal websites matter"           # highlights, Exa chooses the amount
./scripts/search.sh -o "prefer official docs; pull the default k value" "reciprocal rank fusion"
./scripts/search.sh -c publication -a 2024-01-01 "form validation usability"
./scripts/search.sh -t lite "recent product updates from major AI labs"     # $0.004, ~0.5 s
./scripts/search.sh -d "nngroup.com,baymard.com" "checkout flow research"
./scripts/search.sh -x -n 5 "digital garden essays"       # + full text (no extra cost observed)
./scripts/search.sh -H "query"                            # no highlights
./scripts/search.sh -h 600 "query"                        # fixed ~600-char highlight per result (smaller output)

./scripts/find-similar.sh https://lawsofux.com/           # DEPRECATED endpoint, still works
./scripts/find-similar.sh -e -n 10 https://seirdy.one/    # exclude source domain

./scripts/contents.sh URL1 URL2                           # $0.001/page, cache when available
./scripts/contents.sh -l URL                              # fresh fetch (maxAgeHours=0)
./scripts/contents.sh -a 168 URL                          # refetch if cache is older than 7 days
./scripts/contents.sh -s URL                              # + AI summary (+$0.001/page)
```

### Search types (`-t`)

Exa recommends `lite`, `auto` and `deep` (changelog 2026-10-19).

| Type | Price | Use |
|---|---|---|
| `lite` | **$0.004** | ~0.5 s; loops and fan-outs. Cached pages only. Default in `meta-search.sh` |
| `auto` (default here) | $0.007 | ~1.5 s; more compute for candidates, highlights and ranking |
| `deep-lite` | $0.012 | ~4 s synthesis |
| `deep` | $0.012 | 4-15 s multi-step research with synthesis |
| `instant`, `fast` (legacy) | $0.004, $0.007 | use `lite` |
| `deep-reasoning` (legacy) | $0.015 | use `deep` |

**`lite` accepts only** `query`, `numResults`, `category`, `includeDomains`, `excludeDomains`, `startPublishedDate`, `endPublishedDate`, `objective`, `contents.highlights`, `contents.text`, `contents.snapshotAsOf`, `userLocation`, `userIdentifier`, `metadata`, `moderation` and `compliance`. Any other field returns HTTP 400 that names it, e.g. `Not supported with type "lite": contents.maxAgeHours`. Then use `-t auto`.

**`lite` against `auto`** (2026-10-19, 5 queries, 10 results each): they shared 7-9 of the top 10 (mean 7.8) and 12 of 15 top-3 slots. The differing results were not worse; only `lite` found the original RRF paper. Mean latency: 0.5 s against 1.5 s.

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
- **Highlights default: Exa chooses** (bare `highlights: true`, Exa's recommended default since 3.0). Observed 1.6-5.6K chars per result, so 10 results can reach ~40K chars. For a smaller output use `-h CHARS` (a fixed per-result limit, and a **soft** one: a 600-char request returned a 2,566-char highlight) or fewer results (`-n`). `meta-search.sh` sizes Exa highlights to its snippet cap (`-s`, default 500), and lets Exa choose with `-s 0`.
- `warnings` (Exa 3.0): request fields with no effect, e.g. `{"code": "IGNORED_FIELD", "path": "/startCrawlDate", "message": "…"}`. Fix the request.
- `notices` (Exa 3.0): how the results were produced, written for the model, e.g. `RESTRICTIONS_RELAXED` (path `/query`). Both arrays are omitted when empty; codes are an open set, so read `message` for unknown codes.
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

## Pricing (exa.ai/docs/admin/pricing + live costDollars, 2026-10-19)

| Endpoint | Cost |
|---|---|
| `/search` `lite` | **$0.004** base (≤10 results) |
| `/search` `auto` | **$0.007** base (≤10 results) |
| `/search` legacy `instant` / `fast` | $0.004 / $0.007 (unchanged) |
| `/search` `deep-lite` / `deep` (legacy `deep-reasoning` $0.015) | $0.012 |
| results above 10 | +$0.001/result |
| highlights / text inside `/search` | **no extra charge observed** (5 results, live) |
| AI page summaries | +$0.001/page, any endpoint |
| `/findSimilar` (deprecated) | **$0.004** observed (was $0.007) |
| `/contents` | **$0.001/page per content type** (text, highlights, summary each) |
| `/answer` | $0.005 (not wrapped; our agents synthesize) |

Not wrapped but available: `/monitors` (scheduled searches, $0.015), `/agent/runs` (async research, $0.012-$1.00; Exa now points `deep-reasoning` users there), `/batches` (async batch of API requests), Snapshot (`snapshotAsOf`, paid tiers only). Deprecated and not used here: `/search` `subpages`/`subpageTarget` (use `/contents`), rich links and code-block extras, `summary.maxTokens`.

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
| Products, local businesses, events, sports, weather | **Exa** (Exa 3.0 added these to its index; plain descriptive queries, no special category) |
| Indie/old web, anti-SEO | **Marginalia** |
| Multi-engine corroboration | **web-research** `../web-research/scripts/meta-search.sh -e all` |

## Errors and limits

- 400 → bad body, a filter the category does not support (`company`/`people` + dates), or a field `lite` does not accept (the message names it; use `-t auto`)
- 401 → key rejected (check `~/.config/exa/api_key`)
- 402 → out of credits (free tier resets monthly; top up at dashboard)
- 429 → rate limit: **10 QPS** for search/answer on free and pay-as-you-go (up to 25 QPS on request); **5 QPS** for deep types. Limits apply per team, across keys.
- `/contents` partial failures come back in `statuses[]` with HTTP 200 — check per URL.
