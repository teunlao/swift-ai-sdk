# Audit Slices

Use these slices to keep provider and core audits comparable. Do not mark a
component verified unless each applicable slice has evidence or a short `n/a`
reason.

## Provider Slices

| Slice | Check |
| --- | --- |
| Request serialization | URL, method, query, body, multipart fields, file uploads, headers, defaults, provider options. |
| Auth and config timing | API keys, service tokens, env vars, custom base URL behavior, request-time vs creation-time validation. |
| Tool contracts | Tool choice, tool schemas, provider tools, dynamic/static tool calls, approvals, deferred results. |
| Response parsing | Text, reasoning, files, annotations, tool calls, warnings, provider metadata, usage, logprobs. |
| Streaming | Raw event handling, chunk order, deltas, finish events, errors, cancellation, callback timing. |
| Error mapping | HTTP failures, provider payloads, validation failures, thrown Swift error type and message. |
| Model and feature gates | Model IDs, capability detection, unsupported options, warnings, defaults. |
| Tests and fixtures | Swift regressions, fixture ownership, no runtime dependency on `external/**`. |

## Core Slices

| Slice | Check |
| --- | --- |
| Public API | Names, parameter semantics, return shape, async/cancellation adaptation. |
| Prompt conversion | System/user/assistant/tool messages, content parts, provider options, metadata. |
| Generation loops | Step ordering, stop conditions, tool execution, callbacks, response messages. |
| Streams | Async sequence behavior, finish/error propagation, cancellation, race safety. |
| Persistence | Swift-native `Codable` contracts, lossless restoration, schema evolution. |
| Validation | Boundary parsing, typed runtime state, diagnostics, errors. |

## Docs Slices

| Slice | Check |
| --- | --- |
| Upstream copy | Page starts from `external/vercel-ai-sdk/content/**`, not from scratch. |
| Starlight compatibility | Unsupported React/MDX components replaced. |
| Swift adaptation | TypeScript examples converted to Swift using real public products. |
| JS-only content | AI SDK UI/RSC/framework-only content removed or marked as JS-only. |
| Navigation and build | `apps/docs/astro.config.mjs` updated; docs check/build pass. |

## Evidence Format

Use short evidence bullets:

```md
- Swift: `Tests/<Target>Tests/...`
- Swift: `Sources/<Target>/...`
- Upstream: `external/vercel-ai-sdk/packages/<package>/src/...`
- Result: `<command>` passed
```
