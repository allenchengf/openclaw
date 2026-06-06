#!/usr/bin/env bash
# 從本機用 Docker 映像對「遠端 Cloud Run Gateway」執行 devices list / approve / reject。
#
# 設定來源（依序）：環境變數 → 同層 ../.env
# 用法：
#   ./scripts/devices-remote.sh list
#   ./scripts/devices-remote.sh approve <requestId>
#   ./scripts/devices-remote.sh reject  <requestId>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT/.env" ]] && { set -a; source "$ROOT/.env"; set +a; }

: "${OPENCLAW_GATEWAY_TOKEN:?請設定 OPENCLAW_GATEWAY_TOKEN（或寫入 .env）}"

# Gateway URL：優先 OPENCLAW_GATEWAY_URL，否則用 OPENCLAW_PUBLIC_URL
GATEWAY_URL="${OPENCLAW_GATEWAY_URL:-${OPENCLAW_PUBLIC_URL:-}}"
: "${GATEWAY_URL:?請設定 OPENCLAW_GATEWAY_URL 或 OPENCLAW_PUBLIC_URL（https://... 或 wss://...）}"
[[ "$GATEWAY_URL" == https://* ]] && GATEWAY_URL="wss://${GATEWAY_URL#https://}"

# 預設用本專案部署的映像（可用 OPENCLAW_CLAWDBOT_IMAGE 覆寫）
REGION="${GCP_REGION:-asia-east1}"
DEFAULT_IMAGE="${REGION}-docker.pkg.dev/${GCP_PROJECT_ID:-}/${AR_REPO_NAME:-clawdbot-repo}/${SERVICE_NAME:-clawdbot}:${IMAGE_TAG:-v1}"
IMAGE="${OPENCLAW_CLAWDBOT_IMAGE:-$DEFAULT_IMAGE}"

SUBCMD="${1:-list}"; shift || true

# 使用 npm 安裝的 openclaw CLI（非舊版 node dist/index.js）
docker run --rm --entrypoint openclaw \
  -e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  "$IMAGE" \
  devices "$SUBCMD" "$@" --url "$GATEWAY_URL" --token "$OPENCLAW_GATEWAY_TOKEN"
