# Provider: Prodia

- Audited against upstream commit: `f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9`
- Upstream package: `external/vercel-ai-sdk/packages/prodia/src/**`
- Swift implementation: `Sources/ProdiaProvider/**`

## What is verified (checked + tested)

- [x] Provider settings: baseURL + headers + user-agent suffix
- [x] Request mapping: size parsing + providerOptions precedence + seed/steps/stylePreset/loras/progressive
- [x] Multipart response parsing (job + image bytes)
- [x] Provider metadata mapping from job result
- [x] Error mapping (detail/message variants) + invalid size warning

## Known gaps / TODO

- [ ] Expand multipart parser coverage for edge-case boundaries/headers.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/prodia/src/prodia-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/prodia/src/prodia-image-model.ts`
- Swift: `Sources/ProdiaProvider/ProdiaProvider.swift`
- Swift: `Sources/ProdiaProvider/ProdiaImageModel.swift`

