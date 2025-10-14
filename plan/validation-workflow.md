# Validation Workflow Guide

> Documentation for using the custom validator agent in Swift AI SDK project

**Last Updated**: 2025-10-12
**Agent**: `.claude/agents/validator.md`

---

## Overview

Validation is now **automation-first**. Executors and validators receive system промты, поддерживают артефакты в `.orchestrator/`, а MCP-сервер сам запускает проверки и повторные итерации. Этот документ описывает автоматический поток и поясняет, когда стоит использовать ручные инструменты как fallback.

## Quick Start

### Automation (default path)

1. **Executor работает** под системным промтом и ведёт `.orchestrator/flow/<executor-id>.json`.
   - После завершения итерации создаёт Markdown-заявку в `.orchestrator/requests/` и ставит `status = "ready_for_validation"`.
2. **Оркестратор замечает обновление** и автоматически:
   - создаёт запись валидации,
   - запускает валидатора в том же worktree,
   - уведомляет валидатора через системный промт, где лежит запрос.
3. **Validator** читает `.orchestrator/requests/…`, выполняет проверку, пишет отчёт в `.orchestrator/reports/…`, обновляет свой flow-файл.
4. **Оркестратор завершает цикл**:
   - `approved` → executor → `validated`, validator → `completed`;
   - `rejected` → executor → `needs_fix`, validator → `completed`, автоматический `continue_agent` запускает новую итерацию.
5. **Blockers** (`status = "needs_input"`) останавливают автоматику до ручного вмешательства.

### Manual override (fallback)

Используйте ручные MCP-инструменты (`request_validation`, `assign_validator`, `submit_validation`, `continue_agent`) только если автоматический процесс сломан или отключён. В этом случае вы можете создавать запросы/отчёты вручную и управлять статусами шаг за шагом (см. раздел Fallback Flow ниже).

---

## Directory Structure

```
swift-ai-sdk/
├── .claude/
│   └── agents/
│       └── validator.md           # Custom validator agent definition
├── .orchestrator/                 # Automation artifacts (gitignored)
│   ├── flow/                      # JSON state files for each agent
│   │   └── executor-000.json
│   ├── requests/                  # Executor-authored validation requests
│   │   └── validate-task-iteration-timestamp.md
│   └── reports/                   # Validator-authored reports
│       └── validate-task-iteration-timestamp-report.md
└── plan/
    ├── validation-workflow.md      # This file
    └── validator-guide.md          # Existing validator checklist
```

### File Organization

| Location | Purpose | Committed? |
|----------|---------|------------|
| `.claude/agents/` | Agent definitions | ✅ Yes |
| `.orchestrator/flow/` | Automation state (executor & validator) | ❌ No (temporary) |
| `.orchestrator/requests/` | Validation requests | ❌ No (temporary) |
| `.orchestrator/reports/` | Validation reports | ❌ No (temporary) |
| `plan/` | Permanent documentation | ✅ Yes |

**Important**: `.orchestrator/` полностью gitignored. Итоги валидации фиксируются в Task Master и `plan/design-decisions.md` (если необходимы), а файлы служат только для автоматизации цикла.

---

## Validation Workflow

### Phase 1: Implementation (Executor)

1. Port TypeScript code to Swift
2. Port all upstream tests
3. Ensure build and tests pass
4. Add upstream references to all files
5. Document adaptations in code comments

### Phase 2: Signal readiness (Executor)

1. Сформируй Markdown-заявку в `.orchestrator/requests/` (шаблон в `plan/orchestrator-automation.md`).
2. Обнови `.orchestrator/flow/<executor-id>.json`:
   - `status = "ready_for_validation"`
   - `request.ready = true`
   - `request.path` — относительный путь к только что созданному файлу.

### Phase 3: Automated validation (Server + Validator Agent)

1. Watcher создаёт запись `validation_sessions`, переводит исполнителя в `blocked` и запускает валидатора (manual worktree).
2. Валидатор читает `.orchestrator/flow/<executor-id>.json` + запрос, анализирует код, запускает тесты.
3. По завершении записывает отчёт в `.orchestrator/reports/…`, обновляет свой flow-файл (`report.path`, `report.result`).
4. Сервер фиксирует вердикт (`approved`/`rejected`).

### Phase 4: Resolution (Executor)

- `approved` → статус исполнителя `validated`, цикл завершён.
- `rejected` → статус `needs_fix`, сервер отправляет follow-up промт через `continue_agent` с указанием отчёта. Исполнитель выполняет исправления, формирует новую заявку и повторяет Phase 2.
- Любой `needs_input` требует ручного вмешательства (уточнить требования/данные, обновить flow-файл).

### Phase 5: Documentation (Both)

1. Executor updates task status in Task Master
2. Validation outcome summarized (not full report)
3. Файлы в `.orchestrator/` остаются как операционные артефакты (gitignored). При необходимости их можно очистить вручную после завершения релиза.

---

## Validation Request Template

> Save this as `.orchestrator/requests/validate-<task>-<iteration>-<timestamp>.md`.

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
**Block**: [Block A/B/C/etc from Task Master]

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
2. Executor updates task status in Task Master
3. Validator manually reads code
4. Validator creates review in `plan/review-*.md`
5. Review file committed to git

### After (With Custom Agent)

1. Executor implements feature
2. Executor формирует запрос в `.orchestrator/requests/` и обновляет flow-файл (`status = ready_for_validation`).
3. **Оркестратор автоматически запускает валидатора и выполняет review** ✨
4. Валидатор пишет отчёт в `.orchestrator/reports/` и обновляет свой flow-файл.
5. Executor фиксит проблемы (если `rejected`)
6. Оркестратор отправляет follow-up промт и ждёт новую итерацию
7. Итог фиксируется в Task Master / `plan/design-decisions.md` при необходимости

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
.orchestrator/requests/validate-delay-function-2025-10-12.md
```

**Agent Action**:
1. Reads request
2. Compares `Delay.swift` vs `delay.ts`
3. Verifies all 8 test cases ported
4. Runs tests
5. Creates report

**Result**:
```
.orchestrator/reports/delay-validation-2025-10-12-report.md
Status: ✅ APPROVED
```

### Example 2: Complex Type System

**Request**:
```
.orchestrator/requests/validate-language-model-v3-2025-10-12.md
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
.orchestrator/reports/v3-validation-2025-10-12-report.md
Status: ⚠️ ISSUES FOUND
- MAJOR: Missing `preliminary` field in ToolResult
- MAJOR: Usage fields not optional
```

**Resolution**:
1. Executor fixes both issues
2. Обновляет flow-файл и создаёт новую заявку (status `ready_for_validation`)
3. Автоматический цикл выполняет повторную проверку → финальный отчёт: ✅ APPROVED

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

**Problem**: Automation не подхватывает заявку

**Solution**:
- Убедись, что файл лежит в `.orchestrator/requests/` и указан в flow-файле (`request.path`, `request.ready = true`).
- Проверь, что flow-файл валиден (minified JSON) и `status = "ready_for_validation"`.
- При необходимости запусти fallback: `request_validation(executor_id)`.

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

### 2025-10-14
- 🤖 Enabled automated executor→validator loop (.orchestrator flow files)
- 📝 Updated documentation to cover automation-first workflow

### 2025-10-12
- ✨ Created custom validator agent
- ✨ Established `.validation/` (legacy) directory structure
- ✨ Added `.validation/` to `.gitignore`
- 📝 Documented initial validation workflow

---

**Remember**: The validator agent is a tool to make validation faster and more consistent. It complements, not replaces, human judgment in architectural decisions.

For questions or improvements, update this document and the validator agent definition.
