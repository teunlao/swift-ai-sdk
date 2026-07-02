# Upstream Parity Progress

This folder is the source of truth for “what is verified” vs “what is unknown” against a specific upstream commit.

Rules:
- Always tie statements to an upstream commit hash from `upstream/UPSTREAM.md`.
- Prefer provider parity work (prompt ↔ HTTP ↔ decode ↔ streaming) over core refactors.
- Keep docs short and actionable: checklists + links to Swift/upstream paths.

## Current core audit status

Audited against upstream commit: `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`
for the current `core:provider`, `core:provider-utils`, and `core:ai`
foundation slices.

Status:
- `core:provider`: partial/current. Swift now has the V4 provider, model,
  realtime, middleware, shared-file, warning, and provider-reference foundation,
  but concrete provider targets still need native V4 vertical migrations.
- `core:ai`: partial/current. Swift high-level model resolution and runtime
  entrypoints now use the V4 rail for text, object, embed, rerank, image,
  speech, transcription, and experimental video flows while preserving V3/V2
  compatibility through adapters; URL-backed video and transcription downloads
  now use shared `createDownload`/`DownloadFileFunction` hooks.
- `core:provider-utils`: partial/current for the shared content/data helper
  support touched by the V4 prompt/upload flow and provider-reference
  detection/resolution, V4 reasoning-to-provider mapping helpers, and shared
  header, filename, same-origin URL, nullable filtering, line extraction, and
  media-type detection/resolution, inline file-data conversion, and multipart
  form-data helpers, plus shared download URL validation, manual redirect
  validation, size-limit reads, download error wrapping, model-option workflow
  serialization, streaming tool-call tracking, provider tool-name mapping, and
  JSON Schema additional-properties normalization for standard schemas, plus
  the shared `asArray` normalization helper, response-body cancellation, and
  delayed-promise primitive, baseURL trailing-slash normalization, and browser
  runtime detection. The Swift-applicable `@ai-sdk/provider-utils` export
  surface is now audited against this baseline; remaining provider-utils work
  is provider-driven integration behavior, not unidentified exported helper
  drift.

Latest validation:
- `2026-07-02`: `AGENT=1 swift test`
  passed all 3973 Swift Testing tests.
- `2026-07-02`: `node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3973 selected tests.
- `2026-07-02`: `pnpm run examples:build`
  built the examples package successfully.
- `2026-07-02`: `pnpm run docs:check` and `pnpm run docs:build`
  passed; the docs build generated 53 pages.

## Known gaps / TODO

- [ ] Migrate concrete provider targets to native V4 contracts in
  provider-first vertical slices.
- [ ] Keep provider-utils re-audits tied to provider-driven integration slices.
  The Swift-applicable exported helper/type surface has current evidence; JS
  runtime/type-only exports such as Node `Buffer` guards, TypeScript
  conditional types, workflow serde symbols, and external EventSource parser
  re-exports are classified as Swift `n/a` unless a concrete Swift runtime
  contract later needs them.
- [ ] Re-audit stale P0 provider pages against
  `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`.
- [ ] Decide whether new upstream P1 providers `anthropic-aws`, `quiverai`, and
  `voyage` should get Swift targets or be marked intentionally out of scope.

## Current priorities

1) Providers parity (tools, streaming, errors)
2) Core API parity only when blocked by providers
3) Docs updates only after behavior parity is green

## Current upstream intake snapshot

### 2026-06-30: `ai@7.0.8` / upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `intake:latest-main`.

Evidence:
- `external/vercel-ai-sdk` refreshed from upstream `main` to `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`.
- `npm view ai version time.modified --json` reported `7.0.8`, modified `2026-06-30T04:05:57.112Z`.
- Generated local artifacts:
  - `.upstream/current/component-catalog.md`
  - `.upstream/refresh-2026-06-30/package-diff.md`
  - `.upstream/refresh-2026-06-30/work-queue.md`

Important interpretation:
- No component should be treated as `verified` against the current baseline until
  it is re-audited against `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`.
- The previous baseline was `4891db8bfc583d3767831dac83439ac190c93cb0`
  from 2026-04-15. The current upstream package line is major-version newer
  across core and most providers (`ai` 7.x, `provider` 4.x,
  `provider-utils` 5.x, `openai` 4.x, `anthropic` 4.x).
- This pass refreshed intake artifacts only. It did not claim runtime parity,
  port behavior, or update provider-specific verification checklists.

Component scan summary:

| Priority | Status | Count | Components |
| --- | --- | ---: | --- |
| P0 | stale | 8 | `ai`, `provider`, `provider-utils`, `anthropic`, `gateway`, `google`, `google-vertex`, `openai` |
| P0 | mapped | 1 | `openai-compatible` has an intake tracking page but no audited commit |
| P1 | stale | 29 | Existing Swift provider targets with old audited commits |
| P1 | mapped | 3 | `baseten`, `moonshotai`, `open-responses` have Swift owners and intake tracking pages but no audited commit |
| P1 | unknown | 3 | `anthropic-aws`, `quiverai`, `voyage` are upstream provider packages with intake tracking pages but no Swift owner target |
| P2 | n/a | 5 | Framework packages: `angular`, `react`, `rsc`, `svelte`, `vue` |
| P3 | n/a | 20 | Upstream tooling/internal packages, including new `harness*`, `sandbox-*`, `policy-opa`, `tui`, `workflow-harness` |

Added upstream packages since the previous catalog:
- Runtime provider surface: `anthropic-aws`, `quiverai`, `voyage`.
- Tooling/internal surface: `harness`, `harness-claude-code`,
  `harness-codex`, `harness-deepagents`, `harness-opencode`, `harness-pi`,
  `policy-opa`, `sandbox-just-bash`, `sandbox-vercel`, `tui`,
  `workflow-harness`.

Recommended audit order:
1) Re-audit P0 core contracts first: `provider`, `provider-utils`, then `ai`.
2) Audit `openai-compatible`, because it is P0 and currently only `mapped`.
3) Re-audit P0 providers by blast radius: `openai`, `anthropic`, `gateway`,
   `google`, `google-vertex`.
4) Triage missing P1 provider surface: decide whether Swift should add
   `anthropic-aws`, `voyage`, and `quiverai`, or mark them intentionally out of
   scope.
5) After P0 contracts stabilize, sweep stale P1 providers in provider-first
   vertical slices.

### 2026-06-30: `core:provider` audit start against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider`.

Initial finding:
- Upstream `@ai-sdk/provider` is now centered on `ProviderV4` and v4 model
  contracts. Swift `AISDKProvider` still exposes `ProviderV3` as the main
  provider protocol and only contains a small v4 upload/shared slice.
- Swift currently has v4 files/skills/shared support, but no provider-level
  `ProviderV4` and no Swift equivalents for upstream `LanguageModelV4`,
  `EmbeddingModelV4`, `ImageModelV4`, `RealtimeModelV4`, `RerankingModelV4`,
  `SpeechModelV4`, `TranscriptionModelV4`, or v4 middlewares.
- `ProviderV4` renamed the embedding factory surface from v3
  `textEmbeddingModel` to `embeddingModel`, adds optional `files()` and
  `skills()` upload surfaces, and does not include `videoModel` on the provider
  protocol even though upstream exports standalone v4 video model contracts.
- `LanguageModelV4CallOptions` adds the normalized `reasoning` effort option
  (`provider-default`, `none`, `minimal`, `low`, `medium`, `high`, `xhigh`).
  Swift `LanguageModelV3CallOptions` has no corresponding core field.
- `LanguageModelV4Content` adds `custom` content and `reasoning-file` parts.
  Swift `LanguageModelV3Content` does not represent either content variant.
- Non-language v4 model protocols are not present in Swift. Some of their
  shapes are close to the existing V3 Swift contracts, but they still need
  explicit v4 types because they switch to shared v4 options/metadata and
  `specificationVersion: "v4"`.
- `VideoModelV4CallOptions` has new input surfaces for `frameImages`,
  `inputReferences`, and `generateAudio`; Swift `VideoModelV3CallOptions`
  only has a single `image` input and cannot represent these upstream v4
  video-generation modes.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider/src/provider/v4/provider-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/language-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/language-model-v4-call-options.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/language-model-v4-content.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/video-model/v4/video-model-v4-call-options.ts`
- Swift: `Sources/AISDKProvider/ProviderV3.swift`
- Swift: `Sources/AISDKProvider/LanguageModel/V3/LanguageModelV3.swift`
- Swift: `Sources/AISDKProvider/LanguageModel/V3/LanguageModelV3CallOptions.swift`
- Swift: `Sources/AISDKProvider/LanguageModel/V3/LanguageModelV3Content.swift`
- Swift: `Sources/AISDKProvider/VideoModel/VideoModelV3CallOptions.swift`

Implementation slice 1: shared v4 foundation:
- Added Swift `SharedV4FileData` for upstream tagged `data` / `url` /
  `reference` / `text` file data.
- Added `SharedV4Headers` and `NoSuchProviderReferenceError`.
- Replaced the `SharedV4Warning = SharedV3Warning` alias with a real v4
  warning enum, including upstream `deprecated`.
- Extended the upload data subset used by files/skills to include upstream
  text payloads, and aligned `SkillsV4File` to the upstream `data` field while
  preserving the previous Swift `content` initializer/property as compatibility
  sugar.
- Updated Anthropic files/skills upload consumers to send text payloads as
  UTF-8 multipart file bodies.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'SharedV4TypesTests|ProviderErrorsTests|AnthropicFilesTests|AnthropicSkillsTests'`
  passed 40 Swift Testing tests.
- `AGENT=1 swift test --filter 'UploadFileTests|UploadSkillTests'`
  passed 8 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider/src/shared/v4/shared-v4-file-data.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/shared/v4/shared-v4-headers.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/shared/v4/shared-v4-warning.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/errors/no-such-provider-reference-error.ts`
- Swift: `Sources/AISDKProvider/Shared/V4/SharedV4FileData.swift`
- Swift: `Sources/AISDKProvider/Shared/V4/SharedV4Headers.swift`
- Swift: `Sources/AISDKProvider/Shared/V4/SharedV4Warning.swift`
- Swift: `Sources/AISDKProvider/Errors/NoSuchProviderReferenceError.swift`
- Swift tests: `Tests/AISDKProviderTests/SharedV4TypesTests.swift`

Implementation slice 2: v4 provider and model contract surface:
- Added Swift `ProviderV4` with upstream factory shape:
  `languageModel`, renamed `embeddingModel`, `imageModel`, optional
  `transcriptionModel`, `speechModel`, `rerankingModel`, `files`, and `skills`.
- Added `LanguageModelV4` core contracts, call options, prompt/message parts,
  generated content parts, stream parts, finish reason, usage, tools, and
  response/request info.
- Included upstream V4 language deltas over V3:
  normalized `reasoning` effort (`provider-default`, `none`, `minimal`,
  `low`, `medium`, `high`, `xhigh`), `custom` content, `reasoning-file`
  content, `SharedV4FileData` prompt file input, and shared v4 warnings /
  metadata.
- Added explicit non-language V4 model contracts for embedding, image,
  reranking, speech, transcription, and video.
- Included new v4 video generation inputs: `frameImages`, `inputReferences`,
  and `generateAudio`.
- Left existing provider implementations on V3. This slice establishes the
  public foundation and compile-checked shapes; provider-by-provider migration
  remains a separate vertical parity task.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'ProviderV4ContractTests|SharedV4TypesTests|ProviderErrorsTests|AnthropicFilesTests|AnthropicSkillsTests|UploadFileTests|UploadSkillTests'`
  passed 53 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderTests`
  passed 151 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider/src/provider/v4/provider-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/**`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/embedding-model/v4/**`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/image-model/v4/**`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/reranking-model/v4/**`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/speech-model/v4/**`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/transcription-model/v4/**`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/video-model/v4/**`
- Swift: `Sources/AISDKProvider/ProviderV4.swift`
- Swift: `Sources/AISDKProvider/LanguageModel/V4/**`
- Swift tests: `Tests/AISDKProviderTests/ProviderV4ContractTests.swift`

Implementation slice 3: realtime and middleware v4 foundation:
- Added Swift `RealtimeModelV4` and `RealtimeFactoryV4` contract surfaces for
  upstream realtime client-secret creation, websocket config, session config,
  client-event serialization, server-event normalization, and optional health
  check responses.
- Added explicit realtime session/config shapes for output modalities, audio
  formats, transcription config, turn detection, tool definitions, conversation
  items, client events, and normalized server events.
- Added V4 middleware contract surfaces for language, embedding, and image
  models, including provider/model-id overrides, supported-url overrides,
  parameter transformation hooks, and generate/embed/stream wrappers.
- Kept this slice as provider-foundation only. It does not add websocket
  runtime orchestration or migrate concrete providers from V3 to V4.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'RealtimeV4MiddlewareTests|ProviderV4ContractTests|SharedV4TypesTests|ProviderErrorsTests|AnthropicFilesTests|AnthropicSkillsTests|UploadFileTests|UploadSkillTests'`
  passed 56 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderTests`
  passed 154 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider/src/realtime-model/v4/**`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model-middleware/v4/language-model-v4-middleware.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/embedding-model-middleware/v4/embedding-model-v4-middleware.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/image-model-middleware/v4/image-model-v4-middleware.ts`
- Swift: `Sources/AISDKProvider/RealtimeModel/RealtimeModelV4.swift`
- Swift: `Sources/AISDKProvider/LanguageModel/Middleware/LanguageModelV4Middleware.swift`
- Swift: `Sources/AISDKProvider/EmbeddingModel/Middleware/EmbeddingModelV4Middleware.swift`
- Swift: `Sources/AISDKProvider/ImageModel/Middleware/ImageModelV4Middleware.swift`
- Swift tests: `Tests/AISDKProviderTests/RealtimeV4MiddlewareTests.swift`

### 2026-06-30: `core:ai` V4 model adapter foundation against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:ai`.

Initial finding:
- Upstream `@ai-sdk/ai` now resolves model inputs to V4 model contracts via
  `resolve-model.ts` and the `as*ModelV4` / `asProviderV4` adapter layer.
- Swift `Sources/SwiftAISDK/Model/ResolveModel.swift` still resolves only
  language and embedding inputs to V3 contracts. Other AI-level call sites
  still accept raw V3 model aliases and locally guard `specificationVersion`.
- Swift `customProvider` and `ProviderRegistry` remain V3-only. This slice does
  not migrate registry behavior yet; it creates the V4 adapter rail that the
  runtime call sites can move onto in later slices.

Implementation slice 4: AI-level V4 model adapters and resolution helpers:
- Added public Swift adapter entry points mirroring upstream intent:
  `asProviderV4`, `asLanguageModelV4`, `asEmbeddingModelV4`, `asImageModelV4`,
  `asRerankingModelV4`, `asSpeechModelV4`, `asTranscriptionModelV4`, and
  `asVideoModelV4`.
- Added public V4 resolution helpers for AI-owned code:
  `resolveLanguageModelV4`, `resolveEmbeddingModelV4`, plus direct V3/V4
  helper overloads for image, reranking, speech, transcription, and video.
- Added a `ProviderV3 -> ProviderV4` bridge that maps V3 language, embedding,
  image, transcription, speech, and reranking factories to V4 adapters while
  intentionally returning `nil` for V4 files/skills surfaces (V3 providers do
  not own those upload capabilities).
- Added explicit V3->V4 adapters for language, embedding, image, reranking,
  speech, transcription, and video models. The adapters preserve core result
  fields such as usage, warnings, provider metadata, response metadata, files,
  segments, rankings, and generated media.
- Added strict guards for V4-only input surfaces that V3 models cannot
  faithfully represent:
  - language `reasoning` call option
  - language prompt `custom` and `reasoning-file` parts
  - provider-reference file data when adapting V4 prompt input to V3
  - video `frameImages`, `inputReferences`, and `generateAudio`
  - video V3 generated outputs missing required V4 `mediaType`
- Kept existing V3 `resolveLanguageModel` / `resolveEmbeddingModel` behavior
  unchanged. Downstream `generate*`, `embed*`, `rerank`, speech,
  transcription, and video runtime migration remains a separate behavioral
  slice.

Validation:
- `swift build`
- `AGENT=1 swift test --filter ResolveModelV4Tests`
  passed 5 Swift Testing tests.
- `AGENT=1 swift test --filter 'ResolveModelV4Tests|ResolveLanguageModelTests|ResolveEmbeddingModelTests|ProviderRegistryTests'`
  passed 21 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-provider-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-language-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-embedding-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-image-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-reranking-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-speech-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-transcription-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-video-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/resolve-model.ts`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/Model/ResolveModel.swift`
- Swift tests: `Tests/SwiftAISDKTests/Model/ResolveModelV4Tests.swift`

Implementation slice 5: embed runtime V4 migration:
- Migrated AI-level `embed` and `embedMany` runtime entrypoints from the legacy
  V3 resolver path to `resolveEmbeddingModelV4`, matching upstream
  `packages/ai/src/embed/embed.ts` and `embed-many.ts`.
- Aligned Swift `EmbeddingModel` with the current upstream text-embedding
  model input union: `string | EmbeddingModelV4 | EmbeddingModelV3 |
  EmbeddingModelV2<string>`.
- Added direct V4 embedding model overloads while preserving V2/V3 provider
  compatibility through the existing V3->V4 adapter rail.
- Promoted public AI-level embedding result response fields to
  `EmbeddingModelV4ResponseInfo` and added `warnings` to `EmbedResult` and
  `EmbedManyResult`, so V4 provider warnings are no longer dropped.
- Extended warning logging with an embedding-model V4 warning variant and kept
  legacy V3 warnings mapped into V4 result warnings through shared embed
  helpers.
- Preserved existing `embedMany` batching, max-parallel-call behavior, usage
  aggregation, provider metadata merge semantics, and response collection while
  moving the model call options and results to V4.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'EmbedTests|EmbedManyTests|ResolveModelV4Tests|ResolveModelTests'`
  passed 40 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/embed/embed.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/embed/embed-many.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/embed/embed-result.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/embed/embed-many-result.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/embedding-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/warning.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/embedding-model/v4/**`
- Swift: `Sources/SwiftAISDK/Types/EmbeddingModel.swift`
- Swift: `Sources/SwiftAISDK/Embed/Embed.swift`
- Swift: `Sources/SwiftAISDK/Embed/EmbedMany.swift`
- Swift: `Sources/SwiftAISDK/Embed/EmbedResult.swift`
- Swift: `Sources/SwiftAISDK/Embed/EmbedManyResult.swift`
- Swift: `Sources/SwiftAISDK/Logger/LogWarnings.swift`
- Swift tests: `Tests/SwiftAISDKTests/Embed/EmbedTests.swift`
- Swift tests: `Tests/SwiftAISDKTests/Embed/EmbedManyTests.swift`
- Swift tests: `Tests/SwiftAISDKTests/TestSupport/TestEmbeddingModel.swift`

Implementation slice 6: language model input V4 resolver alignment:
- Aligned the public AI-level `LanguageModel` input union with upstream by
  adding direct `LanguageModelV4` support alongside string, V3, and V2 inputs.
- Updated `resolveLanguageModelV4` to return direct V4 language models without
  routing them through the legacy V3 resolver/adaptation path.
- Kept `resolveLanguageModel` as an explicit legacy V3 resolver and made it
  reject direct V4 language models with `UnsupportedModelVersionError`, matching
  the embedding-model migration pattern from slice 5.
- Added a reusable Swift `MockLanguageModelV4` test model and direct V4
  resolver coverage that proves V4-only call options and V4 warnings pass
  through without V3 downgrade.
- This slice intentionally does not migrate `generateText`, `streamText`,
  `generateObject`, or `streamObject` runtime execution yet; those still need
  dedicated V4 result/type migration work.

Validation:
- `swift build`
- `AGENT=1 swift test --filter ResolveModelV4Tests`
  passed 6 Swift Testing tests.
- `AGENT=1 swift test --filter ResolveModelTests`
  passed 9 Swift Testing tests.
- `AGENT=1 swift test --filter 'ResolveModelV4Tests|ResolveModelTests|EmbedTests|EmbedManyTests'`
  passed 42 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/language-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/resolve-model.ts`
- Swift: `Sources/SwiftAISDK/Types/LanguageModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ResolveModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/Test/MockLanguageModelV4.swift`
- Swift tests: `Tests/SwiftAISDKTests/Model/ResolveModelV4Tests.swift`
- Swift tests: `Tests/SwiftAISDKTests/Model/ResolveModelTests.swift`

Implementation slice 7: V4 reasoning call option foundation:
- Added upstream V4 language reasoning effort to the public AI-level
  `CallSettings` surface via `LanguageModelV4ReasoningEffort`.
- Preserved the setting through `PreparedCallSettings` and every current
  language-runtime preparation site (`generateText`, `streamText`,
  `generateObject`, and `streamObject`), so the eventual V4 runtime call path
  can pass it to `LanguageModelV4CallOptions` without another public API
  migration.
- Kept current V3 runtime calls unchanged. This slice does not pretend V3
  providers can consume V4-only `reasoning`; actual provider delivery remains
  blocked on migrating language runtimes to V4 call options.
- Added prompt settings tests for reasoning pass-through and equality
  semantics.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'PrepareCallSettingsTests|ResolveModelV4Tests|ResolveModelTests|EmbedTests|EmbedManyTests'`
  passed 50 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/prompt/language-model-call-options.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/prompt/prepare-language-model-call-options.ts`
- Swift: `Sources/SwiftAISDK/Prompt/CallSettings.swift`
- Swift: `Sources/SwiftAISDK/Prompt/PrepareCallSettings.swift`
- Swift: `Sources/SwiftAISDK/GenerateText/GenerateText.swift`
- Swift: `Sources/SwiftAISDK/GenerateText/StreamText.swift`
- Swift: `Sources/SwiftAISDK/GenerateObject/GenerateObject.swift`
- Swift: `Sources/SwiftAISDK/GenerateObject/StreamObject.swift`
- Swift tests: `Tests/SwiftAISDKTests/Prompt/PrepareCallSettingsTests.swift`

Implementation slice 8: V4 language usage conversion foundation:
- Added `asLanguageModelUsage(_ usage: LanguageModelV4Usage)` so upcoming
  V4 language runtime calls can preserve provider usage details without
  down-converting through V3 usage types.
- Mapped V4 input token totals, no-cache/cache-read/cache-write details,
  output text/reasoning details, raw provider usage, and derived total token
  count into the existing AI-level `LanguageModelUsage` contract.
- Added focused tests for populated V4 usage and nil-total behavior.

Validation:
- `swift build`
- `AGENT=1 swift test --filter LanguageModelUsageTests`
  passed 2 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/language-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/usage.ts`
- Swift: `Sources/SwiftAISDK/Types/Usage.swift`
- Swift tests: `Tests/SwiftAISDKTests/Types/LanguageModelUsageTests.swift`

Implementation slice 9: `generateText` V4 runtime foundation:
- Migrated non-streaming `generateText` from the legacy V3 language model call
  path to `resolveLanguageModelV4` + `LanguageModelV4CallOptions`.
- Added V4 prompt and tool preparation rails alongside the existing V3 rails:
  `convertToLanguageModelV4Prompt`, `convertToLanguageModelV4Message`, and
  `prepareToolsAndToolChoiceV4`.
- Preserved V3 model/provider compatibility through the existing V3->V4 model
  adapter while allowing direct `LanguageModelV4` models to receive V4 prompt,
  tool, toolChoice, providerOptions, headers, and `reasoning` call options.
- Mapped V4 response content into AI-level `ContentPart`, including V4-only
  `custom` and `reasoning-file` content, V4 `Source`, V4 `CallWarning`
  (`deprecated` included), and V4 usage.
- Kept `streamText`, `generateObject`, and `streamObject` on their current V3
  runtime rails for this slice, but converted their public boundary aliases
  (`FinishReason`, `CallWarning`, `Source`) to the V4 AI-level contract so the
  SDK has one current public language-model surface.
- Added direct V4 contract coverage proving `generateText` calls a V4 model
  with V4 prompt/tools/toolChoice/reasoning/providerOptions and preserves V4
  response content/warnings in the result.

Validation:
- `swift build`
- `AGENT=1 swift test --filter GenerateTextV4Tests`
  passed 1 Swift Testing test.
- `AGENT=1 swift test --filter GenerateTextTests`
  passed 48 Swift Testing tests.
- `AGENT=1 swift test --filter GenerateTextAdvancedTests`
  passed 45 Swift Testing tests.
- `AGENT=1 swift test --filter GenerateObjectTests`
  passed 29 Swift Testing tests.
- `AGENT=1 swift test --filter StreamTextSSEIntegrationTests`
  passed 16 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3791 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-text/generate-text.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/prompt/convert-to-language-model-prompt.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/prompt/prepare-tools-and-tool-choice.ts`
- Swift: `Sources/SwiftAISDK/GenerateText/GenerateText.swift`
- Swift: `Sources/SwiftAISDK/Prompt/ConvertToLanguageModelPrompt.swift`
- Swift: `Sources/SwiftAISDK/Prompt/PrepareToolsAndToolChoice.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateText/GenerateTextV4Tests.swift`

Implementation slice 10: `streamText` V4 runtime foundation:
- Migrated streaming `streamText` from the legacy V3 language model stream
  call path to `resolveLanguageModelV4` + `LanguageModelV4CallOptions`.
- Preserved V3 model/provider compatibility through the V3->V4 model adapter,
  while direct `LanguageModelV4` stream models now receive V4 prompt, tools,
  toolChoice, providerOptions, headers, and normalized `reasoning` options.
- Updated `StreamTextActor` to consume `LanguageModelV4StreamPart` directly and
  map V4 stream output into AI-level `TextStreamPart` / `ContentPart`.
- Added stream support for V4-only `custom` and `reasoning-file` chunks across
  full stream, content aggregation, SSE encoding, event/log streams, and tests.
- Kept the existing stream actor ownership model for continuation steps, tool
  approvals, provider-deferred tool results, abort/timeout behavior, and
  replayable full/text stream broadcasters.
- `generateObject` and `streamObject` remain on their current V3 runtime rails
  after this slice.

Validation:
- `swift build`
- `AGENT=1 swift test --filter StreamTextV4Tests`
  passed 1 Swift Testing test.
- `AGENT=1 swift test --filter StreamTextTests`
  passed 42 Swift Testing tests.
- `AGENT=1 swift test --filter StreamText`
  passed 114 Swift Testing tests.
- `AGENT=1 swift test --filter GenerateTextV4Tests`
  passed 1 Swift Testing test.
- `AGENT=1 swift test --filter GenerateTextTests`
  passed 48 Swift Testing tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-text/stream-text.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-text/stream-language-model-call.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/language-model-v4-stream-part.ts`
- Swift: `Sources/SwiftAISDK/GenerateText/StreamText.swift`
- Swift: `Sources/SwiftAISDK/GenerateText/StreamTextActor.swift`
- Swift: `Sources/SwiftAISDK/GenerateText/TextStreamPart.swift`
- Swift: `Sources/SwiftAISDK/GenerateText/GeneratedFileV4.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateText/StreamTextV4Tests.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateText/StreamTextTests.swift`

Implementation slice 11: `generateObject` and `streamObject` V4 runtime foundation:
- Migrated non-streaming `generateObject` from the legacy V3 language model
  call path to `resolveLanguageModelV4` + `LanguageModelV4CallOptions`.
- Migrated streaming `streamObject` from the legacy V3 language model stream
  call path to `resolveLanguageModelV4` + `LanguageModelV4CallOptions`.
- Preserved V3 model/provider compatibility through the existing V3->V4
  adapter, while direct `LanguageModelV4` object models now receive V4 prompt,
  responseFormat, providerOptions, headers, and normalized `reasoning` options.
- Updated object telemetry to serialize V4 prompt messages for the object
  runtime call span.
- Updated object request/result plumbing to consume V4 request metadata,
  response metadata, warnings, finish reasons, provider metadata, and V4 usage
  without down-converting through V3 types.
- Kept object streaming semantics focused on text deltas and partial JSON
  validation. V4-only non-text stream chunks such as `custom` and
  `reasoning-file` are ignored by `streamObject`, matching the upstream object
  stream transformer behavior.

Validation:
- `swift build`
- `AGENT=1 swift test --filter GenerateObjectV4Tests`
  passed 2 Swift Testing tests.
- `AGENT=1 swift test --filter 'GenerateObjectTests|StreamObjectTests|GenerateObjectV4Tests'`
  passed 40 Swift Testing tests.
- `git diff --check`
- `AGENT=1 swift test --filter 'GenerateObject|StreamObject|GenerateTextV4Tests|StreamTextV4Tests|ResolveModelV4Tests'`
  passed 48 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3794 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-object/generate-object.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-object/stream-object.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-object/output-strategy.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/language-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/language-model/v4/language-model-v4-call-options.ts`
- Swift: `Sources/SwiftAISDK/GenerateObject/GenerateObject.swift`
- Swift: `Sources/SwiftAISDK/GenerateObject/StreamObject.swift`
- Swift: `Sources/SwiftAISDK/GenerateObject/GenerateObjectShared.swift`
- Swift: `Sources/SwiftAISDK/GenerateObject/GenerateObjectTelemetry.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateObject/GenerateObjectV4Tests.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateObject/GenerateObjectTests.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateObject/StreamObjectTests.swift`

Implementation slice 12: V4-first registry, custom provider, and string model resolution:
- Migrated AI-level V4 string model resolution away from the legacy V3 resolver:
  `resolveLanguageModelV4(.string)` and `resolveEmbeddingModelV4(.string)`
  now resolve through a V4 provider first, with legacy V3 task/global providers
  adapted through `asProviderV4`.
- Added `globalDefaultProviderV4` and task-local `withGlobalProviderV4` helpers
  so V4 runtime paths can resolve string model IDs without requiring a V3
  provider shape.
- Added upstream-style `customProviderV4`, including direct V4 model
  dictionaries, legacy V3 model dictionaries adapted to V4, optional files and
  skills surfaces, and V3 fallback-provider compatibility via `asProviderV4`.
- Kept legacy `customProvider` as a V3 source-compatible API because Swift
  cannot make one concrete type conform to `ProviderV3` and `ProviderV4` at
  once: the protocols share factory method names but require different return
  types.
- Reworked `ProviderRegistry` to be V4-first internally: legacy V3 provider
  registries are normalized to `[String: ProviderV4]` at creation time, direct
  V4 providers use the upstream-style `createProviderRegistry` overload
  (with `createProviderRegistryV4` kept as an explicit Swift alias), and
  registry accessors now throw recoverable errors instead of crashing through
  `fatalError`.
- Preserved V3 language-model middleware behavior for legacy providers by
  applying the middleware before adapting the resolved model to V4.
- Kept experimental video registry support backed by legacy V3 provider video
  models and adapted returned video models to V4. Direct V4 provider video
  factory parity remains separate because Swift `ProviderV4` intentionally
  mirrors upstream and does not include `videoModel`.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'ProviderRegistryTests|ResolveModelV4Tests|ResolveLanguageModelTests|ResolveEmbeddingModelTests'`
  passed 28 Swift Testing tests.
- `AGENT=1 swift test --filter 'ProviderRegistryTests|ResolveModelV4Tests|ResolveLanguageModelTests|ResolveEmbeddingModelTests|GenerateTextV4Tests|StreamTextV4Tests|GenerateObjectV4Tests|EmbedTests|EmbedManyTests'`
  passed 59 Swift Testing tests.
- `git diff --check -- Sources/SwiftAISDK/Registry/CustomProvider.swift Sources/SwiftAISDK/Registry/ProviderRegistry.swift Sources/SwiftAISDK/Model/ResolveModel.swift Sources/SwiftAISDK/Model/ModelV4Adapters.swift Tests/SwiftAISDKTests/Model/ProviderRegistryTests.swift Tests/SwiftAISDKTests/Model/ResolveModelV4Tests.swift`
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3799 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/resolve-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/registry/custom-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/registry/provider-registry.ts`
- Swift: `Sources/SwiftAISDK/Model/ResolveModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/Registry/CustomProvider.swift`
- Swift: `Sources/SwiftAISDK/Registry/ProviderRegistry.swift`
- Swift tests: `Tests/SwiftAISDKTests/Model/ResolveModelV4Tests.swift`
- Swift tests: `Tests/SwiftAISDKTests/Model/ProviderRegistryTests.swift`

Implementation slice 13: `rerank` V4 runtime foundation:
- Aligned AI-level `RerankingModel` with upstream as a Swift input union:
  string model IDs, direct `RerankingModelV4`, and legacy `RerankingModelV3`.
- Added `resolveRerankingModelV4(_:)` for the AI-level union. Direct V4 models
  are returned as-is, V3 models adapt through `asRerankingModelV4`, and string
  IDs resolve through the V4 global/default provider path.
- Migrated `rerank` runtime calls from `RerankingModelV3CallOptions` /
  `RerankingModelV3DoRerankResult` to `RerankingModelV4CallOptions` /
  `RerankingModelV4Result`.
- Preserved source-compatible `rerank(model: any RerankingModelV3, ...)`
  overloads for text and JSON documents, and added direct V4 overloads.
- Updated reranking warning logging to use `SharedV4Warning`, including V4
  `deprecated` warning support, while V3 provider warnings still adapt through
  the V3->V4 model adapter.
- Kept concrete reranking providers on their existing V3 implementations for
  this slice. Provider-by-provider native V4 migration remains a separate
  provider parity task.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'RerankTests|ResolveModelV4Tests|ProviderRegistryTests'`
  passed 29 Swift Testing tests.
- `AGENT=1 swift test --filter 'ProviderRegistryTests|ResolveModelV4Tests|ResolveLanguageModelTests|ResolveEmbeddingModelTests|GenerateTextV4Tests|StreamTextV4Tests|GenerateObjectV4Tests|EmbedTests|EmbedManyTests|RerankTests'`
  passed 69 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3801 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/rerank/rerank.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/rerank/rerank-result.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/reranking-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/reranking-model/v4/**`
- Swift: `Sources/SwiftAISDK/Types/RerankingModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/Rerank/Rerank.swift`
- Swift: `Sources/SwiftAISDK/Logger/LogWarnings.swift`
- Swift tests: `Tests/SwiftAISDKTests/Rerank/RerankTests.swift`

Implementation slice 14: `generateImage` V4 runtime foundation:
- Aligned AI-level `ImageModel` with the current upstream input union:
  string model IDs, direct `ImageModelV4`, legacy `ImageModelV3`, and legacy
  `ImageModelV2`.
- Added `resolveImageModelV4(_:)` for the AI-level union. Direct V4 models are
  returned as-is, V3 models adapt through `asImageModelV4`, V2 models adapt
  through the upstream-equivalent V2->V3->V4 bridge, and string IDs resolve
  through the V4 global/default provider path.
- Migrated `generateImage` runtime calls from `ImageModelV3CallOptions` /
  `ImageModelV3GenerateResult` to `ImageModelV4CallOptions` /
  `ImageModelV4GenerateResult`.
- Updated image prompt normalization to produce `ImageModelV4File` inputs,
  including upstream-style `http*` URL detection and data-URL/base64/binary
  file conversion.
- Promoted AI-level image warnings, provider metadata, and usage to the V4
  provider contracts. V3 provider warnings, metadata, usage, and files still
  adapt through the compatibility rail.
- Preserved source-compatible `generateImage` / `experimental_generateImage`
  overloads for direct V3 models and V3 image files, while adding direct V4
  overloads.
- Added reusable `MockImageModelV4` test support and direct V4 runtime tests
  proving V4 call options, V4-only deprecated warnings, V4 usage, and string
  model resolution through `customProviderV4`.
- Kept concrete image providers on their existing V3 implementations for this
  slice. Provider-by-provider native V4 migration remains a separate provider
  parity task.

Validation:
- `swift build`
- `AGENT=1 swift test --filter GenerateImageTests`
  passed 21 Swift Testing tests.
- `AGENT=1 swift test --filter 'ProviderRegistryTests|ResolveModelV4Tests|ResolveModelTests|GenerateImageTests|GenerateTextV4Tests|StreamTextV4Tests|GenerateObjectV4Tests|EmbedTests|EmbedManyTests|RerankTests'`
  passed 90 Swift Testing tests.
- `git diff --check -- Sources/SwiftAISDK/Types/ImageModel.swift Sources/SwiftAISDK/Types/Usage.swift Sources/SwiftAISDK/Logger/LogWarnings.swift Sources/SwiftAISDK/GenerateImage/GenerateImage.swift Sources/SwiftAISDK/GenerateImage/GenerateImagePrompt.swift Sources/SwiftAISDK/GenerateImage/Exports.swift Sources/SwiftAISDK/Model/ModelV4Adapters.swift Sources/SwiftAISDK/Test/MockImageModelV4.swift Tests/SwiftAISDKTests/GenerateImage/GenerateImageTests.swift upstream/PROGRESS.md`
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3803 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-image/generate-image.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-image/generate-image-result.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/image-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/warning.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-image-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-image-model-v3.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/image-model/v4/**`
- Swift: `Sources/SwiftAISDK/Types/ImageModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/GenerateImage/GenerateImage.swift`
- Swift: `Sources/SwiftAISDK/GenerateImage/GenerateImagePrompt.swift`
- Swift: `Sources/SwiftAISDK/GenerateImage/Exports.swift`
- Swift: `Sources/SwiftAISDK/Test/MockImageModelV4.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateImage/GenerateImageTests.swift`

Implementation slice 15: `generateSpeech` V4 runtime foundation:
- Aligned AI-level `SpeechModel` with the current upstream input union:
  string model IDs, direct `SpeechModelV4`, legacy `SpeechModelV3`, and legacy
  `SpeechModelV2`.
- Added `resolveSpeechModelV4(_:)` for the AI-level union. Direct V4 models are
  returned as-is, V3 models adapt through `asSpeechModelV4`, V2 models adapt
  through the upstream-equivalent V2->V3->V4 bridge, and string IDs resolve
  through the V4 global/default provider path.
- Migrated `generateSpeech` runtime calls from `SpeechModelV3CallOptions` /
  `SpeechModelV3Result` to `SpeechModelV4CallOptions` /
  `SpeechModelV4Result`.
- Promoted AI-level speech warnings to the V4 provider contract, including V4
  `deprecated` warning support. V3/V2 provider warnings still adapt through the
  compatibility rail.
- Preserved source-compatible `generateSpeech` / `experimental_generateSpeech`
  overloads for direct V3 and V2 models, while adding direct V4 overloads.
- Added reusable `MockSpeechModelV4` test support and direct V4 runtime tests
  proving V4 call options, V4-only deprecated warnings, response metadata, and
  string model resolution through `customProviderV4`.
- Kept concrete speech providers on their existing V3/V2 implementations for
  this slice. Provider-by-provider native V4 migration remains a separate
  provider parity task.

Validation:
- `swift build`
- `AGENT=1 swift test --filter GenerateSpeechTests`
  passed 10 Swift Testing tests.
- `AGENT=1 swift test --filter 'ProviderRegistryTests|ResolveModelV4Tests|ResolveModelTests|GenerateImageTests|GenerateSpeechTests|RerankTests|EmbedTests|EmbedManyTests|GenerateTextV4Tests|StreamTextV4Tests|GenerateObjectV4Tests'`
  passed 100 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3805 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-speech/generate-speech.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-speech/generate-speech-result.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/speech-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/warning.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-speech-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-speech-model-v3.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/speech-model/v4/**`
- Swift: `Sources/SwiftAISDK/Types/SpeechModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/GenerateSpeech/GenerateSpeech.swift`
- Swift: `Sources/SwiftAISDK/GenerateSpeech/Index.swift`
- Swift: `Sources/SwiftAISDK/Test/MockSpeechModelV4.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateSpeech/GenerateSpeechTests.swift`

Implementation slice 16: `transcribe` V4 runtime foundation:
- Aligned AI-level `TranscriptionModel` with the current upstream input union:
  string model IDs, direct `TranscriptionModelV4`, legacy
  `TranscriptionModelV3`, and legacy `TranscriptionModelV2`.
- Added `resolveTranscriptionModelV4(_:)` for the AI-level union. Direct V4
  models are returned as-is, V3 models adapt through `asTranscriptionModelV4`,
  V2 models adapt through an explicit compatibility bridge, and string IDs
  resolve through the V4 global/default provider path.
- Migrated `transcribe` runtime calls from `TranscriptionModelV3CallOptions` /
  `TranscriptionModelV3Result` to `TranscriptionModelV4CallOptions` /
  `TranscriptionModelV4Result`.
- Promoted AI-level transcription warnings to the V4 provider contract,
  including V4 `deprecated` warning support. V3/V2 provider warnings still
  adapt through the compatibility rail.
- Preserved source-compatible `transcribe` overloads for direct V3 and V2
  models, while adding a direct V4 overload.
- Added reusable `MockTranscriptionModelV4` test support and direct V4 runtime
  tests proving V4 call options, V4-only deprecated warnings, response
  metadata, and string model resolution through `customProviderV4`.
- Kept concrete transcription providers on their existing V3/V2
  implementations for this slice. Provider-by-provider native V4 migration
  remains a separate provider parity task.

Validation:
- `swift build`
- `AGENT=1 swift test --filter TranscribeTests`
  passed 10 Swift Testing tests.
- `AGENT=1 swift test --filter 'ProviderRegistryTests|ResolveModelV4Tests|ResolveModelTests|GenerateImageTests|GenerateSpeechTests|TranscribeTests|RerankTests|EmbedTests|EmbedManyTests|GenerateTextV4Tests|StreamTextV4Tests|GenerateObjectV4Tests'`
  passed 110 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3807 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/transcribe/transcribe.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/transcribe/transcribe-result.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/transcription-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/transcription-model-response-metadata.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/warning.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-transcription-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-transcription-model-v3.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/transcription-model/v4/**`
- Swift: `Sources/SwiftAISDK/Types/TranscriptionModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/Transcribe/Transcribe.swift`
- Swift: `Sources/SwiftAISDK/Test/MockTranscriptionModelV4.swift`
- Swift tests: `Tests/SwiftAISDKTests/Transcribe/TranscribeTests.swift`

Implementation slice 17: `experimental_generateVideo` V4 runtime foundation:
- Aligned AI-level `VideoModel` with the current upstream input union:
  string model IDs, direct `VideoModelV4`, and legacy `VideoModelV3`.
- Added `resolveVideoModelV4(_:)` for the AI-level union. Direct V4 models are
  returned as-is, V3 models adapt through `asVideoModelV4`, and string IDs
  resolve through the legacy/raw global provider path because upstream video
  factories remain experimental and are not part of `ProviderV4`.
- Migrated `experimental_generateVideo` runtime calls from
  `VideoModelV3CallOptions` / `VideoModelV3GenerateResult` to
  `VideoModelV4CallOptions` / `VideoModelV4GenerateResult`.
- Promoted AI-level video warnings and provider metadata to the V4 provider
  contracts, including V4 `deprecated` warning support. V3 provider warnings,
  media outputs, and metadata still adapt through the compatibility rail.
- Added V4 video input surfaces to the AI-level runtime:
  `frameImages`, `inputReferences`, and `generateAudio`.
- Implemented upstream conflict handling for `frameImages` vs
  `inputReferences`, and for `prompt.image` vs a `first_frame` frame image.
  These conflicts emit AI-level `.other` warnings and use the same precedence
  rules as upstream.
- Updated prompt/image normalization to produce `VideoModelV4File` inputs while
  preserving URL, data-URL, base64, and binary image behavior.
- Preserved source-compatible `experimental_generateVideo` overloads for
  direct V3 models and text prompts, while adding direct V4 overloads and the
  enum/string model entrypoint.
- Added reusable `MockVideoModelV4` test support and direct V4 runtime tests
  proving V4 call options, V4-only input surfaces, warning precedence, and
  string model resolution through the legacy global provider path.
- Kept concrete video providers on their existing V3 implementations for this
  slice. Provider-by-provider native V4 migration remains a separate provider
  parity task.

Validation:
- `swift build`
- `AGENT=1 swift test --filter GenerateVideoTests`
  passed 28 Swift Testing tests.
- `AGENT=1 swift test --filter 'ProviderRegistryTests|ResolveModelV4Tests|ResolveModelTests|GenerateImageTests|GenerateSpeechTests|TranscribeTests|GenerateVideoTests|RerankTests|EmbedTests|EmbedManyTests|GenerateTextV4Tests|StreamTextV4Tests|GenerateObjectV4Tests'`
  passed 138 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3809 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-video/generate-video.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/generate-video/generate-video-result.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/video-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/video-model-response-metadata.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/types/warning.ts`
- Upstream: `external/vercel-ai-sdk/packages/ai/src/model/as-video-model-v4.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/video-model/v4/**`
- Swift: `Sources/SwiftAISDK/Types/VideoModel.swift`
- Swift: `Sources/SwiftAISDK/Model/ModelV4Adapters.swift`
- Swift: `Sources/SwiftAISDK/GenerateVideo/GenerateVideo.swift`
- Swift: `Sources/SwiftAISDK/GenerateVideo/GenerateVideoExports.swift`
- Swift: `Sources/SwiftAISDK/Test/MockVideoModelV4.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateVideo/GenerateVideoTests.swift`

### 2026-07-02: `core:provider-utils` provider-reference helpers against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `isProviderReference` and
  `resolveProviderReference` as shared helpers for the provider-reference map
  shape used by V4 file data.
- Swift already had the core `SharedV4ProviderReference` type and
  `NoSuchProviderReferenceError`, but no common provider-utils owner for
  detecting reference maps or resolving a provider-specific identifier.
- Without this utility layer, future provider uploads and V4 file-reference
  consumers would need to duplicate the same guard/error behavior inside
  concrete provider targets.

Implementation slice 18: provider-reference detection and resolution:
- Added public `isProviderReference(_:)` to recognize Swift provider-reference
  maps while rejecting tagged content/file data, binary data, URLs, nulls, and
  maps whose provider identifiers are not strings.
- Added public `resolveProviderReference(reference:provider:)`, returning the
  requested provider identifier or throwing the existing
  `NoSuchProviderReferenceError` with the original reference payload.
- Kept the helper in `AISDKProviderUtils`, because the behavior is a shared
  provider utility over `AISDKProvider` V4 contracts rather than a concrete
  provider transport concern.

Validation:
- `swift build`
- `AGENT=1 swift test --filter ProviderReferenceTests`
  passed 4 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 322 Swift Testing tests.
- `git diff --check`
- `AGENT=1 swift test`
  passed all 3813 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3813 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/is-provider-reference.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/resolve-provider-reference.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/types/provider-reference.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider/src/shared/v4/shared-v4-provider-reference.ts`
- Swift: `Sources/AISDKProviderUtils/ProviderReference.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ProviderReferenceTests.swift`

### 2026-07-02: `core:provider-utils` V4 reasoning mapping helpers against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `isCustomReasoning`,
  `mapReasoningToProviderEffort`, and `mapReasoningToProviderBudget` so
  concrete providers can translate the common V4 reasoning option into
  provider-specific effort strings or token budgets while producing shared V4
  warnings.
- Swift already exposed `LanguageModelV4ReasoningEffort` and `SharedV4Warning`,
  but had no shared provider-utils owner for this translation. That would force
  each provider migration to reimplement warning details and budget clamping.

Implementation slice 19: reasoning-to-provider mapping:
- Added public `isCustomReasoning` overloads for optional and non-optional
  `LanguageModelV4ReasoningEffort`. The non-optional overload preserves the
  upstream contract that enum case `.none` is custom reasoning; the optional
  overload handles absent reasoning as false.
- Added public `mapReasoningToProviderEffort`, preserving upstream direct,
  compatibility, and unsupported-warning behavior.
- Added public `mapReasoningToProviderBudget`, preserving upstream default
  percentages, rounding, minimum budget, maximum budget, custom percentages,
  and unsupported-warning behavior.
- Kept the helper in `AISDKProviderUtils`, because it maps shared provider V4
  options to provider-specific request values without belonging to one concrete
  provider target.

Validation:
- `swift build`
- `AGENT=1 swift test --filter MapReasoningToProviderTests`
  passed 11 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 333 Swift Testing tests.
- `git diff --check`
- `AGENT=1 swift test`
  passed all 3824 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3824 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/map-reasoning-to-provider.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/map-reasoning-to-provider.test.ts`
- Swift: `Sources/AISDKProviderUtils/MapReasoningToProvider.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/MapReasoningToProviderTests.swift`

### 2026-07-02: `core:provider-utils` header normalization against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `normalizeHeaders` as the shared
  owner for lower-casing header keys and dropping undefined header values
  across record, tuple-array, and `Headers` inputs.
- Swift already performed equivalent lower-casing and nil filtering locally
  inside `withUserAgentSuffix`, but there was no public shared helper for other
  provider-utils consumers or future provider migrations.
- Keeping this behavior local would invite duplicated header canonicalization
  in concrete providers as they migrate to the refreshed V4/core utilities.

Implementation slice 20: normalized header helper:
- Added public `normalizeHeaders(_:)` overloads for Swift dictionary headers and
  tuple-array header entries, preserving the upstream lowercase-key and
  nil-filtering behavior.
- Updated `withUserAgentSuffix` to delegate to the shared helper and added a
  tuple-entry overload for parity with the upstream tuple-array input path.
- Kept the helper in `AISDKProviderUtils`, because header normalization is a
  shared transport utility and does not belong to one concrete provider target.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'NormalizeHeadersTests|UserAgentTests'`
  passed 20 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 338 Swift Testing tests.
- `git diff --check`
- `AGENT=1 swift test`
  passed all 3829 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3829 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/normalize-headers.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/normalize-headers.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/with-user-agent-suffix.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/with-user-agent-suffix.test.ts`
- Swift: `Sources/AISDKProviderUtils/NormalizeHeaders.swift`
- Swift: `Sources/AISDKProviderUtils/WithUserAgentSuffix.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/NormalizeHeadersTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/UserAgentTests.swift`

### 2026-07-02: `core:provider-utils` filename and URL-origin helpers against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `stripFileExtension` as the shared
  first-dot filename helper and `isSameOrigin` as the fail-closed scheme/host/
  port comparison used before provider credentials may be attached to URLs from
  provider responses.
- Swift already had adjacent media/URL helpers such as `mediaTypeToExtension`
  and `isUrlSupported`, but it had no common owner for stripping extension
  segments or enforcing same-origin credential boundaries.
- Provider migrations would otherwise need to duplicate this logic inside
  individual transport implementations.

Implementation slice 21: filename and same-origin helpers:
- Added public `stripFileExtension(_:)`, preserving upstream first-dot behavior
  for single-extension, multi-extension, trailing-dot, and leading-dot names.
- Added public `isSameOrigin(_:_:)`, comparing absolute URL scheme, host, and
  effective port while failing closed on invalid or relative inputs.
- Normalized default HTTP/HTTPS ports to match JavaScript `URL.origin`
  behavior.
- Kept both helpers in `AISDKProviderUtils`, because they are shared utility
  contracts rather than provider-specific transport code.

Validation:
- `swift build`
- `AGENT=1 swift test --filter 'IsSameOriginTests|StripFileExtensionTests'`
  passed 10 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 348 Swift Testing tests.
- `git diff --check`
- `AGENT=1 swift test`
  passed all 3839 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3839 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/strip-file-extension.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/strip-file-extension.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/is-same-origin.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/is-same-origin.test.ts`
- Swift: `Sources/AISDKProviderUtils/StripFileExtension.swift`
- Swift: `Sources/AISDKProviderUtils/IsSameOrigin.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/StripFileExtensionTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/IsSameOriginTests.swift`

### 2026-07-02: `core:provider-utils` nullable, line, and media-type helpers against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `filterNullable`,
  `isNonNullable`, `extractLines`, `detectMediaType`,
  `getTopLevelMediaType`, `isFullMediaType`, and `resolveFullMediaType` as
  shared helpers used by provider/core flows.
- Swift had adjacent media sniffing in `SwiftAISDK`, but `AISDKProviderUtils`
  did not expose the upstream shared helper surface for provider migrations.
- Provider migrations would otherwise need local nil filtering, line slicing,
  media sniffing, and full media-type guards in individual targets.

Implementation slice 22: nullable, line, and media-type helpers:
- Added public `isNonNullable` and `filterNullable` helpers for optional value
  lists and optional arrays.
- Added public `extractLines(text:startLine:endLine:)`, preserving upstream
  one-based inclusive line range semantics and original line-ending style.
- Added provider-utils media sniffing helpers for inline bytes and base64
  strings, plus top-level and full media-type guards.
- Added `resolveFullMediaType(part:)` for V4 file parts, returning full media
  types as-is, detecting inline bytes for top-level/wildcard media types, and
  throwing `UnsupportedFunctionalityError` when non-inline data or unknown
  bytes cannot be resolved.

Validation:
- `AGENT=1 swift test --filter 'FilterNullableTests|ExtractLinesTests|ProviderUtilsDetectMediaTypeTests|ResolveFullMediaTypeTests'`
  passed 29 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 377 Swift Testing tests.
- `swift build`
- `git diff --check`
- `AGENT=1 swift test`
  passed all 3868 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3868 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/filter-nullable.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/filter-nullable.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/is-non-nullable.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/extract-lines.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/extract-lines.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/detect-media-type.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/detect-media-type.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/resolve-full-media-type.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/resolve-full-media-type.test.ts`
- Swift: `Sources/AISDKProviderUtils/FilterNullable.swift`
- Swift: `Sources/AISDKProviderUtils/ExtractLines.swift`
- Swift: `Sources/AISDKProviderUtils/DetectMediaType.swift`
- Swift: `Sources/AISDKProviderUtils/ResolveFullMediaType.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/FilterNullableTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ExtractLinesTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/DetectMediaTypeTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ResolveFullMediaTypeTests.swift`

### 2026-07-02: `core:provider-utils` inline file-data and multipart form-data helpers against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports
  `convertInlineFileDataToUint8Array` and `convertToFormData`.
- Swift already had `SharedV4DataContent` for inline upload data and a
  low-level `MultipartFormDataBuilder`, but did not expose the upstream shared
  conversion helpers.
- `postFormDataToAPI` still used an intentional Swift shortcut:
  `application/x-www-form-urlencoded` instead of upstream multipart
  `FormData`, making the public provider-utils request boundary diverge from
  upstream.

Implementation slice 23: inline bytes and multipart form-data:
- Added `convertInlineFileDataToData(_:)` for Swift's `Data` equivalent of
  upstream `Uint8Array`, covering text UTF-8 encoding, raw bytes, base64, and
  base64url input through the existing uint8/base64 utility owner.
- Added typed Swift `FormDataValue` / `FormDataInputValue` and
  `convertToFormData(...)` helpers over `MultipartFormDataBuilder`, preserving
  upstream null-skip, single-element array, multi-element `[]` suffix, and
  repeated-key behavior.
- Changed `postFormDataToAPI` and `PostBody.Content.formData` encoding to send
  multipart bodies with a boundary `Content-Type`, aligning the public request
  boundary with upstream `postFormDataToApi`.
- Kept provider targets unchanged. Existing provider-specific multipart code
  can migrate to the shared helper in later provider slices.

Validation:
- `AGENT=1 swift test --filter 'ConvertInlineFileDataToDataTests|ConvertToFormDataTests|PostToAPITests'`
  passed 18 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 386 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3877 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3877 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/convert-inline-file-data-to-uint8-array.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/convert-to-form-data.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/convert-to-form-data.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/post-to-api.ts`
- Swift: `Sources/AISDKProviderUtils/ConvertInlineFileDataToData.swift`
- Swift: `Sources/AISDKProviderUtils/ConvertToFormData.swift`
- Swift: `Sources/AISDKProviderUtils/MultipartFormDataBuilder.swift`
- Swift: `Sources/AISDKProviderUtils/PostToAPI.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ConvertInlineFileDataToDataTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ConvertToFormDataTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/PostToAPITests.swift`

### 2026-07-02: `core:provider-utils` download guard and size-limit helpers against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `downloadBlob`,
  `DownloadError`, `fetchWithValidatedRedirects`,
  `readResponseWithSizeLimit`, `DEFAULT_MAX_DOWNLOAD_SIZE`,
  `cancelResponseBody`, and `validateDownloadUrl`.
- Swift only had a high-level `SwiftAISDK` `download(url:)` helper and
  `DownloadError`; there was no shared provider-utils owner for SSRF download
  guards, per-hop redirect validation, or bounded body reads.
- This made provider-utils incomplete against upstream 5.x and left future
  provider slices without a shared download boundary.

Implementation slice 24: shared download guard stack:
- Added provider-utils `DownloadError`, `DownloadedBlob`, `downloadBlob`,
  `validateDownloadUrl`, `fetchWithValidatedRedirects`,
  `readResponseWithSizeLimit`, `DEFAULT_MAX_DOWNLOAD_SIZE`, and
  `cancelResponseBody`.
- `validateDownloadUrl` blocks upstream private/internal SSRF cases including
  localhost/trailing-dot hosts, private/reserved IPv4, numeric IPv4 bypass
  forms, private IPv6, and IPv6 forms embedding private IPv4.
- `fetchWithValidatedRedirects` validates the initial URL before request,
  follows only safe redirect hops, resolves relative locations, and enforces the
  upstream redirect limit. The default Swift fetch uses a no-auto-follow
  `URLSession` delegate so redirect targets can be validated before request.
- `downloadBlob` wraps network/status/size failures in `DownloadError`, returns
  Swift `Data` plus optional media type, supports data URLs, and enforces the
  upstream 2 GiB default maximum download size.
- Kept the existing `SwiftAISDK.download(url:)` API as a compatibility wrapper
  over provider-utils while preserving its `ai-sdk/<version>` User-Agent
  behavior; `SwiftAISDK.DownloadError` is now a typealias to the shared
  provider-utils error.
- Added AI-level `DownloadFileRequest`, `DownloadFileFunction`, and
  `createDownload(maxBytes:)` over the same guarded download stack.
- `download(url:)` now accepts `maxBytes` and `isAborted` while preserving its
  existing default behavior.
- `experimental_generateVideo` and `transcribe` now accept
  `experimentalDownload` hooks matching the upstream custom download option;
  both default to `createDownload()` and forward the call abort signal to the
  download request.
- Replaced `GenerateVideo` URL-output tests' global `URLProtocol` interception
  with the explicit custom download contract.
- Kept provider targets unchanged.

Validation:
- `AGENT=1 swift test --filter 'ValidateDownloadURLTests|ReadResponseWithSizeLimitTests|FetchWithValidatedRedirectsTests|DownloadBlobTests|DownloadTests'`
  passed 31 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 413 Swift Testing tests.
- `AGENT=1 swift test --filter 'DownloadTests|GenerateVideo|TranscribeTests'`
  passed 45 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3907 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3907 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/download-blob.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/download-blob.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/download-error.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/fetch-with-validated-redirects.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/fetch-with-validated-redirects.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/read-response-with-size-limit.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/read-response-with-size-limit.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/validate-download-url.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/validate-download-url.test.ts`
- Swift: `Sources/AISDKProviderUtils/DownloadBlob.swift`
- Swift: `Sources/AISDKProviderUtils/DownloadError.swift`
- Swift: `Sources/AISDKProviderUtils/FetchWithValidatedRedirects.swift`
- Swift: `Sources/AISDKProviderUtils/ReadResponseWithSizeLimit.swift`
- Swift: `Sources/AISDKProviderUtils/ValidateDownloadURL.swift`
- Swift: `Sources/SwiftAISDK/Util/Download/Download.swift`
- Swift: `Sources/SwiftAISDK/Util/Download/DownloadError.swift`
- Swift: `Sources/SwiftAISDK/Util/Download/DownloadFunction.swift`
- Swift: `Sources/SwiftAISDK/GenerateVideo/GenerateVideo.swift`
- Swift: `Sources/SwiftAISDK/GenerateVideo/GenerateVideoExports.swift`
- Swift: `Sources/SwiftAISDK/Transcribe/Transcribe.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/DownloadBlobTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/FetchWithValidatedRedirectsTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ReadResponseWithSizeLimitTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ValidateDownloadURLTests.swift`
- Swift tests: `Tests/SwiftAISDKTests/Util/Download/DownloadTests.swift`
- Swift tests: `Tests/SwiftAISDKTests/GenerateVideo/GenerateVideoTests.swift`
- Swift tests: `Tests/SwiftAISDKTests/Transcribe/TranscribeTests.swift`

### 2026-07-02: `core:provider-utils` model-option workflow serialization against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `serializeModelOptions` as the
  shared helper used by provider model workflow serialization boundaries.
- The helper returns `modelId` plus only JSON-serializable config fields,
  resolves synchronous `headers` functions as a special case, and rejects
  asynchronous header resolution with `Promise returned from resolveSync`.
- Swift had no `AISDKProviderUtils` owner for this policy, so future provider
  workflow serialization would either duplicate filtering locally or serialize
  non-JSON runtime state accidentally.

Implementation slice 25: model option serialization:
- Added `SerializedModelOptions`, `SerializeModelOptionsOptions`,
  `ModelOptionsHeadersResolver`, `AsyncModelOptionsHeadersResolver`, and
  `serializeModelOptions`.
- The Swift helper filters config values to `JSONValue` primitives, arrays, and
  objects, omits non-serializable functions/class instances, and omits nil
  entries that correspond to upstream `undefined`.
- The `headers` key resolves a synchronous headers closure and omits nil header
  entries. Async headers resolvers throw `SerializeModelOptionsError` with the
  upstream `Promise returned from resolveSync` message.
- Kept provider targets unchanged.

Validation:
- `AGENT=1 swift test --filter SerializeModelOptionsTests`
  passed 7 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 420 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3914 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3914 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/serialize-model-options.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/serialize-model-options.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/is-json-serializable.ts`
- Swift: `Sources/AISDKProviderUtils/SerializeModelOptions.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/SerializeModelOptionsTests.swift`

### 2026-07-02: `core:provider-utils` streaming tool-call tracker against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `StreamingToolCallTracker` and
  its delta/options types for OpenAI-compatible streaming tool-call deltas.
- Swift already had V4 stream part contracts and parsing code, but no shared
  provider-utils owner for accumulating streaming tool-call argument deltas.
- Without a shared owner, provider migrations would need duplicate state
  machines for argument accumulation, JSON-completion detection, flush
  finalization, type/id/name validation, and provider metadata propagation.

Implementation slice 26: streaming tool-call delta tracker:
- Added `StreamingToolCallDelta`, `StreamingToolCallFunctionDelta`,
  `StreamingToolCallTypeValidation`, `StreamingToolCallTrackerOptions`, and
  `StreamingToolCallTracker`.
- The tracker emits `LanguageModelV4StreamPart.toolInputStart`,
  `toolInputDelta`, `toolInputEnd`, and `toolCall` in upstream order.
- It accumulates argument deltas by index, falls back to append-order index when
  omitted, skips late deltas after finish, finalizes parsable JSON
  automatically, and finalizes unfinished calls on `flush()`.
- It preserves upstream validation modes (`none`, `ifPresent`, `required`) and
  throws `InvalidResponseDataError` with upstream messages for invalid type,
  missing id, and missing function name.
- It supports metadata extraction/build hooks and keeps provider targets
  unchanged.

Validation:
- `AGENT=1 swift test --filter StreamingToolCallTrackerTests`
  passed 15 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 435 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3929 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3929 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/streaming-tool-call-tracker.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/streaming-tool-call-tracker.test.ts`
- Swift: `Sources/AISDKProviderUtils/StreamingToolCallTracker.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/StreamingToolCallTrackerTests.swift`

### 2026-07-02: `core:provider-utils` tool-name mapping against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `createToolNameMapping` and
  `ToolNameMapping` as the shared contract for translating client-facing
  provider-tool aliases to provider-native tool names and back.
- Swift had provider-private ports in `OpenAIProvider` and `AnthropicProvider`,
  but no shared `AISDKProviderUtils` owner for the V4 tool mapping contract.
- Without the shared owner, future provider migrations would keep duplicating
  the same name translation state machine in provider targets.

Implementation slice 27: shared V4 tool-name mapping:
- Added `ToolNameMapping` and `createToolNameMapping` to
  `AISDKProviderUtils`.
- The helper accepts optional `[LanguageModelV4Tool]`, ignores function tools,
  maps only provider tools whose ids are present in `providerToolNames`, and
  returns the input name when no mapping exists.
- Kept provider targets unchanged; existing provider-private copies can migrate
  in later provider slices.

Validation:
- `AGENT=1 swift test --filter ToolNameMappingTests`
  passed 6 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 441 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3935 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3935 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/create-tool-name-mapping.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/create-tool-name-mapping.test.ts`
- Swift: `Sources/AISDKProviderUtils/ToolNameMapping.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ToolNameMappingTests.swift`

### 2026-07-02: `core:provider-utils` standard-schema JSON Schema normalization against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` uses
  `addAdditionalPropertiesToJsonSchema` inside `standardSchema` to recursively
  set `additionalProperties: false` on object schemas before providers receive
  the JSON Schema.
- The upstream helper covers object schemas nested in `properties`, `items`,
  `anyOf`, `allOf`, `oneOf`, and `definitions`, overwrites existing
  `additionalProperties: true`, and leaves boolean schema definitions
  unchanged.
- Swift `standardSchema` previously returned custom-vendor JSON schemas
  unchanged, and the Swift default empty object schema missed upstream's
  `type: "object"` field.

Implementation slice 28: standard-schema JSON Schema normalization:
- Added the shared `AISDKProviderUtils` normalization helper for `JSONValue`
  JSON Schemas.
- Wired `standardSchema` JSON Schema resolution through the helper.
- Aligned the default `asSchema(nil)` / missing-standard-schema fallback shape
  to upstream's object schema with `type`, empty `properties`, and
  `additionalProperties: false`.
- Added standard-schema tests covering the upstream recursion cases plus
  boolean JSON Schema definitions.

Validation:
- `AGENT=1 swift test --filter StandardSchemaJSONSchemaNormalizationTests`
  passed 10 Swift Testing tests.
- `AGENT=1 swift test --filter SchemaTests`
  passed 67 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 451 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3945 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3945 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/add-additional-properties-to-json-schema.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/add-additional-properties-to-json-schema.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/schema.ts`
- Swift: `Sources/AISDKProviderUtils/Schema/AddAdditionalPropertiesToJsonSchema.swift`
- Swift: `Sources/AISDKProviderUtils/Schema/Schema.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/StandardSchemaJSONSchemaNormalizationTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/SchemaTests.swift`

### 2026-07-02: `core:provider-utils` asArray helper against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `asArray` from
  `packages/provider-utils/src/index.ts`.
- Swift had `asArray` only under `SwiftAISDK/Util`, which put a shared
  provider-utils helper in the high-level AI target instead of the upstream
  owner.
- `SwiftAISDK` already re-exports `AISDKProviderUtils`, so keeping a local
  wrapper in `SwiftAISDK` creates source ambiguity and is not needed for
  source-level `import SwiftAISDK` access.

Implementation slice 29: shared asArray helper:
- Added `AISDKProviderUtils.asArray` overloads for optional single values and
  optional arrays, matching upstream's nil/undefined-to-empty-array and
  single-value wrapping behavior under Swift value semantics.
- Removed the duplicate `SwiftAISDK/Util/AsArray.swift` owner.
- Kept source-level `asArray` availability through `import SwiftAISDK` via the
  existing `@_exported import AISDKProviderUtils`.
- Added provider-utils contract tests and updated the SwiftAISDK tests to prove
  the re-exported helper remains available from the high-level facade.

Validation:
- `AGENT=1 swift test --filter 'ProviderUtilsAsArrayTests|AsArrayTests'`
  passed 9 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 454 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3948 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3948 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/as-array.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/as-array.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/index.ts`
- Swift: `Sources/AISDKProviderUtils/AsArray.swift`
- Swift: `Sources/SwiftAISDK/ModuleExports.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/AsArrayTests.swift`
- Swift tests: `Tests/SwiftAISDKTests/Util/AsArrayTests.swift`

### 2026-07-02: `core:provider-utils` response-body cancellation against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `cancelResponseBody` as a public
  helper and uses it from download rejection paths so failed responses do not
  leave response bodies holding underlying connections.
- Swift had the helper inside `ReadResponseWithSizeLimit.swift`, but it was a
  no-op for `.stream` bodies and had no direct upstream contract tests.
- The correct owner is `AISDKProviderUtils`, because the helper is shared by
  download, redirect, and size-limit boundaries rather than by any concrete
  provider target.

Implementation slice 30: response-body cancellation:
- Moved `cancelResponseBody` to a dedicated provider-utils owner file.
- Implemented Swift stream cancellation through a short cancelled consumer
  task, which triggers `AsyncThrowingStream` termination without changing the
  public `ProviderHTTPResponseBody.stream` case shape.
- Added `onTermination` cancellation to the default `URLSession.AsyncBytes`
  bridge so cancelling a streamed response also cancels its producer task.
- Added direct provider-utils tests for stream cancellation, missing/buffered
  body no-op behavior, and swallowed stream errors.

Validation:
- `AGENT=1 swift test --filter 'CancelResponseBodyTests|ReadResponseWithSizeLimitTests|DownloadBlobTests|FetchWithValidatedRedirectsTests'`
  passed 22 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 457 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3951 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3951 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/cancel-response-body.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/cancel-response-body.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/read-response-with-size-limit.ts`
- Swift: `Sources/AISDKProviderUtils/CancelResponseBody.swift`
- Swift: `Sources/AISDKProviderUtils/FetchFunction.swift`
- Swift: `Sources/AISDKProviderUtils/ReadResponseWithSizeLimit.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/CancelResponseBodyTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/ReadResponseWithSizeLimitTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/DownloadBlobTests.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/FetchWithValidatedRedirectsTests.swift`

### 2026-07-02: `core:provider-utils` DelayedPromise primitive against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `DelayedPromise` is exported from `@ai-sdk/provider-utils` and used
  by high-level `ai` stream result surfaces (`streamText`, `streamObject`) and
  serial job executor tests.
- Swift had the implementation in `SwiftAISDK/Util/DelayedPromise.swift` with
  an older comment pointing at `@ai-sdk/ai`, so the reusable concurrency
  primitive lived in the high-level target instead of the current upstream
  owner.
- The Swift implementation also lacked upstream's public status probes:
  `isPending`, `isResolved`, and `isRejected`.

Implementation slice 31: provider-utils delayed promise:
- Moved the `DelayedPromise` implementation into `AISDKProviderUtils`.
- Added `isPending`, `isResolved`, and `isRejected` with the same observable
  status semantics as upstream.
- Kept `SwiftAISDK.DelayedPromise` as a public typealias to preserve the
  existing SwiftAISDK source surface while making provider-utils the owner.
- Added provider-utils tests for resolving/rejecting before and after task
  access, repeated task access, blocking until resolution/rejection, multi-task
  access, and status methods.

Validation:
- `AGENT=1 swift test --filter 'DelayedPromiseTests|SerialJobExecutorTests|StreamTextTests|StreamObjectTests'`
  passed 66 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 466 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3960 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3960 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/delayed-promise.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/delayed-promise.test.ts`
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/index.ts`
- Upstream use: `external/vercel-ai-sdk/packages/ai/src/generate-text/stream-text.ts`
- Upstream use: `external/vercel-ai-sdk/packages/ai/src/generate-object/stream-object.ts`
- Swift: `Sources/AISDKProviderUtils/DelayedPromise.swift`
- Swift compatibility: `Sources/SwiftAISDK/Util/DelayedPromise.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/DelayedPromiseTests.swift`
- Swift consumer tests: `Tests/SwiftAISDKTests/Util/SerialJobExecutorTests.swift`
- Swift consumer tests: `Tests/SwiftAISDKTests/GenerateText/StreamTextTests.swift`
- Swift consumer tests: `Tests/SwiftAISDKTests/GenerateObject/StreamObjectTests.swift`

### 2026-07-02: `core:provider-utils` withoutTrailingSlash baseURL normalization against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `withoutTrailingSlash` as the
  shared helper for provider baseURL normalization.
- Swift already had the helper in `AISDKProviderUtils`, and provider targets
  consume that shared owner, but there was no direct owner-level test evidence
  for the exact upstream `url?.replace(/\/$/, '')` behavior.
- This is core shared surface: provider targets should consume the helper but
  not own or duplicate this normalization rule.

Implementation slice 32: baseURL trailing-slash normalization:
- Added direct provider-utils tests for nil input, unchanged values, removing
  exactly one final slash, and preserving slashes that are not terminal, such
  as a slash before a query string.
- No provider target behavior was edited.

Validation:
- `AGENT=1 swift test --filter WithoutTrailingSlashTests`
  passed 5 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 471 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3965 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3965 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/without-trailing-slash.ts`
- Upstream export: `external/vercel-ai-sdk/packages/provider-utils/src/index.ts`
- Swift: `Sources/AISDKProviderUtils/WithoutTrailingSlash.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/WithoutTrailingSlashTests.swift`

### 2026-07-02: `core:provider-utils` browser runtime detection against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils` exports `isBrowserRuntime` as the shared
  `window != null` browser-runtime guard.
- Swift already had `RuntimeEnvironmentSnapshot.hasWindow` for the matching
  `getRuntimeEnvironmentUserAgent` port, but lacked the public
  provider-utils helper itself.
- This belongs beside the runtime user-agent helper because both upstream
  utilities intentionally share the same browser definition. Provider targets
  should not own this runtime detection policy.

Implementation slice 33: browser runtime detection:
- Added public `isBrowserRuntime(_:)` over `RuntimeEnvironmentSnapshot`.
- Added direct provider-utils tests for browser and server-runtime snapshots.
- No provider target behavior was edited.

Validation:
- `AGENT=1 swift test --filter UserAgentTests`
  passed 18 Swift Testing tests.
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 473 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3967 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3967 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/provider-utils/src/is-browser-runtime.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/provider-utils/src/is-browser-runtime.test.ts`
- Upstream export: `external/vercel-ai-sdk/packages/provider-utils/src/index.ts`
- Swift: `Sources/AISDKProviderUtils/GetRuntimeEnvironmentUserAgent.swift`
- Swift tests: `Tests/AISDKProviderUtilsTests/UserAgentTests.swift`

### 2026-07-02: `core:provider-utils` Swift-applicable export-surface closure against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:provider-utils`.

Initial finding:
- Upstream `@ai-sdk/provider-utils/src/index.ts` re-exports runtime helpers,
  tool/message types, TypeScript-only inference helpers, external JavaScript
  runtime symbols, and package constants.
- Swift already had owners/tests for the applicable runtime/helper surface
  landed across slices 18-33.
- One source-level drift remained: upstream `types/provider-options.ts` now
  aliases `SharedV4ProviderOptions`, while Swift `AISDKProviderUtils`
  `ProviderOptions` still named the V3 alias. The underlying Swift shape was
  already identical because `SharedV4ProviderOptions` aliases
  `SharedV3ProviderOptions`, so this was an ownership/name alignment issue, not
  a JSON behavior change.

Implementation slice 34: provider-utils export closure:
- Aligned `AISDKProviderUtils.ProviderOptions` to the V4 provider-options owner.
- Classified upstream JS/TS-only exports as Swift `n/a`: `Arrayable`,
  `HasRequiredKey`, `MaybePromiseLike`, the TypeScript `Infer*` helpers,
  `NeverOptional`, external `@standard-schema/spec` type re-exports,
  `@workflow/serde` symbols, Node `Buffer` guard, and the
  `eventsource-parser/stream` re-export. Swift owns the applicable equivalents
  through concrete types, async closures, `Data`/`URL` boundaries,
  `EventSourceParser`, and compile-time generics.
- Confirmed `isBuffer` does not require a Swift runtime API: Swift provider
  reference detection already rejects `Data`, `URL`, `NSNull`, tagged objects,
  and non-string provider maps without a Node `Buffer` concept.
- No provider target behavior was edited.

Validation:
- `AGENT=1 swift test --filter AISDKProviderUtilsTests`
  passed 473 Swift Testing tests.
- `swift build`
  passed.
- `git diff --check`
  passed.
- `AGENT=1 swift test`
  passed all 3967 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3967 selected tests.

Evidence:
- Upstream export surface: `external/vercel-ai-sdk/packages/provider-utils/src/index.ts`
- Upstream type exports: `external/vercel-ai-sdk/packages/provider-utils/src/types/index.ts`
- Upstream provider options: `external/vercel-ai-sdk/packages/provider-utils/src/types/provider-options.ts`
- Upstream Buffer guard: `external/vercel-ai-sdk/packages/provider-utils/src/is-buffer.ts`
- Upstream provider reference guard: `external/vercel-ai-sdk/packages/provider-utils/src/is-provider-reference.ts`
- Swift provider options: `Sources/AISDKProviderUtils/ContentPart.swift`
- Swift provider reference guard: `Sources/AISDKProviderUtils/ProviderReference.swift`
- Swift provider-utils tests: `Tests/AISDKProviderUtilsTests`

### 2026-07-02: `core:ai` MCP HTTP 202 inbound SSE scheduling against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`

Scope: `core:ai` validation hardening.

Finding:
- Upstream `HttpMCPTransport.send` calls `void this.openInboundSse()` after a
  `202 Accepted` response. In JavaScript, the async function begins execution
  synchronously until its first `await`, so the follow-up GET is started before
  the caller can observe the returned promise.
- Swift used `Task { ... }` for the same fire-and-forget work, but a task is not
  guaranteed to start before `send` returns. Under the parallel test runner this
  made the "reopen inbound SSE after 202" test intermittently miss the follow-up
  GET inside its polling window.

Implementation:
- After scheduling the inbound SSE task for a `202 Accepted` response,
  `HttpMCPTransport.send` now yields once so the task can start the GET request,
  mirroring the upstream fire-and-forget async scheduling behavior.

Validation:
- `AGENT=1 swift test --filter reopenInboundSSEAfter202`
  passed 1 Swift Testing test.
- `AGENT=1 swift test --filter HttpMCPTransportTests`
  passed 8 Swift Testing tests.
- `AGENT=1 node tools/test-runner.js --config tools/test-runner.default.config.json`
  passed all 3868 selected tests.

Evidence:
- Upstream: `external/vercel-ai-sdk/packages/mcp/src/tool/mcp-http-transport.ts`
- Upstream tests: `external/vercel-ai-sdk/packages/mcp/src/tool/mcp-http-transport.test.ts`
- Swift: `Sources/SwiftAISDK/Tool/MCP/HttpMCPTransport.swift`
- Swift tests: `Tests/SwiftAISDKTests/Tool/MCP/HttpMCPTransportTests.swift`

## How to track a provider

1) Copy `upstream/providers/_template.md` → `upstream/providers/<provider>.md`
2) Fill:
   - upstream paths under `external/vercel-ai-sdk/packages/<provider>/src/**`
   - Swift paths under `Sources/<ProviderName>Provider/**`
   - audited commit hash from `upstream/UPSTREAM.md`
3) Update the checklist as you verify behaviors (tests preferred).

## Release recap (Swift tags)

This is a lightweight “memory log” of what we shipped while chasing upstream parity.
For source-of-truth code, always follow the commits and tests.

### Unreleased (main)

No unreleased parity changes yet.

### v0.18.0 - 2026-07-02

- 2026-07-02
  - Core V4 foundation on refreshed upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`: added `ProviderV4` plus V4 language, embedding, image, speech, transcription, video, reranking, realtime, middleware, file, skill, warning, provider-reference, and shared file-data contracts; high-level Swift AI SDK flows now run through V4-compatible adapters while preserving V3/V2 provider compatibility.
  - Provider utils V4 foundation on refreshed upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`: added shared provider-reference resolution, reasoning mapping, normalized headers, origin/filename/media helpers, inline data conversion, multipart form-data support, validated downloads, size-limited reads, model option serialization, streaming tool-call tracking, provider tool-name mapping, standard-schema normalization, response cancellation, delayed promises, and browser runtime detection.
  - OpenAI-compatible V4 surface: added V4 adapters and regression coverage for OpenAI-compatible chat models, including reasoning-content round-trips.
  - Release/CI: tracked the V4 skills contract files and root-scoped the local `skills/` ignore rule so protected GitHub checkouts build the same source tree as local development.

- 2026-04-15
  - Anthropic upload parity on refreshed upstream `4891db8bfc583d3767831dac83439ac190c93cb0`: added provider-side `files()` / `skills()` surfaces with multipart upload support (`AnthropicFiles`, `AnthropicSkills`), including `files-api-2025-04-14` / `skills-2025-10-02` beta headers, version-metadata fetch for uploaded skills, and direct regression coverage for multipart payloads plus mapped provider metadata.
  - Core upload parity on refreshed upstream `4891db8bfc583d3767831dac83439ac190c93cb0`: added `AISDKProvider` v4 files/skills contracts and AI-level `uploadFile` / `uploadSkill` helpers with media-type auto-detection, provider capability checks, and direct regression coverage for provider passthrough plus unsupported-provider / URL-input errors.

- 2026-03-31
  - Amazon Bedrock parity on refreshed upstream `b0c59e850b3d51db40a0816c562da52c63ceaba2`: `convertToBedrockChatMessages` now preserves assistant reasoning parts without Bedrock metadata and no longer trims reasoning text when a Bedrock signature is present; added direct regression coverage for both cases.

- 2026-03-21
  - Anthropic parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added Swift support for provider tools `code_execution_20260120`, `web_fetch_20260209`, and `web_search_20260209`, extended Anthropic tool-name mapping / prepare-tools / public wrappers accordingly, and restored encrypted `code_execution` result round-tripping (`encrypted_code_execution_result`) through prompt conversion and response parsing with direct regression coverage.
  - UI message stream callback parity audit on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added direct Swift regressions for `createUIMessageStream` `onFinish` delivery, persistence-mode `messageId` injection/preservation, async `execute` error mapping, and post-close writes, plus `handleUIMessageStreamFinish` passthrough coverage for abort / `finish-step` chunks when no callbacks are installed.
  - UI message stream parity audit on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: confirmed the previously landed `v0.12.0` UI stream work is already present in Swift (`finishReason`, `abort.reason`, tool `title` / `providerMetadata`, and static/dynamic `output-denied` state handling), and added direct regressions for tool-input metadata/title retention plus static/dynamic denial transitions in `ProcessUIMessageStreamTests.swift` and `UIMessageChunkTests.swift`.
  - Core programmatic tool-calling parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: strengthened the `generateText` / `streamText` multi-step dice game regressions to assert final `response.messages`, deferred `toolResults`, and `onStepFinish` / `onFinish` callback contracts for provider-deferred `code_execution` flows, matching the upstream `programmatic tool calling` fixture more closely.
  - Core deferred tool-result parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `generateText` and `streamText` now preserve provider `tool-result` / `tool-error` `providerMetadata` like upstream, and `streamText` now keeps the original static-vs-dynamic typed result kind from the matched tool call when provider results arrive; updated direct deferred-result regressions accordingly.

- 2026-03-07
  - OpenAI parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: synced Responses model IDs with upstream additions (`gpt-5.2-codex`, `gpt-5.4`, `gpt-5.4-pro`, dated `gpt-5.4` snapshots, `gpt-5.3-codex`), enabled GPT-5.4 non-reasoning parameter compatibility when `reasoningEffort == "none"`, preserved Responses `phase` (`commentary` / `final_answer`) across assistant follow-up input conversion plus non-streaming/streaming provider metadata, and updated OpenAI provider docs for GPT-5.4 / GPT-5.3-codex with direct Swift regressions.
  - UI file-input parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added public Swift `convertFileListToFileUIParts(files:)` as the browser-to-Swift adaptation of upstream `FileList` conversion, reading local file URLs into `FileUIPart` data URLs with MIME-type inference plus `application/octet-stream` fallback; added direct regressions for `nil`, text-file conversion, unknown-type fallback, and non-file URL rejection.
  - UI text stream parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added public Swift `processTextStream(stream:onTextPart:)` with incremental UTF-8 decoding across chunk boundaries, matching upstream chunk callback behavior for regular, empty, and split-multibyte text streams; added direct regressions for plain chunk delivery, empty streams, and UTF-8 boundary preservation.
  - UI stream error parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: promoted `UIMessageStreamError` to a public Swift `AISDKError` with stable `chunkType`/`chunkId`, restored typed error propagation for malformed UI streams through both `processUIMessageStream` and `readUIMessageStream`, and kept `.error` chunks as generic message errors like upstream; added typed regressions for malformed text/tool chunks plus a `readUIMessageStream` terminate-on-error smoke test.
  - UI message helper parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added missing exported helper guards `isTextUIPart`, `isFileUIPart`, and `isReasoningUIPart` with direct Swift regressions.
  - UI message helper parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added public Swift helpers `lastAssistantMessageIsCompleteWithToolCalls(...)` and `lastAssistantMessageIsCompleteWithApprovalResponses(...)`, restored upstream-style tool/data helper surface in `UIMessage` (`isDataUIPart`, `isToolUIPart`, `isStaticToolUIPart`, `getToolName`, `getStaticToolName`), and added direct regression coverage for static/dynamic tool names, type guards, provider-executed exclusions, and approval/tool-call completion checks.
  - UI validation parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `validateUIMessages` now rejects empty message arrays and empty `parts` arrays with upstream message text, and `TypeValidationError` now preserves human-readable local validation messages for these cases; added direct regression coverage for both non-empty contract failures.
  - UI stream invariant parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `processUIMessageStream` now throws descriptive errors for malformed `text-*`, `reasoning-*`, and `tool-input-delta` sequences without their corresponding start chunks, and now resolves `tool-output-*` / approval / denied updates from the already-existing tool invocation type instead of trusting mismatched `dynamic` flags; added direct Swift regressions for malformed stream errors and static-tool output updates under dynamic-flag mismatch.
  - UI parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `convertToModelMessages` now preserves `tool-approval-response` for provider-executed static tools (while still avoiding duplicate tool results in `tool` role), and `processUIMessageStream` now keeps the original static-vs-dynamic tool part kind when `tool-input-error` arrives with a mismatched `dynamic` flag; added direct Swift regressions for both cases.
  - UI convert-to-model parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: `convertToModelMessages` now treats dynamic tools like upstream in assistant/tool message conversion, including provider-executed dynamic tool results staying in assistant content, client-executed tool-message `tool-result` parts carrying `callProviderMetadata` as provider options, and `tool-approval-response` forwarding `providerExecuted`; added direct Swift regression coverage for static/dynamic tool result and approval-response cases.
  - UI message stream / UI message parity on refreshed upstream `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`: added `resultProviderMetadata` flow for tool output chunks and UI tool parts, propagated metadata through `transformFullToUIMessageStream` → chunk encoding → `processUIMessageStream` → `validateUIMessages` → `convertToModelMessages`, and added direct Swift regression coverage for static/dynamic tool outputs plus provider-executed tool result round-tripping.
  - UI message stream: restored upstream API parity for `createUIMessageStream(...)` by exposing `onStepFinish` and forwarding it into `handleUIMessageStreamFinish`; added direct Swift regression coverage for write/close, merged-stream error mapping, delayed merged streams after `execute` returns, and `onStepFinish` callback delivery.

- 2026-02-26
  - Fireworks: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createFireworks`) and regression coverage for no-network-before-fail semantics.
  - Luma: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createLuma`) and regression coverage for no-network-before-fail semantics.
  - Hume: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added regression coverage for no-network-before-fail semantics.
  - Hugging Face: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createHuggingFace`) and regression coverage for no-network-before-fail semantics.
  - Gladia: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createGladia`) and regression coverage for no-network-before-fail semantics.
  - ElevenLabs: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createElevenLabs`) and regression coverage for no-network-before-fail semantics.
  - Deepgram: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added upstream alias parity (`createDeepgram`) and regression coverage for no-network-before-fail semantics.
  - Azure OpenAI: provider auth/config parity fix — removed creation-time `fatalError` for missing API key/resource name; validation now happens at request time (`LoadAPIKeyError` / `LoadSettingError`) via auth fetch wrapper; added regression coverage for no-network-before-fail semantics.
  - LMNT: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added speech-model regression coverage for missing key behavior and no-network-before-fail semantics.
  - Fal: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing key behavior and no-network-before-fail semantics.
  - Replicate: provider auth parity fix — removed creation-time `fatalError` for missing API token; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing token behavior and no-network-before-fail semantics.
  - Prodia: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing key behavior and no-network-before-fail semantics.
  - Black Forest Labs: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added provider regression coverage for missing key behavior and no-network-before-fail semantics.
  - Rev.ai: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper; added regression coverage in `RevAIProviderAuthTests`.
  - Cerebras: provider auth parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, with added provider regression coverage for missing key behavior.
  - AssemblyAI: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createAssemblyAI(...)`, and added provider regression tests (alias + endpoint flow + missing key).
  - DeepInfra: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createDeepInfra(...)`, and added provider regression tests (alias + default chat base URL + missing key).
  - Cohere: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createCohere(...)`, and added provider regression tests (alias + default base URL + missing key).
  - Perplexity: provider parity fix — removed creation-time `fatalError` for missing API key; auth now resolves at request time (`LoadAPIKeyError`) via fetch wrapper, added upstream alias `createPerplexity(...)`, and added provider regression tests (alias + default base URL + missing key).
  - Mistral: provider auth parity fix — API key now loads at request time via auth fetch wrapper, missing key throws `LoadAPIKeyError` instead of crashing; added upstream alias `createMistral(...)` and provider-level regression tests.
  - Groq: provider auth parity fix — API key now loads at request time via auth fetch wrapper, missing key throws `LoadAPIKeyError` instead of crashing; added `createGroq(...)` alias for upstream API parity and provider-level regression tests.
  - DeepSeek: provider auth/baseURL parity fix — default base URL aligned to upstream (`https://api.deepseek.com`), API key now loads at request time via auth fetch wrapper, and missing key throws `LoadAPIKeyError` instead of crashing; added regression tests.
  - OpenAI Responses: provider-options `include` parity tightened to upstream schema-only values (`reasoning.encrypted_content`, `file_search_call.results`, `message.output_text.logprobs`) while preserving internal auto-includes (`web_search_call.action.sources`, `code_interpreter_call.outputs`) for request mapping; added parsing regression tests.
  - TogetherAI: provider auth parity fix — API key now loads at request time via auth fetch wrapper; missing key throws `LoadAPIKeyError` instead of crashing; added provider tests for missing key + auth header injection.
  - Vercel (v0): provider auth parity fix — API key now loads at request time via auth fetch wrapper; missing key throws `LoadAPIKeyError` instead of crashing; added provider test for missing key.
  - Alibaba: port the upstream `@ai-sdk/alibaba` provider (Qwen chat + Wan video generation) including thinking mode, prompt caching (`cacheControl`), tool calling + streaming SSE mapping, and video polling, with end-to-end Swift tests.
  - xAI: add upstream parity for `grok-imagine-video` (generations/edits request mapping, polling behavior, edit-mode warnings, headers/metadata) with Swift tests.
  - xAI: add upstream parity for Responses API (`/responses`) + server-side tools, replace image generation with dedicated `XAIImageModel` (URL download behavior + provider options + metadata), and load API key lazily with request-time `LoadAPIKeyError` (no `fatalError`) + tests.
  - Amazon Bedrock: embedding + image model parity (Cohere/Nova/Titan embeddings; Nova Canvas image gen/editing) + SigV4 fetch coverage, strict response validation, `encodeURIComponent` URL parity, and provider-level tests.
  - xAI: align chat/completions parity (request mapping, usage conversion incl cached+reasoning tokens, and streaming JSON error handling/block ordering) + tests.

- 2026-02-25
  - Anthropic: auth header parity and error semantics now match upstream behavior more closely: API key is loaded lazily and missing key throws request-time `LoadAPIKeyError` (no `fatalError`); `apiKey`/`authToken` conflict now throws `InvalidArgumentError` (no crash). Added coverage in `AnthropicProviderAuthErrorTests`.
  - OpenAI-compatible: request mapping parity updates (provider options, structured outputs strictness, usage passthrough) and new Moonshot AI provider built on OpenAI-compatible with mapping/tests.
  - Open Responses: port the upstream `open-responses` package (request mapping, response/stream decoding, tools/usage) with end-to-end tests.
  - Google/Vertex Gemini image parity: when `usageMetadata` is missing, image generation now still returns usage object with `totalTokens = 0` (matching upstream conversion path); added regression coverage in `GoogleGenerativeAIImageModelTests` and `GoogleVertexImageModelTests`.
  - Google/Vertex Gemini image parity: add regression coverage for Gemini-only aspect ratio `21:9` being forwarded into `generationConfig.imageConfig.aspectRatio`.
  - Google provider parity: align `supportedUrls` files regex construction to upstream unescaped `baseURL` interpolation; add regression coverage in `GoogleProviderTests`.
  - Google/Vertex video parity coverage: add regression tests for alternative model IDs, `n -> sampleCount`, multi-video decode, and empty warnings defaults in `GoogleGenerativeAIVideoModelTests` and `GoogleVertexVideoModelTests`.
  - Google language parity coverage: add regression tests for code-execution finishReason semantics (`providerExecuted` tools keep `STOP -> stop`, mixed function calls keep `STOP -> tool-calls`) and stream mapping of missing `codeExecutionResult.output` to empty string in `GoogleGenerativeAILanguageModelParityTests`.
  - Google language parity: `inlineData` file parts now preserve thought-signature metadata via `providerMetadata` in generate output (stream remains metadata-free, as upstream); added regression coverage in `GoogleGenerativeAILanguageModelTests` and `LanguageModelV3ContentTests`.
  - Google language request-shape parity: explicitly empty `thinkingConfig`/`imageConfig` provider option objects are forwarded as empty objects in `generationConfig` (matches upstream); code-execution tool-call/result no longer attach thought-signature metadata directly.
  - Google language parity: invalid stream chunk schema now emits serialized validation parse error payload (`AI_TypeValidationError`/`AI_JSONParseError` fields) instead of raw chunk JSON.
  - Google tools schema parity: `convertJSONSchemaToOpenAPISchema` now matches upstream for nested empty object schemas (root removed; nested preserved) and for `type: [...]` arrays (converted to `anyOf` + `nullable`), with upstream tests ported to Swift.
  - Google Vertex provider config: custom `baseURL` bypasses `project/location` validation when `apiKey` is absent; missing config errors remain request-time (tests updated accordingly).
  - Google Vertex auth parity (Vertex mode): when `apiKey` is absent and `baseURL` is not provided, requests now auto-inject `Authorization: Bearer <token>` via service-account credentials (settings or env), matching upstream Node/Edge wrapper behavior; added regression coverage in `GoogleVertexAuthTests`.
  - SwiftAISDK tests: stabilized `RerankTests.logsWarnings` against parallel observer races by capturing non-empty warning batches instead of last write wins.

- 2026-02-24
  - Google Vertex: embedding options parity fix — `outputDimensionality` now accepts fractional numbers and rejects `null` (Vertex + Google fallback namespaces), with new coverage in `GoogleVertexEmbeddingModelTests`.
  - Google: language provider options parity fix — `null` is now rejected for optional schema fields (including nested `thinkingConfig.includeThoughts`), with regression coverage in `GoogleGenerativeAILanguageModelTests`.
  - Google/Vertex Imagen: preserve explicit `null` for nullish image provider options in request `parameters`; Google Imagen now defaults missing `predictions` to an empty array (upstream response schema parity).
  - Google streaming: align chunk parsing with upstream by accepting usage-only chunks without `candidates` (no false parse-error events), with regression coverage in `GoogleGenerativeAILanguageModelTests`.

- 2026-02-23
  - Anthropic: Claude 4.6 support (thanks to @bunchjesse).
  - Google Vertex: custom `baseURL` now bypasses `project/location` requirement when explicitly configured (regression test added).
  - OpenAI: upstream parity fixes for Responses provider tools:
    - `web_search_call` now maps to upstream output contract (`action` + optional `sources`) in non-stream + stream.
    - `local_shell_call` input mapping now matches upstream snake_case contract (`timeout_ms`, `working_directory`) in non-stream + stream.
    - `mcp_approval_request` no longer emits extra tool-call provider metadata (matches upstream output shape).
    - `shell` assistant tool-results with `store=true` are reconstructed as `shell_call_output` (instead of `item_reference`) like upstream.
    - `web_search` / `web_search_preview` schema strictness aligned with upstream (`userLocation.type` required, discriminated output actions).
    - Missing OpenAI API key now throws request-time error (lazy load) instead of `fatalError`.
    - Completion parity: `logprobs` mapping (`true -> 0`, `false -> omitted`), plus Responses shell/file-search/image parity updates and tests.

- 2026-02-04
  - Breaking: align `LanguageModelV3FinishReason` with upstream as `{ unified, raw }` and propagate raw finish reasons through providers + `generateText`/`streamText` pipelines (tests updated).
  - Anthropic: tool results no longer set `providerExecuted` (upstream parity); MCP tool-call/result are `dynamic: true` (tests updated).
  - UI: align UI message stream chunks with upstream (`finishReason`, abort `reason`, tool `title`/`providerMetadata`, dynamic tool states) + tests.
  - Core: align `LanguageModelV3ToolResult` with upstream (remove `providerExecuted`); tool results coming from providers are treated as `providerExecuted: true` at the AI level (matches upstream `runToolsTransformation`).
  - Added: reranking model V3 + core `rerank` API parity; Cohere + Amazon Bedrock reranking providers + tests.
  - Added providers: TogetherAI (image + reranking + OpenAI-compatible chat/completion/embedding), Black Forest Labs (image w/ polling), Prodia (image w/ multipart response), Rev.ai (async transcription jobs), Vercel (v0 OpenAI-compatible chat wrapper) + tests.

- 2026-02-05
  - Core: add experimental `experimental_generateVideo` API + `VideoModelV3` (v3) types (ported from upstream `generate-video`).
  - Fal: add `FalVideoModel` + `fal.video(...)` wiring (queue polling + providerMetadata mapping) + tests.
  - Docs: add Video Generation page + Fal provider page (incl. video models) and wire both into the sidebar.

- 2026-02-06
  - Fal: close non-video parity for image/speech/transcription against pinned baseline `f3a72bc2` (request mapping, error mapping, metadata mapping, polling behavior).
  - Fal: add provider/model parity coverage in `Tests/FalProviderTests/FalProviderTests.swift`, `Tests/FalProviderTests/FalImageModelTests.swift`, `Tests/FalProviderTests/FalSpeechModelTests.swift`, `Tests/FalProviderTests/FalTranscriptionModelTests.swift`, `Tests/FalProviderTests/FalErrorTests.swift`.
  - Provider utils: extend `JSONSchemaValidator` to validate tuple schemas (`items: [...]` + `additionalItems`), `uniqueItems`, `multipleOf`, object property count constraints, string `format`/`contentEncoding`, and ensure `anyOf`/`oneOf` doesn't bypass base keywords + tests.
  - Core: fix `AsyncIterableStream` init race that could leave streams open/hanging + regression test.
  - Tools: harden `tools/test-runner.js` (selectors + Swift Testing output parsing) and add `tools/test-suspicious.config.json` for UI message stream suites.

### v0.7.x

- `v0.7.0` (2026-01-26)
  - Core: tool approval requests + dynamic tools.
  - SwiftAISDK: handle approvals in `generate/stream`.
  - OpenAI: Responses MCP tool support + docs/tests for approvals.
- `v0.7.1` (2026-01-31)
  - OpenAI: fallback `itemId` from `providerMetadata`.
- `v0.7.2` (2026-01-31)
  - Provider: add `providerMetadata` to V3 tool parts.
  - OpenAI: Responses tool name mapping parity.
- `v0.7.3` (2026-01-31)
  - OpenAI Responses: citations/annotations `providerMetadata` parity + tests.
- `v0.7.4` (2026-02-01)
  - Release housekeeping.
- `v0.7.5` (2026-02-01)
  - Docs: README update for `0.7.4`.
- `v0.7.6` (2026-02-01)
  - OpenAI Chat: validate `logitBias` keys.
- `v0.7.77` (2026-02-01)
  - OpenAI tools: add output schemas for `web_search` tools.

### v0.8.x

- `v0.8.0` (2026-02-01)
  - Provider utils: strengthen JSON schema validation.
- `v0.8.2` (2026-02-02)
  - SSE streaming: make tool events JSON-serializable.
  - Tools: propagate tool titles through calls/results/errors and stream parts.
  - Docs/site: add branding logos + favicon.
- `v0.8.3` (2026-02-02)
  - Google: send tools as array for `functionDeclarations` (Gemini/GCP compatibility).
  - OpenAI Responses: reasoning summary streaming parity; truncation/finishReason parity.
  - Image: edits support; response_format prefix parity; remove compat init.
  - `streamText`: raw finish reason + abort reason parity.
- `v0.8.4` (2026-02-02)
  - Anthropic: code_execution/memory betas + `toolNameMapping` parity.
  - OpenAI Responses: truncation + finishReason parity.
- `v0.8.5` (2026-02-02)
  - Anthropic: tool streaming + structured outputs + metadata alignment.

### v0.9.x

- `v0.9.0` (2026-02-03)
  - Breaking: rename “provider-defined tools” → “provider tools” (upstream parity).
  - Tools: support `inputExamples` + middleware injection; stabilize JSON formatting.
  - `streamText`: apply `prepareStep` for multi-step streaming.
  - Core: unify V3 warnings under `SharedV3Warning`; `prepareStep` supports providerOptions/experimentalContext.
  - Anthropic: validate `cache_control`; forward container id between steps.
  - Docs: simplify README marketing copy.
- `v0.9.1` (2026-02-03)
  - Anthropic: align settings + custom provider option keys; align provider tool args + prepareTools.

### v0.10.x

- `v0.10.0` (2026-02-03)
  - Breaking (Anthropic): align web tool outputs with upstream.

### v0.11.x

- `v0.11.0` (2026-02-04)
  - Breaking: align `LanguageModelV3Usage` to upstream token detail shape (`inputTokens` / `outputTokens`) and update provider usage mapping accordingly.
  - SwiftAISDK: add AI-level `LanguageModelUsage` helpers + adapter from provider usage for parity with upstream `@ai-sdk/ai`.
- `v0.11.1` (2026-03-21)
  - Core: support deferred results for provider-executed tools (`supportsDeferredResults`) in `generateText`/`streamText` multi-step loops (upstream parity).
  - Streaming: map provider tool outputs with `isError: true` to `.toolError` (not `.toolResult`); propagate tool-call `providerMetadata` to executed tool results/errors (`executeToolCall` parity); preserve `providerMetadata` from provider tool-result chunks in `generateText`/`streamText` content (matches upstream).
  - Tests: add coverage for deferred provider tool results and tool providerMetadata in `Tests/SwiftAISDKTests/GenerateText/*DeferredToolResultsTests.swift`, `ExecuteToolCallProviderMetadataTests.swift`, `StreamTextToolErrorProviderMetadataTests.swift`.
  - Tests: port programmatic tool calling multi-step dice game fixture to validate provider-deferred results + client tool execution, including final `response.messages`, deferred `toolResults`, and `onStepFinish` / `onFinish` callback contracts:
    - `Tests/SwiftAISDKTests/GenerateText/GenerateTextProgrammaticToolCallingTests.swift`
    - `Tests/SwiftAISDKTests/GenerateText/StreamTextProgrammaticToolCallingTests.swift`
