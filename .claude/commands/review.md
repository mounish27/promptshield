---
description: Run Claude code review skill after a coding session. Reviews what was changed, checks deliberation alignment, logs the report. Always offered at end of /implement and /bugfix.
---

# PromptShield Code Review

Reviewing: $ARGUMENTS

## What this does
Runs a structured code review on everything changed in this session.
Logs the report to PromptShield so you can see it in the dashboard.
Checks deliberation alignment — did the implementation match the decisions?

## Step 1 — Collect what changed

```bash
# Get the diff of everything changed in this session
git diff HEAD
git diff --staged
git status
```

If a story file was given as argument, also read:
- `specs/<slug>/stories/<n>-<name>.md` — acceptance criteria
- `.deliberation/<slug>/decision.md` — what was decided

## Step 2 — Run the review across 5 dimensions

For each file changed, evaluate:

### Dimension 1 — Deliberation alignment
- Does this implementation match the DECISION line from decision.md?
- Was any rejected alternative accidentally implemented?
- If deviating from deliberation: is it documented in the code or PR?

Verdict: ALIGNED | DEVIATION (documented) | CONTRADICTION (blocked)

### Dimension 2 — Acceptance criteria coverage
- Read every Given/When/Then from the story file
- Is each criterion covered by the implementation?
- Are there missing test cases?

Verdict: COMPLETE | PARTIAL (list missing) | MISSING

### Dimension 3 — Code quality
Check for:
- Hardcoded values that should be config
- Missing error handling on network/IO calls
- Console.log / debug statements left in
- TODOs added (not pre-existing)
- Functions over 40 lines (complexity warning)
- Duplicate logic that already exists elsewhere

Verdict: PASS | WARN (list issues) | FAIL

### Dimension 4 — Security
Check for:
- Secrets or API keys in code (BLOCK)
- SQL injection risk (unparameterised queries)
- User input used without validation
- Sensitive data logged

Verdict: PASS | WARN | BLOCK

### Dimension 5 — Test coverage
- Is there a test for the main happy path?
- Is there a test for the main failure/error case?
- For /bugfix: is the reproduction test present and committed separately?

Verdict: COMPLETE | PARTIAL | MISSING

## Step 3 — Produce the review report

Format:
```
## PromptShield Code Review
Session: <timestamp>
Developer: <from CLAUDE.md or config>
Story: <if applicable>

### Summary
Verdict: PASS | WARN | BLOCK
Files reviewed: N
Issues found: N (N blocking, N warnings)

### Deliberation alignment
Status: ALIGNED | DEVIATION | CONTRADICTION
<detail>

### Acceptance criteria
Status: COMPLETE | PARTIAL | MISSING
Missing: <list if any>

### Code quality
Status: PASS | WARN | FAIL
Issues:
- <file>:<line> — <issue>

### Security
Status: PASS | WARN | BLOCK
Issues:
- <detail if any>

### Test coverage
Status: COMPLETE | PARTIAL | MISSING
Missing:
- <test case description>

### Recommended next steps
1. <most important action>
2. <second action>
```

## Step 4 — Log the report

Write the report to `.promptshield/review-<timestamp>.md` in the project:

```bash
mkdir -p .promptshield
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
cat > .promptshield/review-${TIMESTAMP}.md << REPORT
<paste full review report here>
REPORT
```

Also send to gateway for dashboard visibility:

```bash
node ~/.devguard/bin/usage-reporter.js --type review --report .promptshield/review-${TIMESTAMP}.md
```

## Step 5 — Show summary to developer

Print a clean summary:
```
┌─ PromptShield Review Complete ──────────────────────────
│ Verdict:        PASS | WARN | BLOCK
│ Files reviewed: N
│ Issues:         N blocking · N warnings
│ Report saved:   .promptshield/review-<timestamp>.md
│
│ <if BLOCK>: Fix these before opening the PR:
│   - <blocking issue 1>
│   - <blocking issue 2>
└──────────────────────────────────────────────────────────
```

## When to run

This command runs automatically at the end of:
- `/implement` — after pre-flight checks pass
- `/bugfix` — after full test suite passes
- `/enhance` — after delta implementation

Or manually any time:
```
/review
/review specs/auth/stories/001-login.md
```

## Hard stops

- BLOCK on security issues (secrets in code, unvalidated SQL injection)
- BLOCK on deliberation contradiction (implementation contradicts decision record without documentation)
- Report is always saved regardless of verdict — logs are permanent
