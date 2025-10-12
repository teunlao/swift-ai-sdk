# Validation Agent Quick Start

⚡ **Fast guide for using the custom validator agent**

---

## For Executors: Request Validation

### Step 1: Prepare Your Code
```bash
# Ensure everything passes
swift build
swift test
```

### Step 2: Create Validation Request
```bash
# Copy template
cp .validation/requests/EXAMPLE-validation-request.md \
   .validation/requests/validate-my-feature-$(date +%Y-%m-%d).md

# Edit the file with your details
# - List all files to validate
# - Provide upstream references
# - Confirm pre-validation checklist
```

### Step 3: Trigger Validator
In Claude Code chat:
```
Use the validator agent to review .validation/requests/validate-my-feature-2025-10-12.md
```

### Step 4: Review Results
```bash
# Read the validation report
cat .validation/reports/my-feature-validation-2025-10-12.md

# If issues found, fix them and re-request validation
# If approved, document in plan/progress.md and delete temp files
```

---

## Common Commands

### Check if validator agent exists
```bash
ls -la .claude/agents/validator.md
```

### Invoke validator manually
```
Use the validator agent to review [exact path to request]
```

### Alternative: Specify what to validate directly
```
Use the validator agent to validate Sources/SwiftAISDK/ProviderUtils/Delay.swift
against external/vercel-ai-sdk/packages/provider-utils/src/delay.ts
```

---

## Validation Request Template (Minimal)

```markdown
# Validation Request — [Feature]

**Executor**: your-name
**Date**: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Files to Validate
- Implementation: [list]
- Tests: [list]
- Upstream: [list]

## Pre-Validation
- [x] Build passes
- [x] Tests pass (X/X)
- [x] Upstream references added

**Ready**: ✅ YES
```

---

## Expected Timeline

| Task | Duration |
|------|----------|
| Create validation request | 5 minutes |
| Validator agent review | 5-10 minutes |
| Fix issues (if any) | Varies |
| Document outcome | 2 minutes |

---

## Troubleshooting

### "No agent named 'validator'"
```bash
# Verify file exists
cat .claude/agents/validator.md | head -5
```

### Agent doesn't respond
- Check request file is in `.validation/requests/`
- Use exact file path in command
- Ensure request has `.md` extension

### Validation too slow
- Split large requests into smaller chunks
- Be specific about files to validate

---

## Full Documentation

- 📖 `.validation/README.md` - Directory overview
- 📘 `plan/validation-workflow.md` - Complete workflow guide
- 🤖 `.claude/agents/validator.md` - Agent definition
- 📝 `.validation/requests/EXAMPLE-validation-request.md` - Request template
- ✅ `.validation/reports/EXAMPLE-validation-report.md` - Report example

---

**Questions?** See `plan/validation-workflow.md` for detailed documentation.
