# Provider: Quiver AI

- Audited against upstream commit: `not audited`
- Upstream package: `external/vercel-ai-sdk/packages/quiverai/src/**`
- Swift implementation: none detected

## What is verified (checked + tested)

- [ ] Provider package ownership decision
- [ ] Prompt conversion (messages/system/tools)
- [ ] Tool call serialization + tool result mapping
- [ ] Response decoding (content blocks -> internal content)
- [ ] Streaming SSE mapping (deltas/events -> internal stream parts)
- [ ] Error mapping (HTTP errors + API error shapes)
- [ ] Model/feature gates (flags, defaults, provider options)

## Known gaps / TODO

- [ ] Upstream provider package exists, but Swift has no `QuiverAIProvider` target.
- [ ] Decide whether to port this provider or mark it intentionally out of scope.
- [ ] If ported, audit against upstream `85a80fc6e71558717899e30c9f1fc0e9eb7d733d`.

## Notes

- This file is an intake tracker only. It does not mark Quiver AI parity as
  verified against the current baseline.

