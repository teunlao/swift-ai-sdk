# Provider: Luma

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/luma/src/**`
- Swift implementation: `Sources/LumaProvider/**`

## What is verified (checked + tested)

- [x] Upstream alias parity: `createLuma(...)`
- [x] Image provider/model wiring
- [x] Auth behavior: missing `LUMA_API_KEY` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/luma/src/luma-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/luma/src/luma-image-model.ts`
- Swift: `Sources/LumaProvider/LumaProvider.swift`
- Swift: `Sources/LumaProvider/LumaImageModel.swift`
- Swift tests: `Tests/LumaProviderTests/LumaProviderTests.swift`
