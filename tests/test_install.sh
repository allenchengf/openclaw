#!/usr/bin/env bash
# make install 多情境測試（stub gcloud/docker/ssh，不觸碰雲端）。
# 驗證新版「完整持久安裝」：Cloud Run + VM(vm-deploy) + HTTPS(vm-https) + 帶令牌 Dashboard 啟動檔。
# 預設模型為 Vertex(google-vertex/*)，免 Gemini 金鑰；google/* 模型才需金鑰且缺則 fail-fast。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "═══ make install 多情境 (test_install) ═══"
command -v make >/dev/null 2>&1 || { skip "全部" "no make"; finish; exit $?; }

# 沙箱 + stub
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$REPO_ROOT/Makefile" "$TMP/Makefile"
cp "$REPO_ROOT/.env.example" "$TMP/.env.example"
mkdir -p "$TMP/scripts" "$TMP/deploy" "$TMP/bin"
cp "$REPO_ROOT/scripts/doctor.sh" "$TMP/scripts/"
# 完整安裝會用到的部署腳本（Cloud Run + VM + HTTPS + 啟動檔）
cp "$REPO_ROOT/deploy/cloudbuild.yaml" "$TMP/deploy/"
cp "$REPO_ROOT/deploy/gce-deploy.sh" "$TMP/deploy/"
cp "$REPO_ROOT/deploy/vm-https.sh" "$TMP/deploy/"
cp "$REPO_ROOT/deploy/gen-dashboard-launcher.sh" "$TMP/deploy/"

CALLLOG="$TMP/calls.log"
cat > "$TMP/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$CALLLOG"
case "\$*" in
  *"secrets describe"*)         exit \${STUB_SECRET_RC:-0};;
  *"run services describe"*)    echo "https://clawdbot-stub-de.a.run.app"; exit 0;;
  *"secrets versions access"*)  echo "AIzaSTUBKEY"; exit 0;;
  *"services list"*)            echo "compute.googleapis.com"; exit 0;;   # compute 視為已啟用
  *"addresses describe"*)       echo "203.0.113.50"; exit 0;;             # VM 靜態 IP（含 --format 取值）
  *"instances describe"*"--format"*) echo "RUNNING"; exit 0;;            # vm-https 查狀態
  *"instances describe"*)       exit 1;;                                  # 存在性檢查→不存在→走 create-with-container（帶 mount-disk）
  *"ssh"*)                      exit 0;;                                  # vm-https 起 Caddy
  *) exit 0;;
esac
EOF
cat > "$TMP/bin/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$CALLLOG"; exit 0
EOF
# curl stub：避免 doctor / vm-https 對假 URL 真的連網（一律回 200）
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *control-ui-config*) echo 200; exit 0;; esac; done
echo 200; exit 0
EOF
chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$PATH"

run_install() { : > "$CALLLOG"; ( cd "$TMP" && env "$@" make install ) 2>&1; }
called()    { grep -q "$1" "$CALLLOG"; }
order_ok()  { # $1 在 $2 之前（皆取首次出現）
  local a b; a=$(grep -n "$1" "$CALLLOG" | head -1 | cut -d: -f1); b=$(grep -n "$2" "$CALLLOG" | head -1 | cut -d: -f1)
  [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]; }

section "情境1：無 .env → check-env 擋下，不呼叫任何 gcloud"
rm -f "$TMP/.env"
out=$(run_install); rc=$?
[[ $rc -ne 0 && "$out" == *"找不到 .env"* ]] && ok "無 .env → 失敗並提示 cp" || ko "無 .env → 失敗" "$out"
called "gcloud" && ko "未呼叫 gcloud" "$(cat "$CALLLOG")" || ok "未呼叫 gcloud"

section "情境2：缺 GCP_PROJECT_ID → check-env 擋下，未部署"
printf 'GCP_PROJECT_ID=\nOPENCLAW_GATEWAY_TOKEN=tok\n' > "$TMP/.env"
out=$(run_install); rc=$?
[[ $rc -ne 0 && "$out" == *"GCP_PROJECT_ID 未設"* ]] && ok "缺 PROJECT_ID → 失敗" || ko "缺 PROJECT_ID → 失敗" "$out"
called "builds submit" && ko "未觸發 builds submit" || ok "未觸發 builds submit"

section "情境3：google/* 模型 + 無金鑰（secret 不存在）→ fail-fast 不部署"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nOPENCLAW_MODEL=google/gemini-2.5-flash\nGEMINI_API_KEY=\n' > "$TMP/.env"
out=$(run_install STUB_SECRET_RC=1); rc=$?
[[ $rc -ne 0 && "$out" == *"找不到 Gemini 金鑰"* ]] && ok "缺金鑰 → fail-fast" || ko "缺金鑰 → fail-fast" "$out"
called "builds submit" && ko "未觸發 builds submit" || ok "未觸發 builds submit"
called "enable" && ok "fail-fast 前已先跑 bootstrap（enable-apis）" || ko "已先跑 bootstrap"

section "情境4：Vertex 預設（免金鑰）happy path → Cloud Run + VM + HTTPS + 啟動檔完整編排"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\n' > "$TMP/.env"   # 無 OPENCLAW_MODEL → 預設 Vertex
rm -f "$TMP/clawdbot-dashboard.html"
out=$(run_install); rc=$?
[[ $rc -eq 0 ]] && ok "install 成功 exit 0（Vertex 免金鑰）" || ko "install 成功 exit 0" "$out"
[[ "$out" == *"Vertex AI"* ]] && ok "走 Vertex AI 認證（免金鑰）" || ko "走 Vertex AI 認證" "$out"
called "builds submit" && ok "觸發 builds submit（Cloud Run 部署）" || ko "觸發 builds submit"
called "run.invoker" && ok "自動 allow-public（allUsers→run.invoker）" || ko "自動 allow-public"
called "aiplatform.user" && ok "授予 Vertex 權限（aiplatform.user）" || ko "授予 aiplatform.user"
called "container-mount-disk=mount-path=/root/.openclaw" && ok "VM 掛載持久磁碟（vm-deploy）" || ko "VM 掛載持久磁碟"
called "ssh" && ok "VM HTTPS 起 Caddy（vm-https）" || ko "VM HTTPS（vm-https）"
[[ -f "$TMP/clawdbot-dashboard.html" ]] && ok "產生帶令牌 Dashboard 啟動檔" || ko "產生 Dashboard 啟動檔"
grep -q "#token=tok" "$TMP/clawdbot-dashboard.html" 2>/dev/null && ok "啟動檔已帶 gateway token" || ko "啟動檔帶 token"
order_ok "builds submit" "run.invoker"      && ok "順序：deploy 在 allow-public 之前" || ko "順序：deploy→allow-public"
order_ok "run.invoker" "container-mount-disk\|update-container" && ok "順序：Cloud Run 在 VM 之前" || ko "順序：CloudRun→VM"

section "情境5：google/* 模型 + .env 金鑰 → 使用並完整部署"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nOPENCLAW_MODEL=google/gemini-2.5-flash\nGEMINI_API_KEY=AIzaFromEnv\n' > "$TMP/.env"
out=$(run_install); rc=$?
[[ $rc -eq 0 && "$out" == *"使用 .env 的 GEMINI_API_KEY"* ]] && ok "使用 .env 金鑰" || ko "使用 .env 金鑰" "$out"
called "builds submit" && ok "觸發部署" || ko "觸發部署"

section "情境6：無 token → install 自動 gen-token 後再完整部署"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=\n' > "$TMP/.env"
out=$(run_install); rc=$?
tok=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$TMP/.env" | cut -d= -f2)
[[ $rc -eq 0 ]] && ok "install 成功" || ko "install 成功" "$out"
[[ "$tok" =~ ^[0-9a-f]{64}$ ]] && ok "自動產生 64 hex token 並寫回 .env" || ko "自動產生 token" "tok=$tok"
called "builds submit" && ok "帶新 token 觸發部署" || ko "觸發部署"

finish
