# Provider: Groq

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/groq/src/**`
- Swift implementation: `Sources/GroqProvider/**`

## What is verified (checked + tested)

- [x] Provider wrapper creates chat and transcription models (`groq.chat`, `groq.transcription`)
- [x] Default base URL matches upstream (`https://api.groq.com/openai/v1`)
- [x] `withoutTrailingSlash` applied to custom base URL
- [x] `User-Agent` suffix includes `ai-sdk/groq/<version>`
- [x] Missing API key throws request-time `LoadAPIKeyError` (no process crash)
- [x] Added upstream alias `createGroq(...)` in Swift (`createGroqProvider(...)` remains supported)
- [x] Unsupported models throw `NoSuchModelError` (embedding + image)
- [x] Chat and transcription requests share request-time auth injection behavior

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/groq/src/groq-provider.ts`
- Swift: `Sources/GroqProvider/GroqProvider.swift`
- Tests: `Tests/GroqProviderTests/GroqProviderTests.swift`
