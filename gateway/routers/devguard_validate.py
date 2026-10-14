"""DevGuard validation — L1 local fast-path + L2 remote via Claude API."""
import re, os
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel
from anthropic import AsyncAnthropic  # P0-FIX-2: async client — never block event loop

router = APIRouter()

# ── L1 rules — instant, no network ──────────────────────────────────────────
HARD_BLOCKS = [
    {"re": re.compile(r"while\s+you'?re?\s+(there|at it)|while\s+you\s+are\s+at\s+it", re.I), "rule": "L1-007", "msg": "Scope creep — 'while you're there'. One change per prompt.", "level": "L1"},
    {"re": re.compile(r"skip\s+(the\s+)?(deliberation|gate\s*[12])", re.I), "rule": "L2-K002", "msg": "Gate bypass — deliberation and gates are mandatory.", "level": "L2"},
    {"re": re.compile(r"bypass\s+gate|override\s+gate", re.I),         "rule": "L2-S005", "msg": "Gate bypass — absolute rule, no exceptions.", "level": "L2"},
    {"re": re.compile(r"merge\s+(it\s+)?myself|auto.merge", re.I),     "rule": "L2-I009", "msg": "Self-merge bypass — PRs always need a reviewer.", "level": "L2"},
    {"re": re.compile(r"deploy\s+to\s+prod(?!uction\s+deploy\s+workflow)", re.I), "rule": "L2-S005", "msg": "Direct prod deploy without /ship is blocked.", "level": "L2"},
    {"re": re.compile(r"and\s+anything\s+else|fix\s+all\s+the\s+issues", re.I), "rule": "L1-007", "msg": "Unbounded scope — one verifiable outcome per prompt.", "level": "L1"},
    {"re": re.compile(r"change\s+the\s+test|modify\s+the\s+assertion", re.I), "rule": "L3-BF004", "msg": "Test manipulation — fix production code, not the test.", "level": "L3"},
]

WARN_PATTERNS = [
    {"re": re.compile(r"make\s+it\s+better(?!\s+by)", re.I), "rule": "L1-008", "msg": "Vague outcome — specify the measurable improvement."},
    {"re": re.compile(r"\brefactor\b|\bclean\s+up\b|\breorganize\b", re.I), "rule": "L2-BF003", "msg": "Refactoring in /bugfix? Needs a separate /enhance story."},
]

def extract_prompt_from_messages(body: dict) -> str:
    """Extract the latest user message from an Anthropic /v1/messages request body."""
    messages = body.get("messages") or []
    for msg in reversed(messages):
        if msg.get("role") != "user":
            continue
        content = msg.get("content", "")
        if isinstance(content, str):
            text = content.strip()
            if text:
                return text
        if isinstance(content, list):
            parts = []
            for block in content:
                if isinstance(block, dict):
                    if block.get("type") == "text" and block.get("text"):
                        parts.append(str(block["text"]))
                    elif block.get("text"):
                        parts.append(str(block["text"]))
                elif isinstance(block, str):
                    parts.append(block)
            text = " ".join(parts).strip()
            if text:
                return text
        if content:
            return str(content).strip()
    return ""


def validate_prompt_local(prompt: str) -> dict:
    if not prompt:
        return {"verdict": "PASS"}
    for b in HARD_BLOCKS:
        if b["re"].search(prompt):
            return {"verdict": "BLOCK", "rule": b["rule"], "msg": b["msg"], "level": b["level"]}
    for w in WARN_PATTERNS:
        if w["re"].search(prompt):
            return {"verdict": "WARN", "rule": w["rule"], "msg": w["msg"]}
    return {"verdict": "PASS"}

# ── L2 remote — uses Claude to validate against full ITM rules ────────────────
L2_SYSTEM = """You are DevGuard, ITM SDLC prompt governance. Validate the developer prompt.
Return ONLY raw JSON:
{
  "verdict": "PASS"|"WARN"|"BLOCK",
  "rule": "rule-id or null",
  "problem": "specific description or null",
  "corrected_prompt": "corrected version or null",
  "out_of_scope": []
}

BLOCK on: skip deliberation, skip gate, self-merge, deploy to prod without /ship,
          refactor during /bugfix, change test assertions, unbounded scope, gate bypasses.
WARN on: vague outcomes, missing file paths, implicit scope.
PASS on: well-formed ITM slash commands with specific arguments."""

async def validate_prompt_remote(prompt: str) -> dict | None:
    try:
        # P0-FIX-2: AsyncAnthropic + await — does NOT block the event loop
        client = AsyncAnthropic(api_key=os.getenv("ANTHROPIC_API_KEY", ""))
        resp = await client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=300,
            system=L2_SYSTEM,
            messages=[{"role": "user", "content": f"Validate:\n\n{prompt}"}],
        )
        import json
        text = resp.content[0].text.replace("```json", "").replace("```", "").strip()
        return json.loads(text)
    except Exception:
        return None

# ── API endpoint ──────────────────────────────────────────────────────────────
class ValidateRequest(BaseModel):
    prompt: str
    level: str = "L1+L2"

@router.post("/devguard/validate")
async def validate(req: ValidateRequest, authorization: str = Header(default="")):
    # L1 always runs
    result = validate_prompt_local(req.prompt)
    if result["verdict"] == "BLOCK":
        return result

    # L2 on request if gateway has API key
    if "L2" in req.level and os.getenv("ANTHROPIC_API_KEY"):
        remote = await validate_prompt_remote(req.prompt)
        if remote and remote.get("verdict") in ("BLOCK", "WARN"):
            return remote

    return result
