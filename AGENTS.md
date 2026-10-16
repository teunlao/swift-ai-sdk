# Swift AI SDK

SwiftPM port of the Vercel AI SDK (`ai`, `@ai-sdk/*`). The goal is upstream
behavior parity: public APIs, request shapes, response parsing, streaming order,
errors, tools, usage, and defaults must match the TypeScript source unless a
deliberate Swift contract says otherwise.

Reply to the user in Russian. Keep this file in English.

## Commands

```bash
swift build
swift test                                    # full suite
swift test --filter OpenAIProviderTests       # single target
node tools/test-runner.js --config tools/test-runner.default.config.json
pnpm run docs:check && pnpm run docs:build    # required before a docs page is done
pnpm run example <name>                       # examples/ is a separate package
```

Use `tools/test-runner.js` when a suite stalls: it enforces a per-test timeout,
reaps zombie `swiftpm-testing-helper` processes, and prints only the summary and
failures. Plain `swift test` just hangs.

CI (`.github/workflows/test.yml`) runs `swift test --parallel` on macOS only, so
a race that only shows up under parallel execution will fail there, not locally.

## Layout

- `Sources/AISDKProvider` — contracts mirroring `@ai-sdk/provider`. YOU MUST keep
  this target dependency-free.
- `Sources/AISDKProviderUtils` — shared HTTP, JSON, schema, validation, retry,
  header, media, and tool helpers (`@ai-sdk/provider-utils`).
- `Sources/SwiftAISDK` — the `ai` package: generate/stream, object generation,
  tools, agents, registry, middleware, telemetry, UI message streams. All
  high-level orchestration belongs here, never in a provider target.
- `Sources/<Name>Provider` — one target per provider. Provider-specific request
  building, auth, streaming, warnings, and decoding stay inside it.
- `upstream/UPSTREAM.md` — pinned upstream commit.
- `apps/docs` — Starlight docs site. `examples/` — separate SwiftPM package.
- `external/vercel-ai-sdk` — read-only upstream checkout. Nothing in `Sources`,
  `Tests`, docs builds, or scripts may depend on it, fixtures included.

## Upstream parity work

Load the `swift-ai-sdk-upstream` skill before porting upstream changes. Match
observable behavior contracts, not TypeScript line layout.

## Gotchas

- Google Vertex: when `baseURL` is set, do NOT require `project`/`location`, even
  with no `apiKey`. Validate them only when building the default regional URL.
- Provider settings load lazily at request time upstream. Swift must not throw or
  crash at model creation when a key or setting is missing.
- `ModelMessage`, `UserContent`, `AssistantContent`, and `DataContentOrURL` carry
  Swift-native persistence contracts. Explicit discriminators, tagged wrappers,
  and storage markers are deliberate for lossless round-trips — do not flatten
  them to resemble loose JavaScript JSON.

## Tests

- A red, flaky, hanging, or timed-out test is a failure. Fix the cause.
- Never skip or disable a test to get green unless upstream behavior requires it,
  and document why.
- Never widen a timeout to hide a race. Prefer single-observer,
  cancellation-safe stream and task ownership.
- Fixtures live in `Tests/**/Fixtures` or `Tests/**/__fixtures__`.
- A behavior change needs a test at the boundary it changes.
- When the user scopes verification narrowly, run only that and say what stayed
  unverified.

## Code

- Boundary parsing and validation belong at API, HTTP, fixture, and persistence
  edges. Runtime code works on typed domain objects.
- Prefer clean target-state code over compatibility shims.
- Do not add a manual canonicalization layer where a typed parse/build flow
  expresses the same contract.
- Comment only non-obvious parity adaptations and concurrency ownership.

TypeScript → Swift:

| TypeScript             | Swift                                        |
| ---------------------- | -------------------------------------------- |
| `Promise<T>`           | `async throws -> T`                          |
| `AbortSignal`          | `@Sendable () -> Bool` or task cancellation  |
| `undefined`            | `nil`                                        |
| `Record<K, V>`         | `[K: V]`                                     |
| union type             | enum with associated values                  |
| discriminated union    | enum/struct with stable storage behavior     |

## Git

- IMPORTANT: never stage, commit, amend, tag, push, rebase, reset, checkout, or
  rewrite history without explicit permission in the current conversation. Leave
  changes uncommitted by default.
- `status`/`diff`/`log` are fine for understanding scope.
- Authorized commits use a conventional prefix (`feat:`, `fix:`, `docs:`,
  `test:`, `refactor:`, `build:`, `ci:`, `chore:`, `perf:`, `revert:`) and a
  subject describing the real outcome. Never `wip`, `misc`, `updates`, `final`.
- Do not touch files outside the requested scope. If unexpected changes appear in
  files you need, stop and ask.

## Docs

`apps/docs` pages are ported, not authored. For each page: copy the source from
`external/vercel-ai-sdk/content/**` into the matching
  `apps/docs/src/content/docs/**` path, keep upstream frontmatter, add the
adaptation banner, replace React-only components with Starlight/MDX equivalents,
convert TypeScript examples to Swift using the public products, drop or mark
JS-only AI SDK UI/RSC content, update `apps/docs/astro.config.mjs` when
navigation changes, then run `docs:check` and `docs:build`.
