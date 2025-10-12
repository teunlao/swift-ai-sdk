# Swift AI SDK - Agent Guide

## Project Mission

Port **Vercel AI SDK** from TypeScript to Swift with **100% upstream parity**.

**Goal**: 1:1 feature-complete implementation matching TypeScript API, behavior, types, and tests.

## Quick Start

**Read these files first every session**:
```bash
plan/todo.md              # Task list
plan/progress.md          # Current status & history
plan/executor-guide.md    # Executor workflow
plan/validator-guide.md   # Validator checklist
plan/principles.md        # Porting rules
```

**Важно (CLI исполнение):** для _любой_ команды через `shell` всегда указываем `with_escalated_permissions: true` и заполняем `justification`. Без этого Codex CLI блокирует даже безопасные операции.

## Project Structure

```
swift-ai-sdk/
├── Sources/
│   ├── EventSourceParser/       # SSE parser
│   └── SwiftAISDK/
│       ├── Provider/            # V2/V3 types, errors, JSONValue
│       ├── ProviderUtils/       # HTTP, JSON, delays, headers
│       └── Core/                # Generate-text, streams, tools
├── Tests/                        # Swift Testing tests
├── external/                     # ⚠️ UPSTREAM REFERENCE (read-only)
│   ├── vercel-ai-sdk/           # TypeScript source to port
│   └── eventsource-parser/      # SSE parser reference
└── plan/                         # Documentation & progress tracking
```

## Upstream References

**Vercel AI SDK** (current: 6.0.0-beta.42, commit `77db222ee`):
```
external/vercel-ai-sdk/
├── packages/provider/            # Language model types (V2/V3)
├── packages/provider-utils/      # Utilities (HTTP, JSON, SSE)
└── packages/ai/                  # Core SDK (generate-text, streams, tools)
```

**EventSource Parser**:
```
external/eventsource-parser/      # SSE parsing library
```

## Roles & Workflow

### Executor Role
**Implement features, write tests, update docs.**

1. Read plan docs (`plan/*.md`)
2. Find TypeScript code in `external/vercel-ai-sdk/`
3. Port to Swift in `Sources/SwiftAISDK/`
4. Port tests to `Tests/SwiftAISDKTests/`
5. Run `swift build && swift test` (must pass 100%)
6. Update `plan/progress.md` with timestamped entry

**Never**: Commit/push without permission, break parity, leave failing tests.

### Validator Role
**Review executor work for correctness.**

1. Compare Swift vs TypeScript source
2. Verify 100% API/behavior match
3. Check test coverage completeness
4. Document deviations/issues
5. Approve or request fixes

## Standard Workflow

### 1. Planning
```bash
# Check what needs to be done
cat plan/todo.md

# Check current status
cat plan/progress.md | tail -50
```

### 2. Find Upstream Code
```bash
# Example: Porting delay function
cat external/vercel-ai-sdk/packages/provider-utils/src/delay.ts
cat external/vercel-ai-sdk/packages/provider-utils/src/delay.test.ts
```

### 3. Implement in Swift
**File naming pattern**:
```
TypeScript: external/vercel-ai-sdk/packages/provider-utils/src/delay.ts
Swift:      Sources/SwiftAISDK/ProviderUtils/Delay.swift
Tests:      Tests/SwiftAISDKTests/ProviderUtils/DelayTests.swift
```

**⚠️ REQUIRED: Upstream References in Code**

Every ported file MUST include header comment with upstream source:

```swift
/**
 Brief description of the module.

 Port of `@ai-sdk/provider-utils/src/delay.ts`.

 Additional details if needed.
 */
```

**Format:**
- Functions/Types: `Port of '@ai-sdk/PACKAGE/src/PATH.ts'`
- Use backticks around path
- Package names: `provider`, `provider-utils`, `ai`

**Examples:**
```swift
// ✅ Good - File header
/**
 Delays execution for a specified time.

 Port of `@ai-sdk/provider-utils/src/delay.ts`.
 */

// ✅ Good - Complex function
/**
 Converts TypeScript AbortSignal to Swift cancellation check.

 Port of `@ai-sdk/ai/src/generate-text.ts` (abortSignal handling).
 Adapted: Swift uses @Sendable closure instead of AbortSignal.
 */

// ✅ Good - Type with adaptation
/**
 Port of `@ai-sdk/provider/src/language-model/v3/message.ts`.

 TypeScript union: `type | type` → Swift enum with associated values.
 */
```

**API must match exactly**:
```typescript
// TypeScript
export async function delay(delayInMs?: number): Promise<void>
```

```swift
// Swift
public func delay(_ delayInMs: Int?) async throws
```

### 4. Port ALL Tests
```typescript
// TypeScript test
it('resolves after specified time', async () => {
  const start = Date.now();
  await delay(50);
  expect(Date.now() - start).toBeGreaterThanOrEqual(50);
});
```

```swift
// Swift test
@Test("resolves after specified time")
func resolvesAfterSpecifiedTime() async throws {
    let start = Date.now
    try await delay(50)
    #expect(Date.now - start >= 0.05)
}
```

### 5. Verify
```bash
swift build              # Must succeed
swift test               # All tests must pass
```

### 6. Document Progress
**Update `plan/progress.md`**:
```markdown
## [executor][agent-name] Session YYYY-MM-DDTHH:MM:SSZ: Feature Name

**Implemented:**
- ✅ File.swift — description (X tests, 100% parity)

**Details:**
- Key implementation decisions
- Adaptations from TypeScript

**Tests:** X/X passed (+Y new)

— agent-executor/model-name, YYYY-MM-DDTHH:MM:SSZ
```

**Get UTC timestamp**:
```bash
date -u +"%Y-%m-%dT%H:%M:%SZ"
```

## Parity Standards

### Must Match Exactly
✅ Public API (names, parameters, return types)
✅ Behavior (edge cases, errors, null handling)
✅ Error messages (same text when possible)
✅ Test scenarios (all upstream tests ported)

### Swift Adaptations (Allowed)
✅ `Promise<T>` → `async throws -> T`
✅ `AbortSignal` → `@Sendable () -> Bool` or Task cancellation
✅ Union types → `enum` with associated values
✅ `undefined` → `nil` (optional types)
✅ `Record<K, V>` → `[K: V]`

### Document Deviations
If exact parity is impossible:
- **MUST**: Add code comment with upstream reference (see "Upstream References in Code" above)
- **MUST**: Explain why adaptation was needed
- Document significant changes in `plan/design-decisions.md`
- Ensure tests verify adapted behavior

**Example of documented deviation:**
```swift
/**
 Port of `@ai-sdk/ai/src/generate-text.ts` (cancellation handling).

 TypeScript: Uses AbortSignal for cancellation
 Swift: Uses @Sendable () -> Bool closure that returns true when cancelled

 Reason: Swift has no standard AbortSignal type. Closure pattern is idiomatic
 and integrates with Swift's Task cancellation model.
 */
public struct CallSettings {
    public var abortSignal: (@Sendable () -> Bool)?
    // ...
}
```

## Common Patterns

### TypeScript → Swift

**Async functions**:
```typescript
async function foo(): Promise<string> { }
```
```swift
func foo() async throws -> String { }
```

**Optionals**:
```typescript
value?: string | undefined
```
```swift
value: String? = nil
```

**Union types**:
```typescript
type Status = 'pending' | 'done' | 'error'
```
```swift
enum Status: String, Codable {
    case pending, done, error
}
```

**Discriminated unions**:
```typescript
type Result =
  | { type: 'success'; value: T }
  | { type: 'error'; error: Error }
```
```swift
enum Result {
    case success(value: T)
    case error(Error)
}
```

**Dictionaries**:
```typescript
headers?: Record<string, string>
```
```swift
headers: [String: String]? = nil
```

## Testing Standards

### Port ALL Tests
Every `.test.ts` file must be ported to Swift Testing.

### Test Structure
```swift
import Testing
@testable import SwiftAISDK

@Suite("Module Name")
struct ModuleTests {
    @Test("feature works correctly")
    func featureWorksCorrectly() throws {
        // Arrange
        let input = "test"

        // Act
        let result = function(input)

        // Assert
        #expect(result == expected)
    }
}
```

### Naming
- Use upstream test names (converted to camelCase)
- Keep descriptions in English
- Group related tests in `@Suite`

## Current Status

**✅ Completed** (236/236 tests passing):
- EventSourceParser (30 tests)
- LanguageModelV2 (50 tests)
- LanguageModelV3 (39 tests)
- Provider Errors (26 tests)
- ProviderUtils (77 tests): ID gen, delays, headers, user-agent, settings, HTTP utils, version, secure JSON parsing
- JSONValue (universal JSON type)

**🚧 Next Priorities** (see `plan/todo.md`):
- Schema & validation system
- ParseJSON & ValidateTypes
- HTTP API functions (post-to-api, get-from-api)
- Response handlers

## Key Commands

```bash
# Read plan
cat plan/todo.md plan/progress.md

# Find upstream
ls external/vercel-ai-sdk/packages/*/src/

# Build & test
swift build && swift test

# Test summary
swift test 2>&1 | tail -5

# UTC timestamp
date -u +"%Y-%m-%dT%H:%M:%SZ"

# Count files
find Sources Tests -name "*.swift" | wc -l

# Count lines
find Sources Tests -name "*.swift" -exec wc -l {} + | tail -1
```

## Pre-Completion Checklist

Before marking task complete:

- [ ] Public API matches upstream TypeScript
- [ ] Behavior matches exactly (same inputs → outputs/errors)
- [ ] ALL upstream tests ported
- [ ] All tests pass (including existing tests)
- [ ] **Every file has upstream reference in header comment** (`Port of '@ai-sdk/...'`)
- [ ] Adaptations documented with explanation if needed
- [ ] `plan/progress.md` updated with UTC timestamp
- [ ] No regressions introduced

## Key Principles

1. **Read first, code second** — Always check upstream and plan
2. **Test everything** — No code without tests
3. **Document progress** — Every session logged in progress.md
4. **100% parity** — Match TypeScript behavior exactly
5. **Ask before deviating** — Document unavoidable differences
6. **Never commit** — Wait for approval

## Documentation Files

### Core
- `README.md` — Project overview, stats
- `CHANGELOG.md` — Release notes
- `Package.swift` — SwiftPM manifest

### Plan Directory
- `todo.md` — Master task list (blocks A-O)
- `progress.md` — Session history with timestamps
- `principles.md` — Porting guidelines
- `executor-guide.md` — Detailed executor workflow
- `validator-guide.md` — Validation checklist
- `dependencies.md` — External dependencies strategy
- `tests.md` — Testing approach
- `design-decisions.md` — Documented deviations

## Resources

**Upstream repo**: https://github.com/vercel/ai
**EventSource parser**: https://github.com/EventSource/eventsource-parser

---

**Remember**: Every line of code must match upstream behavior. When in doubt, check TypeScript source.

*Last updated: 2025-10-12*
