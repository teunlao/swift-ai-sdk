# Provider: Prodia

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/prodia/src/**`
- Swift implementation: `Sources/ProdiaProvider/**`

## What is verified (checked + tested)

- [x] Provider settings: baseURL + headers + user-agent suffix
- [x] Request mapping: size parsing + providerOptions precedence + seed/steps/stylePreset/loras/progressive
- [x] Multipart response parsing (job + image bytes)
- [x] Multipart parser edge-cases: LF-only line endings and `content-type` boundary with extra params.
- [x] Provider metadata mapping from job result
- [x] Error mapping (detail/message variants) + invalid size warning
- [x] Auth behavior: missing `PRODIA_TOKEN` now throws `LoadAPIKeyError` at request time (no creation-time crash), and does not perform network calls before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/prodia/src/prodia-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/prodia/src/prodia-image-model.ts`
- Swift: `Sources/ProdiaProvider/ProdiaProvider.swift`
- Swift: `Sources/ProdiaProvider/ProdiaImageModel.swift`
