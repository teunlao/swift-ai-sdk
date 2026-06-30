# Provider: KlingAI

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/klingai/src/**`
- Swift implementation: `Sources/KlingAIProvider/**`

## What is verified (checked + tested)

- [x] Auth token generation (HS256 JWT; env + explicit settings)
- [x] Provider headers (Authorization + user-agent suffix) and baseURL handling
- [x] Video request mapping for modes: motion-control / t2v / i2v
- [x] Provider options mapping + passthrough (`providerOptions.klingai`)
- [x] Polling behavior (interval/timeout/abort)
- [x] Warnings parity for unsupported SDK options (`resolution`, `seed`, `fps`, `n`, and mode-specific warnings)
- [x] Response metadata (timestamp/modelId/headers)
- [x] Provider metadata (`taskId`, `videos[]` with `watermarkUrl`/`duration`)
- [x] Error mapping (missing motion-control fields, missing task_id, failed status, empty videos)

## Known gaps / TODO

- [ ] None known (video-only provider; no streaming/chat/tools)

## Notes

- Upstream: `external/vercel-ai-sdk/packages/klingai/src/klingai-video-model.ts`
- Swift: `Sources/KlingAIProvider/KlingAIVideoModel.swift`
- Tests:
  - `external/vercel-ai-sdk/packages/klingai/src/klingai-auth.test.ts` → `Tests/KlingAIProviderTests/KlingAIAuthTests.swift`
  - `external/vercel-ai-sdk/packages/klingai/src/klingai-video-model.test.ts` → `Tests/KlingAIProviderTests/KlingAIVideoModelTests.swift`

