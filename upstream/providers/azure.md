# Provider: Azure OpenAI

- Audited against upstream commit: `73d5c5920e0fea7633027fdd87374adc9ba49743`
- Upstream package: `external/vercel-ai-sdk/packages/azure/src/**`
- Swift implementation: `Sources/AzureProvider/**`

## What is verified (checked + tested)

- [x] URL construction parity (`baseURL` vs `resourceName`, `api-version`, deployment-based URL mode)
- [x] Request mapping parity across chat/completion/embedding/image/responses/speech/transcription
- [x] Headers parity (provider + request headers + user-agent suffix)
- [x] Responses parity for assistant file IDs and `include` provider options mapping
- [x] Auth/config behavior: missing `AZURE_API_KEY` and missing `resourceName` (when `baseURL` is absent) now throw `LoadAPIKeyError` / `LoadSettingError` at request time (no creation-time crash), with no network calls before failure.

## Known gaps / TODO

- [ ] None known.

## Notes

- Upstream: `external/vercel-ai-sdk/packages/azure/src/azure-openai-provider.ts`
- Swift: `Sources/AzureProvider/AzureProvider.swift`
- Swift tests: `Tests/AzureProviderTests/AzureProviderTests.swift`
