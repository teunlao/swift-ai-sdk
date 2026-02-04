# Provider: Rev.ai

- Audited against upstream commit: `f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9`
- Upstream package: `external/vercel-ai-sdk/packages/revai/src/**`
- Swift implementation: `Sources/RevAIProvider/**`

## What is verified (checked + tested)

- [x] Multipart submit request (media + config JSON) + user-agent suffix
- [x] Polling loop (in_progress → transcribed) and transcript fetch
- [x] Transcript mapping to `text` + timed segments + duration calculation
- [x] Error schema parsing + JSON error response mapping

## Known gaps / TODO

- [ ] Provider options schema completeness vs upstream (revaiProviderOptionsSchema is large; current Swift port focuses on the same keys but is not exhaustively audited).
- [ ] Failure paths parity: submission failed / polling failed / timeout errors (not yet covered by tests).

## Notes

- Upstream: `external/vercel-ai-sdk/packages/revai/src/revai-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/revai/src/revai-transcription-model.ts`
- Upstream: `external/vercel-ai-sdk/packages/revai/src/revai-error.ts`
- Swift: `Sources/RevAIProvider/RevAIProvider.swift`
- Swift: `Sources/RevAIProvider/RevAITranscriptionModel.swift`
- Swift: `Sources/RevAIProvider/RevAIError.swift`

