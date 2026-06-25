---
name: kakeibo-small-sprint
description: Safely research, implement, verify, and merge small changes in the yubnsbski/kakeibo repository. Use for frontend, FastAPI backend, encrypted transaction payloads, amount calculations, category summaries, local setup, and AI handoff work.
---

# kakeibo small sprint

## Goal

Advance one independently verifiable concern at a time without breaking encrypted data, totals, or local reproducibility.

## Read first

1. `AGENTS.md`
2. `docs/danger-points.md`
3. Relevant source and tests
4. `git status --short --branch`
5. Recent commits and open pull requests

Never assume an old handoff reflects the current repository. Verify the branch and files directly.

## Sprint boundary

A sprint should have one primary risk cluster. Good examples:

- safe backend amount calculation
- frontend field order and tax metadata
- day/month/year category aggregation
- local setup and AI handoff

Do not mix an unrelated refactor into a feature sprint. State the target files and validation command before editing.

## Non-negotiable invariants

### Encryption and privacy

- The browser encrypts transaction JSON; the server stores opaque `encrypted_payload`.
- Do not move merchant, category, memo, receipt text, or passphrase into plaintext database columns.
- The amount calculation API receives only the expression and tax rate.
- Never log passphrases, derived keys, decrypted payloads, API keys, or full receipt data.
- Preserve old encrypted payloads. New payload fields must be optional unless a versioned migration is implemented and tested.

### Amount calculation

- Never use `eval`, `exec`, JavaScript `Function`, or a shell calculator for user input.
- Keep the grammar limited to decimal numbers, `+`, `-`, `*`, `/`, unary signs, and parentheses.
- Reject unknown characters, division by zero, non-finite values, excessive length, and excessive nesting.
- Keep yen rounding and included-tax rounding covered by tests.

### Category aggregation

- A transaction total must be counted exactly once.
- Allocate to line-item categories only when all line-item amounts are valid and their sum equals the transaction amount.
- Otherwise fall back to the transaction-level category and expose the fallback count.
- Do not silently rename historical categories. Frontend and legacy backend vocabularies are not fully unified.

### OCR

- Receipt preview sends an image to the backend for OCR.
- `/api/receipts/preview` must not persist the image, OCR text, or plaintext transaction.
- Gemini OCR is optional and requires explicit local key configuration. Tesseract is the fallback.

## Workflow

1. Establish the baseline with the existing verification commands.
2. Create a branch from current `main`.
3. Add or adjust tests before broad UI changes when practical.
4. Implement the smallest complete vertical slice.
5. Review the full diff for privacy, compatibility, double counting, and accidental files.
6. Run:

```bash
bash scripts/verify_local.sh
```

7. Open a pull request that states purpose, changed behavior, compatibility, privacy boundary, tests, and remaining risks.
8. Merge with squash only after all required CI jobs succeed. The repository does not rely on GitHub auto-merge being enabled.
9. Pull `main` locally with:

```bash
bash scripts/sync_local.sh
```

## Before an AI usage limit or tool switch

Stop at a coherent boundary. Do not leave an unreported half-change.

```bash
bash scripts/verify_local.sh
bash scripts/create_handoff.sh
```

Then update `AI_HANDOFF.local.md` with the current task, acceptance conditions, test result, branch, pull request state, and the next smallest action. Review it for sensitive names before pasting it into ChatGPT or another coding assistant.

## Failure handling

- Do not merge failing CI.
- Do not hide a failure by weakening or deleting an unrelated test.
- If a dependency or platform cannot be validated, mark the result as unverified and state what can break.
- If local work is dirty, do not automatically discard or stash it.
