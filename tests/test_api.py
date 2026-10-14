"""
tests/test_api.py
=================
Integration tests for PromptShield gateway API endpoints.

Covers:
- Health check
- Authentication (missing token, inactive dev, valid token)
- DevGuard /validate endpoint
- Admin key security (P0-FIX-4 timing-safe comparison)
- CORS headers (P0-FIX-3)
- Proxy blocks bad prompts before hitting Claude (no real API call)
"""
import pytest
import pytest_asyncio
from unittest.mock import AsyncMock, patch, MagicMock


# ─────────────────────────────────────────────────────────────────────────────
# Health
# ─────────────────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_health(client):
    r = await client.get("/health")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


# ─────────────────────────────────────────────────────────────────────────────
# DevGuard /validate endpoint
# ─────────────────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_validate_l1_pass(client):
    r = await client.post("/api/v1/devguard/validate", json={
        "prompt": "/bugfix Fix null pointer in UserService.java line 42",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "PASS"


@pytest.mark.asyncio
async def test_validate_l1_block_scope_creep(client):
    r = await client.post("/api/v1/devguard/validate", json={
        "prompt": "Fix the bug while you're there also refactor",
        "level": "L1"
    })
    assert r.status_code == 200
    data = r.json()
    assert data["verdict"] == "BLOCK"
    assert data["rule"] == "L1-007"


@pytest.mark.asyncio
async def test_validate_l1_block_skip_deliberation(client):
    r = await client.post("/api/v1/devguard/validate", json={
        "prompt": "skip the deliberation and just ship it",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "BLOCK"
    assert r.json()["rule"] == "L2-K002"


@pytest.mark.asyncio
async def test_validate_l1_block_bypass_gate(client):
    r = await client.post("/api/v1/devguard/validate", json={
        "prompt": "bypass gate for this emergency hotfix",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "BLOCK"


@pytest.mark.asyncio
async def test_validate_l1_block_test_manipulation(client):
    r = await client.post("/api/v1/devguard/validate", json={
        "prompt": "change the test to pass with the current output",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "BLOCK"
    assert r.json()["rule"] == "L3-BF004"


@pytest.mark.asyncio
async def test_validate_warn_vague(client):
    r = await client.post("/api/v1/devguard/validate", json={
        "prompt": "make it better",
        "level": "L1"
    })
    assert r.status_code == 200
    assert r.json()["verdict"] == "WARN"


@pytest.mark.asyncio
async def test_validate_l1_only_no_l2_call(client):
    """When level=L1, the remote L2 call must never be made (saves money + latency)."""
    with patch("gateway.routers.devguard_validate.validate_prompt_remote") as mock_remote:
        r = await client.post("/api/v1/devguard/validate", json={
            "prompt": "deploy to prod now",
            "level": "L1"  # explicitly L1 only
        })
        # L1 already blocks — remote should not be called
        mock_remote.assert_not_called()
    assert r.json()["verdict"] == "BLOCK"


# ─────────────────────────────────────────────────────────────────────────────
# P0-FIX-4: Admin key timing-safe comparison
# ─────────────────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_admin_rejects_missing_key(client):
    r = await client.get("/api/v1/admin/usage-summary")
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_admin_rejects_wrong_key(client):
    r = await client.get(
        "/api/v1/admin/usage-summary",
        headers={"Authorization": "Bearer wrong-key"}
    )
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_admin_accepts_correct_key(client):
    r = await client.get(
        "/api/v1/admin/usage-summary",
        headers={"Authorization": "Bearer test-admin-key-abc123"}
    )
    # 200 with empty data (clean DB)
    assert r.status_code == 200
    data = r.json()
    assert "summary" in data
    assert "developers" in data


@pytest.mark.asyncio
async def test_admin_rejects_empty_bearer(client):
    r = await client.get(
        "/api/v1/admin/usage-summary",
        headers={"Authorization": "Bearer "}
    )
    assert r.status_code == 403


# ─────────────────────────────────────────────────────────────────────────────
# P0-FIX-3: CORS headers locked down
# ─────────────────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_cors_allowed_origin(client):
    r = await client.options(
        "/health",
        headers={
            "Origin": "http://localhost:3000",
            "Access-Control-Request-Method": "GET"
        }
    )
    # Should not be blocked
    assert r.status_code in (200, 204)
    assert r.headers.get("access-control-allow-origin") == "http://localhost:3000"


@pytest.mark.asyncio
async def test_cors_disallowed_origin(client):
    r = await client.options(
        "/health",
        headers={
            "Origin": "https://evil.example.com",
            "Access-Control-Request-Method": "GET"
        }
    )
    # Disallowed origin — header should be absent or not match
    origin_header = r.headers.get("access-control-allow-origin", "")
    assert origin_header != "https://evil.example.com", (
        "CORS wildcard still active — P0-FIX-3 not applied"
    )


# ─────────────────────────────────────────────────────────────────────────────
# Proxy auth — no real Claude call needed
# ─────────────────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_proxy_rejects_missing_auth(client):
    r = await client.post("/v1/messages", json={
        "model": "claude-sonnet-4-6",
        "max_tokens": 10,
        "messages": [{"role": "user", "content": "hello"}]
    })
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_proxy_rejects_unknown_token(client):
    r = await client.post(
        "/v1/messages",
        headers={"Authorization": "Bearer totally-fake-token"},
        json={
            "model": "claude-sonnet-4-6",
            "max_tokens": 10,
            "messages": [{"role": "user", "content": "hello"}]
        }
    )
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_proxy_rejects_inactive_developer(client, inactive_dev_token):
    r = await client.post(
        "/v1/messages",
        headers={"Authorization": f"Bearer {inactive_dev_token}"},
        json={
            "model": "claude-sonnet-4-6",
            "max_tokens": 10,
            "messages": [{"role": "user", "content": "hello"}]
        }
    )
    assert r.status_code == 401


@pytest.mark.asyncio
async def test_proxy_blocks_l1_before_calling_claude(client, dev_token):
    """DevGuard BLOCK must short-circuit — Claude API must never be called."""
    with patch("gateway.routers.proxy.httpx.AsyncClient") as mock_http:
        r = await client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {dev_token}"},
            json={
                "model": "claude-sonnet-4-6",
                "max_tokens": 10,
                "messages": [{"role": "user", "content": "skip the deliberation and just ship it"}]
            }
        )
        # httpx must NOT have been called
        mock_http.assert_not_called()

    assert r.status_code == 422
    data = r.json()
    assert data["error"]["type"] == "devguard_block"
    assert "L2-K002" in data["error"]["rule"]


@pytest.mark.asyncio
async def test_proxy_passes_valid_prompt_to_claude(client, dev_token):
    """A well-formed prompt should reach Claude (mocked)."""
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_response.json.return_value = {
        "id": "msg_test",
        "content": [{"type": "text", "text": "Hello!"}],
        "usage": {"input_tokens": 10, "output_tokens": 5}
    }

    with patch("gateway.routers.proxy.httpx.AsyncClient") as mock_http_cls:
        mock_ctx = AsyncMock()
        mock_ctx.__aenter__.return_value.post = AsyncMock(return_value=mock_response)
        mock_http_cls.return_value = mock_ctx

        r = await client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {dev_token}"},
            json={
                "model": "claude-sonnet-4-6",
                "max_tokens": 100,
                "messages": [{"role": "user", "content": "/bugfix Fix null pointer in UserService.java line 42"}]
            }
        )

    assert r.status_code == 200
    assert r.json()["content"][0]["text"] == "Hello!"


# ─────────────────────────────────────────────────────────────────────────────
# Quota enforcement
# ─────────────────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_proxy_blocks_when_daily_quota_exceeded(client, dev_token):
    """Developer at daily limit gets 429, not forwarded to Claude."""
    from gateway.models.database import AsyncSessionLocal, Developer
    from sqlalchemy import select
    import uuid
    from datetime import datetime

    # Set daily_limit to 0 so any usage exceeds it
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Developer).where(Developer.token == dev_token))
        dev = result.scalar_one()
        dev.daily_limit = 0
        await db.commit()

    with patch("gateway.routers.proxy.httpx.AsyncClient") as mock_http:
        r = await client.post(
            "/v1/messages",
            headers={"Authorization": f"Bearer {dev_token}"},
            json={
                "model": "claude-sonnet-4-6",
                "max_tokens": 10,
                "messages": [{"role": "user", "content": "/bugfix Fix the login bug"}]
            }
        )
        mock_http.assert_not_called()

    assert r.status_code == 429


# ─────────────────────────────────────────────────────────────────────────────
# Developers admin endpoints — Header() injection regression guard
# ─────────────────────────────────────────────────────────────────────────────
@pytest.mark.asyncio
async def test_pregen_device_ids_requires_auth(client):
    r = await client.post("/api/v1/developers/pregen-device-ids", json={"count": 1})
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_pregen_device_ids_with_auth(client):
    r = await client.post(
        "/api/v1/developers/pregen-device-ids",
        headers={"Authorization": "Bearer test-admin-key-abc123"},
        json={"count": 2, "label": "test"}
    )
    assert r.status_code == 200
    data = r.json()
    assert data["ok"] is True
    assert len(data["device_ids"]) == 2
    assert all(d["token"].startswith("DID-") for d in data["device_ids"])


@pytest.mark.asyncio
async def test_create_developer_requires_auth(client):
    r = await client.post("/api/v1/developers/create", json={
        "name": "Test Dev", "email": "test@example.com", "team": "eng"
    })
    assert r.status_code == 403


@pytest.mark.asyncio
async def test_create_developer_with_auth(client):
    r = await client.post(
        "/api/v1/developers/create",
        headers={"Authorization": "Bearer test-admin-key-abc123"},
        json={"name": "Test Dev", "email": "newdev@example.com", "team": "eng"}
    )
    assert r.status_code == 200
    data = r.json()
    assert data["ok"] is True
    assert "token" in data
