# Provider: Alibaba

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/alibaba/src/**`
- Swift implementation: `Sources/AlibabaProvider/**`

## What is verified (checked + tested)

- [x] Provider settings parity (`baseURL`, `videoBaseURL`, `apiKey`, `headers`, `fetch`, `includeUsage`)
- [x] Prompt conversion (text, images via URL, cache control) + warnings for excessive `cacheControl` markers
- [x] Request mapping (thinking options, responseFormat json_schema/json_object, tools/toolChoice, parallel tool calls)
- [x] Response decoding (text, reasoning, tool calls, finish reason mapping, usage + cached tokens)
- [x] Streaming SSE mapping (reasoning/text deltas, tool call deltas, usage-only final chunk + includeUsage toggle)
- [x] Video request mapping (T2V/I2V/R2V) including resolution/size mapping and provider options
- [x] Video polling behavior (delay, timeout, FAILED/CANCELED mapping) + provider metadata (`taskId`, `videoUrl`, `actualPrompt`, `usage`)

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/alibaba/src/alibaba-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/alibaba/src/alibaba-chat-language-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/alibaba/src/alibaba-video-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/alibaba/src/convert-to-alibaba-chat-messages.ts`
- Upstream: `external/vercel-ai-sdk/packages/alibaba/src/convert-alibaba-usage.ts`
- Swift: `Sources/AlibabaProvider/AlibabaProvider.swift`
- Swift: `Sources/AlibabaProvider/AlibabaChatLanguageModel.swift`
- Swift: `Sources/AlibabaProvider/AlibabaVideoModel.swift`
- Swift: `Sources/AlibabaProvider/ConvertToAlibabaChatMessages.swift`
- Swift: `Sources/AlibabaProvider/ConvertAlibabaUsage.swift`
- Tests: `external/vercel-ai-sdk/packages/alibaba/src/*.test.ts` → `Tests/AlibabaProviderTests/*.swift`

