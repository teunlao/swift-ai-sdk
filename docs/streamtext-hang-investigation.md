# StreamText Stream Hang Investigation (2025-10-17)

## Context
- Target tests: `StreamTextTextStreamBasic.sendsTextDeltas` and `StreamTextTextStreamBasic.filtersEmptyTextDeltas`.
- Goal: ensure every `StreamTextTests` case completes in << 1s; currently second test intermittently stalls for ~5s.
- Environment: `swift test --filter StreamTextTextStreamBasic` with explicit `timeout 10` wrapper.

## Reproduction
1. Warm build (`swift build`).
2. Run `timeout 10 swift test --filter StreamTextTextStreamBasic`.
3. Observe: first test (`sendsTextDeltas`) finishes in ~3ms, second test (`filtersEmptyTextDeltas`) prints normal chunk logs immediately but `collectText` completes only after the timeout task fires (≈5.33s).
4. Running `filtersEmptyTextDeltas` alone (`timeout 10 swift test --filter ...filtersEmptyTextDeltas`) completes in ≈8ms, proving the test case itself is fine when isolated.

## Instrumentation Added
- Added UUID-tagged debug logs to `withTimeout` helper to identify which timeout fires.
- Added detailed logs in `StitchableStreamController` pump path (enqueue, pump start/end, stream removal, yields, finish).
- Added logs in `DefaultStreamTextResult.processStreamChunk` for finish events (`finish stream enqueued`, `closeStream returned`, `finishProcessedStream finalize`).

## Key Findings
1. **Second run inherits prior stream state**: After the first test, the second test’s `collectText` logs the three outputs immediately. `processStreamChunk finish...` and `finish stream enqueued` fire right away, but the timeout only completes once the 5 s timer cancels the reader. This indicates the outer stream never signalled completion to the consumer, despite the inner pipeline finishing.
2. **`closeStream` returns instantly**: debug log shows `closeStream returned` well before timeout, so `StitchableStream` believes it closed, yet downstream consumer still awaits end-of-stream.
3. **`finishProcessedStream finalize` fires before hang**: the controller’s `finishProcessedStream finalize` log appears, so state promises (`finishReason`, `steps`) resolve promptly. Only the consumer loop waits.
4. **Instruments show pump stops too early**: with the verbose pump logging, when the second test runs, the pump enters the loop, dequeues the finish stream, drains it, and calls `finishIfPossible`. However, it exits without waking any blocked iterator—the `AsyncThrowingStream` returned by `teeBaseStream()` still waits for completion.
5. **Isolation works**: Running tests separately (different process) produces no hang, confirming the issue is cached state in the in-memory pipeline (`StitchableStream`/`teeBaseStream`) that persists across successive invocations in same process.

## Hypotheses
- `teeBaseStream()` feeds off a shared `AsyncThrowingStream` source; after the first consumer drains it and seals, the next invocation receives a branch that still has a pending buffered element (or lacks a final `finish`).
- `StitchableStream` close semantics differ from TypeScript: the Swift version may conclude the outer stream before the `finish` sentinel is forwarded, leaving branch streams waiting forever.
- The pump cancels when `queue` empties but does not propagate `finish` to existing branched streams obtained via `teeAsyncThrowingStream`.

## Next Steps
1. Instrument `teeAsyncThrowingStream` fan-out to log pending buffer and finish propagation; confirm whether branch stream receives `.finish` event.
2. Align `StitchableStream` semantics with upstream `ReadableStream`: ensure `close()` *enqueues* a synthetic stream that delivers `.finish` before terminating pump.
3. After adjustments, rerun `timeout 10 swift test --filter StreamTextTextStreamBasic` multiple times; target total runtime < 1s consistent.
4. Remove temporary debug logs before landing fix; keep only essential telemetry (if any) guarded for debugging builds.

## Execution Notes
- All test runs enforced `timeout` ≤10 s wrapping `swift test` to avoid indefinite waits as per project policy.
- Diagnostics logged under `[DBG timeout]`, `[DBG][Stitchable #…]`, `[DBG][aitxt-…]` for correlation.

