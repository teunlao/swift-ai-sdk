# Provider: OpenAI

- Audited against upstream commit: `f5b2b5ef497ae6c207c17bb8ff81988ef084194b`
- Upstream package: `external/vercel-ai-sdk/packages/openai/src/**`
- Swift implementation: `Sources/OpenAIProvider/**`

## What is verified (checked + tested)

- [x] Prompt conversion (Chat + Responses; files/images/PDF; systemMessageMode)
- [x] Tool call serialization (function + provider tools: `local_shell`, `shell`, `apply_patch`; MCP approvals)
- [x] Response decoding (text/reasoning/tool calls + providerMetadata mapping)
- [x] Streaming SSE mapping (text deltas, tool workflows, citations, errors)
- [x] Error mapping (OpenAI error payloads; response error parts)
- [x] Model/feature gates (reasoning model rules, strictJsonSchema defaults)
- [x] Provider option validation (Chat `metadata` key/value limits)

## Known gaps / TODO

- [ ] JSON Schema union validation is limited (Swift `JSONSchemaValidator` supports only a subset); complex unions are enforced via `Codable` decoding where applicable (e.g. shell tool outputs in Responses input building).

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
