#!/usr/bin/env python3
"""Engine selection for web-research: which engines this machine may use.

Shared by meta-search.sh, fetch-page.sh and engines.sh. Never prints key values.

Sources, highest priority first:
  1. env   WEB_RESEARCH_ENGINES, WEB_RESEARCH_DEFAULT, WEB_RESEARCH_LADDER
  2. file  ${XDG_CONFIG_HOME:-~/.config}/web-research/config   (key = value lines)
             engines = kagi, marginalia, exa, deepseek   # allowed engines
             default = kagi, marginalia                  # plain meta-search set
             ladder  = exa, deepseek, kagi, curl, playwright, camoufox, wayback
  3. auto  engines = every installed engine with a key; default = kagi,marginalia
           filled from the usable engines up to two; ladder = built-in order.
           Marginalia without a key still works through the shared public key
           (rate-limited): explicit -e marginalia runs it, but aliases use it
           only when no engine with a real key is usable.

An engine is *usable* when its skill is installed, it has a key (marginalia:
always), and it is in `engines`.

Usage:
  _engines.py resolve SPEC      SPEC: "" | default | both | all | cheap | a,b,c
                                -> {"run": [...], "skip": {engine: reason}}
  _engines.py ladder [METHODS]  -> {"ladder": [...], "skip": {rung: reason}}
  _engines.py status [--json]
"""
import json
import os
import sys

HOME = os.path.expanduser("~")
# Engine skills are siblings of web-research; SEARCH_SKILLS_DIR overrides.
SKILLS = os.environ.get("SEARCH_SKILLS_DIR") or os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"),
                      "web-research", "config")

# name: (search script, key env var, key file)
ENGINES = {
    "kagi": ("kagi-search/scripts/search-v1.sh", "KAGI_API_KEY", "kagi/api_key"),
    "marginalia": ("marginalia-search/scripts/search.sh", "MARGINALIA_API_KEY", "marginalia/api_key"),
    "exa": ("exa-search/scripts/search.sh", "EXA_API_KEY", "exa/api_key"),
    "deepseek": ("deepseek-search/scripts/search.sh", "DEEPSEEK_API_KEY", "deepseek/api_key"),
}
ORDER = ["kagi", "marginalia", "exa", "deepseek"]
FILL_ORDER = ["kagi", "marginalia", "deepseek", "exa"]  # to complete the auto default
BUILTIN_DEFAULT = ["kagi", "marginalia"]
PAID_RUNGS = {"exa", "deepseek", "kagi"}
FREE_RUNGS = ["curl", "playwright", "camoufox", "wayback"]
BUILTIN_LADDER = ["exa", "deepseek", "kagi"] + FREE_RUNGS
ALIASES = {"both": "default", "": "default"}


def parse_list(text):
    return [t.strip().lower() for t in text.replace(",", " ").split() if t.strip()]


def read_config():
    cfg = {}
    try:
        with open(CONFIG) as f:
            for line in f:
                line = line.split("#", 1)[0].strip()
                if "=" in line:
                    k, v = line.split("=", 1)
                    cfg[k.strip().lower()] = parse_list(v)
    except OSError:
        pass
    for key, env in (("engines", "WEB_RESEARCH_ENGINES"), ("default", "WEB_RESEARCH_DEFAULT"),
                     ("ladder", "WEB_RESEARCH_LADDER")):
        if os.environ.get(env, "").strip():
            cfg[key] = parse_list(os.environ[env])
    return cfg


def key_source(name):
    _, env, rel = ENGINES[name]
    if os.environ.get(env, "").strip():
        return f"env {env}"
    path = os.path.join(HOME, ".config", rel)
    try:
        if os.path.getsize(path) > 0 and os.access(path, os.R_OK):
            return f"file ~/.config/{rel}"
    except OSError:
        pass
    return "public key (shared, rate-limited)" if name == "marginalia" else None


def installed(name):
    # Existence, not the execute bit: scripts are run with `bash`, and some
    # installers (plugin caches, zip downloads) drop the bit.
    return os.path.isfile(os.path.join(SKILLS, ENGINES[name][0]))


def state():
    cfg = read_config()
    for k in ("engines", "default"):
        bad = [e for e in cfg.get(k, []) if e not in ENGINES]
        if bad:
            sys.exit(f"web-research config: unknown engine(s) in '{k}': {', '.join(bad)} "
                     f"(known: {', '.join(ORDER)})")
    rows = {}
    for name in ORDER:
        src = key_source(name)
        inst = installed(name)
        allowed = name in cfg["engines"] if "engines" in cfg else True
        reason = None
        if not inst:
            reason = "skill not installed"
        elif not src:
            reason = "no key"
        elif not allowed:
            reason = "disabled in config"
        rows[name] = {"installed": inst, "key": src, "enabled": allowed, "usable": reason is None,
                      "reason": reason, "public": bool(src) and src.startswith("public")}
    usable = [n for n in ORDER if rows[n]["usable"]]
    # Aliases prefer engines with a real key; the shared public Marginalia key
    # is used by an alias only when nothing else is usable.
    keyed = [n for n in usable if not rows[n]["public"]] or usable
    if "default" in cfg:
        default, configured_default = cfg["default"], True
    else:
        default = [e for e in BUILTIN_DEFAULT if e in keyed]
        for e in FILL_ORDER:
            if len(default) >= 2:
                break
            if e in keyed and e not in default:
                default.append(e)
        configured_default = False
    return cfg, rows, keyed, default, configured_default


def resolve(spec):
    cfg, rows, usable, default, configured_default = state()
    spec = ALIASES.get(spec.strip().lower(), spec.strip().lower())
    skip = {}
    if spec == "default":
        wanted = default
    elif spec == "all":
        wanted = usable
    elif spec == "cheap":
        wanted = ["marginalia", "deepseek"]
    else:
        wanted = parse_list(spec)
        bad = [e for e in wanted if e not in ENGINES]
        if bad:
            sys.exit(f"unknown engine(s): {', '.join(bad)} "
                     f"(known: {', '.join(ORDER)}; aliases: default, both, all, cheap)")
    run = []
    for e in wanted:
        if rows[e]["usable"]:
            run.append(e)
        elif rows[e]["reason"] != "disabled in config" or spec not in ("default", "all", "cheap"):
            # Silent only when an alias meets an engine the user turned off on purpose.
            skip[e] = rows[e]["reason"]
    return {"run": run, "skip": skip}


def ladder(methods):
    cfg, rows, *_ = state()
    explicit = bool(methods.strip())
    rungs = parse_list(methods) if explicit else cfg.get("ladder", BUILTIN_LADDER)
    known = PAID_RUNGS | set(FREE_RUNGS)
    bad = [r for r in rungs if r not in known]
    if bad:
        sys.exit(f"unknown method(s): {', '.join(bad)} (known: {', '.join(BUILTIN_LADDER)})")
    out, skip = [], {}
    for r in rungs:
        if r in PAID_RUNGS and not rows[r]["usable"]:
            if explicit:  # the default ladder drops unusable rungs silently
                skip[r] = f"skipped: {rows[r]['reason']}"
            continue
        out.append(r)
    return {"ladder": out, "skip": skip}


def status(as_json):
    cfg, rows, usable, default, configured_default = state()
    lad = ladder("")
    if as_json:
        print(json.dumps({"config": CONFIG, "config_present": os.path.exists(CONFIG),
                          "engines": rows, "usable": usable, "default": default,
                          "ladder": lad["ladder"]}, indent=2))
        return
    print(f"{'engine':11} {'installed':9} {'enabled':7} {'in default':10} key")
    for n in ORDER:
        r = rows[n]
        print(f"{n:11} {'yes' if r['installed'] else 'NO':9} {'yes' if r['enabled'] else 'no':7} "
              f"{'yes' if n in default and r['usable'] else 'no':10} {r['key'] or '-- none --'}")
    src = "env/config" if configured_default else "auto"
    print(f"\nall:     {', '.join(usable) or 'none'}")
    print(f"default: {', '.join(e for e in default if e in usable) or 'none'} ({src})")
    print(f"fetch ladder: {' -> '.join(lad['ladder'])}")
    print(f"config: {CONFIG} ({'present' if os.path.exists(CONFIG) else 'absent: auto mode'})")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    arg = sys.argv[2] if len(sys.argv) > 2 else ""
    if cmd == "resolve":
        print(json.dumps(resolve(arg)))
    elif cmd == "ladder":
        print(json.dumps(ladder(arg)))
    elif cmd == "status":
        status(arg == "--json")
    else:
        sys.exit(__doc__)
