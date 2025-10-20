# 🔍 Anthropic Provider Implementation Audit

## 📋 Overview

**Purpose**: Verify implementation parity with TypeScript upstream
**Scope**: Source code only (tests excluded)
**Date**: 2025-10-20
**Status**: ⏳ In Progress

---

## 📂 File Structure Comparison

### Upstream TypeScript (`external/vercel-ai-sdk/packages/anthropic/src/`)
```
anthropic-messages-language-model.ts
anthropic-error.ts
anthropic-prepare-tools.ts
anthropic-tools.ts
anthropic-messages-api.ts
anthropic-provider.ts
map-anthropic-stop-reason.ts
convert-to-anthropic-messages-prompt.ts
anthropic-messages-options.ts
version.ts
get-cache-control.ts
tool/text-editor_20250728.ts
tool/web-fetch-20250910.ts
tool/code-execution_20250522.ts
tool/bash_20241022.ts
tool/web-search_20250305.ts
tool/computer-use_20241022.ts (implied from upstream)
```

### Swift Implementation (`Sources/AnthropicProvider/`)
```
AnthropicMessagesLanguageModel.swift      ✅
AnthropicError.swift                      ✅
AnthropicPrepareTools.swift              ✅
AnthropicTools.swift                     ✅
AnthropicMessagesAPI.swift               ✅
AnthropicProvider.swift                  ✅
MapAnthropicStopReason.swift             ✅
ConvertToAnthropicMessagesPrompt.swift   ✅
AnthropicProviderOptions.swift           ✅
AnthropicVersion.swift                   ✅
GetCacheControl.swift                    ✅
AnthropicModelIds.swift                  ⚠️  (Extra file)
Tool/AnthropicTextEditor20250728.swift   ✅
Tool/AnthropicTextEditorTools.swift      ⚠️  (Extra file)
Tool/AnthropicWebTools.swift             ✅ (combines web-fetch + web-search)
Tool/AnthropicCodeExecutionTool.swift    ✅
Tool/AnthropicBashTool.swift             ✅
Tool/AnthropicComputerTool.swift         ✅
```

**Summary**: All upstream files ported + 2 extra files (AnthropicModelIds, AnthropicTextEditorTools)

---

## 🔬 Detailed Implementation Analysis

### 1. AnthropicProvider.swift

**Lines**: 136 lines
**Upstream**: `anthropic-provider.ts` (131 lines)

#### ✅ Correct Patterns
1. **Settings structure** matches upstream (baseURL, apiKey, headers, fetch)
2. **Lazy API key loading** - same pattern as OpenAI
3. **User-Agent suffix** - correct format `ai-sdk/anthropic/{VERSION}`
4. **Header structure** - correct `anthropic-version: 2023-06-01` and `x-api-key`
5. **Provider pattern** - uses factory closures like OpenAI
6. **Default instance** - `public let anthropic = createAnthropicProvider()`

#### ⚠️  Potential Issues

**Issue 1: Supported URLs mismatch**

**Upstream (TypeScript)**:
```typescript
supportedUrls: () => ({
  'image/*': [/^https?:\/\/.*$/],
})
```

**Swift**:
```swift
let supportedURLs: @Sendable () -> [String: [NSRegularExpression]] = {
    [
        "image/*": [anthropicHTTPSRegex],
        "application/pdf": [anthropicHTTPSRegex]  // ⚠️ NOT in upstream
    ]
}
```

**Impact**: Swift supports PDF files, but upstream TypeScript does not.
**Verdict**: ⚠️  **POTENTIAL OVER-IMPLEMENTATION** - Check if this is intentional or error.

---

**Issue 2: Error handling pattern**

**Upstream (TypeScript)**:
```typescript
provider.textEmbeddingModel = (modelId: string) => {
  throw new NoSuchModelError({ modelId, modelType: 'textEmbeddingModel' });
};
```

**Swift**:
```swift
public func textEmbeddingModel(modelId: String) -> any EmbeddingModelV3<String> {
    fatalError(NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel).localizedDescription)
}
```

**Impact**: `fatalError` crashes the app, upstream `throw` allows error handling.
**Verdict**: ❌ **INCORRECT** - Should use `throw` or return error type, not `fatalError`.

**Recommendation**: Change to:
```swift
public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
    throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
}
```

---

### 2. Comparison with OpenAI Provider

#### Structural Consistency ✅

**OpenAI**:
```swift
public struct OpenAIProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    // ...
}

public func createOpenAIProvider(settings: OpenAIProviderSettings = .init()) -> OpenAIProvider {
    let headersClosure: @Sendable () -> [String: String?] = { ... }
    // ...
}
```

**Anthropic**:
```swift
public struct AnthropicProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    // ...
}

public func createAnthropicProvider(settings: AnthropicProviderSettings = .init()) -> AnthropicProvider {
    let headersClosure: @Sendable () -> [String: String?] = { ... }
    // ...
}
```

**Verdict**: ✅ **EXCELLENT** - Follows same pattern as OpenAI.

---

## 🎯 Summary of Findings

### ✅ Strengths
1. All upstream files ported
2. Consistent patterns with OpenAI provider
3. Proper use of `@Sendable`, lazy loading, factory closures
4. Correct header structure and API version
5. Comprehensive tool support

### ⚠️  Issues Found

| Issue | Severity | File | Line | Status |
|-------|----------|------|------|--------|
| PDF support not in upstream | Medium | AnthropicProvider.swift | 106 | Needs verification |
| fatalError for unsupported models | High | AnthropicProvider.swift | 65, 69 | ❌ Must fix |

---

## 📊 Overall Implementation Score

**Structure**: ✅ 100%
**Patterns**: ✅ 95% (minor fatalError issue)
**Parity**: ⚠️  95% (PDF support mismatch)

**Overall**: ⚠️  **96.7% - GOOD with minor issues**

---

### 3. AnthropicMessagesLanguageModel.swift

**Lines**: 1,123 lines (Swift) vs 1,150 lines (TypeScript)
**Upstream**: `anthropic-messages-language-model.ts`

#### ✅ Correct Implementation
1. **Config structure** - AnthropicMessagesConfig with RequestTransform pattern
2. **Key methods present**:
   - `doGenerate` (line 78)
   - `doStream` (line 127)
   - `prepareRequest` (line 290)
   - `mapResponseContent` (line 456)
3. **Warning system** - Correctly warns for unsupported settings (frequencyPenalty, presencePenalty, seed)
4. **JSON response format** - Proper handling with schema validation
5. **Provider options parsing** - Uses parseProviderOptions pattern
6. **Line count comparison** - 1,123 vs 1,150 (97.7% similar size)

**Verdict**: ✅ **EXCELLENT** - Full parity with upstream

---

### 4. ConvertToAnthropicMessagesPrompt.swift

**Lines**: 529 lines
**Upstream**: `convert-to-anthropic-messages-prompt.ts`

#### ✅ Correct Implementation
1. **Block grouping** - `groupIntoAnthropicBlocks` pattern
2. **System message handling** - Aggregates system content
3. **Cache control** - Proper cacheControl JSON generation
4. **Message conversion** - Handles user/assistant/tool messages
5. **Betas tracking** - Collects required beta features

**Verdict**: ✅ **CORRECT** - Matches upstream logic

---

### 5. Tool Implementations

#### Tool Files Comparison

**Upstream**:
- `tool/bash_20241022.ts`
- `tool/code-execution_20250522.ts`
- `tool/text-editor_20250728.ts`
- `tool/web-fetch-20250910.ts`
- `tool/web-search_20250305.ts`
- `tool/computer-use_20241022.ts`

**Swift**:
- `Tool/AnthropicBashTool.swift` ✅
- `Tool/AnthropicCodeExecutionTool.swift` ✅
- `Tool/AnthropicTextEditor20250728.swift` ✅
- `Tool/AnthropicTextEditorTools.swift` ⚠️  (Extra wrapper)
- `Tool/AnthropicWebTools.swift` ✅ (combines web-fetch + web-search)
- `Tool/AnthropicComputerTool.swift` ✅

**Analysis**:
- All upstream tools ported ✅
- `AnthropicTextEditorTools.swift` appears to be a convenience wrapper
- `AnthropicWebTools.swift` combines two upstream files (web-fetch + web-search)

**Verdict**: ✅ **COMPLETE** - All tools implemented with Swift-specific organization

---

### 6. Extra Files Analysis

#### ❌ AnthropicModelIds.swift - INCORRECT IMPLEMENTATION

**Current Implementation**:
```swift
public struct AnthropicMessagesModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    // ... accepts ANY string
}
```

**Upstream TypeScript**:
```typescript
export type AnthropicMessagesModelId =
  | 'claude-sonnet-4-5'
  | 'claude-sonnet-4-5-20250929'
  | 'claude-opus-4-1'
  | 'claude-opus-4-0'
  | 'claude-sonnet-4-0'
  | 'claude-opus-4-1-20250805'
  | 'claude-opus-4-20250514'
  | 'claude-sonnet-4-20250514'
  | 'claude-3-7-sonnet-latest'
  | 'claude-3-7-sonnet-20250219'
  | 'claude-3-5-haiku-latest'
  | 'claude-3-5-haiku-20241022'
  | 'claude-3-haiku-20240307'
  | (string & {});  // Allows other strings but with autocomplete for known models
```

**Problem**:
- ❌ Swift accepts **ANY** string via `RawRepresentable`
- ❌ No type-level documentation of valid models
- ❌ Loses TypeScript's autocomplete benefit
- ❌ Should be in `anthropic-messages-options.ts` equivalent file

**Impact**:
- Type safety weaker than upstream
- No compile-time validation
- Missing model list documentation

**Verdict**: ❌ **INCORRECT** - File should be removed, type definition should be in AnthropicProviderOptions.swift with documented model list

**Comparison with OpenAI**:
OpenAI has same issue - `OpenAIModelIds.swift` with same pattern. This suggests **systematic error** across providers.

---

#### AnthropicTextEditorTools.swift

**Purpose**: Convenience wrapper for text editor tools
**Verdict**: ⚠️  **NEEDS VERIFICATION** - Check if this adds value or just duplicates functionality

---

## 🎯 Final Implementation Analysis

### Code Quality Metrics

| Metric | Score | Notes |
|--------|-------|-------|
| **File Structure** | 100% | All upstream files ported |
| **Pattern Consistency** | 95% | Follows OpenAI patterns |
| **Line Count Match** | 97.7% | 1,123 vs 1,150 lines |
| **API Parity** | 100% | All public APIs present |
| **Error Handling** | 90% | fatalError issue needs fix |

---

## ❌ Critical Issues

### Issue 1: AnthropicModelIds.swift - Incorrect Type Definition
**Severity**: 🔴 **CRITICAL**
**File**: `AnthropicModelIds.swift` (entire file)
**Problem**: Accepts ANY string instead of documented model list

**Current (WRONG)**:
```swift
public struct AnthropicMessagesModelId: RawRepresentable {
    public let rawValue: String  // Accepts ANYTHING
}
```

**Upstream**:
```typescript
export type AnthropicMessagesModelId =
  | 'claude-sonnet-4-5'
  | 'claude-sonnet-4-5-20250929'
  | 'claude-opus-4-1'
  // ... 13 specific models
  | (string & {});  // TypeScript allows custom strings but provides autocomplete
```

**Fix Required**:
1. **DELETE** `AnthropicModelIds.swift`
2. **MOVE** type definition to `AnthropicProviderOptions.swift`
3. **ADD** typealias with documented model list:
```swift
/// Anthropic Claude model identifiers.
/// See: https://docs.claude.com/en/docs/about-claude/models/overview
///
/// Supported models:
/// - claude-sonnet-4-5, claude-sonnet-4-5-20250929
/// - claude-opus-4-1, claude-opus-4-0, claude-sonnet-4-0
/// - claude-opus-4-1-20250805, claude-opus-4-20250514, claude-sonnet-4-20250514
/// - claude-3-7-sonnet-latest, claude-3-7-sonnet-20250219
/// - claude-3-5-haiku-latest, claude-3-5-haiku-20241022
/// - claude-3-haiku-20240307
/// - Any custom model string
public typealias AnthropicMessagesModelId = String
```

**Impact**: Loss of type documentation, weaker API guidance
**Action Required**: ❌ **MUST FIX** - Affects all providers (OpenAI has same issue)

---

### Issue 2: fatalError for Unsupported Models
**Severity**: 🔴 HIGH
**File**: `AnthropicProvider.swift:65, 69`
**Problem**: Using `fatalError` crashes app instead of throwing error

**Current**:
```swift
public func textEmbeddingModel(modelId: String) -> any EmbeddingModelV3<String> {
    fatalError(NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel).localizedDescription)
}
```

**Should be**:
```swift
public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
    throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
}
```

**Action Required**: ❌ MUST FIX before production

---

### Issue 3: PDF Support Not in Upstream
**Severity**: ⚠️  MEDIUM
**File**: `AnthropicProvider.swift:106`
**Problem**: Swift supports `application/pdf` but upstream only supports `image/*`

**Current**:
```swift
let supportedURLs: @Sendable () -> [String: [NSRegularExpression]] = {
    [
        "image/*": [anthropicHTTPSRegex],
        "application/pdf": [anthropicHTTPSRegex]  // ⚠️ NOT in upstream
    ]
}
```

**Upstream**:
```typescript
supportedUrls: () => ({
  'image/*': [/^https?:\/\/.*$/],
})
```

**Options**:
1. Remove PDF support to match upstream exactly
2. Verify if this is intentional enhancement
3. Document as Swift-specific feature

**Action Required**: ⚠️  NEEDS DECISION - Verify intent with team

---

### Issue 4: Function Naming Inconsistency
**Severity**: ⚠️  MEDIUM
**File**: `AnthropicProvider.swift:73, 135`
**Problem**: Function names don't match upstream

**Current (Swift)**:
```swift
public func createAnthropicProvider(settings: AnthropicProviderSettings = .init()) -> AnthropicProvider
public let anthropic = createAnthropicProvider()
```

**Upstream (TypeScript)**:
```typescript
export function createAnthropic(options: AnthropicProviderSettings = {}): AnthropicProvider
export const anthropic = createAnthropic();
```

**Impact**:
- API inconsistency with upstream naming
- Same issue exists in OpenAI (`createOpenAIProvider` vs `createOpenAI`)
- Systematic naming pattern across all providers

**Recommendation**: ⚠️  NEEDS DECISION
1. Either: Match upstream exactly (`createAnthropic`)
2. Or: Document this as intentional Swift naming pattern in `design-decisions.md`

**Current Status**: Not documented in design-decisions.md

---

## 📋 Detailed File-by-File Verification

### Core Files (10 files)

| Upstream File | Swift File | Status | Notes |
|---------------|------------|--------|-------|
| anthropic-provider.ts (130 lines) | AnthropicProvider.swift (135 lines) | ✅ | 96.2% line match, function naming differs |
| anthropic-messages-language-model.ts (1,150 lines) | AnthropicMessagesLanguageModel.swift (1,123 lines) | ✅ | 97.7% line match |
| anthropic-messages-options.ts | AnthropicProviderOptions.swift | ⚠️ | Missing ModelId type definition (in separate file) |
| anthropic-messages-api.ts | AnthropicMessagesAPI.swift | ✅ | Complete |
| anthropic-error.ts | AnthropicError.swift | ✅ | Complete |
| anthropic-prepare-tools.ts | AnthropicPrepareTools.swift | ✅ | Complete |
| anthropic-tools.ts | AnthropicTools.swift | ✅ | All 11 tool versions present |
| convert-to-anthropic-messages-prompt.ts | ConvertToAnthropicMessagesPrompt.swift | ✅ | Complete |
| map-anthropic-stop-reason.ts | MapAnthropicStopReason.swift | ✅ | Complete |
| get-cache-control.ts | GetCacheControl.swift | ✅ | Complete |
| version.ts | AnthropicVersion.swift | ✅ | Complete |

### Tool Files (11 tool versions across 6 Swift files)

**Upstream Tools**:
- bash_20241022.ts, bash_20250124.ts → `AnthropicBashTool.swift` ✅
- code-execution_20250522.ts → `AnthropicCodeExecutionTool.swift` ✅
- computer_20241022.ts, computer_20250124.ts → `AnthropicComputerTool.swift` ✅
- text-editor_20241022.ts → `AnthropicTextEditorTools.swift` ✅
- text-editor_20250124.ts → `AnthropicTextEditorTools.swift` ✅
- text-editor_20250429.ts → `AnthropicTextEditorTools.swift` ✅
- text-editor_20250728.ts → `AnthropicTextEditor20250728.swift` ✅
- web-fetch-20250910.ts → `AnthropicWebTools.swift` ✅
- web-search_20250305.ts → `AnthropicWebTools.swift` ✅

**Tool Count**: ✅ All 11 tool versions implemented

**File Organization**:
- Upstream: 11 separate files (one per tool/version)
- Swift: 6 files (grouped by tool family)
- Verdict: ✅ **ACCEPTABLE** - Different organization, same functionality

### Extra Files (2 files)

| File | Purpose | Verdict |
|------|---------|---------|
| AnthropicModelIds.swift | Model ID type (14 lines) | ❌ **INCORRECT** - Should be in AnthropicProviderOptions.swift |
| AnthropicTextEditorTools.swift | Contains 3 of 4 text editor versions | ⚠️ **REDUNDANT?** - 4th version in separate file |

**Analysis**:
- `AnthropicModelIds.swift`: Entire file is incorrect implementation, should be removed
- `AnthropicTextEditorTools.swift`: Contains older text editor versions (20241022, 20250124, 20250429), while newest version (20250728) is in separate file `AnthropicTextEditor20250728.swift`

### Line Count Comparison

| Metric | Swift | TypeScript | Match % |
|--------|-------|------------|---------|
| Total lines | 3,846 | 3,960 | 97.1% |
| Main provider file | 135 | 130 | 96.2% |
| Language model file | 1,123 | 1,150 | 97.7% |

**Verdict**: ✅ **EXCELLENT** line count parity

---

## ✅ Strengths

1. **Complete file coverage** - All 16 upstream files ported + 2 Swift improvements
2. **Consistent patterns** - Matches OpenAI provider structure
3. **Proper typing** - Uses `@Sendable`, closures, factory patterns correctly
4. **Line count parity** - Within 3% of upstream (1,123 vs 1,150 lines)
5. **Tool support** - All 6 Anthropic tools implemented
6. **Warning system** - Comprehensive unsupported setting warnings
7. **Cache control** - Proper implementation of prompt caching

---

## 📊 Overall Implementation Score

### Category Scores
- **Structure**: ✅ 100/100 - All files ported, 97.1% line count match
- **Patterns**: ⚠️  90/100 (fatalError issue, naming inconsistency)
- **Parity**: ⚠️  90/100 (PDF support, model ID type issues)
- **Code Quality**: ✅ 95/100
- **Completeness**: ✅ 100/100 - All 11 tool versions present

### Final Score
**⚠️  95.0/100 - VERY GOOD with 4 issues to address**

---

## 🔧 Issues Summary

### 🔴 Priority 1 (CRITICAL - Must Fix)
- [ ] **Issue 1**: AnthropicModelIds.swift - Incorrect type definition (DELETE file, move to AnthropicProviderOptions.swift)
  - File: `Sources/AnthropicProvider/AnthropicModelIds.swift` (entire file)
  - Impact: Loss of type documentation, weaker API guidance
  - Fix: Replace with `typealias AnthropicMessagesModelId = String` in AnthropicProviderOptions.swift with model list documentation

### 🟡 Priority 2 (HIGH - Should Fix)
- [ ] **Issue 2**: fatalError for unsupported models
  - Files: `AnthropicProvider.swift:65, 69`
  - Impact: App crashes instead of error handling
  - Fix: Change to `throws -> ...` and use `throw` instead of `fatalError`

### 🟠 Priority 3 (MEDIUM - Needs Decision)
- [ ] **Issue 3**: PDF support not in upstream
  - File: `AnthropicProvider.swift:106`
  - Impact: Feature mismatch with upstream
  - Action: Verify if intentional or remove for exact parity

- [ ] **Issue 4**: Function naming inconsistency
  - Files: `AnthropicProvider.swift:73, 135`
  - Impact: API naming differs from upstream (`createAnthropicProvider` vs `createAnthropic`)
  - Action: Either match upstream exactly or document as intentional Swift pattern
  - Note: Same issue in OpenAI provider (systematic)

---

## 🚨 CRITICAL DISCOVERY - ADDITIONAL AUDIT REQUIRED

**STOP**: During detailed line-by-line analysis, discovered **CRITICAL ISSUES** that invalidate initial assessment.

### Line Count Red Flag

```
Expected: Swift >= TypeScript (Swift is more verbose)
Actual:   Swift < TypeScript (3,846 vs 3,960)
```

❌ **This is WRONG!** Swift code should be LARGER, not smaller!

### Missing Content Discovered

| Issue | Severity | Impact |
|-------|----------|--------|
| Missing 400+ lines of documentation | 🔴 CRITICAL | 99.5% of docs missing (2 vs 431 lines) |
| Computer tool broken (wrong implementation) | 🔴 CRITICAL | Version 20250124 cannot use 6 new actions |
| Wrong schemas for tools | 🔴 CRITICAL | Missing required properties |
| No parameter descriptions | 🔴 CRITICAL | API unusable without docs |

### Documentation Deficit

**TypeScript**: 431 lines of JSDoc comments
**Swift**: 2 lines of doc comments

**Missing**: ~429 lines (99.5%)

### Broken Functionality

**computer_20250124** tool:
- ❌ Missing 6 actions: `hold_key`, `left_mouse_down`, `left_mouse_up`, `triple_click`, `scroll`, `wait`
- ❌ Missing properties: `duration`, `scroll_amount`, `scroll_direction`, `start_coordinate`
- ❌ Using wrong schema from 20241022 version

**Impact**: Feature is **BROKEN**, not just missing docs

---

## 🔴 UPDATED CONCLUSION

**Implementation Status**: ❌ **FAILED PARITY CHECK - PRODUCTION BLOCKER**

**CRITICAL AUDIT FINDINGS**:
See detailed report: `.audit/audit-anthropic-CRITICAL.md`

**Real Score**: ❌ **44.0/100** (not 95.0/100)

**Key Findings**:
1. ❌ **CRITICAL**: 400+ lines of documentation missing (99.5%)
2. ❌ **CRITICAL**: Computer tool implementation broken (wrong schema, missing actions)
3. ❌ **CRITICAL**: All tool files missing type documentation
4. ❌ **CRITICAL**: Line count deficit indicates major missing content
5. ❌ AnthropicModelIds.swift incorrect
6. ❌ fatalError usage needs fixing
7. ⚠️  PDF support mismatch needs decision
8. ⚠️  Function naming inconsistency

**Required Action**:
1. 🚨 **STOP development** - implementation fundamentally incomplete
2. 📋 Read `.audit/audit-anthropic-CRITICAL.md` for full details
3. 🔧 Complete rewrite of tool implementations required
4. 📝 Add ALL missing documentation (~400 lines)
5. ✅ Fix computer tool with correct schemas per version
6. ✅ Port ALL upstream type documentation

**Estimated Work**:
- 400+ lines of documentation to add
- 3-4 files to completely rewrite
- Full verification of every file

**This is NOT production ready**

---

*Part 1 (Implementation) completed: 2025-10-20*
*Part 2 (Test Coverage) - pending*
