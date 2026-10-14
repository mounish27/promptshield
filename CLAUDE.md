# CLAUDE.md — PromptShield
> Read on every session start. Updated by admin.

## Project
PromptShield — AI developer governance: prompt validation, token tracking, PR review, usage dashboard.
Stack: FastAPI, SQLite/PostgreSQL, Node.js CLI, GitHub Pages, Claude API.

## Two human gates — absolute, no bypass
Gate 1: Human approves spec before implementation.
Gate 2: Human approves before production deploy.

## Universal anti-patterns — all blocked
1. Skip deliberation for any reason
2. Skip Gate 1 or Gate 2
3. Refactor during /bugfix
4. Self-merge PRs
5. Modify reproduction tests to pass
6. Combine test: and fix: commits
7. Improve adjacent code during bugfix
8. Silent contradiction of deliberation decisions

## /bugfix TDD rules (mandatory)
1. Write failing reproduction test first
2. Commit with test: prefix separately
3. Minimal fix only
4. Run full test suite
5. Reviewer checks root cause

## Deliberation forbidden phrases
"Sounds good" · "I agree" · "Fair point" · "No objection" · "Absolutely"
