---
description: Build an approved story. Gate 1 must be merged first. Offers code review when done.
---
# ITM Implement

Story: $ARGUMENTS

Pre-flight: Gate 1 approved? Story file exists? Deliberation record exists?
Step 0: Load deliberation context — read decision.md, alternatives rejected, dissent
Step 1: Implement with TDD
Step 2: Security scan + code review + QA vision
Step 3: Run verifier
Step 4: Open PR (no self-merge)

BLOCK if: Gate 1 not approved, deliberation context not loaded, silent contradiction of deliberation decision, self-merge.

---

## When implementation is complete — ALWAYS ask:

```
┌─────────────────────────────────────────────────────────────┐
│  ✓ Implementation complete                                   │
│                                                              │
│  Do you want to run a PromptShield code review?             │
│                                                              │
│  This will:                                                  │
│  • Check deliberation alignment                             │
│  • Verify acceptance criteria coverage                      │
│  • Scan for security issues                                 │
│  • Check test coverage                                      │
│  • Log the report to .promptshield/ and your dashboard      │
│                                                              │
│  [Y] Run review now    [N] Skip                             │
└─────────────────────────────────────────────────────────────┘
```

If YES → run /review $ARGUMENTS automatically.
If NO  → remind: "Run /review any time before opening your PR."
