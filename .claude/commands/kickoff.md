---
description: Start a new feature with 4-role deliberation. Deliberation runs FIRST.
---
# ITM Kickoff

Feature: $ARGUMENTS

Run deliberation engine first:
```bash
node deliberation/cli.js --proposal "$ARGUMENTS" --criteria "Testable,Maintainable,Secure,User value proven" --slug "<slug>"
```

Then: spec bundle (brief + PRD + architecture + stories + wireframes + risk-log) → verifier PASS → Gate 1 PR.

BLOCK if: deliberation skipped, spec contradicts deliberation, no observable acceptance criteria, PR opened with FAIL verification.
