# Provider: Hugging Face

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/huggingface/src/**`
- Swift implementation: `Sources/HuggingFaceProvider/**`

## What is verified (checked + tested)

- [x] Upstream alias parity: `createHuggingFace(...)`
- [x] Responses provider/model wiring
- [x] Auth behavior: missing `HUGGINGFACE_API_KEY` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/huggingface/src/huggingface-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/huggingface/src/responses/huggingface-responses-language-model.ts`
- Swift: `Sources/HuggingFaceProvider/HuggingFaceProvider.swift`
- Swift: `Sources/HuggingFaceProvider/HuggingFaceResponsesLanguageModel.swift`
- Swift tests: `Tests/HuggingFaceProviderTests/HuggingFaceProviderTests.swift`
