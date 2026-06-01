#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["openai>=1.40.0"]
# ///
"""
Review Footswitch's UI translations against external LLMs (Grok / Gemini) WITHOUT
coding agents — direct API calls, one request per (model, locale), parallelized
with a thread pool. Results land in .localization-reviews/external-model-reviews/<model>/
in the SAME format the existing merge.py pipeline consumes (per-locale <loc>.md
plus combined.md, headed by "REVIEWER MODEL: <name>").

Usage (from anywhere; paths are resolved relative to the repo):
    export XAI_API_KEY=...        # for Grok
    export GOOGLE_API_KEY=...     # for Gemini
    uv run --project scripts scripts/review_locales.py
    # or target a subset:
    uv run --project scripts scripts/review_locales.py --models grok --locales de,fr,ja
    uv run --project scripts scripts/review_locales.py --dry-run        # build prompts, no API calls

Both providers expose OpenAI-compatible chat endpoints, so a single `openai`
client talks to both by swapping base_url + api_key.
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import json
import os
import re
import sys
import threading
from dataclasses import dataclass
from pathlib import Path

# ---------------------------------------------------------------------------
# Paths (resolved relative to this file: scripts/ -> repo root)
# ---------------------------------------------------------------------------
REPO = Path(__file__).resolve().parent.parent
LOC_DIR = REPO / "Sources" / "Footswitch" / "Resources" / "Localizations"
OUT_ROOT = REPO / ".localization-reviews" / "external-model-reviews"
EN = "en"  # authoritative reference locale

# ---------------------------------------------------------------------------
# Model registry: each provider is an OpenAI-compatible endpoint.
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class Model:
    key: str            # short name used for the output dir + report header
    model_id: str       # provider's model id
    base_url: str
    api_key_env: str

MODELS = {
    "grok": Model(
        key="grok",
        model_id=os.environ.get("XAI_MODEL", "grok-4"),
        base_url="https://api.x.ai/v1",
        api_key_env="XAI_API_KEY",
    ),
    "gemini": Model(
        key="gemini",
        model_id=os.environ.get("GOOGLE_MODEL", "gemini-2.5-pro"),
        base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
        api_key_env="GOOGLE_API_KEY",
    ),
}

# RTL locales: the arrow in menu.lastFire should be the mirrored one.
RTL = {"ar", "he"}

# ---------------------------------------------------------------------------
# .strings parsing
# ---------------------------------------------------------------------------
_COMMENT = re.compile(r"^/\*\s*(.*?)\s*\*/\s*$")
_ENTRY = re.compile(r'^"([^"]+)"\s*=\s*"(.*)";\s*$')


def parse_strings(path: Path) -> dict[str, tuple[str, str]]:
    """key -> (comment, value), preserving file order via dict insertion order."""
    out: dict[str, tuple[str, str]] = {}
    comment = ""
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        cm = _COMMENT.match(line)
        if cm:
            comment = cm.group(1)
            continue
        m = _ENTRY.match(line)
        if m:
            out[m.group(1)] = (comment, m.group(2))
            comment = ""
    return out


def discover_locales() -> list[str]:
    locs = sorted(
        p.name[: -len(".lproj")]
        for p in LOC_DIR.glob("*.lproj")
        if p.is_dir()
    )
    return locs


# ---------------------------------------------------------------------------
# Prompt construction (mirrors the brief used for the agent-based reviews)
# ---------------------------------------------------------------------------
SYSTEM_PROMPT = (
    "You are an expert reviewer of macOS app localizations. You judge whether a "
    "translated UI string is accurate, uses the terminology Apple itself uses in "
    "macOS for that concept, preserves format placeholders and glyphs, and reads "
    "naturally to a native speaker. You are precise and you do not invent problems: "
    "if a string is fine, you say nothing about it. Output STRICT JSON only."
)


def build_user_prompt(locale: str, en: dict, tgt: dict) -> str:
    rtl_note = (
        f"\nNOTE: {locale} is a right-to-left language. In `menu.lastFire` the arrow "
        "should be the RTL form (←), not →.\n"
        if locale in RTL else ""
    )
    rows = []
    for key, (comment, en_val) in en.items():
        tgt_val = tgt.get(key, ("", "<<MISSING>>"))[1]
        rows.append(
            {
                "key": key,
                "context": comment,
                "english": en_val,
                "translation": tgt_val,
            }
        )
    payload = json.dumps(rows, ensure_ascii=False, indent=1)
    return f"""Review the **{locale}** translation of the Footswitch macOS app.

For each of the {len(rows)} strings below you are given: the `key`, the English
`context` comment (the authoritative intent), the `english` source value, and the
current `translation`. Judge the translation for: accuracy vs. the English meaning;
whether it is the term Apple uses in macOS for that concept (a literal-but-non-native
term is a MINOR defect); placeholder/glyph integrity (%1$@/%2$@/%@/\\n counts must
match; ⌘⌥⌃⇧ and ⚠️ must stay intact); untranslated tokens ("Footswitch", "GitHub",
"USB", and the copyright "© 2026 Eric Fitzgerald" must be preserved); and length
(concise enough for a menu item, compact label, or narrow table column).{rtl_note}
Classify each finding:
- category OBJECTIVE = factual mistranslation, wrong meaning, grammar/inflection
  error, wrong placeholder/glyph, or untranslated-token violation.
- category STYLISTIC = correct but a more idiomatic/Apple-native term exists.
Set verdict WRONG for objective errors, MINOR for stylistic, UNKNOWN if you cannot
confidently assess. Set "lengthens" to true if your suggestion is visibly longer
than the current value (clipping risk).

Report ONLY non-passing strings. Strings you omit are implicit OK.

Output STRICT JSON with this exact shape (no prose, no markdown fence):
{{"locale": "{locale}",
  "findings": [
    {{"key": "...", "verdict": "MINOR|WRONG|UNKNOWN", "category": "OBJECTIVE|STYLISTIC",
      "lengthens": false, "current_value": "...", "issue": "...", "suggested_value": "..."}}
  ]}}

Strings:
{payload}
"""


# ---------------------------------------------------------------------------
# Output formatting (matches gpt-5-codex combined.md format)
# ---------------------------------------------------------------------------
def _cell(s: object) -> str:
    # Coerce whatever the model returned (str/None/number) and escape pipes/
    # newlines so the markdown table stays one row per finding.
    text = "" if s is None else str(s)
    return text.replace("|", "\\|").replace("\n", "\\n").strip()


def rows_to_md(model_key: str, per_locale: dict[str, list[dict]]) -> str:
    lines = [f"REVIEWER MODEL: {model_key}", "",
             "| locale | key | verdict | current_value | issue | suggested_value |",
             "|--------|-----|---------|---------------|-------|-----------------|"]
    for locale in sorted(per_locale):
        for f in per_locale[locale]:
            lines.append(
                f"| {locale} | {_cell(f.get('key'))} | {_cell(f.get('verdict'))} | "
                f"{_cell(f.get('current_value'))} | {_cell(f.get('issue'))} | "
                f"{_cell(f.get('suggested_value'))} |"
            )
    return "\n".join(lines) + "\n"


def one_locale_md(model_key: str, locale: str, findings: list[dict]) -> str:
    return rows_to_md(model_key, {locale: findings})


# ---------------------------------------------------------------------------
# API call
# ---------------------------------------------------------------------------
_print_lock = threading.Lock()


def log(msg: str) -> None:
    with _print_lock:
        print(msg, file=sys.stderr, flush=True)


def review_one(client, model: Model, locale: str, en: dict, tgt: dict,
               dry_run: bool) -> tuple[str, list[dict], str | None]:
    """Returns (locale, findings, error)."""
    prompt = build_user_prompt(locale, en, tgt)
    if dry_run:
        log(f"[dry-run] {model.key}/{locale}: prompt {len(prompt)} chars, "
            f"{len(en)} strings")
        return locale, [], None
    try:
        resp = client.chat.completions.create(
            model=model.model_id,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": prompt},
            ],
            temperature=0,
            response_format={"type": "json_object"},
        )
        content = resp.choices[0].message.content or "{}"
        data = json.loads(content)
        findings = data.get("findings", [])
        if not isinstance(findings, list):
            return locale, [], f"'findings' not a list: {type(findings)}"
        log(f"[ok] {model.key}/{locale}: {len(findings)} findings")
        return locale, findings, None
    except Exception as e:  # noqa: BLE001 — report any provider/parse error per task
        log(f"[ERR] {model.key}/{locale}: {e}")
        return locale, [], str(e)


# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------
def run_model(model: Model, locales: list[str], en: dict, targets: dict,
              workers: int, dry_run: bool, clean: bool) -> None:
    from openai import OpenAI

    api_key = os.environ.get(model.api_key_env)
    if not api_key and not dry_run:
        log(f"[skip] {model.key}: {model.api_key_env} not set")
        return
    client = None if dry_run else OpenAI(api_key=api_key, base_url=model.base_url)

    out_dir = OUT_ROOT / model.key
    if clean and out_dir.exists() and not dry_run:
        for p in out_dir.glob("*.md"):
            p.unlink()
        for name in ("findings.json", "errors.json"):
            (out_dir / name).unlink(missing_ok=True)
        log(f"[{model.key}] cleaned stale output in {out_dir}")
    out_dir.mkdir(parents=True, exist_ok=True)

    per_locale: dict[str, list[dict]] = {}
    errors: dict[str, str] = {}

    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {
            ex.submit(review_one, client, model, loc, en, targets[loc], dry_run): loc
            for loc in locales
        }
        for fut in cf.as_completed(futs):
            locale, findings, err = fut.result()
            per_locale[locale] = findings
            if err:
                errors[locale] = err
            else:
                # write the per-locale file as soon as it lands (crash-resilient)
                (out_dir / f"{locale}.md").write_text(
                    one_locale_md(model.key, locale, findings), encoding="utf-8")

    if dry_run:
        return

    # combined report
    (out_dir / "combined.md").write_text(rows_to_md(model.key, per_locale), encoding="utf-8")
    # machine-readable dump + error log
    (out_dir / "findings.json").write_text(
        json.dumps(per_locale, ensure_ascii=False, indent=1), encoding="utf-8")
    if errors:
        (out_dir / "errors.json").write_text(
            json.dumps(errors, ensure_ascii=False, indent=1), encoding="utf-8")
        log(f"[{model.key}] completed with {len(errors)} locale error(s): "
            f"{', '.join(sorted(errors))}")
    total = sum(len(v) for v in per_locale.values())
    log(f"[{model.key}] DONE: {len(per_locale)} locales, {total} findings -> {out_dir}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--models", default="grok,gemini",
                    help="comma list of: " + ",".join(MODELS))
    ap.add_argument("--locales", default="",
                    help="comma list of locale codes; default = all on disk (minus en)")
    ap.add_argument("--workers", type=int, default=8,
                    help="thread pool size per model (default 8)")
    ap.add_argument("--dry-run", action="store_true",
                    help="build prompts and report sizes; no API calls, no files")
    ap.add_argument("--clean", action="store_true",
                    help="wipe each model's prior .md/json output before running "
                         "(avoids stale per-locale files when reviewing a subset)")
    args = ap.parse_args()

    if not LOC_DIR.exists():
        log(f"error: localizations dir not found: {LOC_DIR}")
        return 2

    en_path = LOC_DIR / f"{EN}.lproj" / "Localizable.strings"
    en = parse_strings(en_path)
    if not en:
        log(f"error: could not parse English source at {en_path}")
        return 2

    all_locales = [l for l in discover_locales() if l != EN]
    if args.locales:
        want = [s.strip() for s in args.locales.split(",") if s.strip()]
        unknown = [l for l in want if l not in all_locales]
        if unknown:
            log(f"error: unknown locale(s): {', '.join(unknown)}")
            log(f"available: {', '.join(all_locales)}")
            return 2
        locales = want
    else:
        locales = all_locales

    targets = {loc: parse_strings(LOC_DIR / f"{loc}.lproj" / "Localizable.strings")
               for loc in locales}

    model_keys = [s.strip() for s in args.models.split(",") if s.strip()]
    for mk in model_keys:
        if mk not in MODELS:
            log(f"error: unknown model '{mk}'. Known: {', '.join(MODELS)}")
            return 2

    log(f"Reviewing {len(locales)} locales x {len(model_keys)} model(s); "
        f"{len(en)} strings each. Output -> {OUT_ROOT}")

    for mk in model_keys:
        run_model(MODELS[mk], locales, en, targets, args.workers,
                  args.dry_run, args.clean)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
