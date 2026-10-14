---
description: Fix a bug TDD-first. Failing test before any production code change. Offers review when done.
---
# ITM Bugfix

Bug: $ARGUMENTS

Step 1: Write failing reproduction test (named for the bug behaviour)
Step 2: Commit test separately — git commit -m "test: reproduce <slug>"
Step 3: Minimal fix only — no refactoring, no adjacent code
Step 4: Run full test suite
Step 5: Code-reviewer checks root cause

BLOCK if: test not written first, refactor in same PR, adjacent code changed, test modified to pass, test+fix in same commit.

---

## When fix is complete — ALWAYS ask:

```
┌─────────────────────────────────────────────────────────────┐
│  ✓ Bug fix complete                                          │
│                                                              │
│  Do you want to run a PromptShield code review?             │
│                                                              │
│  Checks: root cause depth · TDD chain · no scope creep      │
│  Logs report to .promptshield/ and your dashboard           │
│                                                              │
│  [Y] Run review now    [N] Skip                             │
└─────────────────────────────────────────────────────────────┘
```

If YES → run /review automatically.
If NO  → remind: "Run /review any time before opening your PR."
