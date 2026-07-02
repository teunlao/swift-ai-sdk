# Generated Artifacts

Generated upstream parity artifacts are local working state. They help plan and
triage work, but they are not durable evidence and must not be committed.

## Root

Use `.upstream/` at the repository root.

Recommended layout:

```text
.upstream/
  current/
    component-catalog.json
    component-catalog.md
  refresh-<yyyy-mm-dd>/
    package-diff.json
    package-diff.md
    work-queue.md
```

## What Belongs Here

- Generated package/component catalogs.
- Diff snapshots between pinned and candidate upstream commits.
- Work queues produced from scans.
- Scratch notes from a parity intake pass.
- Temporary machine-readable JSON used to drive audits.

## What Does Not Belong Here

- Durable parity conclusions.
- Test fixtures used by CI.
- Source files or generated Swift code.
- Documentation pages for the public docs site.
- Anything required for a fresh clone to build or test.

## Promotion Rule

If a generated artifact contains a durable conclusion, promote the conclusion to
one of:

- `upstream/UPSTREAM.md`
- `upstream/PROGRESS.md`
- `upstream/providers/<provider>.md`
- `plan/design-decisions.md`

Then keep the generated artifact local.
