# Provider: Fal

- Audited against upstream commit: `f3a72bc2`
- Upstream package: `external/vercel-ai-sdk/packages/fal/src/**`
- Swift implementation: `Sources/FalProvider/**`

## What is verified (checked + tested)

- [x] Video: request mapping (prompt/image/aspectRatio/duration/seed + providerOptions)
- [x] Video: polling behavior (queue + in-progress handling + timeout/abort)
- [x] Video: providerMetadata mapping (videos[], seed, timings.inference optional, contentType optional)
- [ ] Image: request/response parity
- [ ] Speech: request/response parity
- [ ] Transcription: request/response parity

## Known gaps / TODO

- [ ] Audit Fal image/speech/transcription against the pinned baseline commit.

## Notes

- Swift evidence:
  - `Sources/FalProvider/FalVideoModel.swift`
  - `Sources/FalProvider/FalProvider.swift`
  - `Tests/FalProviderTests/FalVideoModelTests.swift`
- Upstream evidence:
  - `external/vercel-ai-sdk/packages/fal/src/fal-video-model.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-video-model.test.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-provider.ts`
