#!/usr/bin/env bash
# 產生「帶 gateway token、雙擊即連」的本機 Dashboard 啟動檔（clawdbot-dashboard.html）。
#
# 為何需要：control UI 的 token 放在網址的 #fragment（#token=...）。使用者手動複製/貼上
# 網址時，#fragment 常被截斷而遺失，導致 Dashboard 卡在「需要驗證」。改用 HTML + JS 導向，
# 雙擊檔案即可帶著完整 token 開啟，fragment 不會掉。
#
# 來源優先序：VM 的 HTTPS(nip.io，持久記憶) > Cloud Run URL。
# 設定來源：../.env（由 Makefile `make dashboard-launcher` 呼叫，或可獨立執行）。
# 注意：產生的 HTML 含 gateway token，已加入 .gitignore/.gcloudignore/.dockerignore，勿提交。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT/.env" ]] && { set -a; source "$ROOT/.env"; set +a; }

: "${GCP_PROJECT_ID:?請在 .env 設 GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION:-asia-east1}"
VM="${GCE_VM_NAME:-clawdbot-vm}"
SERVICE_NAME="${SERVICE_NAME:-clawdbot}"
TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
[[ -n "$TOKEN" ]] || { echo "✗ .env 無 OPENCLAW_GATEWAY_TOKEN，無法產生啟動檔"; exit 1; }

G=(gcloud --project="$GCP_PROJECT_ID")
[[ -n "${GCP_ACCOUNT:-}" ]] && G+=(--account="$GCP_ACCOUNT")

# 1) 優先取 VM 靜態 IP → nip.io HTTPS（持久記憶）
IP="$("${G[@]}" compute addresses describe "${VM}-ip" --region="$GCP_REGION" --format='value(address)' 2>/dev/null || true)"
if [[ -n "$IP" ]]; then
  BASE="https://${IP//./-}.nip.io"; KIND="VM（持久記憶・HTTPS）"
else
  # 2) 退回 Cloud Run
  BASE="$("${G[@]}" run services describe "$SERVICE_NAME" --region="$GCP_REGION" --format='value(status.url)' 2>/dev/null || true)"
  KIND="Cloud Run（無狀態）"
fi
[[ -n "$BASE" ]] || { echo "✗ 取不到 VM 或 Cloud Run URL，請先部署（make vm-deploy / make deploy）"; exit 1; }

URL="${BASE}/chat?session=main#token=${TOKEN}"
OUT="$ROOT/clawdbot-dashboard.html"

cat > "$OUT" <<HTML
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<title>開啟小龍蝦 Dashboard</title>
<script>
  // 用 JS 導向，確保 #token 片段不會在複製/貼上時遺失。
  location.href = "${URL}";
</script>
</head>
<body style="font-family:sans-serif;background:#111;color:#eee;text-align:center;padding:60px">
  <h2>正在帶著令牌開啟小龍蝦 Dashboard…</h2>
  <p>目標：${KIND}</p>
  <p>若沒有自動跳轉，請點下方連結：</p>
  <p><a style="color:#ff6b6b;font-size:18px" href="${URL}">進入小龍蝦 Dashboard</a></p>
</body>
</html>
HTML

echo ""
echo "════════════════════════════════════════════════════════════════════"
echo "📋 Dashboard 網址（整行複製，務必含 # 後的 token，勿漏字）："
echo ""
echo "${URL}"
echo ""
echo "目標：${KIND}"
echo "（建議用無痕視窗開啟，避免舊 token 快取）"
echo "────────────────────────────────────────────────────────────────────"
echo "✓ 或雙擊啟動檔（令牌不會掉、最不易出錯）：${OUT}"
echo "════════════════════════════════════════════════════════════════════"
