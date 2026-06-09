#!/usr/bin/env bash
# GCE VM 部署（deploy/gce-deploy.sh）多情境測試（stub gcloud，不觸碰雲端）。
# 驗證：compute API 啟用、靜態IP/防火牆/磁碟冪等、create vs update 分支、
#       持久磁碟掛載 /root/.openclaw、container-env 帶入、缺 Gemini fail-fast。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "═══ GCE VM 部署多情境 (test_vm) ═══"
command -v bash >/dev/null 2>&1 || { skip "全部" "no bash"; finish; exit $?; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/deploy" "$TMP/bin"
cp "$REPO_ROOT/deploy/gce-deploy.sh" "$TMP/deploy/"

CALLLOG="$TMP/calls.log"
cat > "$TMP/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$CALLLOG"
case "\$*" in
  *"services list"*"compute"*)   [ "\${STUB_API_ENABLED:-0}" = "1" ] && echo compute.googleapis.com; exit 0;;
  *"addresses describe"*"value(address)"*) echo "203.0.113.50"; exit 0;;
  *"addresses describe"*)        exit \${STUB_ADDR_EXISTS:-1};;
  *"firewall-rules describe"*)   exit \${STUB_FW_EXISTS:-1};;
  *"disks describe"*)            exit \${STUB_DISK_EXISTS:-1};;
  *"instances describe"*)        exit \${STUB_VM_EXISTS:-1};;
  *"secrets versions access"*)   [ "\${STUB_NO_SECRET:-0}" = "1" ] && exit 1; echo "AIzaSTUB"; exit 0;;
  *) exit 0;;
esac
EOF
chmod +x "$TMP/bin/gcloud"
export PATH="$TMP/bin:$PATH"

# 沙箱 .env（含必要值；GEMINI 空 → 走 secret）
cat > "$TMP/.env" <<'EOF'
GCP_PROJECT_ID=demo
GCP_REGION=asia-east1
GCE_ZONE=asia-east1-b
GCE_VM_NAME=clawdbot-vm
GCE_MACHINE_TYPE=e2-small
GCE_DATA_DISK_SIZE=10GB
AR_REPO_NAME=clawdbot-repo
SERVICE_NAME=clawdbot
IMAGE_TAG=v1
GEMINI_API_KEY=
OPENCLAW_GATEWAY_TOKEN=vmtoken123
OPENCLAW_MODEL=google/gemini-3-flash-preview
OPENCLAW_MEMORY_PROVIDER=gemini
GOOGLECHAT_ENABLED=true
EOF

run_vm() { : > "$CALLLOG"; ( cd "$TMP" && env "$@" bash deploy/gce-deploy.sh ) 2>&1; }
called() { grep -q "$1" "$CALLLOG"; }

section "情境1：全新部署（資源皆不存在）"
out=$(run_vm STUB_API_ENABLED=0); rc=$?
[[ $rc -eq 0 ]] && ok "部署成功 exit 0" || ko "部署成功" "$out"
called "services enable compute.googleapis.com" && ok "啟用 Compute API" || ko "啟用 Compute API"
called "addresses create" && ok "建立靜態 IP" || ko "建立靜態 IP"
called "firewall-rules create" && ok "建立防火牆" || ko "建立防火牆"
called "disks create"     && ok "建立持久磁碟" || ko "建立持久磁碟"
called "create-with-container" && ok "建立 VM(create-with-container)" || ko "建立 VM"
called "container-mount-disk=mount-path=/root/.openclaw" && ok "掛載持久磁碟到 /root/.openclaw" || ko "掛載持久磁碟"
called "OPENCLAW_MEMORY_PROVIDER=gemini" && ok "帶入記憶 provider=gemini" || ko "帶入記憶 provider"
called "GOOGLE_CLOUD_PROJECT=demo" && ok "帶入 Vertex GOOGLE_CLOUD_PROJECT" || ko "帶入 Vertex 專案"
called "GOOGLE_CLOUD_LOCATION=global" && ok "帶入 Vertex GOOGLE_CLOUD_LOCATION" || ko "帶入 Vertex location"
called "OPENCLAW_PUBLIC_URL=http://203.0.113.50:8080" && ok "PUBLIC_URL 用靜態 IP" || ko "PUBLIC_URL 用靜態 IP"
called "GEMINI_API_KEY=AIzaSTUB" && ok "Gemini 金鑰自 Secret 帶入" || ko "Gemini 金鑰帶入"

section "情境2：資源已存在 → 冪等不重建"
out=$(run_vm STUB_API_ENABLED=1 STUB_ADDR_EXISTS=0 STUB_FW_EXISTS=0 STUB_DISK_EXISTS=0 STUB_VM_EXISTS=0); rc=$?
[[ $rc -eq 0 ]] && ok "成功 exit 0" || ko "成功" "$out"
called "services enable" && ko "API 已啟用不重複 enable" || ok "API 已啟用不重複 enable"
called "addresses create" && ko "IP 已存在不重建" || ok "IP 已存在不重建"
called "disks create" && ko "磁碟已存在不重建" || ok "磁碟已存在不重建"
called "update-container" && ok "VM 已存在 → update-container" || ko "VM 已存在 → update-container"
called "create-with-container" && ko "不重複 create VM" || ok "不重複 create VM"

section "情境3：缺 Gemini 金鑰 → fail-fast，不建立 VM"
out=$(run_vm STUB_API_ENABLED=1 STUB_NO_SECRET=1); rc=$?
[[ $rc -ne 0 && "$out" == *"找不到 Gemini 金鑰"* ]] && ok "缺金鑰 → fail-fast" || ko "缺金鑰 → fail-fast" "$out"
called "create-with-container" && ko "未建立 VM" || ok "未建立 VM"

finish
