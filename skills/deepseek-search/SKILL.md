---
name: deepseek-search
description: "Web search and page fetch via the DeepSeek Search & Fetch API (POST api.deepseek.com/v1/tools/search and /v1/tools/fetch), DeepSeek's in-house index. Cheapest paid engine in the stack: $0.00075 per search or fetch, and empty results, errors and timeouts are not billed. Each result carries a query-focused 600-800 char summary written for models, a rerank_score (0-3) and an authority tier (0-4). Supports site:/-site:/quoted/lang:/after:/before: operators. Verified live 2026-10-18; results are passages with synthetic URL fragments and locale copies, which web-research's meta-search merges. Use for cheap search loops with quality signals, Chinese-language sources (lang:zh), date-bounded queries, and as the cheapest fetch rung for known URLs (live, but flat text: no links or code fences, so Exa/Kagi rank above it in fetch-page.sh). Prefer kagi-search for news workflows and X/Twitter, exa-search for conceptual/neural queries and find-similar, marginalia-search for indie/old web. Requires DEEPSEEK_API_KEY or ~/.config/deepseek/api_key."
---

# DeepSeek Search & Fetch

Two raw JSON endpoints on the normal DeepSeek API key:

| API | Endpoint | Price |
|---|---|---|
| Search | `POST https://api.deepseek.com/v1/tools/search` | $0.75 / 1K **successful** calls |
| Fetch | `POST https://api.deepseek.com/v1/tools/fetch` | $0.75 / 1K **successful** calls |

Billed only on HTTP 200 **with** a result (search: non-empty `results`; fetch: non-empty `content`). `count` does not change the price. Source: api-docs.deepseek.com/guides/search (read 2026-10-18).

> **Verified live 2026-10-18** (key in `~/.config/deepseek/api_key`). Search, fetch, operators, billing and the ledger work. Real output differs from the docs in several ways; see **Live behavior** below. Search quality for English technical queries is below Kagi's (results lean to package registries and localized doc copies). It is strong for Chinese sources, date-bounded queries and as a cheap extra vote.

## Setup

1. Create a key at platform.deepseek.com (the chat-API key works; same bearer auth).
2. `mkdir -p ~/.config/deepseek && printf '%s' "$KEY" > ~/.config/deepseek/api_key && chmod 600 ~/.config/deepseek/api_key` (or export `DEEPSEEK_API_KEY`).
3. Fund the account. HTTP 402 means zero balance.

## Scripts

```bash
./scripts/search.sh "deepseek v4 release"                    # 10 results
./scripts/search.sh -c 20 "rank fusion site:arxiv.org after:2024"
./scripts/search.sh "大模型 推理 优化 lang:zh"                 # Chinese web
./scripts/search.sh -o "Is RRF better than score fusion?" "reciprocal rank fusion evaluation"
./scripts/search.sh -x -c 3 "query"                         # + full page content per result
./scripts/fetch.sh https://example.com/article              # {"title", "content"} (escapes removed)
./scripts/fetch.sh -r https://example.com/article           # raw API response
```

| Option | API field | Notes |
|---|---|---|
| `-c N` | `count` | 1-50, default 10, same price at any count |
| `-o Q` | `ori_question` | the user's original question; improves query understanding; truncated to 128 chars |
| `-x` | `need_content` | full page content in `content`; large output |
| `-L IP` | `localization` | localize results to an IP's region |

The query must be **1-128 Unicode characters**. `search.sh` refuses longer queries (exit 2) rather than truncate them. That limit enforces the right habit: short, broad queries first, then narrow.

## Query operators (from the docs)

| Operator | Example |
|---|---|
| `site:` / `OR` | `DeepSeek site:github.com OR site:huggingface.co` |
| `-site:` | `DeepSeek -site:example.com` |
| `-term` / `-"phrase"` | `DeepSeek -advertisement -"release notes"` |
| `"phrase"` | `DeepSeek "exact phrase"` |
| `lang:` | `DeepSeek lang:zh,en` |
| `after:` / `before:` | `after:2025` · `before:2026-06-01` |

## Response (search)

```json
{"results": [{"rerank_score": 2.4, "title": "...", "url": "...",
  "snippet": "100-200 chars, for UI", "summary": "600-800 chars, for a model",
  "content": "", "site_name": "...", "site_icon": "...",
  "date": "2026-06-01T00:00:00+00:00", "authority": 3}]}
```

- `rerank_score` 0-3 mixes relevance, authority and freshness. **≥ 1.5 = high quality** per the docs.
- `authority` 0-4, **≥ 3 = highly authoritative**, `-1` = unknown.
- `date` is publication time or `null`.
- `summary` is engine-selected text. Use it to triage. **Do not quote it as evidence.** Fetch the page and quote the page.

## Live behavior (verified 2026-10-18)

Search:

- **Results are passages, not pages.** URLs carry synthetic fragments (`…/ranknexus/#1`, `…#files#1`, `…#h`). One page can appear several times. `meta-search.sh` strips the fragment and merges the copies.
- **Locale copies.** An English query returned `ja-jp`, `id-id`, `pl-pl` and `el-gr` copies of one Microsoft Learn page. `lang:en` did **not** remove them. `meta-search.sh` merges `/xx-yy/` locale paths and keeps the English URL.
- **`summary` is not 600-800 chars.** Observed 282-4,641 chars, and it reads like page text, not a summary. `snippet` reached 3,064 chars. Cap them (`meta-search.sh -s`, default 500).
- **Weak quality signals.** `authority` was 4 on nearly every result; `rerank_score` sat between 1.9 and 2.4. They hardly separate results. Do not filter on them.
- **Operators.** `after:2026-05-01` worked (one result dated 2026-04-30). `site:arxiv.org` matched `ar5iv.labs.arxiv.org` mirrors (merged by arXiv ID). `lang:zh` returned good Chinese sources (Aliyun, Tencent Cloud, Microsoft zh-cn).
- **`ori_question` (`-o`) helps.** "reciprocal rank fusion paper" with the question attached found the original 2009 SIGIR paper at rank 4; it also returned a university proxy copy (`dl-acm-org.ezproxy…`), merged by DOI.

Fetch:

| URL | Result |
|---|---|
| api-docs.deepseek.com (new page) | current content, 0.4 s |
| en.wikipedia.org article | 8.6K chars, 4 s |
| seirdy.one | 3.3K chars, 3.4 s |
| x.com status | works (tweet text, 4.5 s), title localized ("X 上的 OpenAI") |
| reddit.com thread | **404** "failed to fetch URL" (unbilled) |
| missing page | 404 (unbilled) |

- **Escaped markdown.** `content` backslash-escapes nearly every punctuation mark (`\#`, `\.`, `\-`, `\(`, `\/`), which breaks headings and tables. `fetch.sh` removes the escapes by default (`-r` = raw).
- **Flat text.** No links and no code fences: code blocks arrive as plain lines. For crawl/follow work or code-heavy docs, prefer Exa contents or Kagi extract. This is why `fetch-page.sh` tries `exa` before `deepseek`.

## Errors and limits

| HTTP | Meaning | Script behavior |
|---|---|---|
| 400 | bad body or field (e.g. count out of range) | exit 1 with the API message |
| 401 | key missing/invalid | exit 1 |
| 402 | insufficient balance | exit 1, "top up" |
| 403 | fetch rejected by security policy (unbilled) | exit 1 |
| 404 | fetch found no usable content (unbilled) | exit 1 |
| 408 / 429 / 5xx | timeout, QPS limit, server | retried twice (1 s, 2 s backoff), then exit 1 |

Rate limits: **5 QPS for search and 5 QPS for fetch**, per account (all keys), independent of model concurrency. Fetch also has a per-domain QPS limit. A fan-out of more than 5 parallel DeepSeek calls will hit 429 and slow down on retries.

Env: `DEEPSEEK_BASE_URL` (mocks), `DEEPSEEK_RETRIES` (default 2), `DEEPSEEK_TIMEOUT` (default 30 s).

## Cost ledger

`~/.local/state/deepseek/usage.jsonl`, one line per HTTP-200 call: `{ts, ep, usd, n, q}`. Unbilled empty results log `usd: 0`. Disable with `DEEPSEEK_LEDGER=off`. The `search-cost` extension shows it in the footer as `ds $…` and in `/search-cost`.

## Gotchas

- **Harness pricing is a different channel.** The "free until 2026-10-31 16:00 UTC" offer covers server-side search tools when DeepSeek is the *model backend* in DeepSeek Harness, Claude Code or Codex. Direct calls from these scripts are billed now.
- **One account-wide QPS budget.** Parallel agents share 5 QPS. Batch and space out loops.
- **Fetch thin-content rule.** `fetch-page.sh` rejects DeepSeek content under 200 chars and falls through. DeepSeek may still bill that call, because it returned content.
- **Pasted keys.** If a key was ever pasted into a chat or a log, rotate it at platform.deepseek.com and rewrite `~/.config/deepseek/api_key`.

## Where it sits in the stack

The `web-research` skill coordinates this engine with Kagi, Marginalia and Exa: `meta-search.sh -e all` or `-e cheap` (Marginalia + DeepSeek), and the `deepseek` rung of `fetch-page.sh` (after `exa`). Engine selection (`~/.config/web-research/config`) can turn it off or make it a default.
