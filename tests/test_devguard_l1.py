"""
tests/test_devguard_l1.py
=========================
Unit tests for DevGuard L1 local regex validation.

These are ZERO-network, ZERO-DB tests — pure logic.
They run in milliseconds and catch regressions in the rule set immediately.

TDD approach: each rule has a BLOCK case, a PASS case, and an edge case.
"""
import pytest
from gateway.routers.devguard_validate import validate_prompt_local


# ─────────────────────────────────────────────────────────────────────────────
# Helper
# ─────────────────────────────────────────────────────────────────────────────
def assert_block(prompt: str, expected_rule: str):
    result = validate_prompt_local(prompt)
    assert result["verdict"] == "BLOCK", (
        f"Expected BLOCK for {prompt!r}, got {result['verdict']}"
    )
    assert result["rule"] == expected_rule, (
        f"Expected rule {expected_rule}, got {result['rule']}"
    )

def assert_pass(prompt: str):
    result = validate_prompt_local(prompt)
    assert result["verdict"] in ("PASS", "WARN"), (
        f"Expected PASS/WARN for {prompt!r}, got BLOCK (rule={result.get('rule')})"
    )

def assert_warn(prompt: str, expected_rule: str):
    result = validate_prompt_local(prompt)
    assert result["verdict"] == "WARN", (
        f"Expected WARN for {prompt!r}, got {result['verdict']}"
    )
    assert result["rule"] == expected_rule


# ─────────────────────────────────────────────────────────────────────────────
# L1-007 Scope creep — "while you're there"
# ─────────────────────────────────────────────────────────────────────────────
class TestScopeCreepWhileThere:
    def test_blocks_while_youre_there(self):
        assert_block("Fix the login bug while you're there", "L1-007")

    def test_blocks_while_you_are_at_it(self):
        assert_block("add logging while you are at it", "L1-007")

    def test_blocks_case_insensitive(self):
        assert_block("WHILE YOU'RE THERE also fix the typos", "L1-007")

    def test_pass_unrelated_sentence(self):
        assert_pass("Fix the login bug in auth.py — the token check fails on empty strings")

    def test_pass_there_in_different_context(self):
        # "there" alone should not trigger
        assert_pass("There is a bug in auth.py, please fix it")


# ─────────────────────────────────────────────────────────────────────────────
# L2-K002 Gate bypass — skip deliberation
# ─────────────────────────────────────────────────────────────────────────────
class TestSkipDeliberation:
    def test_blocks_skip_deliberation(self):
        assert_block("skip the deliberation and just implement it", "L2-K002")

    def test_blocks_skip_gate1(self):
        assert_block("skip gate 1 for now", "L2-K002")

    def test_blocks_skip_gate2(self):
        assert_block("skip gate2 this time", "L2-K002")

    def test_pass_normal_implement(self):
        assert_pass("/implement Fix the null pointer in UserService.java line 42")

    def test_pass_word_gate_in_other_context(self):
        # "gateway" should not match "gate"
        assert_pass("Configure the API gateway timeout to 30s")


# ─────────────────────────────────────────────────────────────────────────────
# L2-S005 Gate bypass — bypass/override gate
# ─────────────────────────────────────────────────────────────────────────────
class TestBypassOverrideGate:
    def test_blocks_bypass_gate(self):
        assert_block("bypass gate and deploy to staging", "L2-S005")

    def test_blocks_override_gate(self):
        assert_block("override gate for this hotfix", "L2-S005")

    def test_pass_no_gate_mention(self):
        assert_pass("Deploy to staging via the /ship workflow")


# ─────────────────────────────────────────────────────────────────────────────
# L2-I009 Self-merge bypass
# ─────────────────────────────────────────────────────────────────────────────
class TestSelfMerge:
    def test_blocks_merge_myself(self):
        assert_block("I'll merge it myself once tests pass", "L2-I009")

    def test_blocks_merge_it_myself(self):
        assert_block("just merge it myself", "L2-I009")

    def test_blocks_automerge(self):
        assert_block("enable auto-merge on this PR", "L2-I009")

    def test_pass_normal_pr(self):
        assert_pass("Create a PR for the login fix and assign to @alice for review")


# ─────────────────────────────────────────────────────────────────────────────
# L2-S005 Direct prod deploy
# ─────────────────────────────────────────────────────────────────────────────
class TestDirectProdDeploy:
    def test_blocks_deploy_to_prod(self):
        assert_block("deploy to prod now", "L2-S005")

    def test_blocks_deploy_to_prod_urgently(self):
        assert_block("deploy to prod urgently, it's critical", "L2-S005")

    def test_pass_ship_workflow(self):
        # The negative lookahead allows "production deploy workflow"
        assert_pass("run the production deploy workflow via /ship")

    def test_pass_staging_deploy(self):
        assert_pass("deploy to staging for QA review")


# ─────────────────────────────────────────────────────────────────────────────
# L1-007 Unbounded scope
# ─────────────────────────────────────────────────────────────────────────────
class TestUnboundedScope:
    def test_blocks_and_anything_else(self):
        assert_block("fix the bug and anything else you notice", "L1-007")

    def test_blocks_fix_all_the_issues(self):
        assert_block("please fix all the issues in this file", "L1-007")

    def test_pass_specific_fix(self):
        assert_pass("Fix the NullPointerException in UserService.java line 84")


# ─────────────────────────────────────────────────────────────────────────────
# L3-BF004 Test manipulation
# ─────────────────────────────────────────────────────────────────────────────
class TestTestManipulation:
    def test_blocks_change_the_test(self):
        assert_block("change the test to match the new output", "L3-BF004")

    def test_blocks_modify_assertion(self):
        assert_block("modify the assertion to expect 200 instead", "L3-BF004")

    def test_pass_fix_production_code(self):
        assert_pass("Fix UserService.java so the existing test passes")


# ─────────────────────────────────────────────────────────────────────────────
# WARN patterns
# ─────────────────────────────────────────────────────────────────────────────
class TestWarnPatterns:
    def test_warns_make_it_better(self):
        assert_warn("make it better", "L1-008")

    def test_pass_make_it_better_with_by(self):
        # "make it better by" is specific enough — should not warn
        assert_pass("make it better by adding input validation on the email field")

    def test_warns_refactor(self):
        assert_warn("refactor the auth module", "L2-BF003")

    def test_warns_clean_up(self):
        assert_warn("clean up the service layer", "L2-BF003")

    def test_warns_reorganize(self):
        assert_warn("reorganize the folder structure", "L2-BF003")


# ─────────────────────────────────────────────────────────────────────────────
# Edge cases
# ─────────────────────────────────────────────────────────────────────────────
class TestEdgeCases:
    def test_empty_string_passes(self):
        result = validate_prompt_local("")
        assert result["verdict"] == "PASS"

    def test_none_like_empty_passes(self):
        # validate_prompt_local guards against falsy input
        result = validate_prompt_local("")
        assert result["verdict"] == "PASS"

    def test_block_takes_priority_over_warn(self):
        # A prompt that matches both a BLOCK and a WARN rule: BLOCK wins
        prompt = "refactor the auth module and skip the deliberation"
        result = validate_prompt_local(prompt)
        assert result["verdict"] == "BLOCK"

    def test_first_block_rule_wins(self):
        # Multiple block patterns in one prompt — first match returned
        prompt = "while you're there also skip gate 1"
        result = validate_prompt_local(prompt)
        assert result["verdict"] == "BLOCK"
        assert result["rule"] == "L1-007"   # first in HARD_BLOCKS list

    def test_well_formed_slash_command_passes(self):
        assert_pass("/bugfix Fix 401 returned from POST /api/login when password contains special chars; repro: curl with password='abc!@#'")

    def test_well_formed_implement_passes(self):
        assert_pass("/implement Add rate limiting to /api/v1/messages — 100 req/min per developer token, return 429 with Retry-After header")
