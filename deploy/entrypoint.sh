#!/usr/bin/env bash
# Cloud Run entrypoint：產生 ~/.openclaw/openclaw.json 後啟動 OpenClaw gateway。
#
# 環境變數（詳見 .env.example 與 deploy/gen-config.mjs）：
#   OPENCLAW_GATEWAY_TOKEN   gateway token（未設則自動產生隨機值）
#   OPENCLAW_PUBLIC_URL      對外公開 URL（control UI / Google Chat audience）
#   OPENCLAW_MODEL           主要模型（預設 google/gemini-3-flash-preview）
#   PORT                     監聽埠（Cloud Run 注入，預設 8080）
#   OPENCLAW_BIND            gateway 綁定模式（預設 lan）
#   OPENCLAW_CONFIG_DIR      設定目錄（預設 $HOME/.openclaw；測試可覆寫）
#   CLAWDBOT_CONFIG_ONLY=1   只產生並驗證設定後結束，不啟動 gateway（供測試用）
# 注意：勿設 OPENCLAW_HOME（openclaw 會當家目錄基底再接 .openclaw/，造成路徑錯亂）。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PATH="/usr/local/bin:/usr/bin:${PATH}"

# 1) 確保 gateway token 有值（未設則用 node 產生 64 字元 hex）
if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  OPENCLAW_GATEWAY_TOKEN="$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")"
  export OPENCLAW_GATEWAY_TOKEN
  echo "[entrypoint] Generated random OPENCLAW_GATEWAY_TOKEN" 1>&2
fi

# 2) 解析設定路徑（openclaw 預設讀 $HOME/.openclaw/openclaw.json）
CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}"
mkdir -p "${CONFIG_DIR}"
CONFIG_PATH="${CONFIG_DIR}/openclaw.json"

# 3) 用 node 產生設定（正確跳脫，避免字串拼接 bug）
OPENCLAW_CONFIG_PATH="${CONFIG_PATH}" node "${SCRIPT_DIR}/gen-config.mjs"

# 4) 驗證輸出為合法 JSON（fail fast）
node -e "JSON.parse(require('fs').readFileSync('${CONFIG_PATH}','utf8'))" \
  || { echo "[entrypoint] ERROR: generated config is not valid JSON" 1>&2; exit 1; }

echo "[entrypoint] Config written to ${CONFIG_PATH}"
# 顯示設定但遮蔽機密（token / apiKey）
sed -E 's/"(token|apiKey)": "[^"]*"/"\1": "***"/g' "${CONFIG_PATH}"

# 5) 測試模式：只產生設定即結束
if [[ "${CLAWDBOT_CONFIG_ONLY:-}" == "1" ]]; then
  echo "[entrypoint] CLAWDBOT_CONFIG_ONLY=1 → config generated, exiting without starting gateway"
  exit 0
fi

# 5b) Vertex AI：用 google-vertex/* 模型時，確保 ADC 憑證檔存在並設 GOOGLE_APPLICATION_CREDENTIALS。
#     openclaw 的 vertex 同步預判只認憑證檔（不認 metadata ADC）；缺檔則自 Secret Manager(vertex-adc) 取，
#     讓 Cloud Run/VM 皆免手動佈署金鑰（runtime SA 需 roles/secretmanager.secretAccessor）。
if [[ "${OPENCLAW_MODEL:-}" == google-vertex/* ]]; then
  ADC_FILE="${GOOGLE_APPLICATION_CREDENTIALS:-${CONFIG_DIR}/vertex-adc.json}"
  if [[ -s "$ADC_FILE" ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$ADC_FILE"
    echo "[entrypoint] Vertex model: using existing ADC at ${ADC_FILE}"
  else
    echo "[entrypoint] Vertex model: fetching ADC from Secret Manager (vertex-adc)…"
    if node "${SCRIPT_DIR}/fetch-adc.mjs" "$ADC_FILE" "${GOOGLE_CLOUD_PROJECT:-}" >&2; then
      export GOOGLE_APPLICATION_CREDENTIALS="$ADC_FILE"
    else
      echo "[entrypoint] WARN: fetch vertex-adc 失敗；Vertex 認證可能無法運作（檢查 SA secretAccessor 與 secret vertex-adc）" 1>&2
    fi
  fi
fi

PORT="${PORT:-8080}"
BIND="${OPENCLAW_BIND:-lan}"
echo "[entrypoint] Starting gateway: port=${PORT} bind=${BIND} public=${OPENCLAW_PUBLIC_URL:-<unset>}"

command -v openclaw >/dev/null 2>&1 \
  || { echo "[entrypoint] ERROR: openclaw CLI not found on PATH" 1>&2; exit 1; }

exec openclaw gateway --allow-unconfigured --port "${PORT}" --bind "${BIND}"
