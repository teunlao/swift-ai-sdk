# Provider: DeepInfra

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/deepinfra/src/**`
- Swift implementation: `Sources/DeepInfraProvider/**`

## What is verified (checked + tested)

- [x] Provider factory naming parity: added upstream alias `createDeepInfra(...)` (while keeping `createDeepInfraProvider(...)`).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Default chat base URL parity for provider-created models: `https://api.deepinfra.com/v1/openai/chat/completions`.
- [x] Chat usage fix parity for DeepInfra Gemini/Gemma models: when `completion_tokens_details.reasoning_tokens > completion_tokens`, Swift corrects `completion_tokens` (and derived `outputTokens`) in both `doGenerate` and `doStream` finish.
- [x] Image model parity: JSON generation request mapping + base64 data-URL stripping, and image editing via multipart `.../openai/images/edits` when `files` are provided.
- [x] Completion + embedding base URL parity for provider-created models: `https://api.deepinfra.com/v1/openai/completions` and `https://api.deepinfra.com/v1/openai/embeddings`.
- [x] Image inference base URL parity for provider-created models: `https://api.deepinfra.com/v1/inference/<modelId>` and respects custom `baseURL`.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/deepinfra/src/deepinfra-provider.ts`
- Upstream reference: `external/vercel-ai-sdk/packages/deepinfra/src/deepinfra-chat-language-model.ts`
- Upstream reference: `external/vercel-ai-sdk/packages/deepinfra/src/deepinfra-image-model.ts`
- Swift files:
  - `Sources/DeepInfraProvider/DeepInfraProvider.swift`
  - `Sources/DeepInfraProvider/DeepInfraImageModel.swift`
  - `Tests/DeepInfraProviderTests/DeepInfraProviderTests.swift`
  - `Tests/DeepInfraProviderTests/DeepInfraChatUsageFixTests.swift`
  - `Tests/DeepInfraProviderTests/DeepInfraImageModelTests.swift`
