# Instruction Analysis and Next-Step Plan

## Goal Recap
Build and maintain **only** the receipt classification engine for the household bookkeeping app.

## Scope Constraints (from AGENTS.md)
### In scope
- Merchant normalization
- Category classification
- Confidence calculation
- `needsReview` decision
- Unit tests

### Out of scope
- OCR / image upload
- Database
- Login / UI
- External API connections

## Mandatory Classification Priority
1. User override rules
2. Merchant rules
3. Item keyword rules
4. Ambiguous merchant handling
5. Needs review fallback

## Ambiguous Merchants Policy
These merchants must not be confidently finalized by merchant name alone:
- Amazon
- 楽天
- イオン
- ドン・キホーテ
- メルカリ

If item details are missing, `needsReview=true`.

## Why Previous Work Was Rejected
Recent changes expanded into server, wallet, and automation layers. That created scope drift against the repository policy and made maintainability review harder.

## Proposed Recovery Strategy
### 1) Folder-level documentation organization
Create `docs/review/` to keep decision logs and reduce ambiguity for future tasks.

### 2) Branch discipline
Use feature-scoped branches only, for example:
- `feat/classifier-rule-tuning-*`
- `test/classifier-edge-cases-*`
- `docs/review-*`

### 3) Code-change filter before implementation
For each new task, verify every changed file is one of:
- `src/classifyReceipt.ts`
- `src/normalizeMerchant.ts`
- `src/rules.ts`
- `src/types.ts`
- `tests/classifyReceipt.test.ts`
- fixtures/docs related to classifier behavior

If not, reject or split the task.

### 4) Verification gate
After any code change:
- `npm test`
- `npm run verify`

## Next Execution Plan (Minimal Risk)
1. Keep classification core and tests as the only active development target.
2. Add/adjust tests for rule priority and ambiguous merchants first.
3. Refactor only when tests are green and behavior is unchanged.
4. Keep documentation updates in `docs/review/` for traceability.
