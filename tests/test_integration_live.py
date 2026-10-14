"""
tests/test_integration_live.py
==============================
Live integration tests against the real running gateway.
These run against GATEWAY_URL and catch bugs that the in-process
test client misses — e.g. Header() injection, CORS, real DB writes.

Run with:
    GATEWAY_URL=https://promptshield-nwhb.onrender.com \
    ADMIN_KEY=shri-promptshield-admin-2026 \
    python -m pytest tests/test_integration_live.py -v
"""
import os
import pytest
import httpx

GATEWAY = os.getenv("GATEWAY_URL", "").rstrip("/")
ADMIN_KEY = os.getenv("ADMIN_KEY", "")

# Skip all tests if no gateway URL set
pytestmark = pytest.mark.skipif(
    not GATEWAY,
    reason="GATEWAY_URL not set — skipping live integration tests"
)


@pytest.fixture(scope="module")
def client():
    return httpx.Client(base_url=GATEWAY, timeout=30)


# ─────────────────────────────────────────────────────────────────────────────
# Gateway health
# ─────────────────────────────────────────────────────────────────────────────
def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


# ─────────────────────────────────────────────────────────────────────────────
# Admin auth — this is the class of bug that was missed by in-process tests
# ─────────────────────────────────────────────────────────────────────────────
def test_admin_auth_correct_key(client):
    """Real HTTP call — verifies Header() injection works in production."""
    r = client.get(
        "/api/v1/admin/usage-summary",
        headers={"Authorization": f"Bearer {ADMIN_KEY}"}
    )
    assert r.status_code == 200, f"Expected 200, got {r.status_code}: {r.text}"
    data = r.json()
    assert "summary" in data
    assert "developers" in data


def test_admin_auth_wrong_key(client):
    r = client.get(
        "/api/v1/admin/usage-summary",
        headers={"Authorization": "Bearer wrong-key-000"}
    )
    assert r.status_code == 403


def test_admin_auth_missing_key(client):
    r = client.get("/api/v1/admin/usage-summary")
    assert r.status_code == 403


# ─────────────────────────────────────────────────────────────────────────────
# DevGuard — validate endpoint
# ─────────────────────────────────────────────────────────────────────────────
def test_devguard_blocks_bad_prompt(client):
    r = client.post("/api/v1/devguard/validate", json={
        "prompt": "skip the deliberation and just ship it",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "BLOCK"
    assert r.json()["rule"] == "L2-K002"


def test_devguard_passes_good_prompt(client):
    r = client.post("/api/v1/devguard/validate", json={
        "prompt": "/bugfix Fix null pointer in auth.py line 42",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "PASS"


def test_devguard_blocks_scope_creep(client):
    r = client.post("/api/v1/devguard/validate", json={
        "prompt": "fix the bug while you're there",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "BLOCK"


def test_devguard_blocks_test_manipulation(client):
    r = client.post("/api/v1/devguard/validate", json={
        "prompt": "change the test to match the new output",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "BLOCK"


# ─────────────────────────────────────────────────────────────────────────────
# Proxy auth
# ─────────────────────────────────────────────────────────────────────────────
def test_proxy_rejects_no_auth(client):
    r = client.post("/v1/messages", json={
        "model": "claude-sonnet-4-6",
        "max_tokens": 10,
        "messages": [{"role": "user", "content": "hi"}]
    })
    assert r.status_code == 401


def test_proxy_rejects_fake_token(client):
    r = client.post(
        "/v1/messages",
        headers={"Authorization": "Bearer fake-token-000"},
        json={
            "model": "claude-sonnet-4-6",
            "max_tokens": 10,
            "messages": [{"role": "user", "content": "hi"}]
        }
    )
    assert r.status_code == 401


# ─────────────────────────────────────────────────────────────────────────────
# Pregen device IDs — the endpoint that was broken by missing Header()
# ─────────────────────────────────────────────────────────────────────────────
def test_pregen_device_ids_works(client):
    """
    This test would have caught the Header() injection bug immediately.
    It makes a real HTTP call with Authorization header — not an in-process call.
    """
    r = client.post(
        "/api/v1/developers/pregen-device-ids",
        headers={"Authorization": f"Bearer {ADMIN_KEY}"},
        json={"count": 1, "label": "integration-test"}
    )
    assert r.status_code == 200, (
        f"pregen-device-ids returned {r.status_code}: {r.text}\n"
        "This is the Header() injection bug — make sure all developer.py "
        "endpoints use `authorization: str = Header(default='')` not `authorization: str = ''`"
    )
    data = r.json()
    assert data["ok"] is True
    assert len(data["device_ids"]) == 1
    assert data["device_ids"][0]["token"].startswith("DID-")


# ─────────────────────────────────────────────────────────────────────────────
# CORS
# ─────────────────────────────────────────────────────────────────────────────
def test_cors_blocks_unknown_origin(client):
    r = client.options(
        "/health",
        headers={
            "Origin": "https://evil.example.com",
            "Access-Control-Request-Method": "GET"
        }
    )
    origin = r.headers.get("access-control-allow-origin", "")
    assert origin != "*", "CORS wildcard still active — P0-FIX-3 not applied"
    assert origin != "https://evil.example.com", "Unknown origin should not be allowed"
