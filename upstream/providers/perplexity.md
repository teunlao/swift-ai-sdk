# Provider: Perplexity

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/perplexity/src/**`
- Swift implementation: `Sources/PerplexityProvider/**`

## What is verified (checked + tested)

- [x] Provider factory naming parity: added upstream alias `createPerplexity(...)` (while keeping `createPerplexityProvider(...)`).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Default base URL parity for provider-created models: `https://api.perplexity.ai`.
- [x] `PerplexityLanguageModel` request/response mapping parity (`doGenerate`/`doStream`): citations → `source`, PDF file parts → `file_url`, provider options passthrough, raw response headers exposure.
- [x] Usage conversion parity (including `reasoning_tokens` mapping to `outputTokens.reasoning` and `outputTokens.text = completion - reasoning`).
- [x] Streaming parity: `stream-start` warnings, `response-metadata`, text deltas, provider metadata (images + extended usage), and `includeRawChunks` raw/error parts (schema failures do not crash the stream).

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/perplexity/src/perplexity-provider.ts`
- Upstream reference: `external/vercel-ai-sdk/packages/perplexity/src/perplexity-language-model.ts`
- Upstream reference: `external/vercel-ai-sdk/packages/perplexity/src/convert-to-perplexity-messages.ts`
- Swift files:
  - `Sources/PerplexityProvider/PerplexityProvider.swift`
  - `Sources/PerplexityProvider/PerplexityLanguageModel.swift`
  - `Sources/PerplexityProvider/ConvertToPerplexityMessages.swift`
  - `Tests/PerplexityProviderTests/PerplexityProviderTests.swift`
  - `Tests/PerplexityProviderTests/PerplexityLanguageModelTests.swift`
