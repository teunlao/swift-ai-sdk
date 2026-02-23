# Provider: OpenAI

- Audited against upstream commit: `32be973f7f70fea5bab1fa0cb393f95db1267503`
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
- [x] Responses parity for provider tools: `shell`/`local_shell`/`apply_patch` and `web_search` output mapping
- [x] Local shell input contract matches upstream (`timeout_ms`, `working_directory` in tool input/output mapping)
- [x] `mcp_approval_request` tool-call mapping matches upstream (no extra provider metadata on emitted tool-call)
- [x] `shell` assistant tool-result with `store=true` reconstructs `shell_call_output` (instead of `item_reference`) like upstream
- [x] `web_search` / `web_search_preview` args + output schemas aligned with upstream discriminated unions and required `userLocation.type = approximate`

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
