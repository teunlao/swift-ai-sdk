# StreamTextV2 Port Progress (October 18, 2025)

This document tracks the Swift port of `packages/ai/src/generate-text/stream-text.ts` from Vercel AI SDK and highlights what is implemented versus what remains.

## Completed
- **Stream runtime**  
  - `StreamTextV2.swift` – public API (`streamTextV2` overloads, `DefaultStreamTextV2Result` accessors, `consumeStream`, `pipeTextStreamToResponse`, `toTextStreamResponse`).  
  - Added top-level response helpers: `streamTextV2AsResponse`, `pipeStreamTextV2ToResponse` for parity with upstream fetch/response ergonomics.
  - Stream actor now owns approval flow: pending client tool calls are queued inside `StreamTextV2Actor`, synchronous callbacks resolve approvals before `finishStep`, and the built-in resolver can execute tools or emit approval requests without an extra transform layer.
  - `StreamTextV2Actor.swift` – core actor handling provider streams, multi-step logic, stop/abort flow, tool handling, usage aggregation.  
    - Step result aggregation now mirrors upstream (text/reasoning/tool/file/source) and feeds ResponseMessage history for parity.
    - Multi-step continuation honours finishReason `tool-calls`, stop conditions, and rebuilds prompts from conversation + tool outputs.
    - Tool call/result events emit static vs dynamic variants (with JSON parsing fallback + invalid tagging) ready for ToolSet-aware flow. Tools now propagate from API surface to transforms/tests.
  - `StreamTextV2EventRecorder.swift` – diagnostic recorder for tests (replay, counters, ordering checks).
- **Event & SSE utilities**  
  - `StreamTextV2Events.swift` – high-level event stream (`StreamTextV2Event`) and summariser (`summarizeStreamTextV2Events`).  
  - `StreamTextV2SSE.swift` – SSE encoder mirroring upstream `stream-text.ts` output.  
  - Tool events supported in both: `tool-error`, `tool-approval-request`, `tool-output-denied`.
- **Logging helpers**  
  - `StreamTextV2Logging.swift` – text log stream (`StreamTextV2LogOptions`, `makeStreamTextV2LogStream`, `logStreamTextV2Events`).
  - Logs now include tool events (error/approval/denied).
- **Test coverage**  
  - `StreamTextV2Tests.swift` (basic scenarios).  
  - `StreamTextV2ConcurrencyTests.swift`, `StreamTextV2ErrorAndReplayTests.swift`, `StreamTextV2EventsTests.swift`, `StreamTextV2SSEEncodingTests.swift`, `StreamTextV2LoggingTests.swift`.

## Remaining Work
- **HTTP/Fetch wrappers**  
  - If required, port fetch-style entry points (`fetchText`, etc.) to wrap V2, mapping to our response helpers. This is optional if consumers call the Swift helpers directly.
- **UI response builders**  
  - Upstream exposes `createStreamTextResponse`, `streamTextToUI`, etc., which still rely on V1 plumbing. Validate V2 code paths and ensure wrappers delegate to `StreamTextV2`.
- **Transforms & tools integration**  
  - Extend approval flow to support end-to-end execution (post-approval tool run), align with V1 `RunToolsTransformation` semantics. Add conditional opt-out if needed.
- **Telemetry & logging integration**  
  - Align V2 telemetry with upstream (spans, attributes, onError). Ensure `StreamTextV2Logging` is hooked into telemetry where appropriate.
- **Advanced SSE features**  
  - Evaluate need for event type parity such as `response-metadata`, `raw`, or provider-specific payloads beyond the minimal subset currently encoded.
- **Documentation & samples**  
  - Update public docs to reference the new V2 helpers and ensure playground / CLI commands demonstrate them.
- **Upstream drift audit**  
  - Reconcile against the latest upstream commit (`packages/ai/src/generate-text/stream-text.ts`) to double-check there are no newly introduced branches (e.g., streaming tool approval prompts, new event kinds).

## Next Steps
1. Expand actor-managed approval flow to support full post-approval tool execution parity (multiple pending approvals, conditional policies, etc.).
2. Port fetch/response helpers so V2 can be consumed via `fetchStreamText`.
3. Expand integration tests to cover approval flows and tool result propagation end-to-end (по одному тесту за итерацию).
4. Document public API changes and migrate playground examples to the V2 surface.

> Last updated: October 18, 2025 (later, approval-transform integration).
