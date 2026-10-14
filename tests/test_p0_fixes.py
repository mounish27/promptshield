"""
tests/test_p0_fixes.py
======================
Focused tests that PROVE each P0 fix is actually in place.
These are your regression guard — if someone reverts a fix, these fail loudly.
"""
import secrets
import pytest
import pytest_asyncio
import os


# ─────────────────────────────────────────────────────────────────────────────
# P0-FIX-1: No sync Anthropic client in async context
# ─────────────────────────────────────────────────────────────────────────────
class TestAsyncAnthropicClient:
    def test_devguard_validate_uses_async_client(self):
        """devguard_validate.py must import AsyncAnthropic, not Anthropic."""
        import ast, inspect
        import gateway.routers.devguard_validate as mod
        source = inspect.getsource(mod)
        tree = ast.parse(source)

        sync_imports = []
        async_imports = []
        for node in ast.walk(tree):
            if isinstance(node, ast.ImportFrom) and node.module == "anthropic":
                for alias in node.names:
                    if alias.name == "Anthropic":
                        sync_imports.append(alias.name)
                    if alias.name == "AsyncAnthropic":
                        async_imports.append(alias.name)

        assert not sync_imports, (
            "P0-FIX-2 REGRESSION: devguard_validate.py still imports sync `Anthropic`. "
            "Change to `from anthropic import AsyncAnthropic`."
        )
        assert async_imports, (
            "P0-FIX-2 MISSING: devguard_validate.py must import `AsyncAnthropic`."
        )

    def test_proxy_uses_async_anthropic(self):
        """proxy.py rewrite endpoint must use AsyncAnthropic."""
        import inspect
        import gateway.routers.proxy as mod
        source = inspect.getsource(mod)

        # The async rewrite endpoint uses anthropic.AsyncAnthropic(...)
        assert "AsyncAnthropic" in source, (
            "P0-FIX-2 REGRESSION: proxy.py rewrite endpoint still uses sync Anthropic client."
        )

    def test_admin_uses_async_anthropic(self):
        """admin.py generate-claude-md endpoint must use AsyncAnthropic."""
        import inspect
        import gateway.routers.admin as mod
        source = inspect.getsource(mod)
        assert "AsyncAnthropic" in source, (
            "P0-FIX-2 REGRESSION: admin.py generate-claude-md still uses sync Anthropic client."
        )


# ─────────────────────────────────────────────────────────────────────────────
# P0-FIX-2: CORS not wildcard
# ─────────────────────────────────────────────────────────────────────────────
class TestCorsNotWildcard:
    def test_main_py_has_no_wildcard_origin(self):
        """main.py must not have allow_origins=["*"]."""
        import inspect
        import gateway.main as mod
        source = inspect.getsource(mod)
        assert 'allow_origins=["*"]' not in source, (
            'P0-FIX-3 REGRESSION: main.py still has allow_origins=["*"]. '
            "Set ALLOWED_ORIGINS env var and use that list."
        )

    def test_allowed_origins_read_from_env(self):
        """ALLOWED_ORIGINS env var drives the CORS list."""
        import importlib, gateway.main as mod
        # The module-level ALLOWED_ORIGINS list must exist and be non-empty
        assert hasattr(mod, "ALLOWED_ORIGINS"), (
            "P0-FIX-3: gateway/main.py must define ALLOWED_ORIGINS from os.getenv"
        )
        assert isinstance(mod.ALLOWED_ORIGINS, list), "ALLOWED_ORIGINS must be a list"
        assert len(mod.ALLOWED_ORIGINS) > 0, "ALLOWED_ORIGINS must not be empty"
        # Wildcard must not be in the list
        assert "*" not in mod.ALLOWED_ORIGINS, (
            "P0-FIX-3 REGRESSION: '*' still present in ALLOWED_ORIGINS list"
        )


# ─────────────────────────────────────────────────────────────────────────────
# P0-FIX-3: Timing-safe admin key comparison
# ─────────────────────────────────────────────────────────────────────────────
class TestTimingSafeAdminKey:
    def test_admin_py_uses_compare_digest(self):
        """admin.py must use secrets.compare_digest, not != for token comparison."""
        import inspect
        import gateway.routers.admin as mod
        source = inspect.getsource(mod)

        assert "secrets.compare_digest" in source, (
            "P0-FIX-4 REGRESSION: admin.py must use secrets.compare_digest(token, ADMIN_KEY). "
            "Simple `!=` comparison is vulnerable to timing attacks."
        )
        # The unsafe pattern must be gone
        assert "token != ADMIN_KEY" not in source, (
            "P0-FIX-4 REGRESSION: unsafe `token != ADMIN_KEY` still present in admin.py"
        )

    def test_secrets_compare_digest_is_constant_time(self):
        """Sanity check: secrets.compare_digest behaves correctly."""
        assert secrets.compare_digest("abc123", "abc123") is True
        assert secrets.compare_digest("abc123", "wrong!!") is False
        assert secrets.compare_digest("", "") is True
        assert secrets.compare_digest("a", "b") is False

    def test_admin_imports_secrets(self):
        """admin.py must import the secrets module."""
        import inspect
        import gateway.routers.admin as mod
        source = inspect.getsource(mod)
        assert "secrets" in source and "import" in source, (
            "P0-FIX-4: admin.py must import secrets to use compare_digest"
        )
        # More specific: the import line must contain secrets
        import_lines = [l for l in source.splitlines() if "import" in l and "secrets" in l]
        assert import_lines, (
            "P0-FIX-4: No import line containing 'secrets' found in admin.py. "
            "Add `import secrets` or `import os, secrets`."
        )


# ─────────────────────────────────────────────────────────────────────────────
# P0-FIX-4: Tests exist (meta-test — this file proves tests exist)
# ─────────────────────────────────────────────────────────────────────────────
class TestTestsExist:
    def test_devguard_l1_test_file_exists(self):
        import os
        here = os.path.dirname(__file__)
        assert os.path.exists(os.path.join(here, "test_devguard_l1.py")), (
            "P0-FIX-1: test_devguard_l1.py is missing — DevGuard L1 must have tests."
        )

    def test_api_test_file_exists(self):
        import os
        here = os.path.dirname(__file__)
        assert os.path.exists(os.path.join(here, "test_api.py")), (
            "P0-FIX-1: test_api.py is missing — API integration tests must exist."
        )
