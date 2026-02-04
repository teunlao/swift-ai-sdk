# Provider: Black Forest Labs

- Audited against upstream commit: `f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9`
- Upstream package: `external/vercel-ai-sdk/packages/black-forest-labs/src/**`
- Swift implementation: `Sources/BlackForestLabsProvider/**`

## What is verified (checked + tested)

- [x] Submit request mapping (prompt + providerOptions)
- [x] Polling behavior (interval/timeout overrides, abort) + result mapping
- [x] Final image download + binary response handling
- [x] Error mapping via JSON error envelope

## Known gaps / TODO

- [ ] Expand edge-case parity vs upstream tests (webhook fields, more poll statuses).

## Notes

- Upstream: `external/vercel-ai-sdk/packages/black-forest-labs/src/black-forest-labs-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/black-forest-labs/src/black-forest-labs-image-model.ts`
- Swift: `Sources/BlackForestLabsProvider/BlackForestLabsProvider.swift`
- Swift: `Sources/BlackForestLabsProvider/BlackForestLabsImageModel.swift`

