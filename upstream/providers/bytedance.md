# Provider: ByteDance

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/bytedance/src/**`
- Swift implementation: `Sources/ByteDanceProvider/**`

## What is verified (checked + tested)

- [x] Video request mapping (prompt/image/seed/aspectRatio/duration/resolution)
- [x] Provider options mapping + passthrough (`providerOptions.bytedance`)
- [x] Polling behavior (interval/timeout/abort)
- [x] Warnings parity (unsupported `fps`, `n > 1`)
- [x] Response metadata (timestamp/modelId/headers)
- [x] Provider metadata (`taskId`, `usage.completion_tokens`)
- [x] Error mapping (no task id, task failed, no video url, task creation API errors)

## Known gaps / TODO

- [ ] None known (video-only provider; no streaming/chat/tools)

## Notes

- Upstream: `external/vercel-ai-sdk/packages/bytedance/src/bytedance-video-model.ts`
- Swift: `Sources/ByteDanceProvider/ByteDanceVideoModel.swift`
- Tests: `external/vercel-ai-sdk/packages/bytedance/src/bytedance-video-model.test.ts` → `Tests/ByteDanceProviderTests/ByteDanceVideoModelTests.swift`

