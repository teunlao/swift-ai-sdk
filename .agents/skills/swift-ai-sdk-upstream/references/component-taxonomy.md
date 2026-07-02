# Upstream Component Taxonomy

This file defines how Vercel AI SDK upstream packages are classified for Swift
AI SDK parity work. The generated component catalog should follow these
definitions.

## Areas

| Area | Meaning |
| --- | --- |
| `core` | Public contracts and runtime orchestration in `ai`, `provider`, and `provider-utils`. |
| `provider` | Provider implementation packages that can map to Swift provider targets. |
| `docs` | Documentation content and examples that may need Swift adaptation. |
| `framework` | JavaScript UI/framework packages such as React, Vue, Svelte, Angular, and RSC. |
| `tooling` | Upstream development tooling, codemods, devtools, test helpers, or internal adapters. |
| `unknown` | Package exists upstream but has not been classified yet. |

## Priorities

| Priority | Meaning |
| --- | --- |
| `P0` | Must stay close to upstream: `ai`, `provider`, `provider-utils`, `openai`, `openai-compatible`, `anthropic`, `google`, `google-vertex`, `gateway`. |
| `P1` | Runtime provider package. If Swift has a target, audit after P0 or when touched by upstream. If Swift has no target, track as missing provider surface. |
| `P2` | Docs, examples, framework-only packages, and integrations that are JS-specific or lower urgency for Swift runtime parity. |
| `P3` | Upstream tooling/internal packages that are usually not ported unless they affect tests, fixtures, or release process. |

## Status Values

| Status | Meaning |
| --- | --- |
| `unknown` | No owner or evidence has been established. |
| `mapped` | A Swift owner exists, but parity has not been proven for the current baseline. |
| `partial` | Some contracts are verified, but gaps or incomplete evidence remain. |
| `verified` | Audited against the pinned baseline with concrete source/test evidence. |
| `stale` | Previously audited, but the audited commit differs from the pinned baseline. |
| `drift` | A concrete upstream/Swift behavior mismatch is known. |
| `n/a` | Intentionally not ported or not applicable to Swift runtime parity. |

## Freshness Values

| Freshness | Meaning |
| --- | --- |
| `current` | Audited commit matches `upstream/UPSTREAM.md`. |
| `stale` | Tracking evidence exists but references an older commit. |
| `unknown` | No audited commit was found. |
| `n/a` | Component is not applicable to Swift runtime parity. |

## P0 Components

| Upstream package | Swift owner |
| --- | --- |
| `ai` | `Sources/SwiftAISDK` |
| `provider` | `Sources/AISDKProvider` |
| `provider-utils` | `Sources/AISDKProviderUtils` |
| `openai` | `Sources/OpenAIProvider` |
| `openai-compatible` | `Sources/OpenAICompatibleProvider` |
| `anthropic` | `Sources/AnthropicProvider` |
| `google` | `Sources/GoogleProvider` |
| `google-vertex` | `Sources/GoogleVertexProvider` |
| `gateway` | `Sources/GatewayProvider` |

## P1 Provider Components

These are upstream runtime provider packages that should be visible in the
component catalog even when Swift does not yet have an owner target:

- `alibaba`
- `amazon-bedrock`
- `anthropic`
- `anthropic-aws`
- `assemblyai`
- `azure`
- `baseten`
- `black-forest-labs`
- `bytedance`
- `cerebras`
- `cohere`
- `deepgram`
- `deepinfra`
- `deepseek`
- `elevenlabs`
- `fal`
- `fireworks`
- `gladia`
- `groq`
- `huggingface`
- `hume`
- `klingai`
- `lmnt`
- `luma`
- `mistral`
- `moonshotai`
- `open-responses`
- `perplexity`
- `prodia`
- `quiverai`
- `replicate`
- `revai`
- `togetherai`
- `vercel`
- `voyage`
- `xai`

## Non-Runtime Packages

These usually become `P2` or `P3` unless a task explicitly targets them:

- Framework/UI: `react`, `vue`, `svelte`, `angular`, `rsc`.
- Ecosystem adapters: `langchain`, `llamaindex`, `mcp`, `otel`, `valibot`.
- Tooling/internal: `codemod`, `devtools`, `harness*`, `policy-opa`, `sandbox-*`,
  `test-server`, `tui`, `workflow`, `workflow-harness`.
