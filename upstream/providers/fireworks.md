# Provider: Fireworks

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/fireworks/src/**`
- Swift implementation: `Sources/FireworksProvider/**`

## What is verified (checked + tested)

- [x] Provider/model wiring for chat/completion/embedding/image
- [x] Chat request base URL mapping (`https://api.fireworks.ai/inference/v1`)
- [x] Upstream alias parity: `createFireworks(...)`
- [x] Auth behavior: missing `FIREWORKS_API_KEY` throws `LoadAPIKeyError` at request time (no creation-time crash), and no network call is made before failing.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/fireworks/src/fireworks-provider.ts`
- Swift: `Sources/FireworksProvider/FireworksProvider.swift`
- Swift tests: `Tests/FireworksProviderTests/FireworksProviderTests.swift`
