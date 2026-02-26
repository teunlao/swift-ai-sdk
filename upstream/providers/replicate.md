# Provider: Replicate

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/replicate/src/**`
- Swift implementation: `Sources/ReplicateProvider/**`

## What is verified (checked + tested)

- [x] Provider creation and image model wiring (`createReplicate`, custom `baseURL`)
- [x] Request mapping for image generation (`input`, versioned/unversioned model routing, merged provider options)
- [x] Image download flow and response metadata mapping
- [x] Auth behavior: missing `REPLICATE_API_TOKEN` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] Video model parity from upstream `replicate-provider.ts` is not yet implemented in Swift provider surface.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/replicate/src/replicate-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/replicate/src/replicate-image-model.ts`
- Swift: `Sources/ReplicateProvider/ReplicateProvider.swift`
- Swift: `Sources/ReplicateProvider/ReplicateImageModel.swift`
