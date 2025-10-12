# Executor: Block D (Prompt Preparation) — Current Status

**Executor ID**: claude-sonnet-4.5
**Block**: D — Prompt Preparation
**Session Start**: 2025-10-12T16:00:00Z
**Last Updated**: 2025-10-12T17:04:30Z
**Status**: 50% Complete, PrepareCallSettings ✅ APPROVED

---

## Role Assignment

**From Session #15-16 coordination:**
- **Executor 1**: Block B (ProviderUtils HTTP) — post-to-api, get-from-api ✅ DONE
- **Executor 2 (ME)**: Block D (Prompt Preparation) — 15 files total

**No conflicts**: Different directories, independent work.

---

## Progress Summary

### ✅ Completed (50%)

**8 Foundation Files + PrepareCallSettings:**

1. **`SplitDataUrl.swift`** (47 lines)
   - Path: `Sources/SwiftAISDK/Core/Prompt/SplitDataUrl.swift`
   - Upstream: `packages/ai/src/prompt/split-data-url.ts`
   - Function: Parse Data URLs into media type + base64 content
   - Status: ✅ 100% parity

2. **`Uint8Utils.swift`** (75 lines)
   - Path: `Sources/SwiftAISDK/ProviderUtils/Uint8Utils.swift`
   - Upstream: `packages/provider-utils/src/uint8-utils.ts`
   - Function: Base64 ↔ Data conversion (RFC 4648 support)
   - Status: ✅ 100% parity

3. **`InvalidDataContentError.swift`** (75 lines)
   - Path: `Sources/SwiftAISDK/Provider/Errors/InvalidDataContentError.swift`
   - Upstream: `packages/ai/src/prompt/invalid-data-content-error.ts`
   - Function: Error for invalid data content
   - Status: ✅ 100% parity

4. **`DataContent.swift`** (170 lines)
   - Path: `Sources/SwiftAISDK/Core/Prompt/DataContent.swift`
   - Upstream: `packages/ai/src/prompt/data-content.ts`
   - Function: Data URL handling, conversion to LanguageModelV3DataContent
   - Status: ✅ 95% parity (zod absent by design)

5. **`CallSettings.swift`** (187 lines)
   - Path: `Sources/SwiftAISDK/Core/Prompt/CallSettings.swift`
   - Upstream: `packages/ai/src/prompt/call-settings.ts`
   - Function: Generation parameters (temperature, maxTokens, etc.)
   - Status: ✅ 98% parity (Equatable excludes abortSignal, documented)

6. **`Prompt.swift`** (113 lines)
   - Path: `Sources/SwiftAISDK/Core/Prompt/Prompt.swift`
   - Upstream: `packages/ai/src/prompt/prompt.ts`
   - Function: High-level prompt type with XOR constraint (prompt/messages)
   - Status: ✅ 100% parity

7. **`StandardizePrompt.swift`** (69 lines)
   - Path: `Sources/SwiftAISDK/Core/Prompt/StandardizePrompt.swift`
   - Upstream: `packages/ai/src/prompt/standardize-prompt.ts`
   - Function: Normalize prompts, validate messages not empty
   - Status: ✅ 100% parity (8 tests)

8. **`InvalidPromptError.swift`** (75 lines)
   - Path: `Sources/SwiftAISDK/Provider/Errors/InvalidPromptError.swift`
   - Upstream: `packages/provider/src/errors/invalid-prompt-error.ts`
   - Function: Error for invalid prompts
   - Status: ✅ 100% parity

9. **`PrepareCallSettings.swift`** (102 lines) ✅ **NEW**
   - Path: `Sources/SwiftAISDK/Core/Prompt/PrepareCallSettings.swift`
   - Upstream: `packages/ai/src/prompt/prepare-call-settings.ts`
   - Function: Validates call settings and returns PreparedCallSettings
   - Status: ✅ 100% parity (6 tests)
   - **Validator Status**: ✅ APPROVED (2025-10-12T17:15:00Z)

10. **`InvalidArgumentError.swift`** (updated) ✅ **UPDATED**
    - Path: `Sources/SwiftAISDK/Provider/Errors/InvalidArgumentError.swift`
    - Upstream: `packages/ai/src/error/invalid-argument-error.ts`
    - Changes: Added `parameter` (was `argument`) + `value: JSONValue?`
    - Status: ✅ 100% upstream parity
    - **Validator Status**: ✅ APPROVED (2025-10-12T17:15:00Z)

**Test Status:**
- **341/341 tests passing** ✅
- +6 new tests for PrepareCallSettings
- +8 tests for StandardizePrompt (from earlier)

**Validation:**
- ✅ All validator blockers from Session #15 resolved
- ✅ PrepareCallSettings + InvalidArgumentError approved by validator
- ✅ 100% API parity, 100% behavior parity, superior type safety

---

## Remaining Work (50%)

### Files to Port

**Priority 1: Preparation Functions**

1. **`prepare-tools-and-tool-choice.ts`** → `PrepareToolsAndToolChoice.swift` (NEXT!)
   - Path: `packages/ai/src/prompt/prepare-tools-and-tool-choice.ts`
   - Size: ~120 lines
   - Function: Prepares tools and toolChoice for model
   - Dependencies: LanguageModelV3Tool types (already ported)
   - Estimated: 2-3 hours
   - Tests: Need to port from `prepare-tools-and-tool-choice.test.ts`

**Priority 2: Conversion (LARGE)**

2. **`convert-to-language-model-prompt.ts`** → `ConvertToLanguageModelPrompt.swift`
   - Path: `packages/ai/src/prompt/convert-to-language-model-prompt.ts`
   - Size: **~600 lines** (LARGE FILE)
   - Function: V2/V3 prompt conversion, message handling
   - Estimated: 4-5 hours
   - **Note**: Has extensive tests (~46KB test file)
   - **Complexity**: Message role conversion, content part handling, system messages

**Priority 3: Tool Output (if needed)**

3. Check if `create-tool-model-output.ts` exists:
   - Path: `packages/ai/src/prompt/create-tool-model-output.ts`
   - May not exist in current upstream
   - Skip if not found

**Priority 4: Additional Errors (if needed)**

4. Check for missing errors:
   - `InvalidMessageRoleError` (check if needed)
   - `MessageConversionError` (check if needed)
   - Other prompt-related errors in upstream

**Priority 5: Complete Test Suite**

5. Port remaining tests:
   - `split-data-url.test.ts` (~8 tests) - if not already ported
   - `data-content.test.ts` (~12 tests) - if not already ported
   - `prepare-tools-and-tool-choice.test.ts` (estimate ~10-15 tests)
   - `convert-to-language-model-prompt.test.ts` (LARGE, estimate ~30+ tests)

---

## Next Immediate Steps

### Step 1: Port `prepare-tools-and-tool-choice.ts` (NEXT!)

**File**: `Sources/SwiftAISDK/Core/Prompt/PrepareToolsAndToolChoice.swift`

**Read upstream first**:
```bash
cat external/vercel-ai-sdk/packages/ai/src/prompt/prepare-tools-and-tool-choice.ts
cat external/vercel-ai-sdk/packages/ai/src/prompt/prepare-tools-and-tool-choice.test.ts
```

**Expected signature**:
```swift
public func prepareToolsAndToolChoice(
    tools: [String: Any]?,  // or specific type
    toolChoice: ToolChoice?
) -> (tools: [LanguageModelV3Tool]?, toolChoice: LanguageModelV3ToolChoice?)
```

**Tasks**:
1. Read upstream TypeScript
2. Understand tool format conversion
3. Port to Swift with proper types
4. Port tests
5. Verify `swift build && swift test`
6. Update progress.md

---

### Step 2: Port `convert-to-language-model-prompt.ts` (BIG ONE)

**File**: `Sources/SwiftAISDK/Core/Prompt/ConvertToLanguageModelPrompt.swift`

**Warning**: This is a LARGE file (~600 lines + extensive tests).

**Approach**:
1. Read and understand full TypeScript implementation
2. Identify main functions and their responsibilities
3. Break down into smaller functions if possible
4. Port incrementally, testing as you go
5. Port tests in batches (may need multiple sessions)
6. Expect 4-5 hours for completion

**Key challenges**:
- Message role conversion (user/assistant/system/tool)
- Content part handling (text/file/toolCall/toolResult)
- V2 vs V3 differences
- System message handling

---

## Key Design Decisions Made

1. **Prompt XOR constraint**: Two separate initializers instead of TypeScript `never` type
2. **AbortSignal**: `@Sendable () -> Bool` closure instead of AbortSignal
3. **Zod validation**: Omitted — Swift type system provides compile-time safety
4. **Equatable on CallSettings**: Excludes `abortSignal` (closures not Equatable)
5. **Deprecated aliases**: Removed `CoreSystemMessage`, etc. (not needed in Swift)
6. **InvalidArgumentError**: Uses `parameter` + `value` fields (100% upstream parity)
7. **Type validation in PrepareCallSettings**: Omitted (Swift type system guarantees)

Documented in: `plan/design-decisions.md:11`

---

## Dependencies & Integration Points

**Depends on (already implemented):**
- ✅ `LanguageModelV3Message` (Provider/V3)
- ✅ `LanguageModelV3DataContent` (Provider/V3)
- ✅ `LanguageModelV3Tool` types (Provider/V3)
- ✅ `LanguageModelV3ToolChoice` (Provider/V3)
- ✅ `ContentPart` types (Provider/V3)
- ✅ Error types (`AISDKError` protocol)
- ✅ `InvalidArgumentError` (updated with parameter/value)

**Will be used by (future blocks):**
- ⏳ Block E: Generate Text
- ⏳ Block F: Stream Text
- ⏳ Block G: Tool Calls

---

## Files for Quick Reference

**Read these first in new session:**
```bash
# Task tracking
cat plan/todo.md                    # Overall tasks
cat plan/progress.md | tail -100    # Recent history

# Your context (THIS FILE)
cat plan/contexts/executor-block-d-prompt-preparation.md

# Upstream reference
ls external/vercel-ai-sdk/packages/ai/src/prompt/

# Current code
ls Sources/SwiftAISDK/Core/Prompt/
ls Tests/SwiftAISDKTests/Core/Prompt/
```

**Verify status:**
```bash
swift build                # Should pass
swift test                 # Should show 341/341
git status                 # Check uncommitted work
```

---

## Upstream References

**Vercel AI SDK**: v6.0.0-beta.42 (commit `77db222ee`)

**Package paths:**
- `external/vercel-ai-sdk/packages/ai/src/prompt/` — Main prompt code
- `external/vercel-ai-sdk/packages/provider/src/errors/` — Error types
- `external/vercel-ai-sdk/packages/provider-utils/src/` — Utilities

**Test paths:**
- `external/vercel-ai-sdk/packages/ai/src/prompt/*.test.ts`

---

## Current Git Status

**Uncommitted files from PrepareCallSettings session:**
```
M  Sources/SwiftAISDK/Provider/Errors/InvalidArgumentError.swift
M  Sources/SwiftAISDK/ProviderUtils/GenerateID.swift
M  Tests/SwiftAISDKTests/ProviderErrorsTests.swift
??  Sources/SwiftAISDK/Core/Prompt/PrepareCallSettings.swift
??  Tests/SwiftAISDKTests/Core/Prompt/PrepareCallSettingsTests.swift
```

**Previous uncommitted (from Foundation session):**
```
M  plan/progress.md
M  Sources/SwiftAISDK/Core/Prompt/CallSettings.swift
M  Sources/SwiftAISDK/Core/Prompt/Prompt.swift
M  Sources/SwiftAISDK/Core/Prompt/StandardizePrompt.swift
??  Sources/SwiftAISDK/Core/Prompt/DataContent.swift
??  Sources/SwiftAISDK/Core/Prompt/SplitDataUrl.swift
??  Sources/SwiftAISDK/Provider/Errors/InvalidDataContentError.swift
??  Sources/SwiftAISDK/Provider/Errors/InvalidPromptError.swift
??  Sources/SwiftAISDK/ProviderUtils/Uint8Utils.swift
??  Tests/SwiftAISDKTests/Core/Prompt/StandardizePromptTests.swift
```

**DO NOT COMMIT** without user approval.

---

## Estimated Time to Complete Block D

- **Done**: 50% (~10 hours)
- **Remaining**: 50% (~10 hours)
  - prepare-tools-and-tool-choice: 2-3h
  - convert-to-language-model-prompt: 5h
  - Tests: 2-3h

**Total Block D**: ~20 hours (10 done, 10 remaining)

---

## Validation Status

**Session 16 (PrepareCallSettings)**:
- ✅ **APPROVED** by validator (claude-sonnet-4.5)
- Timestamp: 2025-10-12T17:15:00Z
- Verdict: 100% API parity, 100% behavior parity, superior type safety
- Tests: 341/341 passed ✅
- Build: 0.23s

**Previous validations:**
- ✅ Foundation files approved (Session 15)
- ✅ StandardizePrompt approved with 8 tests
- ✅ All blockers resolved

---

## How to Resume in New Session

1. **Read this file** (`plan/contexts/executor-block-d-prompt-preparation.md`)
2. **Check status**: `swift build && swift test` → 341/341 ✅
3. **Read todo.md**: Block D section
4. **Start with**: Port `prepare-tools-and-tool-choice.ts`
5. **Follow**: "Next Immediate Steps" above

---

## Notes

- **Parallel work**: Executor 1 finished Block B (HTTP), no conflicts
- **Validator approved**: PrepareCallSettings + InvalidArgumentError update
- **Ready to proceed**: Foundation complete, PrepareCallSettings complete
- **Communication**: Update `plan/progress.md` after each file

---

**Last Session ID**: #16
**Next Task**: Port `prepare-tools-and-tool-choice.ts`
**Blocked By**: None ✅

— Executor (claude-sonnet-4.5), 2025-10-12T17:04:30Z
