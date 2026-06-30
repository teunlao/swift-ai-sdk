# Provider: DeepSeek

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/deepseek/src/**`
- Swift implementation: `Sources/DeepSeekProvider/**`

## What is verified (checked + tested)

- [x] Provider wrapper creates OpenAI-compatible chat model (`deepseek.chat`)
- [x] Default base URL matches upstream (`https://api.deepseek.com`)
- [x] `withoutTrailingSlash` applied to custom base URL
- [x] `User-Agent` suffix includes `ai-sdk/deepseek/<version>`
- [x] Missing API key throws request-time `LoadAPIKeyError` (no process crash)
- [x] Unsupported models throw `NoSuchModelError` (embedding + image)
- [x] DeepSeek-specific metadata extractor behavior is covered by tests

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/deepseek/src/deepseek-provider.ts`
- Swift: `Sources/DeepSeekProvider/DeepSeekProvider.swift`
- Tests: `Tests/DeepSeekProviderTests/DeepSeekProviderTests.swift`
