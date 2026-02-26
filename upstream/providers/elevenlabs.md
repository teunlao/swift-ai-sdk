# Provider: ElevenLabs

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/elevenlabs/src/**`
- Swift implementation: `Sources/ElevenLabsProvider/**`

## What is verified (checked + tested)

- [x] Upstream alias parity: `createElevenLabs(...)`
- [x] Provider wiring for transcription and speech models
- [x] Auth behavior: missing `ELEVENLABS_API_KEY` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/elevenlabs/src/elevenlabs-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/elevenlabs/src/elevenlabs-transcription-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/elevenlabs/src/elevenlabs-speech-model.ts`
- Swift: `Sources/ElevenLabsProvider/ElevenLabsProvider.swift`
- Swift: `Sources/ElevenLabsProvider/ElevenLabsTranscriptionModel.swift`
- Swift: `Sources/ElevenLabsProvider/ElevenLabsSpeechModel.swift`
- Swift tests: `Tests/ElevenLabsProviderTests/ElevenLabsProviderTests.swift`
