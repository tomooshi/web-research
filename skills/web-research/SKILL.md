---
name: web-research
description: "Coordinate four search engines for multi-source web research: Kagi (lexical, commercial-quality), Marginalia (lexical anti-SEO, free 1000/day), Exa (neural/semantic, own index) and DeepSeek (in-house index, $0.00075/call, lang:zh, after:/before:). Every engine is optional: the scripts detect which keys exist and an optional config file selects engines, the default fan-out and the fetch ladder. Provides a parallel fan-out script that canonicalizes URLs (arXiv IDs, DOIs, tracking params), dedupes, fuses ranks with Reciprocal Rank Fusion, and flags cross-engine agreement — independent indexes returning the same document is the strongest relevance vote available. Includes routing rules (when to fan out vs. hit one engine directly), research-practice rules from published deep-research systems, budget-aware workflow recipes (breadth pass, claim verification, indie deep-dive, cheap loops), failure fallbacks, and fetch-page.sh: a page-extraction fallback ladder (Exa → DeepSeek fetch → Kagi extract → curl → headless Playwright → anti-detect Camoufox → Wayback Machine) for bot-walled, JS-heavy, fingerprint-checked, stale-cached or dead pages. Also trigger when a page fetch/extraction fails or a site blocks scraping. Use for open-ended or multi-source research: 'research X', 'deep dive on', 'find the best sources about', 'what do different corners of the web say about', 'thorough search', literature/source surveys, contested claims, topic landscapes. For a single targeted lookup, use one engine skill directly instead. Works with any subset of engines (KAGI_API_KEY, MARGINALIA_API_KEY, EXA_API_KEY, DEEPSEEK_API_KEY or their key files; scripts/engines.sh shows what is configured); with no keys at all it still runs Marginalia's public key and the free fetch rungs."
---

# Web Research (four-engine coordinator)

This skill sits **above** four engine skills and coordinates them. The engine skills are **sibling folders** of this one (`../kagi-search`, `../marginalia-search`, `../exa-search`, `../deepseek-search`); all `./scripts/...` paths below are relative to this skill's own directory.

**First run:** `./scripts/doctor.sh` checks tools, API keys, engine selection and optional extras (no network calls; add `--live` for one real query per usable engine). Every engine is optional.

**Engines that are not configured (read this before you mention keys to the operator):**

1. An engine without a key is a choice the operator made, not a fault. `meta-search.sh` and `fetch-page.sh` skip it on their own, without errors.
2. Before you call an engine skill directly, check that it is configured: `./scripts/engines.sh`, or the `engines` field of any `meta-search.sh` result. If it is not configured, use the fallback in **Routing → If an engine is not configured**.
3. If an engine script exits **3** or prints `not configured`, skip that engine for the rest of the session. Do not retry it.
4. **Do not ask the operator for a key, and do not suggest getting one.** Mention a missing engine only when the operator asks about setup or names that engine, or once, as a plain fact, when it blocks the task (example: only Kagi renders X/Twitter posts well).
5. Never treat a `skipped: not configured` entry or a `–` line in `doctor.sh` as something to fix.


- **kagi-search** (`../kagi-search/`) — lexical + quality re-ranking (hybrid index: own + upstream commercial), $0.012/search + $0.004/extract, operator precision (site:/filetype:), news workflows, X/Twitter extraction.
- **marginalia-search** (`../marginalia-search/`) — lexical anti-SEO, fully own index, free, **1000 queries/day hard limit**, snippets only, indie/old-web coverage nothing else has.
- **exa-search** (`../exa-search/`) — **neural/semantic** (custom-trained embeddings over Exa's own crawl), $0.007/search (`instant` $0.004), free query-relevant highlights inside search, $0.001/contents with `maxAgeHours` freshness control, find-similar (deprecated by Exa, still works, $0.004), categories (`publication`, `company`, `people`, `news`, `personal site`, `financial report`). Free $10/mo credits.
- **deepseek-search** (`../deepseek-search/`) — DeepSeek's in-house index, **$0.00075/search and /fetch, unbilled when empty or failed**. Results are passages with a long `summary`; operators include `lang:` and `after:`/`before:`; 5 QPS per account. Verified live 2026-10-18: strong for Chinese sources and date-bounded queries, weaker than Kagi for English technical queries, quality fields barely discriminate. Its fetch is live but flat text.

Four engines, at least three retrieval mechanisms. When independent indexes return the same document, that is the strongest relevance vote this stack produces (verified: `-e all` with three engines yielded a triple-agreement hit and doubled the overlap count vs two engines).

**Read the engine skill before using engine-specific features** (Kagi lens/filters/workflows, Marginalia custom filters, Exa categories, DeepSeek operators and limits). This skill only covers coordination.

## Fan-out with fusion: meta-search.sh

```bash
./scripts/engines.sh                            # which engines this machine can use
./scripts/meta-search.sh "query"                # default set (kagi+marginalia unless configured)
./scripts/meta-search.sh -e all "query"         # every usable engine
./scripts/meta-search.sh -e cheap "query"       # marginalia+deepseek: free + $0.00075
./scripts/meta-search.sh -e kagi,exa "query"    # any subset
./scripts/meta-search.sh -c 20 "query"          # results per engine (deepseek caps at 50)
./scripts/meta-search.sh -w news "query"        # kagi workflow (kagi side only)
./scripts/meta-search.sh -o "user's question / goal" "query"   # deepseek ori_question + exa objective
./scripts/meta-search.sh -i -e all "query"      # exa type instant ($0.004 instead of $0.007)
./scripts/meta-search.sh -s 0 "query"           # no snippet cap (default 500 chars)
```

Cost per call: default **$0.012 + 1 Marginalia quota**. `-e all` adds **$0.007** (Exa; `-i` makes it $0.004) and **$0.00075** (DeepSeek, only if it returned results). The output's `cost` object reports what each engine charged. The Marginalia quota line passes through on stderr.

## Engine selection (any subset of the four)

Every engine is optional. With no setup, the scripts use every engine whose skill is installed and whose key exists (env var or `~/.config/<engine>/api_key`). `./scripts/engines.sh` prints the result without showing any key:

```
engine      installed enabled in default key
kagi        yes       yes     yes        env KAGI_API_KEY
marginalia  yes       yes     yes        file ~/.config/marginalia/api_key
exa         yes       yes     no         file ~/.config/exa/api_key
deepseek    yes       yes     no         file ~/.config/deepseek/api_key
```

To choose engines, create `~/.config/web-research/config` (all lines optional):

```ini
engines = kagi, exa, deepseek          # allowed engines; others are never called
default = kagi, deepseek               # what a plain meta-search.sh call runs
ladder  = exa, kagi, curl, playwright, camoufox, wayback   # fetch-page.sh order
```

Env vars override the file for one run: `WEB_RESEARCH_ENGINES`, `WEB_RESEARCH_DEFAULT`, `WEB_RESEARCH_LADDER`.

| Situation | Behavior |
|---|---|
| No `default` set | `kagi,marginalia`, minus unusable engines, filled up to two from `kagi, marginalia, deepseek, exa` |
| `-e all` | every usable engine |
| Aliases (`default`, `all`, `cheap`) | run only configured engines; engines without a key, not installed or disabled are left out **silently** |
| Alias with no configured engine (e.g. `-e cheap` without Marginalia and DeepSeek keys) | runs the automatic default set instead and adds a `note` field to the output |
| `-e kagi,exa` with no Kagi key | Exa runs; `engines.kagi = "skipped: not configured"`. Named engines are reported, because the caller asked for them |
| Marginalia without a key | runs through the shared public key (rate-limited) when named with `-e`; aliases use it only when no engine with a real key is usable. When the public key is busy, Marginalia is skipped for the task |
| fetch-page.sh default ladder | paid rungs without a usable engine drop out silently; with `-m` they appear in `attempts` as `skipped: <reason>` |
| No usable engine | stderr says so, exit 1 |
| Engine script called directly without a key | one-line `not configured` message on stderr, **exit 3** |
| Unknown engine name | exit 2 with the list of known names |

The `search-cost` footer follows the same rule: it shows the engines in `engines`, else every engine with a key or ledger history.

Output is one JSON object:

```json
{
  "query": "...",
  "engines": {"kagi": "ok", "marginalia": "ok", "exa": "ok", "deepseek": "skipped: no key configured"},
  "cost": {"kagi": 0.012, "marginalia": "1 quota", "exa": 0.007},
  "overlap": 1,
  "results": [
    {"url": "...", "title": "...", "snippet": "...",
     "sources": ["kagi", "deepseek"], "rank": {"kagi": 1, "deepseek": 2},
     "score": 0.0325, "published": "2025-06-13T00:00:00Z",
     "variants": ["https://anthropic.com/...?utm_source=ds"],
     "kagi_type": "search", "authority": 3, "deepseek_rerank": 2.9}
  ]
}
```

How the merge works:

- **Canonical dedupe.** arXiv `abs`/`pdf`/`html` and all `vN` collapse to one key; `ar5iv` mirrors join their arXiv ID; DOIs on doi.org and publisher hosts, and any `/doi/10.x` path (library proxies included), collapse to one key; `/xx-yy/` locale paths (`learn.microsoft.com/el-gr/…`) collapse, keeping the English URL; DeepSeek's synthetic passage fragments (`#1`, `#h`) are stripped; `utm_*`/`fbclid`/`gclid`-style params, fragments, `www.`, `m.`, `index.html`, trailing slashes and param order are ignored. Other URLs merged into a result appear in `variants`. **Limit:** the same paper on a publisher site and an author's homepage PDF stays two results (titles are too unreliable to merge on).
- **Reciprocal Rank Fusion** (Cormack et al., SIGIR 2009): `score = Σ 1/(60 + rank)` over engines. With k=60 and ≤50 results per engine, any multi-engine hit outranks any single-engine hit, and inside each tier better ranks win. Example: an overlap hit at Kagi #18 and Marginalia #3 beats every single-engine #1.
- A repeat inside one engine is not agreement. Only distinct engines add to `sources` and `score`.
- One engine failing is non-fatal. `engines` reports `error: ...` or `skipped: ...` (no key, query too long for DeepSeek). Exit 1 only when **no** engine returned a result set.
- Kagi's `related_search` group is dropped (relative URLs). Other groups keep their name in `kagi_type`.

Triage fields (inputs to judgement, not filters):

| Field | Engine | Reading |
|---|---|---|
| `sources`, `score` | all | agreement and fused rank |
| `published` | kagi `time`, exa `publishedDate`, deepseek `date` | first date any engine reported. **Kagi times are approximate**: they carry the current clock time, so they come from relative dates ("4 months ago") |
| `authority` | deepseek | 0-4, ≥3 = authoritative per docs; **live: nearly always 4**, so it hardly separates results |
| `deepseek_rerank` | deepseek | 0-3, ≥1.5 = high per docs; **live: 1.9-2.4 band** |
| `marginalia_quality` | marginalia | **lower = better** |
| `paywalled`, `ai_generated` | kagi `props` | present only when true. `ai_generated` flags likely content-farm text |

Snippets: Kagi and Marginalia send short snippets. DeepSeek sends a long `summary` (282-4,641 chars live; it reads like page text). Exa results carry **highlights** (query-relevant excerpts), requested by default at no extra cost (live `costDollars` unchanged, 2026-10-18). The longest snippet wins on merged results, capped by `-s`.

## Extraction with fallback: fetch-page.sh

`fetch-page.sh` walks an escalation ladder automatically and reports which rung succeeded plus why earlier rungs failed:

```bash
./scripts/fetch-page.sh URL                      # exa → deepseek → kagi → curl → playwright → camoufox → wayback
./scripts/fetch-page.sh -m curl,playwright URL   # free rungs only
./scripts/fetch-page.sh -m wayback URL           # straight to archive (known-dead page)
./scripts/fetch-page.sh -t 40 URL                # per-rung timeout seconds (default 25)
```

| Rung | Cost | Handles | Doesn't handle |
|---|---|---|---|
| `exa` | $0.001 | most pages via Exa's crawl cache, markdown keeps tables and code fences (succeeded on seirdy.one where Kagi failed); cache older than `FETCH_EXA_MAX_AGE_HOURS` (default 168) is refetched | X/Twitter (auto-skipped), thin-content pages |
| `deepseek` | **$0.00075**, unbilled on 403/404 | live fetch, 0.4-4.5 s; Wikipedia, personal sites, new docs pages (verified 2026-10-18). Escapes are removed by `fetch.sh` | **flat text: no links, no code fences**; Reddit (404); X/Twitter (auto-skipped, though it works); content under 200 chars falls through |
| `kagi` | $0.004 | most pages, X/Twitter, best markdown quality | some bot walls, dead pages |
| `curl` | free | static HTML, no-JS pages | SPAs, bot walls (403/shell pages) |
| `playwright` | free, ~3-5s | JS-rendered SPAs, mild bot walls (verified: Reddit) | Cloudflare turnstile, logins |
| `camoufox` | free, ~10s, ~200MB RAM | fingerprint-checked walls that block plain headless browsers (anti-detect Firefox, geoip, uBO) | logins, CAPTCHAs that need a human |
| `wayback` | free | dead pages, hard walls (if archived) | never-archived URLs (stale content); API itself 429s under load |

Output: `{"url", "method", "title", "markdown", "attempts": {rung: error, ...}}` — exit 1 with an `attempts` breakdown if every rung fails. The local rungs use `scripts/_extract.py` (bs4-based, preserves headings/links/lists/code); quality is below Kagi's but serviceable.

Gotchas:

- **Exa serves stale cache as success.** Verified 2026-10-18: `api-docs.deepseek.com/guides/search` (a new page) came back from Exa as the cached site index ("Your First API Call"), `status: success`, `source: cached`, same URL. The `exa` rung now rejects a **cached** page when the URL's last path segment has plain words and none of them occur in the page. That case falls through to the next rung. Slugs that are numbers or hashes are not checked, so this guard cannot catch everything. The rung also sends `maxAgeHours=168` (Exa's replacement for the deprecated `livecrawl`). With it, the same URL came back `source: crawled` with the correct page at the same $0.001.
- **Soft-404s pass the ladder.** A parked/redirected domain returns HTTP 200 with junk (verified: geocities.com → parking page, 118 chars). Compare `markdown` length and content against what you expected — a short result from `curl` on an old URL usually means the real page is on `wayback`.
- **archive.org's availability API rate-limits aggressively** (HTTP 429, reported in `attempts`). Retry later or fetch `https://web.archive.org/web/<url>` manually.
- **The free rungs are optional extras.** `curl`/`playwright`/`camoufox`/`wayback` need `beautifulsoup4`; `playwright` also needs `pip install playwright && playwright install chromium`; `camoufox` needs the `camoufox` package plus `camoufox fetch`. A missing extra just fails that rung with a clear message in `attempts` and the ladder moves on. `FETCH_PYTHON` picks the python used for bs4/playwright (default `python3`); `CAMOUFOX_PYTHON` picks the one for camoufox (default `~/.venvs/camoufox/bin/python` if it exists, else `FETCH_PYTHON`). Run `./scripts/doctor.sh` to see which rungs are available.
- Playwright is plain headless Chromium with a desktop UA — *not* anti-detect; Camoufox is the anti-detect escalation and sits right after it in the ladder. Keep Camoufox in a dedicated venv (e.g. `~/.venvs/camoufox`) — system-Python upgrades can silently remove it. If the rung reports a version/install error, re-run `<that-python> -m camoufox fetch`.
- For logged-in views or bulk session work, use the session-hybrid pattern (Camoufox establishes cookies, `curl_cffi` bulk-pulls) in the kagi-search skill's X/Twitter section.
- Ladder order is cost-aware, not speed-aware. Paid rungs go cheapest first. In a free-only loop use `-m curl,playwright,camoufox,wayback`.

Verified live 2026-09-01: Reddit's shell page fails `curl` (“empty extraction”) and succeeds on `playwright`; `-m curl,camoufox` on Reddit falls through into a successful Camoufox render; hard 404s produce clean per-rung diagnostics.

## Research practice

These rules come from published deep-research systems. Sources: Anthropic, "How we built our multi-agent research system" (2025); TinyFish, "Lessons from building a deep research system" (2026); Cormack, Clarke & Büttcher, "Reciprocal Rank Fusion outperforms Condorcet and individual rank learning methods" (SIGIR 2009).

1. **Scale effort to the question.** Anthropic's prompts budget 1 agent with 3-10 tool calls for a simple fact, 2-4 subagents with 10-15 calls each for a comparison, and more than 10 subagents only for complex research. Over-investment in simple queries was their most common early failure. The routing table below is that budget for this stack.
2. **Start wide, then narrow.** Agents default to long, specific queries that return few results. Start with short, broad queries, look at what exists, then narrow. DeepSeek enforces this with a 128-char query limit. Exa is the exception: give it a *description* of the answer.
3. **Put deterministic steps in code.** TinyFish removed per-query subagents because ranking, dedupe and classification have fixed inputs. `meta-search.sh` already canonicalizes, dedupes and fuses. Read `score`, `sources` and `variants`. Do not re-dedupe by hand.
4. **Source quality depends on the objective.** Sentiment research wants forums and social posts. Statistics want primary agencies. Anthropic's testers found early agents chose SEO content farms over academic PDFs and personal blogs. Use the triage fields to find primary sources. Do not use them as hard filters.
5. **Agreement is only as strong as independence.** Engines that share an upstream index agree for free. Kagi blends upstream commercial results. Exa, Marginalia and (by its own claim) DeepSeek crawl their own indexes. Ten sites that repeat one press release are one source. Weight agreement by how different the agreeing mechanisms are.
6. **Quote pages, not snippets.** Snippets and DeepSeek summaries are engine-written text. Fetch the page and cite text that is on it.
7. **Absence is not evidence.** Zero results usually means the phrasing has the wrong shape. Try the other shape (keyword ↔ descriptive) before you conclude anything.
8. **Measure routing changes on a small eval set.** Anthropic started with about 20 real queries, because early changes have large effects. Before you change defaults (for example, adding DeepSeek to the default pair), compare engines on such a set.

## Routing: fan out or go direct?

Fan-out is not the default. It spends several budgets, so route first. First question: **what shape is the query?** Keyword-shaped (names, exact terms, operators) → lexical engines. Description-shaped ("essays arguing…", "tools similar to…") → Exa. Both → fan-out.

| Situation | Route |
|---|---|
| Single fact, quick lookup ("when was X", "who is Y") | **Kagi direct**, `search-v1.sh "Q" 2` — extraction answers it in one call. DeepSeek direct ($0.00075, with `-o` question) is the cheap alternative |
| Known URL to read | **`fetch-page.sh URL`** (exa $0.001 → deepseek $0.00075 → kagi $0.004 → free rungs) — never search for what you already have |
| "More sources like this one" (have a known-good URL) | **Exa `find-similar.sh URL`** — nothing else does this. Exa deprecated the endpoint (still works 2026-10-18); fallback: describe the page in one sentence and run `../exa-search/scripts/search.sh` on that |
| Conceptual / descriptive query ("blog posts where practitioners argue X") | **Exa direct** (`../exa-search/scripts/search.sh`) — keyword engines mangle these |
| Papers, companies, people as a class | **Exa `-c` category** (`publication`, `company`, `people`). For GitHub repos use Kagi `site:github.com`; for PDFs use Kagi `filetype:pdf` or `lens_id: pdf` |
| Exact string / identifier / operator-scoped (`site:`, `filetype:`) | **Kagi direct** (DeepSeek supports `site:`/quotes too; Exa `-t keyword` is undocumented now and weaker) |
| Chinese-language sources, or `lang:` filtering | **DeepSeek direct** with `lang:zh` (or `lang:zh,en`) |
| Date-bounded search (`after:`/`before:`) | **DeepSeek direct** operators, or Kagi `filters`, or Exa `-a/-b` |
| News / current events / images / videos / X | **Kagi direct** (only engine with these workflows + tweet extraction) |
| Indie/old-web/blog discovery, `year<` filtering, SEO-spam-prone topics | **Marginalia direct** (free; the others under-index this) |
| Open-ended research, topic landscape, "find the best sources" | **Fan-out** (default pair; `-e all` if the query is even partly conceptual) |
| Contested claim, need independent corroboration | **Fan-out `-e all`** |
| Tight loop (query expansion, evals, many candidate queries) | **`-e cheap`** (Marginalia free + DeepSeek $0.00075), or Marginalia direct; one full fan-out on the winner. Respect DeepSeek's 5 QPS |

### If an engine is not configured

Route to the next configured engine. Do not ask for the missing key.

| Missing engine | Use instead |
|---|---|
| **Kagi** | quick facts and `site:`/quoted queries → DeepSeek direct (with `-o`) or Exa `-t instant`; news → Exa `-c news` or DeepSeek `after:`; page extraction → `fetch-page.sh` (exa/deepseek/free rungs); X/Twitter posts → `fetch-page.sh` free rungs (weak: say once that results may be thin) |
| **Exa** | conceptual queries → DeepSeek direct with `-o "<the goal>"`, or Kagi with a keyword rephrase; find-similar → search a one-sentence description of the page; papers → Kagi `lens_id: academic` or `site:arxiv.org` |
| **Marginalia** | indie/old web → Kagi `lens_id: small web`, or Exa `-c "personal site"`; free loops → DeepSeek (`$0.00075`) |
| **DeepSeek** | Chinese sources → Kagi with a Chinese-language query; date bounds → Kagi `filters.after`/`before` or Exa `-a`/`-b`; cheap loops → Marginalia |
| **only one engine configured** | use it for everything; `meta-search.sh` still works (one engine, no agreement signal) |

## Workflow recipes

### Breadth-then-depth (default research pattern)

0. If the question is *conceptual*, phrase it descriptively and use `-e all`. For "more like this known-good source", skip search: `../exa-search/scripts/find-similar.sh URL`.
1. `meta-search.sh -c 15 "short broad query"` — one fan-out for breadth.
2. Triage the merged list: multi-engine hits first, then titles, snippets and triage fields. Note what the first pass shows exists, then write narrower follow-up queries.
3. Extract only the winners with `fetch-page.sh URL` (cheapest paid rung first, falls back automatically), or `../exa-search/scripts/contents.sh URL1 URL2 …` for bulk.
4. Total: ~$0.012 + ~$0.001×N — versus $0.052 for a naive Kagi search with extract=10.

### Claim verification

1. `meta-search.sh -e all -o "<the user's question>" "<neutral claim phrasing>"`. Phrase the claim neutrally, not as a leading question.
2. Check `overlap`. Weight a hit by how *independent* the agreeing engines are (rule 5), not just by count.
3. Extract 3-5 pages that span **all** source pools via `fetch-page.sh`. Marginalia surfaces non-SEO primary sources. Exa surfaces semantically on-point pages that keyword ranking buried.
4. For evidence-grade claims, add `../exa-search/scripts/search.sh -c publication "<claim>"`. Publication results can carry `entities` with year and citation count.
5. If the claim is recent, add a `meta-search.sh -w news` pass. Marginalia crawls slowly and Exa's cache lags: treat missing recent results as "not yet indexed", not "not true".
6. Quote from the fetched pages (rule 6).

### Indie deep-dive

1. `../marginalia-search/scripts/search.sh -c 20 -d 1 "topic"` — free; one result per domain maximizes site diversity.
2. Paginate (`-p 2`, `-p 3`) while promising domains keep appearing.
3. **Expand from the best find**: `../exa-search/scripts/find-similar.sh -e <best-url>`. Exa's `-c "personal site"` category is a second indie-discovery axis.
4. Extract chosen pages via `fetch-page.sh`.
5. Optional: a Marginalia custom filter (`filter.sh`) for a recurring beat.

### Multi-angle survey

For a landscape question, run 2-4 fan-outs with *different phrasings/facets*, not one vague fan-out. Make at least one phrasing description-shaped and run it `-e all`. Dedupe across runs by canonical URL (the script dedupes only within a run). URLs that recur **across phrasings** are a second agreement signal, orthogonal to cross-engine overlap. Close with one `find-similar.sh` on the strongest result.

## Budget model

| Pattern | Kagi $ | Exa $ | DeepSeek $ | Marginalia quota |
|---|---|---|---|---|
| Quick fact (Kagi direct, extract 2) | $0.020 | 0 | 0 | 0 |
| Known URL (fetch-page, exa rung hits) | 0 | $0.001 | 0 | 0 |
| Conceptual query (Exa direct) | 0 | $0.007 | 0 | 0 |
| Find-similar expansion | 0 | $0.004 | 0 | 0 |
| Cheap loop query (`-e cheap`) | 0 | 0 | $0.00075 | 1 |
| Breadth-then-depth (default fan-out + 3 extracts) | $0.012 | $0.003 | 0 | 1 |
| Claim verification (`-e all` + scholarly + news + 5 extracts) | $0.024 | $0.019 | $0.00075 | 2 |
| Indie deep-dive (3 Marginalia pages + find-similar + 3 extracts) | 0 | $0.007 | 0 | 3 |
| Multi-angle survey (3 fan-outs, one `-e all`, + find-similar + 5 extracts) | $0.036 | $0.016 | $0.00075 | 3 |

Extract figures assume the exa rung succeeds. Without an Exa key, each extract falls to DeepSeek ($0.00075), then Kagi ($0.004). Exa's **$10/month free credits ≈ $0.33/day**. Every script call is logged to a local ledger; `./scripts/search-cost.sh` prints today / month / all-time spend for every engine. (In pi, the bundled `search-cost` extension also shows a live footer for the engines you have, `⌕ kagi $ · exa $ · ds $ · marg n/1k`, and a `/search-cost` command.) Marginalia's 1000/day is a **hard 503 wall** in loops — batch and dedupe queries before you fire them.

## Failure fallbacks

- **Marginalia 503 (quota)** — continue with `-e kagi,exa,deepseek`. Quota resets at UTC midnight. Losing Marginalia costs the indie-web axis; say so if that mattered.
- **Exa 402 (credits exhausted)** — continue without Exa; `fetch-page.sh` skips a failing exa rung. Credits reset monthly.
- **Exa contents stale** — the rung already refetches cache older than 168 h, and the slug guard catches some younger stale copies. Otherwise run `contents.sh -l URL` (`maxAgeHours=0`, fresh fetch) or fall to the kagi rung.
- **DeepSeek 402 (balance)** — top up, or continue without it (`-e kagi,marginalia,exa`, or drop it from `engines` in the config). **429** — the script retries twice. Above 5 QPS across all agents, slow the loop.
- **Engine skipped (not configured, or DeepSeek query >128 chars)** — expected states, not failures. Do not report them as problems. Shorten the query to include DeepSeek.
- **Any extract fails on a specific URL** — use `fetch-page.sh`; it walks every rung automatically.
- **Kagi down entirely** — Marginalia + Exa + DeepSeek still cover discovery; DeepSeek/Exa + free rungs cover extraction. Only news workflows and X/Twitter rendering are lost.
- **All engines down** — stop and report. Do not silently answer from training data when the user asked for research.
- **Zero overlap** is *normal* for niche queries (small index intersection). It is a missing bonus signal, not a red flag.

## Verified

- 2026-09-01: parallel execution, merge, percent-encoding dedupe (`Gemini_(protocol)` ≡ `Gemini_%28protocol%29`), overlap detection, single-engine mode.
- 2026-10-18: canonical dedupe unit cases (arXiv abs/pdf/html/vN, DOI on doi.org/dl.acm.org, utm/fbclid, `en.m.wikipedia`, param order) merge; distinct pages stay distinct. Live Kagi + mock DeepSeek fan-out merged a UTM-tagged, no-`www` variant into Kagi's #1 result. DeepSeek scripts tested against a schema mock: retry on 429, 401/402/403/404 mapping, 128-char refusal, billing-aware ledger. Exa stale guard rejected the real stale page and passed 5 normal pages. Fixed: the Marginalia quota line never reached stderr (redirect order `2>/dev/null >&2` sent it to /dev/null).
- 2026-10-18 API audit (Kagi spec + changelog, Exa spec v2.0.0 + pricing + live calls): Exa highlights now fill fan-out snippets at no extra cost; `-o` reaches Exa as `objective`; `-i` (instant) bills $0.004; the exa fetch rung uses `maxAgeHours`. Details live in the kagi-search and exa-search skills.
- 2026-10-18 DeepSeek live: search, fetch, operators, unbilled 404s and the ledger work; findings are in the deepseek-search skill. Four-engine `-e all` ran with all engines `ok` and merged Kagi's `en-us` Azure page with two DeepSeek locale copies.
- 2026-10-18 engine selection: simulated users with only Exa + DeepSeek keys (default became `deepseek,exa`; `-e kagi,exa` reported `kagi: skipped: no key`), with no keys (Marginalia public key + free fetch rungs; Wikipedia fetched via `curl`), and with `WEB_RESEARCH_ENGINES=kagi,deepseek`. Footer hides engines without a key or history.
