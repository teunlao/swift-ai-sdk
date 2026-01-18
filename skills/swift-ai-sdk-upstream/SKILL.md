---
name: swift-ai-sdk-upstream
description: "Workflow for long-term maintenance of swift-ai-sdk against Vercel AI SDK upstream: refresh external/vercel-ai-sdk via shallow clone (--depth 1), audit provider/core parity (TS→Swift), track progress in markdown, and land fixes with tests."
---

# Swift AI SDK Upstream Maintenance

## Canonical upstream reference

- Upstream repo: `https://github.com/vercel/ai`
- Local reference mirror: `external/vercel-ai-sdk/` (read-only reference, not shipped)
- **Rule:** when updating upstream reference, always use a **shallow clone**: `--depth 1` (no sparse checkout).

**Depth (git clone):** `--depth 1` fetches only the latest commit (no history) → faster, smaller, enough for code reference/parity work.

## Quick start (typical flow)

1) Refresh upstream reference (when requested)
- Delete `external/vercel-ai-sdk/`
- Re-clone upstream with `--depth 1`
- Record the new upstream commit hash in `upstream/UPSTREAM.md`

2) Pick a target (provider-first)
- Prefer provider parity (behavior/streaming/errors/tools) over core refactors.
- Work in small vertical slices: upstream TS file(s) → matching Swift file(s) → tests.

3) Ship safely
- Add/adjust tests for every behavior change.
- Run `swift test` until green.

## When user says “обнови upstream версию”

Use exactly this sequence (depth 1, no sparse):

```bash
rm -rf external/vercel-ai-sdk
git clone --depth 1 https://github.com/vercel/ai external/vercel-ai-sdk
git -C external/vercel-ai-sdk rev-parse HEAD
```

Then update `upstream/UPSTREAM.md`:
- Set `Upstream commit` to the new hash
- Set `Last refreshed` to today’s date

## Parity audit workflow (TS → Swift)

Goal: match upstream observable behavior, not “similar-looking code”.

### 1) Locate upstream source of truth

Upstream packages live under:
- `external/vercel-ai-sdk/packages/provider/src/**`
- `external/vercel-ai-sdk/packages/provider-utils/src/**`
- `external/vercel-ai-sdk/packages/ai/src/**`
- Provider packages: `external/vercel-ai-sdk/packages/<provider>/src/**` (e.g. `anthropic`, `openai`, etc.)

### 2) Locate Swift counterpart

Swift targets:
- `Sources/AISDKProvider/**` ↔ upstream `packages/provider`
- `Sources/AISDKProviderUtils/**` ↔ upstream `packages/provider-utils`
- `Sources/SwiftAISDK/**` ↔ upstream `packages/ai`
- `Sources/<ProviderName>Provider/**` ↔ upstream `packages/<provider>`

### 3) Audit by file (not by git diff)

For each upstream file you touch:
- Read the full upstream implementation (branches, defaults, error paths).
- Compare to Swift implementation line-by-line.
- Fix the minimal set of Swift code to match behavior.

Useful commands:

```bash
# Find upstream implementation
rg -n \"function|class|export\" external/vercel-ai-sdk/packages/<pkg>/src -S

# Find Swift equivalent
rg -n \"<TypeOrFunctionName>\" Sources -S
```

### 4) Tests (scenario parity)

- Port upstream scenarios; Swift tests may not be text-identical, but must cover the same behaviors.
- Prefer tests close to the boundary (prompt conversion, HTTP payloads, decoding, streaming mappers).

## Progress tracking (agent-first markdown)

Keep progress in `upstream/` (not scripts):
- `upstream/UPSTREAM.md` — pinned upstream commit + refresh history
- `upstream/PROGRESS.md` — high-level checklist + current priorities
- `upstream/providers/<provider>.md` — per-provider parity notes (what’s verified, what’s missing)

Use the templates in `upstream/` and keep each entry tied to an upstream commit hash.

