#!/usr/bin/env bash
# 從本機用 Docker 映像對「遠端 Cloud Run Gateway」執行 devices list / approve / reject。
# 用法：
#   export OPENCLAW_GATEWAY_TOKEN="your-token"
#   export OPENCLAW_GATEWAY_URL="https://clawdbot-xxx.asia-east1.run.app"   # 或 wss://...
#   ./scripts/devices-remote.sh list
#   ./scripts/devices-remote.sh approve <requestId>
#   ./scripts/devices-remote.sh reject <requestId>
#
# 也可直接傳入 URL 與 token：
#   OPENCLAW_GATEWAY_URL="https://..." OPENCLAW_GATEWAY_TOKEN="..." ./scripts/devices-remote.sh list

set -e

IMAGE="${OPENCLAW_CLAWDBOT_IMAGE:-asia-east1-docker.pkg.dev/project-df9933f9-89bc-4f20-9f2/clawdbot-repo/clawdbot:v1}"

if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
  echo "錯誤：請設定 OPENCLAW_GATEWAY_TOKEN（或傳入環境變數）" 1>&2
  exit 1
fi

# 若為 https:// 開頭則改為 wss://（同一 host）
GATEWAY_URL="${OPENCLAW_GATEWAY_URL:-}"
if [ -z "$GATEWAY_URL" ]; then
  echo "錯誤：請設定 OPENCLAW_GATEWAY_URL（例如 https://clawdbot-xxx.asia-east1.run.app）" 1>&2
  exit 1
fi
if [[ "$GATEWAY_URL" == https://* ]]; then
  GATEWAY_URL="wss://${GATEWAY_URL#https://}"
fi

SUBCMD="${1:-list}"
shift || true

docker run --rm --entrypoint "" \
  -e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  "$IMAGE" \
  node dist/index.js devices "$SUBCMD" "$@" \
  --url "$GATEWAY_URL" \
  --token "$OPENCLAW_GATEWAY_TOKEN"
