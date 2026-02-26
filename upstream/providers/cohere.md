# Provider: Cohere

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/cohere/src/**`
- Swift implementation: `Sources/CohereProvider/**`

## What is verified (checked + tested)

- [x] Provider factory naming parity: added upstream alias `createCohere(...)` (while keeping `createCohereProvider(...)`).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Default base URL parity for provider-created chat model: `https://api.cohere.com/v2`.

## Known gaps / TODO

- [ ] Full parity audit for all Cohere model paths (`chat`, `embed`, `rerank`) beyond provider-construction/auth semantics.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/cohere/src/cohere-provider.ts`
- Swift files:
  - `Sources/CohereProvider/CohereProvider.swift`
  - `Tests/CohereProviderTests/CohereProviderTests.swift`
