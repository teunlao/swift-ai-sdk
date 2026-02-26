# Provider: Amazon Bedrock

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/amazon-bedrock/src/**`
- Swift implementation: `Sources/AmazonBedrockProvider/**`

## What is verified (checked + tested)

- [x] Reranking request mapping: query/documents (text + object), `topN`, `nextToken`, `additionalModelRequestFields`, and `modelArn` region mapping.
- [x] Reranking endpoint selection uses `bedrock-agent-runtime.<region>.amazonaws.com` when `baseURL` is not provided (upstream parity).
- [x] Reranking response mapping (`results[].index` + `results[].relevanceScore`) and response headers passthrough.

Tests live under:
- `Tests/SwiftAISDKTests/Rerank/RerankTests.swift`

## Known gaps / TODO

- [ ] Chat language model parity (tool prep, prompt conversion, streaming event stream decoder, finish reasons).
- [ ] Embedding model parity.
- [ ] Image model parity.
- [ ] SigV4 fetch parity (header canonicalization + body signing edge cases) and error messages.

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/amazon-bedrock/src/bedrock-provider.ts`
  - `external/vercel-ai-sdk/packages/amazon-bedrock/src/reranking/bedrock-reranking-model.ts`
- Swift (key files):
  - `Sources/AmazonBedrockProvider/BedrockProvider.swift`
  - `Sources/AmazonBedrockProvider/Reranking/BedrockRerankingModel.swift`

