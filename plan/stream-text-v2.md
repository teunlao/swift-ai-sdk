# StreamText — Implementation Plan

Goal: Rebuild `streamText` from scratch as `StreamText` with 1:1 upstream parity (TypeScript `stream-text.ts`) while eliminating race conditions and flakiness seen in the current Swift port. Work in 6–8 small, verifiable milestones, each landing code plus a matching focused test file `StreamTextTests` (added incrementally by the executor flow).

Status: Design-only — no code gated yet. Old `StreamText` remains untouched until V2 reaches feature-parity. A feature flag will later switch default to V2.

## Design Principles (Race-Free)

- Single owner for pipeline state: one dedicated actor (`StreamTextActor`) mediates all state transitions and output. No shared mutable state outside the actor.
- Deterministic event ordering: the actor processes provider parts strictly FIFO and pushes derived parts to a fan-out broadcaster with idempotent finish.
- Idempotent termination: exactly one terminal path; cancellations/errors funnel through the actor, which decides how to finish streams. No finish() inside onTermination callbacks.
- Lazy, replayable subscribers: consumers subscribe to pre-buffered, replay-capable streams (broadcaster), so late subscribers receive the history before terminal.
- Backpressure-safe: producer reads from provider stream in one task; consumers never write back into producer pathways.
- Small surface per step: each milestone adds a thin vertical slice (code + tests) to keep regressions local and observable.

## Public API (V2)

- New entrypoint: `streamText<T, P>(...) -> DefaultStreamTextResult<T, P>` with the same public parameters as upstream (`stream-text.ts`) and the current V1, keeping naming consistent but namespaced to V2 types.
- Result mirrors V1 surface (text, content, usage, finishReason, etc.) but implemented on top of the V2 pipeline. After parity is achieved, a feature flag will alias `streamText = streamText`.

## Concurrency Architecture

- `StreamTextActor` (actor)
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
- Define `DefaultStreamTextResult<T, P>` and public `streamText(...)` signature (parity with V1, parameters pass-through, but only `prompt` and `model` initially needed).
- Add `StreamTextActor` with minimal state and `textStream` only.
- Ingest provider stream parts: support only `stream-start`, `response-metadata`, `text-start`, `text-delta`, `text-end`, `finish`.
- Implement idempotent finish path and subscriber broadcaster.
Deliverables:
- Sources/SwiftAISDK/GenerateTextV2/* (new folder)
- `textStream` returns raw deltas in order and finishes deterministically.
Tests:
- StreamTextTests: “textStream yields raw deltas in order”.
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
  - `StreamText.swift` (public API + result type)
  - `StreamTextActor.swift` (pipeline state machine)
  - `TextStreamPartsV2.swift`, `EnrichedPartV2.swift` (internal parts)
  - `BroadcasterV2.swift` (if needed; otherwise reuse existing `AsyncStreamBroadcaster`)
  - `TransformsV2.swift`, `ToolsV2.swift`, etc. as milestones progress
- Tests: `Tests/SwiftAISDKTests/GenerateTextV2/StreamTextTests.swift` (added incrementally per milestone)
- Feature flag switch and migration doc once parity achieved.

## Acceptance Criteria (Overall)

- 1:1 API and behavior with upstream `stream-text.ts`.
- Zero observed race timeouts across 10× runs with 10s cap, warm build.
- All V2 tests pass; V1 tests remain unaffected until we flip the feature flag.

---

## Immediate Next Actions (Concrete TODO)

This section turns open items into precise code tasks with file paths and expected effects. Each item lands with exactly one small test (executor adds), and must not regress previous tests.

1) Emit final `.finish` for the whole session (not just `finishStep`).
- Why: Upstream emits a terminal `finish(TextStreamPart)` after the last step; some ordering tests expect it.
- Where: `Sources/SwiftAISDK/GenerateTextV2/StreamTextActor.swift`
  - In `finishAll(...)` before finishing broadcasters, send `fullBroadcaster.send(.finish(totalUsage: accumulatedUsage, providerMetadata: nil))` (shape from V1/Vercel upstream).
  - Ensure this executes only once (guarded by `terminated`).
- Tests: Extend “fullStream emits framing and text events in order (V2)” to assert the last chunk is `.finish` (executor adds/updates single test only).

2) Move `start`/`startStep` emission after provider `.streamStart(warnings)` so `startStep.warnings` is populated.
- Where: `consumeProviderStream(..., emitStartStep: Bool)`.
  - Current: emits `.start` + `.startStep(..., warnings: [])` before the loop.
  - Target: buffer until the first `.streamStart(warnings)` and then emit:
    - `.start` (once per session) → `.startStep(request: recordedRequest, warnings: capturedWarnings)`.
  - Edge case: If provider never sends `.streamStart`, still emit `.start`/`.startStep` with empty warnings on first content part.
- Tests: “startStep carries warnings”; use synthetic stream that sends `streamStart([warning])` before text.

3) Keep frame order strict on `.finish(finishReason, usage, providerMetadata)` from provider.
- Where: same method as (2).
  - Ensure `.textEnd` is sent for all open text IDs before `.finishStep`.
  - Immediately after `.finishStep`, update `recordedSteps`, `accumulatedUsage`, and resolve `finishReasonPromise`.
  - Do not finish broadcasters here; let `finishAll` emit terminal `.finish` once the multi‑step loop decides to stop.

4) Aggregate `totalUsage` across steps and resolve once at session end.
- Where: `finishAll(...)` in the actor.
  - Already resolves `totalUsagePromise` with `accumulatedUsage`. Keep this behavior.
  - Ensure `run()` calls `finishAll(...)` exactly once after step loop terminates.

5) UI stream error mapping cleanup.
- Where: `Sources/SwiftAISDK/GenerateTextV2/StreamText.swift` in `toUIMessageStream(...)`.
  - Remove the unused-result warning by directly returning `mapErrorMessage(error)` in `onError:` closure (already done) and keep it as is; no functional change needed beyond confirming.

6) Multi‑step prompt continuity (basic text-only path).
- Where: `run()` after first `consumeProviderStream`.
  - Already builds `responseMessages → nextMessages → LanguageModelV3Prompt` and calls `model.doStream` again.
  - Add TODO markers for future tool/media support; for now ensure next iteration’s `setInitialRequest(...)` is called and subsequent `consumeProviderStream(..., emitStartStep: true)` produces a new `startStep` framing.

7) Cancellation and idempotent finish.
- Where: `ensureStarted()`/`finishAll(...)`.
  - Keep `terminated` guard; add a comment that cancellation paths must call `finishAll` and never finish broadcasters directly elsewhere.
  - Verify `onTerminate` is invoked exactly once and then nulled.

8) Telemetry/warnings logging hook (scaffold).
- Where: V2 actor `run()` and when emitting `start`/`finish`.
  - Add scaffolding comments for integrating `getTracer()` and `logWarnings` later (Milestone 7). No-op for now to avoid scope creep.

---

## Event Contract Reference (Upstream Parity)

For a single-step, text-only generation the expected `fullStream` order:
- `.start`
- `.startStep(request, warnings)`
- `.textStart(id)`
- `.textDelta(id, "...")` × N
- `.textEnd(id)`
- `.finishStep(response, usage, finishReason)`
- `.finish(totalUsage)`

For 2 steps (stopWhen(stepCountIs(2))):
- Step 1: same framing as above through `.finishStep`
- Step 2: same framing as above through `.finishStep`
- Session terminal: `.finish(totalUsage = usage1 + usage2)`

Notes:
- `.start` is session-wide and emitted once.
- `.finish` is session-wide and emitted once, after the last `.finishStep`.
- Warnings belong to `.startStep.warnings` for each step based on the immediately preceding provider `.streamStart`.

---

## Test Roadmap (Incremental, one test per step)

Order to add tests (each added only after the previous is stable across 5–10 runs):
1) textStream raw deltas (done).
2) fullStream framing order with final `.finish` (update existing V2 order test).
3) startStep carries warnings from `.streamStart`.
4) two steps with `stopWhen(stepCountIs(2))`, correct `.finish(totalUsage)`.
5) UI message stream: onFinish invoked once with correct flags (no continuation, no abort) and injected messageId when provided.
6) Transform: single uppercasing transform; ensure ordering and once-only application.
7) Late subscriber replay: both subscribers see identical history including terminal `.finish`.
8) Cancellation: cancelling consumer doesn’t deadlock producer; actor emits terminal exactly once.

Each test must target ≤100ms runtime and avoid sleeps; simulate provider events deterministically.

---

## Invariants & Guards (Checklist)

- Single terminal path guarded by `terminated` flag.
- Broadcasters: send history before terminal to new subscribers; terminal is idempotent.
- No `.startStep` with empty warnings if provider sends `.streamStart(warnings)` first.
- On provider `.finish`: close any open text spans before `.finishStep`.
- `finishAll` is the only place that calls `.finish` on broadcasters and resolves `totalUsagePromise`/`stepsPromise`.

---

## Mapping Gaps (To be addressed by later milestones)

- Reasoning/files/sources/tool streaming content → UI chunks parity (Milestones 5–7).
- Full telemetry: `stringifyForTelemetry`, request/response headers, log warnings once (Milestone 7).
- Prompt conversion with downloads/supportedUrls for rich content (beyond plain text).

