#!/usr/bin/env bash
# Run this once to set up the gateway on a fresh server
set -e
echo "→ Installing Python deps..."
pip install -r gateway/requirements.txt --break-system-packages

echo "→ Creating .env from example..."
[ ! -f .env ] && cp .env.example .env && echo "✓ Edit .env with your keys before starting"

echo "→ Starting gateway..."
python -m gateway.main
