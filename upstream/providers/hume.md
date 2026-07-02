# Provider: Hume

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/hume/src/**`
- Swift implementation: `Sources/HumeProvider/**`

## What is verified (checked + tested)

- [x] Speech provider/model wiring (`createHume`, `.speech`, `.speechModel`)
- [x] Auth behavior: missing `HUME_API_KEY` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/hume/src/hume-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/hume/src/hume-speech-model.ts`
- Swift: `Sources/HumeProvider/HumeProvider.swift`
- Swift: `Sources/HumeProvider/HumeSpeechModel.swift`
- Swift tests: `Tests/HumeProviderTests/HumeProviderTests.swift`
