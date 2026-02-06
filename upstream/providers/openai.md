# Provider: OpenAI

- Audited against upstream commit: `f5b2b5ef497ae6c207c17bb8ff81988ef084194b`
- Upstream package: `external/vercel-ai-sdk/packages/openai/src/**`
- Swift implementation: `Sources/OpenAIProvider/**`

## What is verified (checked + tested)

- [x] Prompt conversion (Chat + Responses; files/images/PDF; systemMessageMode)
- [x] Tool call serialization (function + provider tools: `local_shell`, `shell`, `apply_patch`, `web_search`, `web_search_preview`; MCP approvals)
- [x] Response decoding (text/reasoning/tool calls + providerMetadata mapping)
- [x] Streaming SSE mapping (text deltas, tool workflows, citations, errors)
- [x] Error mapping (OpenAI error payloads; response error parts)
- [x] Model/feature gates (reasoning model rules, strictJsonSchema defaults)
- [x] Provider option validation (Chat `metadata` + `logitBias` constraints)

## Known gaps / TODO

- [ ] JSON Schema validation is still subset-only (notably: `$ref` resolution and conditional keywords). Tuple schemas (`items: [...]` + `additionalItems`), `uniqueItems`, `multipleOf`, `format`, and `contentEncoding: base64` are supported by Swift `JSONSchemaValidator`.

## Notes

- Upstream (Responses):
  - `external/vercel-ai-sdk/packages/openai/src/responses/convert-to-openai-responses-input.ts`
  - `external/vercel-ai-sdk/packages/openai/src/responses/openai-responses-language-model.ts`
  - `external/vercel-ai-sdk/packages/openai/src/responses/openai-responses-prepare-tools.ts`
- Swift (Responses):
  - `Sources/OpenAIProvider/OpenAIResponsesInput.swift`
  - `Sources/OpenAIProvider/OpenAIResponsesModel.swift`
  - `Sources/OpenAIProvider/OpenAIResponsesPrepareTools.swift`
  - `Sources/OpenAIProvider/Tool/OpenAIShellTool.swift`
