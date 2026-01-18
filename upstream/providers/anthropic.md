# Provider: Anthropic

- Upstream commit (see `upstream/UPSTREAM.md`): `c0fff0368638adbf2c6f9197e13c432c37760751`
- Upstream package: `external/vercel-ai-sdk/packages/anthropic/src/**`
- Swift implementation: `Sources/AnthropicProvider/**`

## Verified (tested)

- [x] Tool call history serialization: `tool_use.input` / `server_tool_use.input` are JSON objects (not JSON strings).
- [x] MCP tool blocks: `mcp_tool_use` + `mcp_tool_result`.
- [x] Tool search server tools/results: `tool_search_tool_regex`, `tool_search_tool_bm25`, `tool_search_tool_result`.

Tests live under:
- `Tests/AnthropicProviderTests/ConvertToAnthropicMessagesPromptTests.swift`
- `Tests/AnthropicProviderTests/AnthropicPrepareToolsTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelStreamAdvancedTests.swift`

## Audit checklist (upstream → Swift)

- [ ] Prompt conversion (messages/system/tools): `convert-to-anthropic-messages-prompt.ts` ↔ `ConvertToAnthropicMessagesPrompt.swift`
- [ ] Tools payload + tool choice: `anthropic-prepare-tools.ts` ↔ `AnthropicPrepareTools.swift`
- [ ] Response decoding: `anthropic-messages-api.ts` ↔ `AnthropicMessagesAPI.swift`
- [ ] Response mapping: `anthropic-messages-language-model.ts` ↔ `AnthropicMessagesLanguageModel.swift`
- [ ] Streaming mapping (SSE): `anthropic-messages-language-model.ts` ↔ `AnthropicMessagesLanguageModel.swift`
- [ ] Stop reasons mapping: upstream stop reasons ↔ `MapAnthropicStopReason.swift`
- [ ] Error mapping (HTTP + API shapes)

## Notes / TODO

- [ ] Apply `toolNameMapping` to response mapping + streaming (`server_tool_use`/tool results → custom tool names).
- [ ] Add support for `code_execution_20250825` (caller, subtools, new tool result block types).
- [ ] Add support for `memory_20250818`.
