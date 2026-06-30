# Provider: Gladia

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/gladia/src/**`
- Swift implementation: `Sources/GladiaProvider/**`

## What is verified (checked + tested)

- [x] Upstream alias parity: `createGladia(...)`
- [x] Transcription provider/model wiring
- [x] Auth behavior: missing `GLADIA_API_KEY` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/gladia/src/gladia-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/gladia/src/gladia-transcription-model.ts`
- Swift: `Sources/GladiaProvider/GladiaProvider.swift`
- Swift: `Sources/GladiaProvider/GladiaTranscriptionModel.swift`
- Swift tests: `Tests/GladiaProviderTests/GladiaProviderTests.swift`
