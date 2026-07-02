# Provider: Black Forest Labs

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/black-forest-labs/src/**`
- Swift implementation: `Sources/BlackForestLabsProvider/**`

## What is verified (checked + tested)

- [x] Submit request mapping (prompt + providerOptions)
- [x] Polling behavior (interval/timeout overrides, abort) + result mapping
- [x] Final image download + binary response handling
- [x] Error mapping via JSON error envelope
- [x] Edge-case parity coverage: webhook fields, `state` vs `status` poll responses, polling retries/timeouts, Error/Failed statuses, URL/id query injection, and merged headers to polling.
- [x] Auth behavior: missing `BFL_API_KEY` now throws `LoadAPIKeyError` at request time (no creation-time crash), and does not perform network calls before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/black-forest-labs/src/black-forest-labs-provider.ts`
- Upstream: `external/vercel-ai-sdk/packages/black-forest-labs/src/black-forest-labs-image-model.ts`
- Swift: `Sources/BlackForestLabsProvider/BlackForestLabsProvider.swift`
- Swift: `Sources/BlackForestLabsProvider/BlackForestLabsImageModel.swift`
