# Provider: <Name>

- Audited against upstream commit: `<hash>`
- Upstream package: `external/vercel-ai-sdk/packages/<provider>/src/**`
- Swift implementation: `Sources/<ProviderName>Provider/**`

## What is verified (checked + tested)

- [ ] Prompt conversion (messages/system/tools)
- [ ] Tool call serialization (tool_use/server_tool_use) + tool result mapping
- [ ] Response decoding (content blocks → internal content)
- [ ] Streaming SSE mapping (deltas/events → internal stream parts)
- [ ] Error mapping (HTTP errors + API error shapes)
- [ ] Model/feature gates (betas, flags, defaults)

## Known gaps / TODO

- [ ] <short note>

## Notes

- Link upstream files: `external/vercel-ai-sdk/packages/<provider>/src/...`
- Link Swift files: `Sources/<ProviderName>Provider/...`

