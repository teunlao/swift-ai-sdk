# Provider: OpenAI

- Audited against upstream commit: `a921fbb381cf2d19ef75ae27906f8d1cb0b8325b`
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
- [x] Responses provider-options include parity: public provider-options include values are restricted to upstream schema (`reasoning.encrypted_content`, `file_search_call.results`, `message.output_text.logprobs`) while internal request/autoinclude still supports full include union
- [x] GPT-5.4 / GPT-5.3-codex parity: Responses model-id helpers include `gpt-5.2-codex`, `gpt-5.4*`, and `gpt-5.3-codex`; GPT-5.4 follows upstream non-reasoning parameter compatibility when `reasoningEffort == "none"`; Responses `phase` is preserved on output text provider metadata and round-tripped back into follow-up assistant input
- [x] Upstream Responses fixtures covered directly in Swift tests for shell skill/container flows and MCP approvals: `openai-shell-skills.1`, `openai-mcp-tool-approval.2`, `.3`, `.4` (both JSON and streaming variants)

## Known gaps / TODO

- None known.

## Notes

- 2026-03-30 targeted refresh against upstream `0a56c9eedb1b421f85b6b81eda9cd01c98995051` (not a full provider re-audit): aligned `getOpenAILanguageModelCapabilities` and Responses model-id allowlists with upstream additions/removals, including `gpt-5.3-chat-latest`, `gpt-5.4-mini*`, `gpt-5.4-nano*`, and removal of legacy `codex-mini-latest`, `computer-use-preview`, `gpt-4-turbo*`, `gpt-4.5-preview*`, `chatgpt-4o-latest`, and `gpt-4o-audio-preview-2024-10-01`.

- Upstream (Responses):
  - `external/vercel-ai-sdk/packages/openai/src/responses/convert-to-openai-responses-input.ts`
  - `external/vercel-ai-sdk/packages/openai/src/responses/openai-responses-language-model.ts`
  - `external/vercel-ai-sdk/packages/openai/src/responses/openai-responses-prepare-tools.ts`
- Swift (Responses):
  - `Sources/OpenAIProvider/OpenAIResponsesInput.swift`
  - `Sources/OpenAIProvider/OpenAIResponsesModel.swift`
  - `Sources/OpenAIProvider/OpenAIResponsesPrepareTools.swift`
  - `Sources/OpenAIProvider/Tool/OpenAIShellTool.swift`

- JSON Schema validation: Swift `JSONSchemaValidator` supports `$ref` (local `#/...`) and conditional keywords (`if`/`then`/`else`). Unsupported keywords remain permissive by design.
