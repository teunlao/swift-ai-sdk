# Provider: OpenAI-compatible

- Audited against upstream commit: `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`
- Upstream package: `external/vercel-ai-sdk/packages/openai-compatible/src/**`
- Swift implementation: `Sources/OpenAICompatibleProvider/**`

## What is verified (checked + tested)

- [x] V4 provider entrypoint shape:
  `createOpenAICompatible(settings:) -> OpenAICompatibleProviderV4`.
- [x] V4 model factory surface:
  `languageModel`, `chatModel`, `completionModel`, `embeddingModel`,
  `textEmbeddingModel`, and `imageModel`.
- [x] V3 API preservation:
  `createOpenAICompatibleProvider(settings:) -> OpenAICompatibleProvider`
  remains the V3 entrypoint.
- [x] Request URL/header/query construction is shared by V3 and V4 surfaces.
- [x] `supportedUrls` is accepted in provider settings and forwarded to V4
  language models through the existing chat config.
- [x] V4 language `doGenerate` wrapper maps V4 call options into the current
  V3-backed OpenAI-compatible chat model and maps content, finish reason, usage,
  request/response metadata, provider metadata, and warnings back to V4.
- [x] V4 language `doStream` wrapper maps V3 stream parts into V4 stream parts,
  including text deltas and finish usage.
- [x] V4 embedding wrapper preserves embeddings, usage, provider metadata,
  response headers/body, and warnings.
- [x] V4 image wrapper preserves base64/binary images, warnings, provider
  metadata, response metadata, and usage when the V3 model returns it.

## Known gaps / TODO

- [ ] Native OpenAI-compatible model implementations are still V3-backed under
  the new V4 provider surface; this diff intentionally adds the V4 entrypoint
  and wrappers rather than rewriting the provider internals.
- [ ] Upstream `convertUsage` setting is not exposed yet. Swift currently maps
  OpenAI-compatible raw usage inside the V3 chat model and the raw upstream
  usage type is not a public provider-level setting contract.
- [ ] Full upstream fixture parity for every chat/completion/tool/error path is
  not claimed by this tracker entry.

## Notes

- Added provider tests:
  `Tests/OpenAICompatibleProviderTests/OpenAICompatibleProviderV4Tests.swift`.
- Targeted verification:
  `swift test --filter OpenAICompatibleProviderV4Tests`.
