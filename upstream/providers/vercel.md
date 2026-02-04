# Provider: Vercel (v0)

- Audited against upstream commit: `f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9`
- Upstream package: `external/vercel-ai-sdk/packages/vercel/src/**`
- Swift implementation: `Sources/VercelProvider/**`

## What is verified (checked + tested)

- [x] Provider wrapper creates OpenAI-compatible chat model (`vercel.chat`)
- [x] Default base URL is `https://api.v0.dev/v1`
- [x] `withoutTrailingSlash` applied to custom base URL
- [x] `Authorization: Bearer <apiKey>` + custom headers applied
- [x] `User-Agent` suffix includes `ai-sdk/vercel/<version>`
- [x] Unsupported models throw `NoSuchModelError` (embedding + image)

## Notes

- Upstream: `external/vercel-ai-sdk/packages/vercel/src/vercel-provider.ts`
- Swift: `Sources/VercelProvider/VercelProvider.swift`

