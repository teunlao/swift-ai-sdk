# Provider: Fal

- Audited against upstream commit: `f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9`
- Upstream package: `external/vercel-ai-sdk/packages/fal/src/**`
- Swift implementation: `Sources/FalProvider/**`

## What is verified (checked + tested)

- [x] Video: request mapping (prompt/image/aspectRatio/duration/seed + providerOptions)
- [x] Video: polling behavior (queue + in-progress handling + timeout/abort)
- [x] Video: providerMetadata mapping (videos[], seed, timings.inference optional, contentType optional)
- [x] Image: request/response parity (providerOptions schema validation + camelCase/snake_case deprecations, image editing, metadata mapping, validation errors).
- [x] Speech: request/response parity (request args incl. providerOptions passthrough, warnings, headers, audio download, response metadata).
- [x] Transcription: request/response parity (queue payload, polling/in-progress loop, text+segments mapping, response metadata).

## Known gaps / TODO

- [ ] Add optional parity tests for additional Fal image validation error envelopes beyond `detail[]` / `message`.

## Notes

- Swift evidence:
  - `Sources/FalProvider/FalImageModel.swift`
  - `Sources/FalProvider/FalImageOptions.swift`
  - `Sources/FalProvider/FalSpeechModel.swift`
  - `Sources/FalProvider/FalSpeechOptions.swift`
  - `Sources/FalProvider/FalTranscriptionModel.swift`
  - `Sources/FalProvider/FalError.swift`
  - `Sources/FalProvider/FalVideoModel.swift`
  - `Sources/FalProvider/FalProvider.swift`
  - `Tests/FalProviderTests/FalImageModelTests.swift`
  - `Tests/FalProviderTests/FalSpeechModelTests.swift`
  - `Tests/FalProviderTests/FalTranscriptionModelTests.swift`
  - `Tests/FalProviderTests/FalProviderTests.swift`
  - `Tests/FalProviderTests/FalErrorTests.swift`
  - `Tests/FalProviderTests/FalVideoModelTests.swift`
- Upstream evidence:
  - `external/vercel-ai-sdk/packages/fal/src/fal-image-model.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-image-options.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-image-model.test.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-speech-model.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-speech-model.test.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-transcription-model.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-transcription-model.test.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-error.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-error.test.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-video-model.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-video-model.test.ts`
  - `external/vercel-ai-sdk/packages/fal/src/fal-provider.ts`
