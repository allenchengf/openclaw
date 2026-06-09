#!/usr/bin/env bash
# 為 GCE VM 接上 HTTPS 反向代理（Caddy + Let's Encrypt，經 nip.io 免網域）。
# 在現有 COS VM 上以 Caddy 容器反代到 clawdbot 容器(localhost:8080)，自動取得憑證。
#
# 設定來源：../.env。需先 make vm-deploy 部署好 VM。
# 用法：make vm-https
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT/.env" ]] && { set -a; source "$ROOT/.env"; set +a; }

: "${GCP_PROJECT_ID:?請在 .env 設 GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION:-asia-east1}"
ZONE="${GCE_ZONE:-${GCP_REGION}-b}"
VM="${GCE_VM_NAME:-clawdbot-vm}"
ADDR="${VM}-ip"

G=(gcloud --project="$GCP_PROJECT_ID")
[[ -n "${GCP_ACCOUNT:-}" ]] && G+=(--account="$GCP_ACCOUNT")

IP="$("${G[@]}" compute addresses describe "$ADDR" --region="$GCP_REGION" --format='value(address)' 2>/dev/null)"
: "${IP:?取不到 VM 靜態 IP，請先 make vm-deploy}"
# nip.io：<dash-ip>.nip.io 解析到該 IP（免自有網域）。可由 .env VM_HTTPS_DOMAIN 覆寫成自有網域。
DOMAIN="${VM_HTTPS_DOMAIN:-${IP//./-}.nip.io}"
PUBLIC_URL="https://${DOMAIN}"

echo "▶ [1/4] 開放防火牆 tcp:80,443"
"${G[@]}" compute firewall-rules describe clawdbot-https >/dev/null 2>&1 \
  || "${G[@]}" compute firewall-rules create clawdbot-https \
       --allow=tcp:80,tcp:443 --target-tags=clawdbot --source-ranges=0.0.0.0/0

echo "▶ [2/4] 更新 clawdbot 對外 URL 為 ${PUBLIC_URL}（control UI allowedOrigins / 頻道 audience）"
# 先做：update-container 會重啟 VM；故須在啟動 Caddy「之前」完成，避免 Caddy 被重啟打斷
"${G[@]}" compute instances update-container "$VM" --zone="$ZONE" \
  --container-env=OPENCLAW_PUBLIC_URL="${PUBLIC_URL}" >/dev/null
echo "  等待 VM 重啟並就緒…"
for _ in $(seq 1 30); do
  st="$("${G[@]}" compute instances describe "$VM" --zone="$ZONE" --format='value(status)' 2>/dev/null)"
  [[ "$st" == "RUNNING" ]] && curl -s -o /dev/null --max-time 5 "http://${IP}:8080/" 2>/dev/null && break
  sleep 8
done

echo "▶ [3/4] 在 VM 上啟動 Caddy 反向代理（自動 HTTPS：${DOMAIN}）"
# 重啟後才起 Caddy（host network 綁 80/443、反代到 clawdbot 8080；--restart=always 隨 VM 回來）
"${G[@]}" compute ssh "$VM" --zone="$ZONE" --quiet --command="
  set -e
  sudo mkdir -p /var/caddy
  echo '${DOMAIN} {
    reverse_proxy localhost:8080
}' | sudo tee /var/caddy/Caddyfile >/dev/null
  sudo docker rm -f caddy >/dev/null 2>&1 || true
  sudo docker run -d --name caddy --restart=always --network host \
    -v /var/caddy:/data \
    -v /var/caddy/Caddyfile:/etc/caddy/Caddyfile:ro \
    caddy:2
"

echo "▶ [4/4] 等待憑證簽發與服務就緒（最多 ~90s）"
ok=0
for _ in $(seq 1 18); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "${PUBLIC_URL}/" 2>/dev/null || true)"
  if [[ "$code" == "200" || "$code" == "403" ]]; then ok=1; break; fi
  sleep 5
done

echo ""
if [[ "$ok" == "1" ]]; then
  echo "✅ HTTPS 就緒"
else
  echo "⚠ 尚未取得有效回應（憑證簽發可能需再等一下；確認 nip.io 解析與 80/443 連通）"
fi
echo "   服務 URL：     ${PUBLIC_URL}"
echo "   Dashboard：    ${PUBLIC_URL}/chat?session=main#token=${OPENCLAW_GATEWAY_TOKEN:-<token>}"
echo "   Google Chat：  ${PUBLIC_URL}/googlechat"
echo "   LINE webhook： ${PUBLIC_URL}/line"
