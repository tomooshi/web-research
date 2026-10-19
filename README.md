# web-research

Web research skills for coding agents, built on four search engines that find things in different ways. Use all four, or any subset: an engine without an API key is skipped.

| Engine | How it retrieves | Good at | Cost |
|---|---|---|---|
| **Kagi** | keyword + quality re-ranking | precise lookups, `site:`/`filetype:`, news, X/Twitter, clean page extraction | $0.012/search, $0.004/page extract |
| **Exa** | neural embeddings | conceptual queries, "find pages *like* this", publications/companies/people, products and local businesses, cheap extraction | $0.004/search `lite` (fan-out default), $0.007 `auto`, $0.001/page ($10 free credit/month) |
| **Marginalia** | keyword, anti-SEO index | personal sites, forums, old web, topics buried under SEO spam | free (1000 queries/day) |
| **DeepSeek** | DeepSeek's in-house index | cheap search loops, Chinese sources (`lang:zh`), date-bounded queries (`after:`/`before:`) | $0.00075/search or fetch; empty results are free |

When two or more of these independently return the same page, that page is very likely relevant. The coordinator skill is built around that signal.

## What's inside

```
skills/
├── web-research/        coordinator: when to use which engine, research recipes
│   └── scripts/
│       ├── meta-search.sh   parallel fan-out, canonical-URL dedupe, rank fusion, agreement flagged, engine notices
│       ├── fetch-page.sh    URL → markdown, fallback ladder: exa → deepseek → kagi → curl → playwright → camoufox → wayback
│       ├── engines.sh       which engines this machine can use (keys, config)
│       ├── doctor.sh        setup check (tools, keys, engine selection, optional extras)
│       └── search-cost.sh   spend/quota summary from the local ledgers
├── kagi-search/         Kagi v1 search + extract
├── exa-search/          Exa search (lite/auto/deep, highlights, objective, notices), find-similar, contents
├── marginalia-search/   Marginalia search + custom filters
└── deepseek-search/     DeepSeek search + fetch
extensions/search-cost/  (pi only, optional) live cost footer + /search-cost command
```

Each skill is a folder with a `SKILL.md` ([Agent Skills](https://agentskills.io) format) and bash scripts. The agent reads the SKILL.md when a task matches and runs the scripts. The five folders need to stay next to each other, because `web-research` calls the engine scripts through `../<skill>/scripts/`.

## Install

### Claude Code

```
/plugin marketplace add tomooshi/web-research
/plugin install web-research@web-research
```

Restart Claude Code. The skills show up as `web-research:web-research`, `web-research:kagi-search`, and so on.

### pi

```bash
pi install git:github.com/tomooshi/web-research
```

This also loads the optional `search-cost` footer extension. To skip it, run `pi config` and disable the extension.

### Anything else (Codex, OpenCode, Cursor, or a plain skills folder)

```bash
git clone https://github.com/tomooshi/web-research.git
cd web-research
./install.sh claude          # or: pi | agents | codex | /path/to/your/skills
```

`install.sh` symlinks by default, so a later `git pull` updates the skills. Use `--copy` to copy the folders instead, and `--force` to replace skills that already use these names.

### Upgrading from search-three

This repo was called `search-three` (three engines) until v0.2.0. GitHub redirects the old URL, but update your install:

- Claude Code: `/plugin uninstall search-three@search-three`, `/plugin marketplace remove search-three`, then the two install commands above. Skill names change from `search-three:*` to `web-research:*`.
- pi: `pi remove git:github.com/tomooshi/search-three`, then `pi install git:github.com/tomooshi/web-research`.
- A clone: `git remote set-url origin https://github.com/tomooshi/web-research.git`, then `git pull` and `./install.sh --force <target>` (adds `deepseek-search`).

## Requirements

- `bash`, `curl`, `python3`. The engine scripts only use the Python standard library. Works on Linux and macOS; on Windows, use WSL or Git Bash.
- Optional extras for `fetch-page.sh`'s free fallback steps. Each missing extra disables one step and the ladder skips it:
  - `pip install beautifulsoup4` enables the curl / wayback steps and is also needed by the browser steps
  - `pip install playwright && playwright install chromium` renders JS-heavy pages
  - Camoufox, a Firefox build that resists bot detection, for pages that block normal headless browsers:
    ```bash
    python3 -m venv ~/.venvs/camoufox
    ~/.venvs/camoufox/bin/pip install 'camoufox[geoip]' beautifulsoup4
    ~/.venvs/camoufox/bin/python -m camoufox fetch
    ```

If your system Python won't allow `pip install` (PEP 668), put the extras in a venv and set `FETCH_PYTHON=/path/to/venv/bin/python`.

## API keys

Get keys only for the engines you want. Each script checks an environment variable first, then a key file:

| Engine | Get a key | Env var | Key file |
|---|---|---|---|
| Kagi | https://kagi.com/api (needs a Kagi account with API credit) | `KAGI_API_KEY` | `~/.config/kagi/api_key` |
| Exa | https://dashboard.exa.ai (free $10/month credit) | `EXA_API_KEY` | `~/.config/exa/api_key` |
| Marginalia | free non-commercial key on request, see https://about.marginalia-search.com/article/api/ | `MARGINALIA_API_KEY` | `~/.config/marginalia/api_key` |
| DeepSeek | https://platform.deepseek.com (same key as the chat API; needs balance) | `DEEPSEEK_API_KEY` | `~/.config/deepseek/api_key` |

```bash
# one engine at a time; repeat for each engine you use
mkdir -p ~/.config/exa && chmod 700 ~/.config/exa
printf '%s' 'YOUR_KEY' > ~/.config/exa/api_key
chmod 600 ~/.config/exa/api_key
```

Without a Marginalia key, an explicit `-e marginalia` uses Marginalia's shared `public` key. That is enough to try things out, but it runs out quickly. The other engines have no fallback: without a key they are skipped.

**Missing keys are not errors.** An engine without a key is *not configured*: the fan-out and the fetch ladder leave it out without a message, an engine script called directly prints one `not configured` line and exits 3, `doctor.sh` lists it with a neutral `–`, and the cost footer hides it. The skills tell the agent to use the next configured engine and **not** to ask you for keys you chose not to add.

## Choose engines

With no setup, every engine that has a key is used. The plain `meta-search.sh "query"` call runs Kagi + Marginalia, or the first two usable engines if you lack one of them. `-e all` runs every usable engine.

To pick engines yourself, create `~/.config/web-research/config` (all lines optional):

```ini
engines = kagi, exa, deepseek     # allowed engines; others are never called
default = kagi, deepseek          # what a plain meta-search.sh call runs
ladder  = exa, kagi, curl, playwright, camoufox, wayback   # fetch-page.sh order
```

`WEB_RESEARCH_ENGINES`, `WEB_RESEARCH_DEFAULT` and `WEB_RESEARCH_LADDER` override the file for one run. `skills/web-research/scripts/engines.sh` shows the result without printing any key.

## Check the setup

```bash
skills/web-research/scripts/doctor.sh          # offline: tools, keys, engine selection, optional extras
skills/web-research/scripts/doctor.sh --live   # plus one real query per usable engine (~$0.02 total)
```

With the Claude Code plugin, you can also just ask: *"run the web-research doctor script"*.

## Try it

```bash
cd skills/web-research
./scripts/meta-search.sh "static site generators for personal wikis"          # default pair
./scripts/meta-search.sh -e all -o "what do practitioners dislike about it?" \
    "infinite scroll usability"                                                # every usable engine + goal
./scripts/meta-search.sh -e cheap "rust async runtimes"                        # Marginalia + DeepSeek
./scripts/fetch-page.sh https://example.com/some/article
./scripts/search-cost.sh
```

Or ask your agent something like *"research what practitioners say about X, find the best sources"*. The `web-research` skill tells it which engine to use and how.

## Handing this to your agent

If you'd rather have your agent set this up and adapt it, paste this:

> Install the skills from https://github.com/tomooshi/web-research for this harness (read its README). Then run `skills/web-research/scripts/doctor.sh`. Fix anything marked ✗. Ask me **once** which of the four engines I want, and help me add keys only for those. Treat the others as not configured and don't bring them up again. Don't put keys in the repo. Use `~/.config/<engine>/api_key` with chmod 600. If a script path doesn't resolve in this harness, fix it so the five skill folders stay side by side, and don't hardcode my home directory.

## Cost tracking

Every script call adds one JSON line to a local ledger:

```
${XDG_STATE_HOME:-~/.local/state}/kagi/usage.jsonl
${XDG_STATE_HOME:-~/.local/state}/exa/usage.jsonl
${XDG_STATE_HOME:-~/.local/state}/deepseek/usage.jsonl
${XDG_STATE_HOME:-~/.local/state}/marginalia/usage.jsonl
```

`search-cost.sh` summarizes spend for today, this month, and all time, for the engines you use. The ledgers only count calls made through these scripts. Each provider's dashboard has the actual bill.

## Configuration

| Variable | Effect |
|---|---|
| `KAGI_API_KEY`, `EXA_API_KEY`, `MARGINALIA_API_KEY`, `DEEPSEEK_API_KEY` | API keys (override the key files) |
| `WEB_RESEARCH_ENGINES`, `WEB_RESEARCH_DEFAULT`, `WEB_RESEARCH_LADDER` | engine selection (override `~/.config/web-research/config`) |
| `KAGI_LEDGER`, `EXA_LEDGER`, `DEEPSEEK_LEDGER`, `MARGINALIA_LEDGER` | ledger path, or `off` |
| `KAGI_RATE_SEARCH`, `KAGI_RATE_EXTRACT` | Kagi prices used by the ledger (defaults: 0.012 / 0.004) |
| `DEEPSEEK_RATE_SEARCH`, `DEEPSEEK_RATE_FETCH` | DeepSeek prices used by the ledger (default 0.00075 each) |
| `DEEPSEEK_RETRIES`, `DEEPSEEK_TIMEOUT` | DeepSeek retries on 429/5xx (default 2) and timeout (default 30 s) |
| `MARGINALIA_QUOTA_LIMIT` | daily Marginalia quota (default 1000) |
| `FETCH_EXA_MAX_AGE_HOURS` | Exa cache age limit in `fetch-page.sh` (default 168; 0 = always fresh) |
| `FETCH_PYTHON` | Python for the bs4/playwright fetch steps (default `python3`) |
| `CAMOUFOX_PYTHON` | Python with camoufox (default `~/.venvs/camoufox/bin/python` if it exists) |
| `SEARCH_SKILLS_DIR` | where the five skill folders live, if they aren't siblings |

pi footer extension only: `KAGI_COST_WARN`/`_ALERT`, `EXA_COST_WARN`/`_ALERT`, `DEEPSEEK_COST_WARN`/`_ALERT`, `MARGINALIA_QUOTA_WARN`/`_ALERT`, `SEARCH_COST_SCOPE`. The footer shows only the engines you have.

## Notes

- API behavior noted in the SKILL.md files (response shapes, quirks, silently ignored parameters) was checked against the live APIs, most recently on 2026-10-18 (Kagi and Exa re-audited against their specs; DeepSeek tested live) and on 2026-10-19 for Exa 3.0. Some of it will drift. If a documented flag stops working, trust what the API returns.
- Marginalia results are CC-BY-NC-SA 4.0 on non-commercial keys.
- `fetch-page.sh`'s browser steps are for reading public pages. Respect site terms.

## License

MIT
