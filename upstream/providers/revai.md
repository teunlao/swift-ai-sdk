# Provider: Rev.ai

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/revai/src/**`
- Swift implementation: `Sources/RevAIProvider/**`

## What is verified (checked + tested)

- [x] Multipart submit request (media + config JSON) + user-agent suffix
- [x] Polling loop (in_progress → transcribed) and transcript fetch
- [x] Transcript mapping to `text` + timed segments + duration calculation
- [x] Error schema parsing + JSON error response mapping
- [x] Provider options schema parity: request config mapping matches upstream `revaiTranscriptionModelOptionsSchema` (incl. `notification_config` empty strings and `custom_vocabularies` stripping).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` (no creation-time crash)
- [x] Upstream factory alias parity: `createRevai(...)`
- [x] Failure paths parity: submission failed / polling failed / timeout errors (covered by Swift tests).

## Known gaps / TODO

- None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/revai/src/revai-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/revai/src/revai-transcription-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/revai/src/revai-error.ts`
- Swift: `Sources/RevAIProvider/RevAIProvider.swift`
- Swift: `Sources/RevAIProvider/RevAITranscriptionModel.swift`
- Swift: `Sources/RevAIProvider/RevAIError.swift`
