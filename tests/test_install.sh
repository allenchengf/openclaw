#!/usr/bin/env bash
# make install 多情境測試（stub gcloud/docker，不觸碰雲端）。
# 驗證各情境下的編排、相依、容錯、是否誤觸發部署(builds submit)。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "═══ make install 多情境 (test_install) ═══"
command -v make >/dev/null 2>&1 || { skip "全部" "no make"; finish; exit $?; }

# 沙箱 + stub
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$REPO_ROOT/Makefile" "$TMP/Makefile"
cp "$REPO_ROOT/.env.example" "$TMP/.env.example"
mkdir -p "$TMP/scripts" "$TMP/deploy" "$TMP/bin"
cp "$REPO_ROOT/scripts/doctor.sh" "$TMP/scripts/"
cp "$REPO_ROOT/deploy/cloudbuild.yaml" "$TMP/deploy/"

CALLLOG="$TMP/calls.log"
cat > "$TMP/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$CALLLOG"
case "\$*" in
  *"secrets describe"*)        exit \${STUB_SECRET_RC:-0};;
  *"run services describe"*)   echo "https://clawdbot-stub-de.a.run.app"; exit 0;;
  *"secrets versions access"*) echo "AIzaSTUBKEY"; exit 0;;
  *) exit 0;;
esac
EOF
cat > "$TMP/bin/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$CALLLOG"; exit 0
EOF
# curl stub：避免 doctor 對假 URL 真的連網
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in *control-ui-config*) echo 200; exit 0;; esac; done
echo 200; exit 0
EOF
chmod +x "$TMP"/bin/*
export PATH="$TMP/bin:$PATH"

run_install() { : > "$CALLLOG"; ( cd "$TMP" && env "$@" make install ) 2>&1; }
called()    { grep -q "$1" "$CALLLOG"; }
order_ok()  { # $1 在 $2 之前
  local a b; a=$(grep -n "$1" "$CALLLOG" | head -1 | cut -d: -f1); b=$(grep -n "$2" "$CALLLOG" | head -1 | cut -d: -f1)
  [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]; }

section "情境1：無 .env → check-env 擋下，不呼叫任何 gcloud"
rm -f "$TMP/.env"
out=$(run_install); rc=$?
[[ $rc -ne 0 && "$out" == *"找不到 .env"* ]] && ok "無 .env → 失敗並提示 cp" || ko "無 .env → 失敗" "$out"
called "gcloud" && ko "未呼叫 gcloud" "$(cat "$CALLLOG")" || ok "未呼叫 gcloud"

section "情境2：缺 GCP_PROJECT_ID → check-env 擋下，未部署"
printf 'GCP_PROJECT_ID=\nOPENCLAW_GATEWAY_TOKEN=tok\nGEMINI_API_KEY=k\n' > "$TMP/.env"
out=$(run_install); rc=$?
[[ $rc -ne 0 && "$out" == *"GCP_PROJECT_ID 未設"* ]] && ok "缺 PROJECT_ID → 失敗" || ko "缺 PROJECT_ID → 失敗" "$out"
called "builds submit" && ko "未觸發 builds submit" || ok "未觸發 builds submit"

section "情境3：無 Gemini 金鑰（secret 不存在）→ fail-fast 不部署"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nGEMINI_API_KEY=\n' > "$TMP/.env"
out=$(run_install STUB_SECRET_RC=1); rc=$?
[[ $rc -ne 0 && "$out" == *"找不到 Gemini 金鑰"* ]] && ok "缺金鑰 → fail-fast" || ko "缺金鑰 → fail-fast" "$out"
called "builds submit" && ko "未觸發 builds submit" || ok "未觸發 builds submit"
called "enable" && ok "fail-fast 前已先跑 bootstrap（enable-apis）" || ko "已先跑 bootstrap"

section "情境4：happy path（KEY= 提供金鑰）→ 完整編排"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nGEMINI_API_KEY=\n' > "$TMP/.env"
out=$(run_install KEY=AIzaTESTKEY); rc=$?
[[ $rc -eq 0 ]] && ok "install 成功 exit 0" || ko "install 成功 exit 0" "$out"
called "secrets create\|secrets versions add" && ok "KEY 寫入 Secret Manager" || ko "KEY 寫入 Secret Manager"
called "builds submit" && ok "觸發 builds submit（部署）" || ko "觸發 builds submit"
called "add-iam-policy-binding" && ok "自動 allow-public" || ko "自動 allow-public"
order_ok "enable" "builds submit" && ok "順序：bootstrap 在 deploy 之前" || ko "順序：bootstrap→deploy"
order_ok "builds submit" "add-iam-policy-binding" && ok "順序：deploy 在 allow-public 之前" || ko "順序：deploy→allow-public"
order_ok "builds submit" "update" && ok "順序：deploy 後 refresh-url(update)" || ko "順序：deploy→refresh-url"

section "情境5：金鑰來自 .env（無 KEY）→ 直接使用並部署"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nGEMINI_API_KEY=AIzaFromEnv\n' > "$TMP/.env"
out=$(run_install); rc=$?
[[ $rc -eq 0 && "$out" == *"使用 .env 的 GEMINI_API_KEY"* ]] && ok "使用 .env 金鑰" || ko "使用 .env 金鑰" "$out"
called "builds submit" && ok "觸發部署" || ko "觸發部署"

section "情境6：金鑰來自既有 Secret（無 KEY、.env 無金鑰、secret 存在）"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nGEMINI_API_KEY=\n' > "$TMP/.env"
out=$(run_install STUB_SECRET_RC=0); rc=$?
[[ $rc -eq 0 && "$out" == *"使用既有 secret"* ]] && ok "使用既有 secret" || ko "使用既有 secret" "$out"
called "builds submit" && ok "觸發部署" || ko "觸發部署"

section "情境7：無 token → install 自動 gen-token 後再部署"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=\nGEMINI_API_KEY=AIzaX\n' > "$TMP/.env"
out=$(run_install); rc=$?
tok=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$TMP/.env" | cut -d= -f2)
[[ $rc -eq 0 ]] && ok "install 成功" || ko "install 成功" "$out"
[[ "$tok" =~ ^[0-9a-f]{64}$ ]] && ok "自動產生 64 hex token 並寫回 .env" || ko "自動產生 token" "tok=$tok"
called "builds submit" && ok "帶新 token 觸發部署" || ko "觸發部署"

finish
