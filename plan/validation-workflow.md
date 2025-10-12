# Validation Workflow Guide

> Documentation for using the custom validator agent in Swift AI SDK project

**Last Updated**: 2025-10-12
**Agent**: `.claude/agents/validator.md`

---

## Overview

The Swift AI SDK project uses a **custom validator agent** to ensure 100% upstream parity with Vercel AI SDK (TypeScript). This document describes the validation workflow, directory structure, and best practices.

## Quick Start

### For Executors (requesting validation)

```bash
# 1. Complete your implementation
# 2. Create validation request
cat > .validation/requests/validate-my-feature-$(date +%Y-%m-%d).md <<EOF
# Validation Request — My Feature

**Executor**: your-name
**Date**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
**Priority**: HIGH

## Context
Brief description of what was implemented

## Files to Validate
- Implementation: [list Swift files]
- Tests: [list test files]
- Upstream: [list TypeScript sources]

## Checklist
- [ ] All public APIs implemented
- [ ] All upstream tests ported
- [ ] Build passes: swift build
- [ ] Tests pass: swift test
- [ ] Upstream references added

## Questions for Validator
[Optional: specific concerns or edge cases to verify]
EOF

# 3. Request validation from Claude
# In chat: "Use the validator agent to review .validation/requests/validate-my-feature-2025-10-12.md"
```

### For Validators (manual review)

```bash
# 1. Read validation request
cat .validation/requests/validate-feature-YYYY-MM-DD.md

# 2. Compare implementation vs upstream
# Use Read, Grep, Glob tools

# 3. Run tests
swift build && swift test

# 4. Create report
# validator agent will write to .validation/reports/
```

---

## Directory Structure

```
swift-ai-sdk/
├── .claude/
│   └── agents/
│       └── validator.md           # Custom validator agent definition
├── .validation/                    # Temporary validation artifacts (gitignored)
│   ├── README.md                   # Directory documentation
│   ├── requests/                   # Validation requests from executors
│   │   └── validate-feature-YYYY-MM-DD.md
│   ├── reports/                    # Validation reports from validator
│   │   └── feature-validation-YYYY-MM-DD.md
│   └── temp/                       # Temporary working files
└── plan/
    ├── validation-workflow.md      # This file
    └── validator-guide.md          # Existing validator checklist
```

### File Organization

| Location | Purpose | Committed? |
|----------|---------|------------|
| `.claude/agents/` | Agent definitions | ✅ Yes |
| `.validation/requests/` | Validation requests | ❌ No (temporary) |
| `.validation/reports/` | Validation reports | ❌ No (temporary) |
| `.validation/temp/` | Scratch files | ❌ No (temporary) |
| `plan/` | Permanent documentation | ✅ Yes |

**Important**: `.validation/` is gitignored. Final validation outcomes should be documented in `plan/progress.md` or committed reports.

---

## Validation Workflow

### Phase 1: Implementation (Executor)

1. Port TypeScript code to Swift
2. Port all upstream tests
3. Ensure build and tests pass
4. Add upstream references to all files
5. Document adaptations in code comments

### Phase 2: Request Validation (Executor)

1. Create validation request in `.validation/requests/`
2. Include:
   - List of files to validate
   - Upstream sources for comparison
   - Specific concerns or questions
   - Confirmation checklist (build/tests pass)

3. Trigger validator agent:
   ```
   Use the validator agent to review .validation/requests/validate-feature-YYYY-MM-DD.md
   ```

### Phase 3: Validation (Validator Agent)

The validator agent automatically:

1. **Reads request** - Parses `.validation/requests/` file
2. **Gathers context** - Reads implementation, tests, upstream sources
3. **Analyzes code**:
   - API surface comparison (Swift vs TypeScript)
   - Behavior verification (edge cases, errors)
   - Test coverage analysis (all cases ported?)
4. **Runs tests** - Executes `swift build && swift test`
5. **Generates report** - Creates detailed report in `.validation/reports/`
6. **Updates status** - Documents verdict (APPROVED/ISSUES/REJECTED)

### Phase 4: Resolution (Executor)

1. Read validation report from `.validation/reports/`
2. Address any issues found:
   - **BLOCKER** 🔴 - Must fix before merge
   - **MAJOR** 🟠 - Should fix
   - **MINOR** 🟡 - Nice to have
   - **INFO** 🔵 - For information only

3. Re-request validation if changes made

### Phase 5: Documentation (Both)

1. Executor documents completion in `plan/progress.md`
2. Validation outcome summarized (not full report)
3. Delete temporary files from `.validation/`

---

## Validation Request Template

```markdown
# Validation Request — [Feature Name]

**Executor**: [executor-name]
**Date**: [YYYY-MM-DDTHH:MM:SSZ]
**Priority**: HIGH/MEDIUM/LOW
**Related**: [links to previous reviews if any]

---

## Context

[2-3 sentences describing what was implemented]

**Upstream**: Vercel AI SDK v6.0.0-beta.42 (commit `77db222ee`)
**Block**: [Block A/B/C/etc from plan/todo.md]

---

## Files to Validate

### Implementation
- `Sources/SwiftAISDK/Path/File1.swift` - [brief description]
- `Sources/SwiftAISDK/Path/File2.swift` - [brief description]

### Tests
- `Tests/SwiftAISDKTests/Path/File1Tests.swift` - [N test cases]

### Upstream References
- `external/vercel-ai-sdk/packages/provider/src/file1.ts`
- `external/vercel-ai-sdk/packages/provider/src/file1.test.ts`

---

## Implementation Summary

**Lines of code**: ~XXX lines
**New functions**: X public, Y internal
**Adaptations**: [list any Swift-specific adaptations]

**Key decisions**:
1. [Decision 1 with justification]
2. [Decision 2 with justification]

---

## Pre-Validation Checklist

Executor confirms:
- [x] All public APIs from upstream implemented
- [x] All upstream tests ported (N/N tests)
- [x] Build passes: `swift build` (no warnings)
- [x] Tests pass: `swift test` (X/X passing)
- [x] Upstream references in file headers
- [x] Adaptations documented in code
- [x] No regressions in existing tests

**Test Results**:
```
✔ Test run with X tests passed after Y seconds.
```

---

## Questions for Validator

[Optional section for specific concerns]

1. Question 1?
2. Question 2?

---

## Expected Validation Scope

Please verify:
- [ ] API parity (function signatures, types)
- [ ] Behavior parity (edge cases, error handling)
- [ ] Test coverage (all upstream cases ported)
- [ ] Code quality (upstream references, documentation)
- [ ] Adaptations (justified and documented)

---

**Ready for validation**: ✅ YES

---
**Submitted by**: executor/[model-name]
**UTC**: [timestamp]
```

---

## Validation Report Template

See `.claude/agents/validator.md` for the complete report template used by the validator agent.

**Key sections**:
1. Executive Summary
2. Files Validated
3. API Parity Analysis
4. Behavior Parity Analysis
5. Test Coverage Analysis
6. Issues Found (with severity levels)
7. Recommendations
8. Final Verdict

---

## Severity Levels

| Level | Icon | Description | Action Required |
|-------|------|-------------|-----------------|
| **BLOCKER** | 🔴 | Breaks parity, missing critical functionality | Must fix before merge |
| **MAJOR** | 🟠 | Significant gaps, incomplete implementation | Should fix |
| **MINOR** | 🟡 | Small improvements, non-critical issues | Nice to have |
| **INFO** | 🔵 | Informational, improvements, enhancements | Optional |

---

## Best Practices

### For Executors

✅ **DO**:
- Create detailed validation requests with all context
- List all files explicitly
- Provide upstream references
- Confirm build and tests pass before requesting validation
- Document known adaptations upfront
- Ask specific questions if uncertain

❌ **DON'T**:
- Request validation with failing tests
- Omit upstream references from code
- Leave undocumented adaptations
- Skip the pre-validation checklist
- Rush validation without thorough self-review

### For Validators

✅ **DO**:
- Be thorough - check every public API
- Be strict - require 100% parity
- Be constructive - provide actionable feedback
- Be fair - recognize good Swift adaptations
- Be clear - use severity levels consistently
- Be efficient - focus on critical paths

❌ **DON'T**:
- Accept "close enough" implementations
- Miss edge cases or error scenarios
- Give vague feedback without specific line numbers
- Reject good Swift idioms that maintain parity
- Forget to run tests yourself
- Skip creating the validation report

---

## Integration with Existing Workflow

This custom validator agent **complements** the existing validation process:

### Before (Manual Review)

1. Executor implements feature
2. Executor updates `plan/progress.md`
3. Validator manually reads code
4. Validator creates review in `plan/review-*.md`
5. Review file committed to git

### After (With Custom Agent)

1. Executor implements feature
2. Executor creates request in `.validation/requests/` (temp)
3. **Validator agent automatically reviews** ✨
4. Agent creates report in `.validation/reports/` (temp)
5. Executor fixes issues
6. **Final outcome documented in `plan/progress.md`**
7. Temp files deleted

### Benefits

- ⚡ **Faster** - Agent reviews in minutes
- 🎯 **Consistent** - Same validation criteria every time
- 📝 **Structured** - Standardized report format
- 🔄 **Iterative** - Easy to re-validate after fixes
- 🧹 **Clean** - Temp files don't clutter git history

---

## Examples

### Example 1: Simple Utility Function

**Request**:
```
.validation/requests/validate-delay-function-2025-10-12.md
```

**Agent Action**:
1. Reads request
2. Compares `Delay.swift` vs `delay.ts`
3. Verifies all 8 test cases ported
4. Runs tests
5. Creates report

**Result**:
```
.validation/reports/delay-validation-2025-10-12.md
Status: ✅ APPROVED
```

### Example 2: Complex Type System

**Request**:
```
.validation/requests/validate-language-model-v3-2025-10-12.md
17 type files, 39 tests
```

**Agent Action**:
1. Systematic comparison of all 17 types
2. Checks discriminated union → enum conversion
3. Verifies optional field handling
4. Confirms test coverage
5. Identifies 2 MAJOR issues

**Result**:
```
.validation/reports/v3-validation-2025-10-12.md
Status: ⚠️ ISSUES FOUND
- MAJOR: Missing `preliminary` field in ToolResult
- MAJOR: Usage fields not optional
```

**Resolution**:
1. Executor fixes both issues
2. Re-requests validation
3. Final report: ✅ APPROVED

---

## Automation Opportunities

### Future: Hooks Integration

Consider adding a hook to auto-trigger validation:

```json
// .claude/settings.json
{
  "hooks": {
    "PostToolUse": {
      "Write": {
        "command": "bash",
        "args": ["-c", "if [[ $TOOL_OUTPUT == *'Tests/SwiftAISDKTests'* ]]; then echo 'Tests updated. Consider running validator agent'; fi"]
      }
    }
  }
}
```

### Future: CI Integration

```bash
# In CI pipeline
claude-code --agents validator \
  --prompt "Validate all changes in current PR against upstream"
```

---

## Troubleshooting

### Validator agent not found

**Problem**: "No agent named 'validator' found"

**Solution**:
```bash
# Verify agent file exists
ls -la .claude/agents/validator.md

# Check YAML frontmatter is valid
head -10 .claude/agents/validator.md
```

### Validation request ignored

**Problem**: Agent doesn't read validation request

**Solution**:
- Ensure file is in `.validation/requests/`
- Use explicit command: "Use the validator agent to review [exact path]"
- Check request file has `.md` extension

### Validation takes too long

**Problem**: Agent spending too much time

**Solution**:
- Split large validation requests into smaller chunks
- Be specific about what to validate
- Provide direct file paths instead of "find all files"

---

## Related Documentation

- `CLAUDE.md` - Project agent guide (for executors)
- `plan/executor-guide.md` - Detailed executor workflow
- `plan/validator-guide.md` - Validator checklist (legacy manual process)
- `plan/principles.md` - Porting principles and standards
- `.claude/agents/validator.md` - Validator agent definition

---

## Changelog

### 2025-10-12
- ✨ Created custom validator agent
- ✨ Established `.validation/` directory structure
- ✨ Added `.validation/` to `.gitignore`
- 📝 Documented validation workflow

---

**Remember**: The validator agent is a tool to make validation faster and more consistent. It complements, not replaces, human judgment in architectural decisions.

For questions or improvements, update this document and the validator agent definition.
