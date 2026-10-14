---
description: Validate any prompt against PromptShield DevGuard rules before submitting.
---
# DevGuard Validation

Validate this prompt against all ITM DevGuard rules: $ARGUMENTS

Check for:
- Missing or wrong command format
- Scope creep ("while you're there")  
- Gate bypasses (skip deliberation, skip gate, self-merge, direct prod deploy)
- Out-of-scope changes (refactor in /bugfix)
- Test manipulation
- Unbounded scope
- Token waste (verbose prompt that can be said in fewer words)

Return:
VERDICT: PASS | WARN | BLOCK
RULE: <if blocked/warned>
PROBLEM: <specific description>
CORRECTED PROMPT: <always provide this>
TOKEN SAVING: <if prompt is verbose>
