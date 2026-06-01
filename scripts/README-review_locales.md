# review_locales.py — direct-API translation review

Reviews the app's `.lproj` translations against external LLMs (Grok / Gemini)
**without coding agents** — plain API calls, one request per (model, locale),
parallelized with a thread pool. Output matches the format the existing
`.localization-reviews/claude-pipeline/merge.py` consumes.

## Prerequisites

- [`uv`](https://docs.astral.sh/uv/) (already used here).
- API keys in the environment:
  - `XAI_API_KEY` — Grok (xAI)
  - `GOOGLE_API_KEY` — Gemini (Google AI Studio / Generative Language API)

Both providers are called through their OpenAI-compatible chat endpoints, so the
single `openai` SDK drives both (see `MODELS` in the script).

## Run

```bash
# from the repo root
export XAI_API_KEY=...
export GOOGLE_API_KEY=...

# all locales, both models
uv run --project scripts scripts/review_locales.py

# a subset
uv run --project scripts scripts/review_locales.py --models grok --locales de,fr,ja

# wipe a model's prior output first (avoids stale per-locale files on subset runs)
uv run --project scripts scripts/review_locales.py --clean

# validate prompts/parsing without spending tokens (no keys needed)
uv run --project scripts scripts/review_locales.py --dry-run
```

Override model IDs via `XAI_MODEL` / `GOOGLE_MODEL` env vars if needed
(defaults: `grok-4`, `gemini-2.5-pro`).

## Output

Written under `.localization-reviews/external-model-reviews/<model>/` (gitignored):

- `<locale>.md` — one report per successfully-reviewed locale.
- `combined.md` — all locales in one file, headed `REVIEWER MODEL: <model>`, in
  the exact table format `merge.py` expects (so a new model folds into the
  existing 2-of-N agreement flow with no changes).
- `findings.json` — machine-readable `{locale: [findings]}`.
- `errors.json` — any per-locale API/parse failures (only written if some occur).

A locale that errors out is recorded in `errors.json` and simply omitted from the
reports — re-run with `--locales <those>` to retry just the failures.

## How findings are used

Drop a fresh `combined.md` into the merge step the same way `gpt-5-codex`'s was:
it becomes another independent vote. Native-speaker review for a locale still
overrides any automated verdict — apply that reviewer's calls directly and clear
the locale from `docs/localization-review-backlog.md`.

## Notes

- `temperature=0` and `response_format=json_object` for determinism + clean parsing.
- The script never edits the `.strings` files; it only produces review reports.
- Re-running is safe and idempotent per model; use `--clean` when narrowing scope.
