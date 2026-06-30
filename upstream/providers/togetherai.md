# Provider: TogetherAI

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/togetherai/src/**`
- Swift implementation: `Sources/TogetherAIProvider/**`

## What is verified (checked + tested)

- [x] Provider construction + model factories (chat/completion/embedding/image/reranking)
- [x] Image request mapping (size/seed/files/providerOptions) + response decoding + errors
- [x] Reranking request mapping + response decoding + errors
- [x] Abort signal handling for HTTP calls
- [x] Chat/completion/embedding provider auth parity: API key is loaded at request time (not provider creation), and missing key throws `LoadAPIKeyError` without crashing the process

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/togetherai/src/togetherai-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/togetherai/src/togetherai-image-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/togetherai/src/togetherai-reranking-model.ts`
- Swift: `Sources/TogetherAIProvider/TogetherAIProvider.swift`
- Swift: `Sources/TogetherAIProvider/Image/TogetherAIImageModel.swift`
- Swift: `Sources/TogetherAIProvider/Reranking/TogetherAIRerankingModel.swift`
