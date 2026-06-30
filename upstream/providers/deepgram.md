# Provider: Deepgram

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/deepgram/src/**`
- Swift implementation: `Sources/DeepgramProvider/**`

## What is verified (checked + tested)

- [x] Upstream alias parity: `createDeepgram(...)`
- [x] Transcription provider/model wiring (`.transcription`)
- [x] Speech provider/model wiring (`.speech`) + request mapping/warnings parity
- [x] Auth behavior: missing `DEEPGRAM_API_KEY` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] (none)

## Notes

- Upstream: `external/vercel-ai-sdk/packages/deepgram/src/deepgram-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/deepgram/src/deepgram-transcription-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/deepgram/src/deepgram-speech-model.ts`
- Swift: `Sources/DeepgramProvider/DeepgramProvider.swift`
- Swift: `Sources/DeepgramProvider/DeepgramTranscriptionModel.swift`
- Swift: `Sources/DeepgramProvider/DeepgramSpeechModel.swift`
- Swift tests: `Tests/DeepgramProviderTests/DeepgramProviderTests.swift`
- Swift tests: `Tests/DeepgramProviderTests/DeepgramSpeechModelTests.swift`
