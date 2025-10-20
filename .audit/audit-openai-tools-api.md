# OpenAI Tools API Discrepancies

**Date**: 2025-10-20
**Status**: CRITICAL - Documentation does not match implementation
**Affected File**: `apps/docs/src/content/docs/providers/openai.mdx`

## Summary

During validation testing, we discovered that the OpenAI tools API signatures shown in the documentation do not match the actual Swift implementation. The documentation shows individual parameters being passed directly, while the actual API requires Args structs.

## Impact

**Severity**: HIGH
**User Impact**: Users copying code from documentation will encounter compilation errors

## Discrepancies Found

### 1. webSearch Tool

**Documentation (Lines ~310-316)**:
```swift
openai.tools.webSearch(
    searchContextSize: "high",
    userLocation: [
        "type": "approximate",
        "city": "San Francisco",
        "region": "California"
    ]
)
```

**Actual Swift API**:
```swift
openai.tools.webSearch(
    OpenAIWebSearchArgs(
        searchContextSize: "high",
        userLocation: OpenAIWebSearchArgs.UserLocation(
            city: "San Francisco",
            region: "California"
        )
    )
)
```

**Signature**: `func webSearch(_ args: OpenAIWebSearchArgs = .init()) -> Tool`
**File**: `Sources/OpenAIProvider/OpenAITools.swift:29`

---

### 2. fileSearch Tool

**Documentation (Lines ~329-342)**:
```swift
openai.tools.fileSearch(
    vectorStoreIds: ["vs_123"],
    maxNumResults: 5,
    filters: [
        "key": "author",
        "type": "eq",
        "value": "Jane Smith"
    ],
    ranking: [
        "ranker": "auto",
        "scoreThreshold": 0.5
    ]
)
```

**Actual Swift API**:
```swift
openai.tools.fileSearch(
    OpenAIFileSearchArgs(
        vectorStoreIds: ["vs_123"],
        maxNumResults: 5,
        ranking: OpenAIFileSearchArgs.RankingOptions(
            ranker: "auto",
            scoreThreshold: 0.5
        ),
        filters: .object([
            "key": .string("author"),
            "type": .string("eq"),
            "value": .string("Jane Smith")
        ])
    )
)
```

**Signature**: `func fileSearch(_ args: OpenAIFileSearchArgs) -> Tool`
**File**: `Sources/OpenAIProvider/OpenAITools.swift:14`
**Note**: `filters` parameter is `JSONValue?`, not a plain dictionary

---

### 3. imageGeneration Tool

**Documentation (Lines ~353-356 and ~423-427)**:
```swift
openai.tools.imageGeneration(outputFormat: "webp")

// or with quality
openai.tools.imageGeneration(
    outputFormat: "webp",
    quality: "low"
)
```

**Actual Swift API**:
```swift
openai.tools.imageGeneration(
    OpenAIImageGenerationArgs(
        outputFormat: "webp",
        quality: "low"
    )
)
```

**Signature**: `func imageGeneration(_ args: OpenAIImageGenerationArgs = .init()) -> Tool`
**File**: `Sources/OpenAIProvider/OpenAITools.swift:19`

---

### 4. codeInterpreter Tool

**Documentation (Lines ~462-468)**:
```swift
openai.tools.codeInterpreter(
    // optional configuration:
    container: [
        "fileIds": ["file-123", "file-456"]
    ]
)
```

**Actual Swift API**:
```swift
openai.tools.codeInterpreter(
    OpenAICodeInterpreterArgs(
        container: .auto(fileIds: ["file-123", "file-456"])
    )
)
```

**Signature**: `func codeInterpreter(_ args: OpenAICodeInterpreterArgs = .init()) -> Tool`
**File**: `Sources/OpenAIProvider/OpenAITools.swift:9`
**Note**: `container` is an enum `OpenAICodeInterpreterContainer` with cases `.string(String)` and `.auto(fileIds: [String]?)`

---

### 5. localShell Tool

**Documentation (Lines ~494-499)**:
```swift
openai.tools.localShell(
    execute: { action in
        // ... your implementation, e.g. sandbox access ...
        return ["output": stdout]
    }
)
```

**Actual Swift API**:
```swift
openai.tools.localShell()
```

**Signature**: `func localShell() -> Tool`
**File**: `Sources/OpenAIProvider/OpenAITools.swift:24`
**Note**: The tool takes NO parameters. The execute logic is internal to the tool implementation.

---

## Validation Status

✅ **Validation Tests Created**: 5 tests covering all tool APIs
✅ **Tests Pass**: Using actual Swift API implementation
❌ **Documentation Incorrect**: All 5 tools have wrong signatures in docs

**Test File**: `examples/Sources/ProviderValidation-OpenAI/main.swift`
**Tests**: Lines 305-399 (tests 14-18)

## Recommended Actions

1. **Update Documentation** (HIGH PRIORITY):
   - Fix all 5 tool examples in `openai.mdx` to use Args structs
   - Add examples showing Args struct construction
   - Document nested types (UserLocation, RankingOptions, etc.)

2. **Consider API Design**:
   - Current design requires explicit Args structs
   - Could add convenience overloads with individual parameters
   - Or document why Args approach is preferred

3. **Add Documentation Tests**:
   - Integrate validation tests into CI/CD
   - Ensure all code examples compile before publishing

## Related Files

- Documentation: `apps/docs/src/content/docs/providers/openai.mdx`
- Implementation: `Sources/OpenAIProvider/OpenAITools.swift`
- Validation: `examples/Sources/ProviderValidation-OpenAI/main.swift`
- Tool Definitions:
  - `Sources/OpenAIProvider/Tool/OpenAIWebSearchTool.swift`
  - `Sources/OpenAIProvider/Tool/OpenAIFileSearchTool.swift`
  - `Sources/OpenAIProvider/Tool/OpenAIImageGenerationTool.swift`
  - `Sources/OpenAIProvider/Tool/OpenAICodeInterpreterTool.swift`
  - `Sources/OpenAIProvider/Tool/OpenAILocalShellTool.swift`

## References

- Previous fixes: Commit `61a4a88` fixed 21 missing `modelId:` labels
- Validation framework: Commit `02b780d` added provider validation
- Current validation: 27 tests, 25 passing, 2 skipped (API required)
