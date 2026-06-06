#!/usr/bin/env bash
# 在 GCE Container-Optimized OS VM 上部署 clawdbot，並以「持久磁碟」掛載 ~/.openclaw，
# 讓 OpenClaw 記憶（sqlite + IDENTITY.md/USER.md/MEMORY.md）跨容器/VM 重啟持久保存。
#
# 設定來源：../.env（由 Makefile `make vm-deploy` 呼叫，或可獨立執行）。
# 冪等：靜態 IP / 防火牆 / 資料磁碟已存在則沿用；VM 已存在則 update-container，否則 create。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -f "$ROOT/.env" ]] && { set -a; source "$ROOT/.env"; set +a; }

: "${GCP_PROJECT_ID:?請在 .env 設 GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION:-asia-east1}"
ZONE="${GCE_ZONE:-${GCP_REGION}-b}"
VM="${GCE_VM_NAME:-clawdbot-vm}"
MACHINE="${GCE_MACHINE_TYPE:-e2-small}"
DISK="${VM}-data"
DISK_SIZE="${GCE_DATA_DISK_SIZE:-10GB}"
ADDR="${VM}-ip"
AR_REPO_NAME="${AR_REPO_NAME:-clawdbot-repo}"
SERVICE_NAME="${SERVICE_NAME:-clawdbot}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
IMAGE="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT_ID}/${AR_REPO_NAME}/${SERVICE_NAME}:${IMAGE_TAG}"
MEM_PROVIDER="${OPENCLAW_MEMORY_PROVIDER:-gemini}"

G=(gcloud --project="$GCP_PROJECT_ID")
[[ -n "${GCP_ACCOUNT:-}" ]] && G+=(--account="$GCP_ACCOUNT")

echo "▶ [0/5] 確保 Compute Engine API 已啟用"
"${G[@]}" services list --enabled --filter="config.name=compute.googleapis.com" --format='value(config.name)' 2>/dev/null | grep -q compute \
  || "${G[@]}" services enable compute.googleapis.com

echo "▶ [1/5] 靜態外部 IP（$ADDR @ ${GCP_REGION}）"
"${G[@]}" compute addresses describe "$ADDR" --region="$GCP_REGION" >/dev/null 2>&1 \
  || "${G[@]}" compute addresses create "$ADDR" --region="$GCP_REGION"
IP="$("${G[@]}" compute addresses describe "$ADDR" --region="$GCP_REGION" --format='value(address)')"
echo "  IP=$IP"

echo "▶ [2/5] 防火牆（tcp:8080 → tag clawdbot）"
"${G[@]}" compute firewall-rules describe clawdbot-8080 >/dev/null 2>&1 \
  || "${G[@]}" compute firewall-rules create clawdbot-8080 \
       --allow=tcp:8080 --target-tags=clawdbot --source-ranges=0.0.0.0/0

echo "▶ [3/5] 持久資料磁碟（$DISK ${DISK_SIZE}）"
"${G[@]}" compute disks describe "$DISK" --zone="$ZONE" >/dev/null 2>&1 \
  || "${G[@]}" compute disks create "$DISK" --size="$DISK_SIZE" --zone="$ZONE"

echo "▶ [4/5] 解析 Gemini 金鑰"
GEMINI="${GEMINI_API_KEY:-}"
[[ -z "$GEMINI" ]] && GEMINI="$("${G[@]}" secrets versions access latest --secret=gemini-api-key 2>/dev/null || true)"
[[ -n "$GEMINI" ]] || { echo "✗ 找不到 Gemini 金鑰（.env GEMINI_API_KEY 或 Secret Manager）"; exit 1; }

# 容器環境變數（PUBLIC_URL 用靜態 IP，故建立前即可確定）
PUBLIC_URL="http://${IP}:8080"
ENV_ARGS=(
  "--container-env=GEMINI_API_KEY=${GEMINI}"
  "--container-env=OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-}"
  "--container-env=OPENCLAW_PUBLIC_URL=${PUBLIC_URL}"
  "--container-env=OPENCLAW_MODEL=${OPENCLAW_MODEL:-google/gemini-3-flash-preview}"
  "--container-env=OPENCLAW_MEMORY_PROVIDER=${MEM_PROVIDER}"
  "--container-env=GOOGLECHAT_ENABLED=${GOOGLECHAT_ENABLED:-true}"
  "--container-env=LINE_CHANNEL_SECRET=${LINE_CHANNEL_SECRET:-}"
  "--container-env=LINE_CHANNEL_ACCESS_TOKEN=${LINE_CHANNEL_ACCESS_TOKEN:-}"
)

echo "▶ [5/5] 部署容器到 VM（${VM} @ ${ZONE}，image=${IMAGE_TAG}）"
if "${G[@]}" compute instances describe "$VM" --zone="$ZONE" >/dev/null 2>&1; then
  echo "  VM 已存在 → update-container"
  "${G[@]}" compute instances update-container "$VM" --zone="$ZONE" \
    --container-image="$IMAGE" "${ENV_ARGS[@]}"
else
  echo "  建立新 VM（COS + 掛載持久磁碟到 /root/.openclaw）"
  "${G[@]}" compute instances create-with-container "$VM" --zone="$ZONE" \
    --machine-type="$MACHINE" \
    --address="$IP" \
    --tags=clawdbot \
    --scopes=cloud-platform \
    --container-image="$IMAGE" \
    "${ENV_ARGS[@]}" \
    --container-mount-disk=mount-path=/root/.openclaw,name="$DISK" \
    --disk=name="$DISK",device-name="$DISK",mode=rw
fi

echo ""
echo "✅ VM 部署完成"
echo "   服務 URL：     $PUBLIC_URL"
echo "   Dashboard：    $PUBLIC_URL/chat?session=main#token=${OPENCLAW_GATEWAY_TOKEN:-<token>}"
echo "   記憶持久化於：  持久磁碟 ${DISK}（掛載到容器 /root/.openclaw）"
echo "   提示：首次開機需 1–2 分鐘拉映像並啟動；webhook 正式上線建議加反向代理(HTTPS)。"
