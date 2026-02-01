# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.7.6] - 2026-02-01

### Fixed
- OpenAI Chat: validate `logitBias` keys are numeric (matches upstream schema behavior).

## [0.7.5] - 2026-02-01

### Added
- OpenAI: port upstream `openai-language-model-capabilities` helper and share it across Chat/Responses.

### Fixed
- OpenAI Chat: validate `metadata` provider option key/value lengths (keys ≤ 64, values ≤ 512) to match upstream.

## [0.7.4] - 2026-02-01

### Fixed
- OpenAI (Responses): validate `shell` tool result output shape and require `exitCode` for `exit` outcomes (matches upstream discriminated union behavior).

## [0.7.3] - 2026-01-31

### Fixed
- OpenAI (Responses): include filtered citation annotations in `providerMetadata` for assistant text and streaming `text-end` (matches upstream behavior).
- OpenAI (Responses): emit document source `providerMetadata` for `file_citation`, `container_file_citation`, and `file_path` (matches upstream behavior).

## [0.7.2] - 2026-01-31

### Added
- LanguageModelV3: add optional `providerMetadata` support for `tool-call` and `tool-result` prompt parts.

### Fixed
- OpenAI (Responses): map provider-defined tool names to OpenAI tool names in requests, and back to custom tool names in responses/streaming (matches upstream behavior).
- OpenAI (Responses): use `providerMetadata.itemId` for provider tool-result item references when `store=true` (matches upstream behavior).
- OpenAI (Responses): validate provider tool call inputs using a JSONValue→Foundation conversion (fixes schema validation for `shell`, `local_shell`, `apply_patch`).

## [0.7.1] - 2026-01-31

### Fixed
- OpenAI (Responses): read `itemId` from tool-call `providerMetadata` as a fallback (matches upstream behavior).

## [0.7.0] - 2026-01-26

### Added
- OpenAI (Responses): provider-executed MCP tool support via `openai.tools.mcp(...)` (tool serialization + output mapping).
- OpenAI (Responses): MCP approval workflow mapping (`mcp_approval_request` / `mcp_approval_response`) with tool call id aliasing via `approval_request_id`.

### Docs
- Docs/examples: document and demonstrate OpenAI MCP tool usage and approvals.

## [0.6.0] - 2026-01-26

### Changed
- BREAKING (OpenAI): `strictJsonSchema` now defaults to `true` for both Chat and Responses models.
- BREAKING (OpenAI Chat): provider option `structuredOutputs` is no longer supported. Use `strictJsonSchema: false` to disable strict structured outputs.
- BREAKING (OpenAI): tool definitions now only include `"strict"` when the tool sets `strict` explicitly.

### Added
- Tools: add `strict` to tool definitions and forward to providers that support it.
- OpenAI: add provider options `promptCacheRetention`, `systemMessageMode`, and `forceReasoning` (Chat + Responses).
- OpenAI (Responses): add provider option `truncation`.

### Fixed
- OpenAI: update reasoning model capability detection to match upstream allowlist behavior.
- OpenAI: match GPT-5.1/5.2 parameter compatibility rules when `reasoningEffort` is `none`.
- Docs/examples: update OpenAI docs and examples to match new options/defaults.

## [0.5.11] - 2026-01-26

### Added
- OpenAI: Responses option `conversation`.
- OpenAI: provider tools `shell` and `apply_patch` (with `execute` examples).

### Fixed
- OpenAI: Responses input now skips execution-denied tool results and uses `itemId` for tool-result item references when available.
- OpenAI: Responses apply-patch tool call mapping now requires `itemId` and forwards it via provider metadata (non-stream + streaming).

## [0.5.10] - 2026-01-25

### Fixed
- OpenAI: Responses input uses item references for assistant text and tool calls when `store=true` and OpenAI `itemId` is available (fixes multi-turn reasoning/tool-call mismatch).

## [0.5.9] - 2026-01-24

### Fixed
- Provider utils: increase default `URLRequest.timeoutInterval` to 24h (avoids the 60s default timeout) and cancel in-flight requests when `abortSignal` triggers.

## [0.5.8] - 2026-01-18

### Fixed
- Anthropic: serialize tool call `input` as a JSON object (not a JSON string) for `tool_use` / `server_tool_use` history blocks.

## [0.5.7] - 2026-01-18

### Added
- Anthropic: support MCP tool blocks (`mcp_tool_use`, `mcp_tool_result`) and tool search server tools/results.

## [0.5.6] - 2026-01-18

### Fixed
- Anthropic: serialize tool call `input` as a JSON object (not a JSON string) to prevent 500 errors in multi-turn tool-use conversations.

## [0.1.1] - 2025-10-21

### Changed
- Lower swift-tools-version from 6.1 to 6.0 for broader compatibility

## [0.1.0] - 2025-10-20

### Added

**Core SDK** (3/3 packages - 101.8% test coverage):
- `AISDKProvider` - Foundation types (139 tests)
- `AISDKProviderUtils` - Provider utilities (272 tests, 85.0% coverage)
- `SwiftAISDK` - Main SDK (1136 tests, 94.7% coverage)

**Providers** (5/32 ported):
- `OpenAIProvider` - Complete (292 tests, 100.7% coverage)
- `AnthropicProvider` - Complete (115 tests, 100.9% coverage)
- `GoogleProvider` - Partial (20 tests, 12.9% coverage)
- `GroqProvider` - Partial (19 tests, 32.8% coverage)
- `OpenAICompatibleProvider` - Partial (9 tests, 7.0% coverage)

**Features**:
- Text generation: `generateText()`, `streamText()`
- Structured output: `generateObject()`, `streamObject()`
- Tool calling and MCP tools support
- Middleware system for language models
- Telemetry and error handling
- Zod-like schema DSL (`AISDKZodAdapter`)
- SSE streaming parser (`EventSourceParser`)

**Platform Support**:
- iOS 16+, macOS 13+, tvOS 16+, watchOS 9+

**Test Coverage**:
- Total: 1728 tests passing
- Upstream parity: 68.4% (2002/2928 relevant upstream tests)

**Upstream Reference**:
- Vercel AI SDK 6.0.0-beta.42 (commit 77db222eeded7a936a8a268bf7795ff86c060c2f)
