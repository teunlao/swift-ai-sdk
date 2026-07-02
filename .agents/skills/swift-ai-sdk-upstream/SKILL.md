---
name: swift-ai-sdk-upstream
description: "Use for Swift AI SDK upstream parity management: refresh or inspect Vercel AI SDK baselines, scan upstream package coverage, classify drift, plan provider/core/docs audits, land parity fixes with tests, and maintain generated local artifacts under .upstream/ plus durable evidence in upstream/*."
---

# Swift AI SDK Upstream Parity

This skill is the operating protocol for keeping Swift AI SDK aligned with the
Vercel AI SDK. It is not only a "refresh upstream" helper; it manages intake,
coverage mapping, drift triage, audits, fixes, tests, and evidence.

## Authority Model

- Tracked process source: this skill directory.
- Durable parity evidence: `upstream/UPSTREAM.md`, `upstream/PROGRESS.md`, and
  `upstream/providers/*.md`.
- Generated working artifacts: `.upstream/**`. These are local scratch
  artifacts and must stay gitignored.
- Upstream reference checkout: `external/vercel-ai-sdk`. Treat it as read-only
  during audits.

Use generated `.upstream/**` files to decide what to inspect next. Do not cite a
generated artifact as final proof unless it is backed by source paths, tests, and
durable evidence.

## When This Skill Applies

Use this skill when the user asks to:

- update or refresh upstream Vercel AI SDK;
- understand current upstream drift;
- audit provider/core/docs parity;
- add or repair provider behavior;
- update `upstream/*` evidence;
- generate or read upstream package coverage/status reports.

## Required First Steps

1. Read `upstream/UPSTREAM.md` for the pinned baseline.
2. Run or inspect the local component scan:
   ```bash
   node .agents/skills/swift-ai-sdk-upstream/scripts/scan-upstream.js --out .upstream/current
   ```
3. Open `.upstream/current/component-catalog.md` for the current coverage map.
4. Pick exactly one audit scope before editing:
   - `core:<package>`
   - `provider:<package>`
   - `docs:<section>`
   - `intake:<baseline>`

## Scope Rules

- Prefer provider-first vertical slices.
- Touch core only when a provider or public API contract requires it.
- Match observable behavior contracts: request shape, response parsing,
  streaming order, errors, tools, provider options, usage, defaults, and tests.
- Do not chase line-by-line TypeScript diffs for their own sake.
- Do not use `parity/*`; this repo tracks parity through `upstream/*`.
- Do not store generated reports, work queues, or scan snapshots in git.

## Refresh Protocol

Only refresh when the user asks for a refresh or the task requires a newer
baseline.

Latest main:

```bash
rm -rf external/vercel-ai-sdk
git clone --depth 1 https://github.com/vercel/ai external/vercel-ai-sdk
git -C external/vercel-ai-sdk rev-parse HEAD
```

Pinned tag or branch:

```bash
rm -rf external/vercel-ai-sdk
git clone --branch <tag-or-branch> --depth 1 https://github.com/vercel/ai external/vercel-ai-sdk
git -C external/vercel-ai-sdk rev-parse HEAD
```

Specific commit:

```bash
rm -rf external/vercel-ai-sdk
git clone --depth 1 https://github.com/vercel/ai external/vercel-ai-sdk
git -C external/vercel-ai-sdk fetch --depth 1 origin <sha>
git -C external/vercel-ai-sdk checkout <sha>
git -C external/vercel-ai-sdk rev-parse HEAD
```

After a refresh, update `upstream/UPSTREAM.md`, regenerate `.upstream/current`,
and add a short `upstream/PROGRESS.md` note only when the baseline or shipped
parity state meaningfully changed.

## Audit Workflows

### Provider Audit

1. Read the upstream provider implementation, tests, and fixtures under
   `external/vercel-ai-sdk/packages/<provider>/`.
2. Read the matching Swift implementation and tests.
3. Use `references/audit-slices.md` as the checklist.
4. Add or tighten Swift regressions near the changed boundary.
5. Fix the minimal owner-level Swift code required for parity.
6. Run targeted tests, then `AGENT=1 swift test` unless the user explicitly
   narrows verification.
7. Update `upstream/providers/<provider>.md` with:
   - audited commit;
   - verified contracts;
   - Swift and upstream evidence paths;
   - gaps or intentional deviations.

### Core Audit

Use only for `packages/ai`, `packages/provider`, `packages/provider-utils`, or
core contracts required by a provider.

1. Define the exact upstream contract.
2. Read upstream implementation and nearest tests.
3. Read Swift owner code and tests.
4. Add or tighten tests under the matching Swift test target.
5. Fix the owner-level contract.
6. Record evidence in `upstream/PROGRESS.md`; if provider-driven, also update
   the relevant provider page.

### Docs Audit

Use only when the task is docs work or a behavior change needs docs.

1. Copy from `external/vercel-ai-sdk/content/**`.
2. Adapt for Swift and Starlight in `apps/docs/src/content/docs/**`.
3. Update navigation in `apps/docs/astro.config.mjs` when needed.
4. Run `pnpm run docs:check` and `pnpm run docs:build`.

## Status Vocabulary

Use the statuses from `references/component-taxonomy.md`:

- `unknown`
- `mapped`
- `partial`
- `verified`
- `stale`
- `drift`
- `n/a`

Do not mark a component `verified` without an audited commit and concrete Swift
test/source evidence.

## Bundled References

- `references/component-taxonomy.md`: areas, priorities, status meanings, and
  package classification.
- `references/audit-slices.md`: provider/core/docs audit checklist.
- `references/artifacts.md`: generated artifact contract for `.upstream/**`.
- `templates/component-status.md`: durable component/provider status template.
- `templates/work-item.md`: generated work queue item template.

## Fast Commands

```bash
node .agents/skills/swift-ai-sdk-upstream/scripts/scan-upstream.js --out .upstream/current
rg -n "<symbol>" external/vercel-ai-sdk/packages -S
rg -n "<symbol>" Sources Tests -S
AGENT=1 swift test
node tools/test-runner.js --config tools/test-runner.default.config.json
```

## Done Criteria

- The selected scope has a named owner.
- The audited upstream commit is explicit.
- Swift behavior matches the intended upstream contract or a deviation is
  documented.
- Tests cover the contract.
- Generated `.upstream/**` artifacts were used only as local working state.
- Durable evidence in `upstream/*` was updated when parity state changed.
