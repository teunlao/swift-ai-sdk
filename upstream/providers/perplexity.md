# Provider: Perplexity

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/perplexity/src/**`
- Swift implementation: `Sources/PerplexityProvider/**`

## What is verified (checked + tested)

- [x] Provider factory naming parity: added upstream alias `createPerplexity(...)` (while keeping `createPerplexityProvider(...)`).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Default base URL parity for provider-created models: `https://api.perplexity.ai`.

## Known gaps / TODO

- [ ] Full file-by-file parity audit for `perplexity-language-model.ts` edge cases beyond existing Swift test coverage.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/perplexity/src/perplexity-provider.ts`
- Swift files:
  - `Sources/PerplexityProvider/PerplexityProvider.swift`
  - `Tests/PerplexityProviderTests/PerplexityProviderTests.swift`
