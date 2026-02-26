# Provider: Cerebras

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/cerebras/src/**`
- Swift implementation: `Sources/CerebrasProvider/**`

## What is verified (checked + tested)

- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Upstream factory alias already present: `createCerebras(...)`.
- [x] Regression coverage includes request-time missing key behavior.

## Known gaps / TODO

- [ ] Full parity audit of all provider tests from upstream `cerebras-provider.test.ts` for constructor-level assertions.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/cerebras/src/cerebras-provider.ts`
- Swift files:
  - `Sources/CerebrasProvider/CerebrasProvider.swift`
  - `Tests/CerebrasProviderTests/CerebrasProviderTests.swift`
