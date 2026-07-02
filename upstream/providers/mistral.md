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
- [x] `supportedUrls` parity: PDF URLs only allow lowercase `https://` (case-sensitive), matching upstream regex.
- [x] Usage parity: `usage.raw` is populated with the provider usage object for generate + stream.
- [x] Stream parse-error parity: invalid SSE chunks emit structured JSON error payload (`name`/`message`/`value`) instead of stringifying the error.
- [x] Tool-call schema parity: tool-call `id` and `function.arguments` are required in chunk/response decoding (missing fields yield stream parse errors).

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/mistral/src/mistral-provider.ts`
- Swift: `Sources/MistralProvider/MistralProvider.swift`
- Tests: `Tests/MistralProviderTests/MistralProviderTests.swift`
