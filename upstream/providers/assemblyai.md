# Provider: AssemblyAI

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/assemblyai/src/**`
- Swift implementation: `Sources/AssemblyAIProvider/**`

## What is verified (checked + tested)

- [x] Provider factory naming parity: added upstream alias `createAssemblyAI(...)` (while keeping `createAssemblyAIProvider(...)`).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Provider endpoint parity: transcription flow uses upstream endpoints (`/v2/upload` then `/v2/transcript` then polling `GET /v2/transcript/:id`).
- [x] Transcription model parity: request mapping (`speech_model` + provider options), polling semantics, and response metadata uses headers/body from the final GET response.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/assemblyai/src/assemblyai-provider.ts`
- Upstream reference: `external/vercel-ai-sdk/packages/assemblyai/src/assemblyai-transcription-model.ts`
- Swift files:
  - `Sources/AssemblyAIProvider/AssemblyAIProvider.swift`
  - `Sources/AssemblyAIProvider/AssemblyAITranscriptionModel.swift`
  - `Tests/AssemblyAIProviderTests/AssemblyAIProviderTests.swift`
  - `Tests/AssemblyAIProviderTests/AssemblyAITranscriptionModelTests.swift`
