# Provider: DeepInfra

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/deepinfra/src/**`
- Swift implementation: `Sources/DeepInfraProvider/**`

## What is verified (checked + tested)

- [x] Provider factory naming parity: added upstream alias `createDeepInfra(...)` (while keeping `createDeepInfraProvider(...)`).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Default chat base URL parity for provider-created models: `https://api.deepinfra.com/v1/openai/chat/completions`.

## Known gaps / TODO

- [ ] Full parity audit of non-chat paths (`completion`, `embedding`, `image`) beyond provider-construction/auth semantics.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/deepinfra/src/deepinfra-provider.ts`
- Swift files:
  - `Sources/DeepInfraProvider/DeepInfraProvider.swift`
  - `Tests/DeepInfraProviderTests/DeepInfraProviderTests.swift`
