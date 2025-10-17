# StreamTextV2 — Implementation Plan

Goal: Rebuild `streamText` from scratch as `StreamTextV2` with 1:1 upstream parity (TypeScript `stream-text.ts`) while eliminating race conditions and flakiness seen in the current Swift port. Work in 6–8 small, verifiable milestones, each landing code plus a matching focused test file `StreamTextV2Tests` (added incrementally by the executor flow).

Status: Design-only — no code gated yet. Old `StreamText` remains untouched until V2 reaches feature-parity. A feature flag will later switch default to V2.

## Design Principles (Race-Free)

- Single owner for pipeline state: one dedicated actor (`StreamTextV2Actor`) mediates all state transitions and output. No shared mutable state outside the actor.
- Deterministic event ordering: the actor processes provider parts strictly FIFO and pushes derived parts to a fan-out broadcaster with idempotent finish.
- Idempotent termination: exactly one terminal path; cancellations/errors funnel through the actor, which decides how to finish streams. No finish() inside onTermination callbacks.
- Lazy, replayable subscribers: consumers subscribe to pre-buffered, replay-capable streams (broadcaster), so late subscribers receive the history before terminal.
- Backpressure-safe: producer reads from provider stream in one task; consumers never write back into producer pathways.
- Small surface per step: each milestone adds a thin vertical slice (code + tests) to keep regressions local and observable.

## Public API (V2)

- New entrypoint: `streamTextV2<T, P>(...) -> DefaultStreamTextV2Result<T, P>` with the same public parameters as upstream (`stream-text.ts`) and the current V1, keeping naming consistent but namespaced to V2 types.
- Result mirrors V1 surface (text, content, usage, finishReason, etc.) but implemented on top of the V2 pipeline. After parity is achieved, a feature flag will alias `streamText = streamTextV2`.

## Concurrency Architecture

- `StreamTextV2Actor` (actor)
  - Owns pipeline state machine and derived streams.
  - Bridges provider `LanguageModelV3StreamResult.stream` → `EnrichedStreamPart` → `TextStreamPart`/UI chunks.
  - Emits to `AsyncStreamBroadcaster`-V2 (or reuse existing with verified idempotent finish semantics).
- Single producer task:
  - Reads provider parts; maps to internal parts; updates state; emits to broadcasters.
  - Handles errors/cancel; decides terminal reason and emits final events once.
- Consumers:
  - `textStream`, `fullStream`, `experimentalPartialOutputStream`, `toUIMessageStream`, and piping to responses are derived readers from broadcasters. No writes.

## State Machine (simplified)

States: `idle → started → inTextBlock? → inToolBlock? → finishing → finished`

Transitions:
- on `stream-start`: `idle → started`
- on `text-start/delta/end`: within `inTextBlock` sub-state; accumulate text and emit deltas
- on tool input/call/result: within tool sub-state; emit appropriate chunks
- on `finish`: record usage/metadata; `→ finishing`
- terminal: actor emits `.finish`/promises resolution once and moves to `finished`

All transitions happen inside the actor; any external cancellation requests are sent as messages to the actor, which resolves to one terminal path.

## Milestones (6–8 tasks)

### 1) Skeleton + Minimal Text Deltas
Scope:
- Define `DefaultStreamTextV2Result<T, P>` and public `streamTextV2(...)` signature (parity with V1, parameters pass-through, but only `prompt` and `model` initially needed).
- Add `StreamTextV2Actor` with minimal state and `textStream` only.
- Ingest provider stream parts: support only `stream-start`, `response-metadata`, `text-start`, `text-delta`, `text-end`, `finish`.
- Implement idempotent finish path and subscriber broadcaster.
Deliverables:
- Sources/SwiftAISDK/GenerateTextV2/* (new folder)
- `textStream` returns raw deltas in order and finishes deterministically.
Tests:
- StreamTextV2Tests: “textStream yields raw deltas in order”.
- Double-subscribe replay test: both subscribers see identical deltas and clean finish.

### 2) Full Text Pipeline + Step Framing
Scope:
- Expose `fullStream` with `TextStreamPart` equivalents: `textStart`, `textDelta`, `textEnd`, `startStep`, `finishStep`, `start`, `finish`.
- Introduce step framing (single step default) and `stopWhen: [stepCountIs(1)]` handling for the trivial case.
- Ensure `fullStream` emits framing chunks before/after text and terminates once.
Deliverables:
- `fullStream` parity for basic case.
Tests:
- “fullStream emits: start → startStep → textStart → deltas → textEnd → finishStep → finish”.

### 3) Final Step Resolution + Promises
Scope:
- Implement `finalStep` resolution, `text`, `content`, `reasoning` accessors, `usage`, `finishReason`, `steps`, `providerMetadata`, `request/response` promises.
- Aggregate text across deltas inside actor; set `finishReason` from provider `finish`.
- Wire `totalUsage` (equal to usage for single-step baseline).
Deliverables:
- Promise holders (DelayedPromise equivalents) in V2; resolution only from actor’s terminal path.
Tests:
- Accessors return expected values after completion; no deadlocks when awaited.

### 4) Transforms (experimentalTransform) — Safe Boundary
Scope:
- Implement transform pipeline as pure functions applied to the internal stream, executed inside the actor but isolated from state mutation (map/tee pattern).
- Guarantee ordering and once-only application. Protect against transforms calling back into result.
Deliverables:
- `experimentalTransform` parity for text-only flows.
Tests:
- “single transform maps deltas”; “multiple transforms kept in order”; cancellation of consumer doesn’t break producer.

### 5) Tools Streaming (Input/Calls/Results)
Scope:
- Support tool input start/delta/end, tool calls, tool results/errors; enrich to `UIMessageChunk`/`StepResult` as upstream.
- Actor tracks tool name resolution and dynamic flags deterministically.
Deliverables:
- Tool-related parts emitted on both `fullStream` and `toUIMessageStream`.
Tests:
- “toolInputStart/delta/end surfaced in order”; “tool call/result converted correctly; dynamic flags consistent”.

### 6) Multi-Step + Stop Conditions
Scope:
- Implement generic `stopWhen` (step count, finish reasons, custom predicate) with clear evaluation points inside actor.
- Support multiple steps framing and accumulation of `steps` array.
Deliverables:
- Multi-step execution with deterministic frame boundaries and final aggregation.
Tests:
- “two steps stop at stepCountIs(2)”; “custom stop predicate halts at expected point”.

### 7) Telemetry, Warnings, Metadata
Scope:
- Integrate telemetry (`getTracer()`), `stringifyForTelemetry(prompt)`, request/response headers, warnings feed.
- Log warnings early from the actor (before consumers subscribe) via a thread-safe multi-observer.
Deliverables:
- Telemetry hooks: attributes set at start, updated at finish; warnings surfaced.
Tests:
- “warnings are logged once with correct values”; “metadata present on start/finish”.

### 8) Response Piping + Feature Flag + Migration
Scope:
- Implement `pipeTextStreamToResponse`, `toUIMessageStream`, and `pipeUIMessageStreamToResponse` built on V2 streams.
- Add internal feature flag (`StreamTextInternalOptions.version = 2` or env var) and wiring so we can toggle V2 in place of V1.
- Documentation + deprecation note for V1 once parity passes.
Deliverables:
- Drop‑in V2 usage path; clean migration plan.
Tests:
- Writer piping tests: correct SSE framing and order; finish semantics consistent.

## Test Discipline (Executor Workflow)

- Add tests one-by-one per milestone, each time running the project’s smart test runner externally (>1 run) to check for flakiness.
- Keep each V2 test focused and sub-100ms; avoid time-based sleeps; use actor-await points instead.
- Use replay subscribers to validate late-subscription behavior and ensure broadcaster delivers terminal events deterministically.

## Risk Register and Mitigations

- Re-entrancy via onTermination → cancel loops: avoided by making the actor the sole finisher; onTermination never calls finish; we only cancel producer on explicit consumer cancellation.
- Shared mutable state: none outside the actor; broadcasters only receive immutable values.
- Late subscribers missing history: broadcaster guarantees replay of the buffer before terminal.
- Transform side-effects: transforms run as pure maps; no state writes from transforms.
- Deadlocks on accessors: all promises resolved only from the actor’s single terminal path.

## Deliverables Summary

- New module folder: `Sources/SwiftAISDK/GenerateTextV2/` containing:
  - `StreamTextV2.swift` (public API + result type)
  - `StreamTextV2Actor.swift` (pipeline state machine)
  - `TextStreamPartsV2.swift`, `EnrichedPartV2.swift` (internal parts)
  - `BroadcasterV2.swift` (if needed; otherwise reuse existing `AsyncStreamBroadcaster`)
  - `TransformsV2.swift`, `ToolsV2.swift`, etc. as milestones progress
- Tests: `Tests/SwiftAISDKTests/GenerateTextV2/StreamTextV2Tests.swift` (added incrementally per milestone)
- Feature flag switch and migration doc once parity achieved.

## Acceptance Criteria (Overall)

- 1:1 API and behavior with upstream `stream-text.ts`.
- Zero observed race timeouts across 10× runs with 10s cap, warm build.
- All V2 tests pass; V1 tests remain unaffected until we flip the feature flag.

