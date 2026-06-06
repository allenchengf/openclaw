#!/usr/bin/env bash
# Cloud Run entrypoint：產生 ~/.openclaw/openclaw.json 後啟動 OpenClaw gateway。
#
# 環境變數（詳見 .env.example 與 deploy/gen-config.mjs）：
#   OPENCLAW_GATEWAY_TOKEN   gateway token（未設則自動產生隨機值）
#   OPENCLAW_PUBLIC_URL      對外公開 URL（control UI / Google Chat audience）
#   OPENCLAW_MODEL           主要模型（預設 google/gemini-3-flash-preview）
#   PORT                     監聽埠（Cloud Run 注入，預設 8080）
#   OPENCLAW_BIND            gateway 綁定模式（預設 lan）
#   OPENCLAW_HOME            設定目錄（預設 $HOME/.openclaw；測試可覆寫）
#   CLAWDBOT_CONFIG_ONLY=1   只產生並驗證設定後結束，不啟動 gateway（供測試用）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/usr/local/bin:/usr/bin:${PATH}"

# 1) 確保 gateway token 有值（未設則用 node 產生 64 字元 hex）
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  OPENCLAW_GATEWAY_TOKEN="$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")"
  export OPENCLAW_GATEWAY_TOKEN
  echo "[entrypoint] Generated random OPENCLAW_GATEWAY_TOKEN" 1>&2
fi

# 2) 解析設定路徑
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
mkdir -p "${OPENCLAW_HOME}"
CONFIG_PATH="${OPENCLAW_HOME}/openclaw.json"

# 3) 用 node 產生設定（正確跳脫，避免字串拼接 bug）
OPENCLAW_CONFIG_PATH="${CONFIG_PATH}" node "${SCRIPT_DIR}/gen-config.mjs"

# 4) 驗證輸出為合法 JSON（fail fast）
node -e "JSON.parse(require('fs').readFileSync('${CONFIG_PATH}','utf8'))" \
  || { echo "[entrypoint] ERROR: generated config is not valid JSON" 1>&2; exit 1; }

echo "[entrypoint] Config written to ${CONFIG_PATH}"
sed 's/"token": "[^"]*"/"token": "***"/' "${CONFIG_PATH}"

# 5) 測試模式：只產生設定即結束
if [[ "${CLAWDBOT_CONFIG_ONLY:-}" == "1" ]]; then
  echo "[entrypoint] CLAWDBOT_CONFIG_ONLY=1 → config generated, exiting without starting gateway"
  exit 0
fi

PORT="${PORT:-8080}"
BIND="${OPENCLAW_BIND:-lan}"
echo "[entrypoint] Starting gateway: port=${PORT} bind=${BIND} public=${OPENCLAW_PUBLIC_URL:-<unset>}"

command -v openclaw >/dev/null 2>&1 \
  || { echo "[entrypoint] ERROR: openclaw CLI not found on PATH" 1>&2; exit 1; }

exec openclaw gateway --allow-unconfigured --port "${PORT}" --bind "${BIND}"
