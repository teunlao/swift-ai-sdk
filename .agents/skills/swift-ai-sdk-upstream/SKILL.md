---
name: swift-ai-sdk-upstream
description: "Use when porting Vercel AI SDK upstream changes into the Swift port: reading upstream at a commit, comparing a package with its Swift target, porting behavior with boundary tests, moving the pin."
---

# Porting upstream into Swift

The goal is behavioral parity with `vercel/ai`: request shape, response and stream parsing, errors, options, defaults, callback order. Names and types follow Swift idiom; TypeScript layout is not copied.

## Reading upstream

`external/vercel-ai-sdk` is a read-only clone. Never check it out or edit it; read a commit directly:

```bash
U=external/vercel-ai-sdk
git -C $U show <sha>:packages/<pkg>/src/<file>
git -C $U ls-tree -r --name-only <sha> packages/<pkg>/src
git -C $U diff <from>..<to> -- packages/<pkg>/src
git -C $U log --no-merges --oneline <from>..<to> -- packages/<pkg>/src
```

A commit missing from the clone is fetched with `git -C $U fetch origin <sha>`.

## Porting a package

1. Read upstream's exported surface (`src/index.ts`) and the implementation behind it at the target commit.
2. Read the Swift target that owns it (`Sources/AISDKProvider`, `AISDKProviderUtils`, `SwiftAISDK`, `<Name>Provider`).
3. Port every observable difference at its owner. Skip upstream code serving only JS frameworks, workflow, harness or code mode.
4. Test the boundary each change moves: the HTTP request, the parsed response, the stream order, the thrown error. Fixtures live in `Tests/**/Fixtures`; nothing in `Sources` or `Tests` reads `external/`.
5. Run the target's tests, then `swift test --num-workers 3` before handing off.

## Where the record lives

The Tagma graph: the task carries what was ported and skipped, a `#note` on the Swift code records a deliberate departure from upstream and its reason. `upstream/UPSTREAM.md` holds only the pinned commit; it moves when a whole refresh lands.
