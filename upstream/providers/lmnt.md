# Provider: LMNT

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/lmnt/src/**`
- Swift implementation: `Sources/LMNTProvider/**`

## What is verified (checked + tested)

- [x] Speech provider/model wiring (`createLMNT`, `.speech`, `.speechModel`)
- [x] Request mapping and headers merge behavior for speech generation
- [x] Audio binary response handling and response metadata mapping
- [x] Auth behavior: missing `LMNT_API_KEY` now throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/lmnt/src/lmnt-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/lmnt/src/lmnt-speech-model.ts`
- Swift: `Sources/LMNTProvider/LMNTProvider.swift`
- Swift: `Sources/LMNTProvider/LMNTSpeechModel.swift`
