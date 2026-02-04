# Provider: TogetherAI

- Audited against upstream commit: `f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9`
- Upstream package: `external/vercel-ai-sdk/packages/togetherai/src/**`
- Swift implementation: `Sources/TogetherAIProvider/**`

## What is verified (checked + tested)

- [x] Provider construction + model factories (chat/completion/embedding/image/reranking)
- [x] Image request mapping (size/seed/files/providerOptions) + response decoding + errors
- [x] Reranking request mapping + response decoding + errors
- [x] Abort signal handling for HTTP calls

## Known gaps / TODO

- [ ] Chat/completion/embedding parity is mediated via `OpenAICompatibleProvider`; audit TogetherAI-specific differences vs upstream if any.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/togetherai/src/togetherai-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/togetherai/src/togetherai-image-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/togetherai/src/togetherai-reranking-model.ts`
- Swift: `Sources/TogetherAIProvider/TogetherAIProvider.swift`
- Swift: `Sources/TogetherAIProvider/Image/TogetherAIImageModel.swift`
- Swift: `Sources/TogetherAIProvider/Reranking/TogetherAIRerankingModel.swift`

