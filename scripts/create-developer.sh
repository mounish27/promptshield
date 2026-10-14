#!/usr/bin/env bash
# Usage: ./scripts/create-developer.sh "Name" email@domain.com team
NAME="${1:-Developer}"; EMAIL="${2:-}"; TEAM="${3:-Engineering}"
ADMIN_KEY="${DEVGUARD_ADMIN_KEY:-$(cat .env 2>/dev/null | grep DEVGUARD_ADMIN_KEY | cut -d= -f2)}"
GATEWAY="${GATEWAY_URL:-http://localhost:8000}"
curl -fsSL -X POST "${GATEWAY}/api/v1/developers/create" \
  -H "Authorization: Bearer ${ADMIN_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${NAME}\",\"email\":\"${EMAIL}\",\"team\":\"${TEAM}\"}" | python3 -m json.tool
