# Provider: Cohere

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/cohere/src/**`
- Swift implementation: `Sources/CohereProvider/**`

## What is verified (checked + tested)

- [x] Provider factory naming parity: added upstream alias `createCohere(...)` (while keeping `createCohereProvider(...)`).
- [x] Provider auth parity: API key now resolves at request time via `loadAPIKey`, missing key throws `LoadAPIKeyError` instead of process crash.
- [x] Default base URL parity for provider-created chat model: `https://api.cohere.com/v2`.
- [x] `convertToCohereChatPrompt` parity: file parts → `documents` extraction + tool call/result message mapping.
- [x] `prepareTools` parity: provider-defined tool warnings and tool choice mapping (including empty `tools: []` behavior).
- [x] Embedding model parity: request mapping (`input_type`, `truncate`, `output_dimension`), headers merge + user-agent suffix, usage/response exposure.

## Known gaps / TODO

- [ ] Chat language model parity (`doGenerate` + `doStream`): request mapping coverage + streaming edge-cases.
- [ ] Reranking model parity (`rerank`): request mapping + response mapping + tests.

## Notes

- Upstream reference: `external/vercel-ai-sdk/packages/cohere/src/cohere-provider.ts`
- Swift files:
  - `Sources/CohereProvider/CohereProvider.swift`
  - `Tests/CohereProviderTests/CohereProviderTests.swift`
