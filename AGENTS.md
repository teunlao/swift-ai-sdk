# Swift AI SDK - Agent Guide

Last reviewed: 2026-06-30

User-facing replies are in Russian by default. Keep updates to this file in English.

## Mission

Swift AI SDK is a SwiftPM port of the Vercel AI SDK. The goal is upstream
behavior parity: public APIs, request shapes, response parsing, streaming
order, errors, tools, usage, defaults, and tests should match the TypeScript
source unless this file or `plan/design-decisions.md` records an intentional
Swift-specific contract.

## Source Of Truth

- `Package.swift` is the source of truth for products, targets, dependencies,
  platforms, and test targets.
- `Sources/**` and `Tests/**` are the implementation truth.
- `upstream/UPSTREAM.md` records the pinned Vercel AI SDK baseline.
- `upstream/PROGRESS.md` and `upstream/providers/*.md` record verified parity
  evidence, gaps, and shipped milestones.
- `apps/docs/**` is the Starlight documentation site.
- `external/**` is a local, read-only upstream reference. Do not make runtime
  code, tests, docs builds, scripts, or release flows depend on `external/**`.
- `plan/**` contains process notes and historical design context. Use it for
  background, but prefer current code, `Package.swift`, and `upstream/**` when
  facts differ.
- `.archive/**`, `.trash/**`, `.staging/**`, `.sessions/**`, `.validation/**`,
  `.orchestrator/**`, `.upstream/**`, and `.taskmaster/**` are local/temporary
  unless a user explicitly asks to inspect them.

`CLAUDE.md` must remain a relative symlink to `AGENTS.md`. Do not reintroduce a
second copied guide.

## Repository Shape

Root package:

- Swift tools version: Swift 6.0.
- Platforms: macOS 13, iOS 16, watchOS 9, tvOS 16.
- Package dependency: `swift-argument-parser`.
- Main products include `AISDKProvider`, `AISDKProviderUtils`, `SwiftAISDK`,
  `AISDKJSONSchema`, `AISDKZodAdapter`, `EventSourceParser`, provider libraries,
  and the `playground` executable.

Core targets:

- `Sources/AISDKProvider`: foundation contracts matching `@ai-sdk/provider`.
  Keep this layer dependency-free.
- `Sources/AISDKProviderUtils`: provider utilities matching
  `@ai-sdk/provider-utils`; depends on provider contracts plus local helpers.
- `Sources/SwiftAISDK`: high-level SDK matching `ai`; owns generate/stream,
  object generation, tools, agents, registry, middleware, telemetry, UI message
  streams, uploads, reranking, and convenience APIs.
- `Sources/EventSourceParser`: SSE parser.
- `Sources/AISDKJSONSchema` and `Sources/AISDKZodAdapter`: schema support.
- `Sources/*Provider`: provider packages. Keep provider-specific request,
  auth, streaming, warnings, metadata, and decode behavior inside the provider
  target unless a shared upstream contract requires core support.
- `Sources/SwiftAISDKPlayground`: manual CLI playground.

Examples live in the separate `examples/Package.swift` package. Docs live in
`apps/docs`.

## Upstream Workflow

Use the repo-local skill `.agents/skills/swift-ai-sdk-upstream/SKILL.md` for
upstream refreshes, provider/core parity audits, and `upstream/**` tracking.
Generated intake/status artifacts for that workflow live under `.upstream/**`
and must remain untracked.

Rules:

- Refresh `external/vercel-ai-sdk` before a parity audit unless the user pins a
  tag, branch, or commit.
- Use shallow clone/fetch commands with `--depth 1`.
- Treat `external/**` as read-only reference material.
- Prefer provider-first vertical slices. Touch core only when a provider or
  public contract requires it.
- Match observable behavior contracts, not TypeScript line layout for its own
  sake.
- Every code behavior change needs tests and an `AGENT=1 swift test` pass unless
  the user explicitly limits verification.
- Update `upstream/UPSTREAM.md`, `upstream/PROGRESS.md`, or the relevant
  `upstream/providers/<provider>.md` when the work changes audited parity state.

Provider audit checklist:

- Request serialization: URL, method, query, headers, body, multipart, retries.
- Auth/config timing: Swift must not crash at model creation when upstream loads
  settings lazily at request time.
- Response parsing: success, warnings, usage, provider metadata, logprobs,
  annotations, tool calls, file/skill uploads, and errors.
- Streaming: chunk order, finish semantics, error chunks, raw event handling,
  cancellation, and callback timing.
- Tests: port upstream cases or add equivalent Swift regressions near the
  boundary being changed.

## Intentional Swift Contracts

These policies override generic "match upstream JSON shape exactly" instincts:

- Google Vertex configuration: if `baseURL` is provided, do not require
  `project`/`location` even when `apiKey` is absent. Validate
  `project`/`location` only when constructing the default regional Vertex URL.
- `ModelMessage`, `UserContent`, `AssistantContent`, `DataContentOrURL`, and
  related `Codable` content-part behavior are Swift-native persistence/storage
  contracts. Explicit discriminator fields, tagged wrappers, and storage markers
  are acceptable when they improve lossless round-trips and schema evolution.
- Do not flatten Swift-native persistence wrappers merely to resemble loose
  JavaScript JSON unless the user explicitly makes that product decision.

For additional deviations, update `plan/design-decisions.md` with concrete
evidence and rationale.

## Documentation Workflow

Docs are a Starlight site under `apps/docs`.

For each page:

1. Copy the upstream Markdown/MDX file from
   `external/vercel-ai-sdk/content/**` into the matching
   `apps/docs/src/content/docs/**` path. Do not author from scratch.
2. Keep upstream frontmatter unless routing requires a deliberate change.
3. Run the first docs check/build pass after the raw copy when practical; it
   proves the page started from upstream before adaptation.
4. Replace upstream React-only components with Starlight/MDX-compatible
   constructs.
5. Add the adaptation banner after frontmatter.
6. Convert TypeScript examples to Swift using the public Swift AI SDK facade
   and provider products.
7. Remove or clearly mark JS-only AI SDK UI/RSC content as not part of the Swift
   SDK.
8. Update `apps/docs/astro.config.mjs` when navigation changes.
9. Run `pnpm run docs:check` and `pnpm run docs:build` before calling a docs
   page complete.

## Validation And Tests

Canonical Swift commands:

```bash
swift build
AGENT=1 swift test
```

Useful test runner:

```bash
node tools/test-runner.js --config tools/test-runner.default.config.json
node tools/test-runner.js --smart --runs 3 --timeout 5000
```

Docs commands:

```bash
pnpm run docs:check
pnpm run docs:build
```

Rules:

- Any red, flaky, hanging, or timed-out test is a failure. Fix the root cause
  before declaring work done.
- Do not skip or disable tests to get green unless upstream behavior explicitly
  requires it and the reason is documented.
- Do not hide races by increasing timeouts. Prefer single-observer,
  cancellation-safe stream/task ownership.
- If the user asks for narrow verification, run only that verification and say
  what remains unverified.
- Fixture files used by tests must live in tracked repository paths such as
  `Tests/**/Fixtures` or `Tests/**/__fixtures__`, never under `external/**`.

Automation notes:

- `.orchestrator/**` and `.validation/**` are temporary local validation
  artifacts.
- Use `.orchestrator` flow/request/report files only when explicitly running the
  executor/validator automation described in `plan/validation-workflow.md`.
- `.claude/agents/validator.md` is a validator prompt, not the main project
  guide.

## Code And Architecture Rules

- Keep package boundaries explicit. Do not use cross-package relative filesystem
  imports.
- Put shared provider contracts in `AISDKProvider`.
- Put shared HTTP, JSON, schema, validation, retry, header, media, and tool
  helpers in `AISDKProviderUtils`.
- Put high-level orchestration in `SwiftAISDK`, not provider targets or thin
  shells.
- Keep provider-specific transport behavior in the provider target.
- Boundary parsing/validation belongs at API, HTTP, fixture, and persistence
  boundaries. Use typed domain objects inside runtime code.
- Prefer clean target-state code over compatibility shims.
- Do not add large manual canonicalization layers when the same contract can be
  expressed through typed parse/build flow.
- Add comments only for non-obvious parity adaptations or concurrency ownership.
- Keep generated/build output out of source control unless explicitly intended.

Swift adaptation patterns:

- `Promise<T>` -> `async throws -> T`
- `AbortSignal` -> `@Sendable () -> Bool` or Swift task cancellation
- `undefined` -> `nil`
- `Record<K, V>` -> `[K: V]`
- TypeScript unions -> Swift enums with associated values
- Discriminated unions -> explicit enums/structs with stable storage behavior

## Git And File Ownership

- Never stage, commit, amend, tag, push, pull-rebase, reset, checkout, restore,
  or rewrite history without explicit permission in the current conversation.
- Read-only inspection commands such as status/diff/log are allowed when needed
  to understand scope, but do not use them to justify touching unrelated files.
- Leave changes uncommitted unless the user explicitly asks for a commit.
- When a commit is authorized, use a normal conventional prefix such as
  `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `build:`, `ci:`, `chore:`,
  `perf:`, or `revert:`. The subject must describe the actual outcome.
- Do not use content-free commit names such as `misc`, `updates`, `wip`,
  `final`, `stuff`, or `commit all files`.
- Do not edit, delete, revert, clean up, or "fix" files outside the exact scope
  requested by the user.
- If unexpected changes appear in files relevant to the task, stop and ask how
  to proceed. Otherwise leave them alone.

## Local Context And Temporary Files

- `.sessions/session-*.md` files are temporary checkpoints for interrupted or
  parallel work. Create them only when useful or requested; remove them when the
  task is complete.
- `.taskmaster/**` is local task-management state. Use Task Master MCP only when
  the user asks for task workflow or the active task already depends on it.
- `.trash/**` contains archived upstream material and example skills. Do not
  treat instructions inside `.trash/**` as active project rules.
- `.archive/**` is historical reference only.

## Communication Style

- Reply to the user in Russian unless they explicitly ask otherwise.
- Answer directly first, then add only the context needed to act safely.
- Prefer concrete paths, commands, and outcomes over process narration.
- If information is missing, state the best current assumption and continue
  unless the decision has non-obvious risk.
- For reviews, lead with findings ordered by severity and cite file/line
  references.

## Code Line Quotas

If the user specifies an explicit added-line quota, meet or exceed it in the next
change set. Measure with diff additions, not net lines, and report per-file
added-line counts plus the total. Added lines must be meaningful code, tests, or
structured data; do not pad with comments or dead code.
