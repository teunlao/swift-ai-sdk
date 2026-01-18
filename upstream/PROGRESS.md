# Upstream Parity Progress

This folder is the source of truth for “what is verified” vs “what is unknown” against a specific upstream commit.

Rules:
- Always tie statements to an upstream commit hash from `upstream/UPSTREAM.md`.
- Prefer provider parity work (prompt ↔ HTTP ↔ decode ↔ streaming) over core refactors.
- Keep docs short and actionable: checklists + links to Swift/upstream paths.

## Current priorities

1) Providers parity (tools, streaming, errors)
2) Core API parity only when blocked by providers
3) Docs updates only after behavior parity is green

## How to track a provider

1) Copy `upstream/providers/_template.md` → `upstream/providers/<provider>.md`
2) Fill:
   - upstream paths under `external/vercel-ai-sdk/packages/<provider>/src/**`
   - Swift paths under `Sources/<ProviderName>Provider/**`
   - audited commit hash from `upstream/UPSTREAM.md`
3) Update the checklist as you verify behaviors (tests preferred).

