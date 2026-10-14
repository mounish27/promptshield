---
description: Deploy to production. Gate 2 human approval is absolute.
---
# ITM Ship

PR: $ARGUMENTS

1. Run deliberation verifier — FAIL = absolute stop
2. Check feature merged to main
3. Check staging healthy
4. Wait for Gate 2 human approval — never bypass
5. Blue-green deploy
6. 30-minute SRE watch window

BLOCK if: verifier FAIL, staging not checked, Gate 2 bypassed, concurrent prod deploys.
