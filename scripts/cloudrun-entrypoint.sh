#!/bin/bash
# Cloud Run entrypoint script
# Creates config file from environment variables and starts the gateway

set -e

# 確保 npm 全域 bin 在 PATH（容器內 openclaw 可能只裝在 /usr/local/bin）
export PATH="/usr/local/bin:/usr/bin:$PATH"

# OpenClaw 預設讀取 ~/.openclaw/openclaw.json，必須寫入此路徑
mkdir -p ~/.openclaw

# Get service account from Secret Manager mounted file
SERVICE_ACCOUNT_FILE=""
if [ -f "/secrets/google-chat-sa/key.json" ]; then
    SERVICE_ACCOUNT_FILE="/secrets/google-chat-sa/key.json"
fi

# Cloud Run 服務 URL（請在 deploy 時用 --set-env-vars 設定，容器內沒有 gcloud）
GOOGLE_CHAT_AUDIENCE="${GOOGLE_CHAT_AUDIENCE:-https://clawdbot.asia-east1.run.app}"

# Build the config file（格式需符合 OpenClaw schema，否則 Gateway 拒絕啟動）
# 參考：https://docs.clawd.bot/gateway/configuration（channels.googlechat 無頂層 requireMention）
# gateway.controlUi.dangerouslyDisableDeviceAuth：Cloud Run 上皆為遠端連線，無法先「本機配對」再跑 CLI；
# 僅持 token 的連線可跳過裝置配對（見 docs.clawd.bot/gateway/security）。
if [ -n "$SERVICE_ACCOUNT_FILE" ]; then
    cat > ~/.openclaw/openclaw.json << EOF
{
  "gateway": {
    "auth": { "mode": "token", "token": "\${OPENCLAW_GATEWAY_TOKEN}" },
    "controlUi": { "dangerouslyDisableDeviceAuth": true },
    "trustedProxies": ["169.254.169.126", "127.0.0.1"]
  },
  "channels": {
    "googlechat": {
      "enabled": true,
      "serviceAccountFile": "${SERVICE_ACCOUNT_FILE}",
      "audienceType": "app-url",
      "audience": "${GOOGLE_CHAT_AUDIENCE}/googlechat",
      "webhookPath": "/googlechat",
      "dm": { "policy": "open", "allowFrom": ["*"] },
      "groupPolicy": "open"
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "google/gemini-3-flash-preview" }
    }
  }
}
EOF
else
    cat > ~/.openclaw/openclaw.json << EOF
{
  "gateway": {
    "auth": { "mode": "token", "token": "\${OPENCLAW_GATEWAY_TOKEN}" },
    "controlUi": { "dangerouslyDisableDeviceAuth": true },
    "trustedProxies": ["169.254.169.126", "127.0.0.1"]
  },
  "channels": {
    "googlechat": {
      "enabled": true,
      "audienceType": "app-url",
      "audience": "${GOOGLE_CHAT_AUDIENCE}/googlechat",
      "webhookPath": "/googlechat",
      "dm": { "policy": "open", "allowFrom": ["*"] },
      "groupPolicy": "open"
    }
  },
  "agents": {
    "defaults": {
      "model": { "primary": "google/gemini-3-flash-preview" }
    }
  }
}
EOF
fi

echo "[entrypoint] Config written to ~/.openclaw/openclaw.json"
cat ~/.openclaw/openclaw.json

# OpenClaw 預設需要 gateway token，未設定會直接 exit(1)
# 使用 Node 產生（slim 映像無 openssl）
if [ -z "$OPENCLAW_GATEWAY_TOKEN" ]; then
  export OPENCLAW_GATEWAY_TOKEN=$(node -e "console.log(require('crypto').randomBytes(32).toString('hex'))")
  echo "[entrypoint] Generated OPENCLAW_GATEWAY_TOKEN (use for Control UI / dashboard)" 1>&2
fi

PORT="${PORT:-8080}"
echo "[entrypoint] Starting gateway: port=$PORT bind=lan cwd=/app"

# 與官方一致：從原始碼建置後在 /app 執行 node dist/index.js
cd /app || { echo "[entrypoint] ERROR: cd /app failed"; exit 1; }
test -f dist/index.js || { echo "[entrypoint] ERROR: dist/index.js not found"; ls -la dist/ 2>/dev/null || true; exit 1; }

exec node dist/index.js gateway --allow-unconfigured --port "$PORT" --bind lan

