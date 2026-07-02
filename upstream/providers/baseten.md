# Provider: Baseten

- Audited against upstream commit: `not audited`
- Upstream package: `external/vercel-ai-sdk/packages/baseten/src/**`
- Swift implementation: `Sources/BasetenProvider/**`

## What is verified (checked + tested)

- [ ] Prompt conversion (messages/system/tools)
- [ ] Tool call serialization + tool result mapping
- [ ] Response decoding (content blocks -> internal content)
- [ ] Streaming SSE mapping (deltas/events -> internal stream parts)
- [ ] Error mapping (HTTP errors + API error shapes)
- [ ] Model/feature gates (flags, defaults, provider options)

## Known gaps / TODO

- [ ] Durable provider tracking page was missing before the 2026-06-30 upstream intake.
- [ ] Re-audit against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`.

## Notes

- This file is an intake tracker only. It does not mark Baseten parity as
  verified against the current baseline.

