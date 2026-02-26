# Provider: Amazon Bedrock

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/amazon-bedrock/src/**`
- Swift implementation: `Sources/AmazonBedrockProvider/**`

## What is verified (checked + tested)

- [x] Reranking request mapping: query/documents (text + object), `topN`, `nextToken`, `additionalModelRequestFields`, and `modelArn` region mapping.
- [x] Reranking endpoint selection uses `bedrock-agent-runtime.<region>.amazonaws.com` when `baseURL` is not provided (upstream parity).
- [x] Reranking response mapping (`results[].index` + `results[].relevanceScore`) and response headers passthrough.
- [x] Embedding model parity: Titan/Cohere v3/Cohere v4/Nova payload mapping, response extraction, strict response validation, URL `encodeURIComponent` parity, and header combination behavior.
- [x] Image model parity: TEXT_IMAGE + editing task payloads (inpainting/outpainting/background removal/image variation), moderation/no-images errors, URL base64 restrictions, `encodeURIComponent` URL parity, and response timestamp/headers.
- [x] SigV4 + API key fetch parity: signing/bypass rules, header injection, token support, and error propagation.

Tests live under:
- `Tests/SwiftAISDKTests/Rerank/RerankTests.swift`
- `Tests/AmazonBedrockProviderTests/BedrockEmbeddingModelTests.swift`
- `Tests/AmazonBedrockProviderTests/BedrockImageModelTests.swift`
- `Tests/AmazonBedrockProviderTests/BedrockSigV4FetchTests.swift`

## Known gaps / TODO

- [ ] Chat language model parity (tool prep, prompt conversion, streaming event stream decoder, finish reasons).

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/amazon-bedrock/src/bedrock-provider.ts`
  - `external/vercel-ai-sdk/packages/amazon-bedrock/src/reranking/bedrock-reranking-model.ts`
- Swift (key files):
  - `Sources/AmazonBedrockProvider/BedrockProvider.swift`
  - `Sources/AmazonBedrockProvider/Reranking/BedrockRerankingModel.swift`
