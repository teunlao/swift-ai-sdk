# Provider: Mistral

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/mistral/src/**`
- Swift implementation: `Sources/MistralProvider/**`

## What is verified (checked + tested)

- [x] Provider wrapper creates chat and embedding models (`mistral.chat`, `mistral.embedding`)
- [x] Default base URL matches upstream (`https://api.mistral.ai/v1`)
- [x] `withoutTrailingSlash` applied to custom base URL
- [x] `User-Agent` suffix includes `ai-sdk/mistral/<version>`
- [x] Missing API key throws request-time `LoadAPIKeyError` (no process crash)
- [x] Added upstream alias `createMistral(...)` in Swift (`createMistralProvider(...)` remains supported)
- [x] Unsupported image model path throws `NoSuchModelError`

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/mistral/src/mistral-provider.ts`
- Swift: `Sources/MistralProvider/MistralProvider.swift`
- Tests: `Tests/MistralProviderTests/MistralProviderTests.swift`
