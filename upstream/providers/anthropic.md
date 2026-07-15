# Provider: Anthropic

- Audited against upstream commit: `c8d2726ae045a28142cb46df5e41cdd51d8dcc71`
- Upstream package: `external/vercel-ai-sdk/packages/anthropic/src/**`
- Swift implementation: `Sources/AnthropicProvider/**`
- Status: verified/current. The default Anthropic facade and Messages model are native Provider V4; the explicit Provider V3 facade remains available for compatibility.

## What is verified (checked + tested)

- [x] Auth headers + error semantics: API key is loaded lazily at request-time and missing key throws `LoadAPIKeyError` (no `fatalError`); `apiKey`/`authToken` conflict throws `InvalidArgumentError`.
- [x] Prompt conversion (messages/system/tools) incl. JSON tool inputs (objects, not JSON strings).
- [x] Assistant prompt conversion: `code_execution_20250825` subtool naming (`bash_code_execution` / `text_editor_code_execution`) and programmatic tool calling type stripping (`programmatic-tool-call`).
- [x] Tool call serialization (tool_use/server_tool_use) + tool result mapping.
- [x] Tool search tools + deferred tool references (regex/bm25).
- [x] Provider tools: set `supportsDeferredResults` on upstream-marked tools (code execution, web tools, tool search) for correct multi-step deferred tool result handling.
- [x] Tool name mapping parity (`toolNameMapping`) for server tools + results.
- [x] Tool schemas parity (bash/computer/text editors/tool search/code execution) — tests in `Tests/AnthropicProviderTests/AnthropicToolSchemasTests.swift`.
- [x] Streaming SSE mapping (advanced tool streaming, multi-step container id forwarding).
- [x] Model/feature gates and validation (`cache_control` usage).
- [x] Settings/provider options parity (custom provider option keys).
- [x] Web tools output shape aligned to upstream (breaking in `v0.10.0`).
- [x] Memory tool: `memory_20250818` prepare-tools payload + `context-management-2025-06-27` beta; parses `tool_use` into V3 tool-call content.
- [x] Programmatic tool calling: parse `caller` metadata for client `tool_use` blocks and inject `type=programmatic-tool-call` for server-side `code_execution` tool calls (upstream parity).
- [x] Tool results parity: tool results do not set `providerExecuted`; MCP tool-call/result set `dynamic: true`.
- [x] Error mapping parity: HTTP errors + SSE `error` events decode via `anthropicErrorDataSchema` (unknown fields tolerated), matching upstream.
- [x] New provider tool versions on refreshed upstream: `code_execution_20260120`, `web_fetch_20260209`, and `web_search_20260209` are now exposed in Swift tools/prepare-tools/model tool-name mapping, with direct schema + prepare + runtime conversion coverage.
- [x] Encrypted code execution parity: Anthropic `encrypted_code_execution_result` now round-trips through Swift prompt conversion and response parsing for `code_execution_20260120`.
- [x] Direct recorded fixture coverage now exercises `anthropic-mcp.1` and `anthropic-web-fetch-tool-20260209.1` in both JSON and streaming modes; streaming `server_tool_use` blocks with populated `content_block_start.input` now preserve that input through the emitted V3 `tool-call`.
- [x] Files API parity: `AnthropicProvider.files()` now exposes a v4 files surface that uploads multipart payloads to `/v1/files` with `files-api-2025-04-14`, preserves Anthropic file metadata in `providerMetadata`, and returns provider references for reuse in later prompts.
- [x] Skills API parity: `AnthropicProvider.skills()` now exposes a v4 skills surface that uploads multipart skill bundles to `/v1/skills` with `skills-2025-10-02`, fetches latest version metadata, and maps `displayTitle` / `name` / `description` / `latestVersion` / provider metadata like upstream.
- [x] Refreshed request parity: Anthropic base URLs normalize to `/v1`; current request options (`metadata`, `taskBudget`, `inferenceGeo`, `fallbacks`) and model capability gates are serialized like the pinned upstream baseline.
- [x] Refreshed prompt parity: mid-conversation system messages, compaction blocks, provider-result/tool-use ordering, and reasoning boundaries round-trip without crossing Anthropic content-block constraints.
- [x] Refreshed response/stream parity: `stop_details`, `usage.iterations`, compaction and fallback blocks, message-delta input-token overrides, and first-delta programmatic code-execution input are mapped with shared generate/stream usage semantics.
- [x] Advisor tool parity: `advisor_20260301` public factory, args/input/output schemas, beta and request payload, three result variants, streaming order, transcript round-trip, and advisor usage exclusion match upstream.
- [x] Native Provider V4 facade: `anthropic` and `createAnthropic(settings:)` expose direct `LanguageModelV4` Messages models, files, skills, and provider-defined tools while `createAnthropicProvider(settings:)` preserves the explicit V3 surface.
- [x] Native V4 model and reasoning parity: current model IDs include `claude-sonnet-5`, `claude-fable-5`, `claude-opus-4-8`, `claude-opus-4-7`, `claude-opus-4-6`, and `claude-sonnet-4-6`; normalized V4 reasoning maps to adaptive or budget thinking, direct `xhigh` is preserved on supported models, and provider `effort: max` remains distinct and takes precedence.
- [x] Native V4 prompt parity: provider-reference files serialize to Anthropic Files API sources, `containerUpload` serializes container uploads, required beta headers are inferred, and V4 result/stream parts preserve the established Messages transport behavior.
- [x] High-level V4 file/skill parity: `generateText(messages:)` preserves provider-reference and inline-text file data, while `uploadFile(api: anthropic, ...)` and `uploadSkill(api: anthropic, ...)` resolve the Provider V4 capabilities directly.

Tests live under:
- `Tests/AnthropicProviderTests/ConvertToAnthropicMessagesPromptTests.swift`
- `Tests/AnthropicProviderTests/AnthropicPrepareToolsTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelProviderMetadataTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelProviderOptionsRequestTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelStreamAdvancedTests.swift`
- `Tests/AnthropicProviderTests/AnthropicAdvisorTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesFixtureTests.swift`
- `Tests/AnthropicProviderTests/AnthropicWebToolsSchemaTests.swift`
- `Tests/AnthropicProviderTests/AnthropicToolSchemasTests.swift`
- `Tests/AnthropicProviderTests/AnthropicProviderAuthErrorTests.swift`
- `Tests/AnthropicProviderTests/AnthropicFilesTests.swift`
- `Tests/AnthropicProviderTests/AnthropicSkillsTests.swift`
- `Tests/AnthropicProviderTests/AnthropicProviderV4Tests.swift`
- `Tests/SwiftAISDKTests/GenerateText/GenerateTextDeferredToolResultsTests.swift` (AI-level deferred provider tool results)
- `Tests/SwiftAISDKTests/GenerateText/StreamTextDeferredToolResultsTests.swift` (AI-level deferred provider tool results)
- `Tests/SwiftAISDKTests/GenerateText/GenerateTextV4Tests.swift` (high-level V4 provider-reference prompt flow)
- `Tests/SwiftAISDKTests/UploadFile/UploadFileTests.swift` (Provider V4 files routing)
- `Tests/SwiftAISDKTests/UploadSkill/UploadSkillTests.swift` (Provider V4 skills routing)
- `Tests/AISDKProviderUtilsTests/ModelMessageCodableTests.swift` (reference/text storage round-trips)

## Latest validation

- `2026-07-15`: `AGENT=1 swift test --filter Anthropic` passed 293 tests in 45 suites, including 9 native Provider V4 HTTP-boundary tests.
- `2026-07-15`: `AGENT=1 swift test` passed 4145 tests in 472 suites; `swift build` also passed.
- `2026-07-15`: `pnpm run examples:build`, `pnpm run docs:check`, and `pnpm run docs:build` passed after the native Anthropic V4 docs and validation-example update. The docs build generated 53 pages and emitted the known nonfatal sitemap/npx ENOENT warning.
- `2026-07-15`: the parity scanner reports `anthropic | provider | P0 | verified | current` at `c8d2726ae045a28142cb46df5e41cdd51d8dcc71`; `git diff --check` also passed.

## Known gaps / TODO

None known for the pinned Anthropic package baseline.

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/anthropic/src/anthropic-prepare-tools.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/convert-to-anthropic-prompt.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/anthropic-language-model.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/tool/*`
  - `external/vercel-ai-sdk/packages/anthropic/src/anthropic-files.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/skills/*`
- Swift (key files):
  - `Sources/AnthropicProvider/AnthropicPrepareTools.swift`
  - `Sources/AnthropicProvider/ConvertToAnthropicMessagesPrompt.swift`
  - `Sources/AnthropicProvider/AnthropicMessagesLanguageModel.swift`
  - `Sources/AnthropicProvider/AnthropicV4Adapters.swift`
  - `Sources/AnthropicProvider/AnthropicProviderV4.swift`
  - `Sources/AnthropicProvider/Tool/*`
  - `Sources/AnthropicProvider/AnthropicFiles.swift`
  - `Sources/AnthropicProvider/Skills/*`
