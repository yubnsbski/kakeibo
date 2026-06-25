# AGENTS.md

## Scope

This file applies to the entire repository. The project is no longer classifier-only; it contains a TypeScript classifier, a Python mirror, a React/Vite frontend, and a FastAPI/SQLite backend.

When a task conflicts with an older component document, verify the current code and this file first. Do not follow historical statements that UI, OCR, database, or API code does not exist.

## Architecture

- `src/`, `tests/`, `fixtures/`: pure TypeScript receipt classification and evaluation.
- `python/`: standard-library Python mirror of the classifier.
- `frontend/`: React/Vite UI. Transaction JSON is encrypted and decrypted in the browser.
- `backend/`: FastAPI, SQLModel, SQLite, OCR preview, encrypted payload persistence, and safe amount calculation.
- `backend/app/crypto_models.py`: server-side models for salt/configuration and opaque encrypted transactions.
- `frontend/src/crypto/txPayload.ts`: encrypted payload types and backward-compatible normalization.
- `frontend/src/crypto/periodSummary.ts`: day/month/year category aggregation.
- `backend/app/calculation.py`: allowed arithmetic grammar and tax calculation.

## Required invariants

### Encryption and privacy

- The server must not interpret or log `encrypted_payload`.
- Merchant, category, memo, receipt text, line items, passphrase, and derived keys remain browser-side plaintext only.
- `/api/calculations/amount` receives only an amount expression and tax rate.
- `/api/receipts/preview` may process an uploaded image, but must not persist the image, OCR text, or plaintext transaction.
- Never commit `.env`, API keys, database files, uploaded receipt images, handoff files, or decrypted data.
- A lost passphrase cannot be recovered by the server. Do not imply otherwise.

### Payload compatibility

- Existing encrypted payload version 1 records may not contain `amount_expression`, `tax_rate`, or `tax_amount`.
- Additive fields must remain optional unless a versioned migration and migration tests are supplied.
- Never rewrite all encrypted records implicitly during display or aggregation.

### Amount expressions and tax

- Do not use `eval`, `exec`, JavaScript `Function`, shell evaluation, or third-party expression evaluators for user input.
- The accepted grammar is decimal numbers, `+`, `-`, `*`, `/`, unary signs, and parentheses.
- Keep validation for unknown characters, length, nesting depth, division by zero, finite results, positive yen results, and tax-rate range.
- Keep yen rounding and included-tax rounding covered by tests.
- Default tax rates are UI defaults, not legal classification. Users must be able to correct them.

### Aggregation

- Count each transaction amount exactly once.
- Use line-item categories only when every line-item amount is valid and their sum equals the transaction amount.
- Otherwise use the transaction-level category and amount, and surface the fallback count.
- Invalid dates and decryption failures must be excluded visibly rather than silently converted.

### Categories

- Category vocabularies are not fully unified across the frontend, legacy CSV/backend code, and historical encrypted records.
- Do not silently rename historical categories or assume two labels are equivalent without an explicit mapping and tests.
- Preserve unknown historical categories in edit controls.

## Classification rules

For classifier changes, also read `docs/classification-policy.md` and preserve this priority:

1. user correction rule
2. merchant rule
3. line-item keyword rule
4. ambiguous merchant handling
5. review fallback

Amazon, Rakuten, Aeon, Don Quijote, Mercari, and comparable marketplaces must not be finalized from merchant name alone when line-item evidence is absent.

Keyword mining may emit candidates, but must not overwrite `src/rules.ts` automatically. Review candidates and compare evaluation results before applying them.

## Small-sprint workflow

1. Read the relevant implementation, tests, `docs/danger-points.md`, and current Git state.
2. State one primary risk cluster, target files, compatibility impact, and validation commands.
3. Create a branch from current `main`.
4. Implement the smallest complete vertical slice.
5. Review the full diff for privacy leaks, schema drift, double counting, stale generated files, and unrelated edits.
6. Run the narrow test while editing, then the repository verification before opening or merging a pull request.
7. Open a pull request with purpose, behavior, privacy boundary, compatibility, tests, and remaining risks.
8. Squash merge only after all required CI jobs succeed.

Do not discard, reset, clean, or automatically stash a user's local changes.

## Setup and verification

First setup:

```bash
bash scripts/setup_local.sh
```

Optional Gemini OCR SDK:

```bash
bash scripts/setup_local.sh --with-gemini
```

Full local verification:

```bash
bash scripts/verify_local.sh
```

Useful narrow checks:

```bash
npm run typecheck
npm test
cd frontend && npm run build
cd backend && .venv/bin/python -m unittest discover -s tests -p 'test_*.py'
```

Local start:

```bash
bash scripts/start.sh
```

## Dependency changes

- Explain why a dependency is needed and whether it is runtime or optional.
- Pin backend direct dependencies in `backend/requirements.txt` or `backend/requirements-gemini.txt`.
- Keep `package-lock.json` files synchronized with their `package.json` files.
- Validate backend application import in CI after dependency changes.
- Tesseract's Python wrapper is not the OCR engine binary; document the system package separately.

## AI continuation

Before changing tools or reaching a usage limit:

```bash
bash scripts/verify_local.sh
bash scripts/create_handoff.sh
```

Update the generated `AI_HANDOFF.local.md` with the current task, acceptance conditions, validation result, branch/PR state, unresolved risks, and next smallest action. Review it before sharing because filenames and commit messages are included.

The reusable workflow is defined in `.claude/skills/kakeibo-small-sprint/SKILL.md`.
