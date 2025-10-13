# ParseToolCallTests Schema Validation Issue - Research Findings

## Problem Summary

ParseToolCallTests has 5 failing tests with this error during schema validation:
```
Expected value of type JSONValue but received {
    param1 = test;
    param2 = 42;
}
```

## Root Cause Analysis

### What TypeScript Does (Upstream)

When using Zod schemas in TypeScript:
```typescript
// TypeScript
tool({
  inputSchema: z.object({
    param1: z.string(),
    param2: z.number(),
  })
})
```

- Zod creates a `Schema` with **both** `jsonSchema` AND `validate` properties
- The `validate` function (line 227-232 in schema.ts):
  ```typescript
  validate: async value => {
    const result = await zodSchema.safeParseAsync(value);
    return result.success
      ? { success: true, value: result.data }  // ← Returns TRANSFORMED value
      : { success: false, error: result.error };
  }
  ```
- **Key point**: `validate` transforms the raw parsed JSON into the target type

### What Swift Does (Current Implementation)

When using `jsonSchema()` in Swift:
```swift
// Swift
tool(
    inputSchema: FlexibleSchema(jsonSchema(.object([
        "type": .string("object"),
        "properties": .object([...])
    ])))
)
```

- `jsonSchema()` creates a `Schema<JSONValue>` with **NO** `validate` callback
- Without a validator, Schema uses "passthrough" mode (Schema.swift:93-101):
  ```swift
  guard let validator else {
      return SchemaValidationResult.passthrough(value, as: Output.self)
  }
  ```
- Passthrough checks: `value as? JSONValue`
- **Problem**: Value is `[String: Any]` (from JSONSerialization), not `JSONValue`
- Error: "Expected value of type JSONValue but received {...}"

## Flow Diagram

```
TypeScript (working):
1. safeParseJSON → [String: Any]
2. safeValidateTypes → calls zod validate
3. validate → transforms [String: Any] to typed object ✓
4. Return typed value ✓

Swift (failing):
1. safeParseJSON → [String: Any]
2. safeValidateTypes → calls Schema.validate
3. No validator → passthrough mode
4. Passthrough: [String: Any] as? JSONValue → nil
5. Error: SchemaTypeMismatchError ✗
```

## Solution

We need to provide a `validate` callback that converts `[String: Any]` to `JSONValue`.

The conversion logic already exists in `ParseJSON.swift`:
```swift
private func jsonValue(from value: Any) throws -> JSONValue {
    if let jsonValue = value as? JSONValue {
        return jsonValue
    }
    // ... conversion logic for [String: Any], [Any], etc.
}
```

### Fix Option 1: Create a `jsonValueSchema()` Helper

Add to `Schema.swift`:
```swift
public func jsonValueSchema(
    _ jsonSchema: JSONValue
) -> Schema<JSONValue> {
    Schema(
        jsonSchemaResolver: { jsonSchema },
        validator: { value in
            do {
                // Reuse existing conversion logic from ParseJSON.swift
                let converted = try jsonValue(from: value)
                return .success(value: converted)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
}
```

Usage in tests:
```swift
tool(
    inputSchema: FlexibleSchema(jsonValueSchema(
        .object([
            "type": .string("object"),
            "properties": .object([...])
        ])
    ))
)
```

### Fix Option 2: Make `jsonSchema<JSONValue>` Auto-Include Validator

Modify `jsonSchema()` to detect when `Output == JSONValue` and automatically add the validator:

```swift
public func jsonSchema(
    _ jsonSchema: JSONValue,
    validate: Schema<JSONValue>.Validator? = nil
) -> Schema<JSONValue> {
    let defaultValidator: Schema<JSONValue>.Validator = { value in
        do {
            let converted = try jsonValue(from: value)
            return .success(value: converted)
        } catch {
            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
        }
    }

    return Schema(
        jsonSchemaResolver: { jsonSchema },
        validator: validate ?? defaultValidator
    )
}
```

This would make `jsonSchema()` work automatically for `JSONValue` output type.

## Recommendation

**Option 2** is better because:
1. Maintains backward compatibility
2. Matches TypeScript behavior (Zod always includes validation)
3. No test changes needed
4. More ergonomic API

However, we need to be careful about the function signature to support both generic and `JSONValue`-specific cases.

## Working Examples Found

1. **ValidateTypesTests** (lines 12-38):
   - Uses `StandardSchemaV1` with custom `validate` callback
   - Manually converts `[String: Any]` to target type
   - This is the pattern we need to replicate

2. **PrepareToolsAndToolChoiceTests**:
   - Only tests schema pass-through, doesn't validate
   - No validation errors because validation never runs

## Files to Modify

1. `/Users/teunlao/projects/public/swift-ai-sdk/Sources/AISDKProviderUtils/Schema/Schema.swift`
   - Add specialized `jsonSchema<JSONValue>` overload with default validator
   - Or add `jsonValueSchema()` helper

2. `/Users/teunlao/projects/public/swift-ai-sdk/Sources/AISDKProviderUtils/ParseJSON.swift`
   - Make `jsonValue(from:)` public (currently private)
   - This function already has all the conversion logic we need

## Upstream Parity Verification

TypeScript behavior (schema.ts:87-112):
- `jsonSchema()` accepts optional `validate` parameter
- Zod/Standard schemas always include validation
- Raw `jsonSchema()` can work without validation

Swift should match:
- `jsonSchema()` should work without validation for generic types
- **BUT** for `JSONValue` output, we need automatic conversion
- This is because Swift's type system is stricter than TypeScript's `unknown`

## Test Changes Required

**None** - if we implement Option 2 correctly, all tests should pass without modification.

The tests are already using the correct API:
```swift
tool(
    inputSchema: FlexibleSchema(jsonSchema(.object([...])))
)
```

They just need the schema to actually validate/convert correctly.
