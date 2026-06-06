#!/usr/bin/env bash
# doctor 健檢多情境測試（scripts/doctor.sh，stub gcloud/curl，不觸碰雲端）。
# 驗證：本機工具偵測、.env 鍵一致、雲端各檢查分支、健康/不健康判定與 exit code、
#       無 gcloud 時僅跑本機檢查、多位元組字元安全（set -u 不報 unbound）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "═══ doctor 健檢多情境 (test_doctor) ═══"
command -v bash >/dev/null 2>&1 || { skip "全部" "no bash"; finish; exit $?; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/scripts" "$TMP/bin"
cp "$REPO_ROOT/scripts/doctor.sh" "$TMP/scripts/"
cp "$REPO_ROOT/.env.example" "$TMP/.env.example"

CALLLOG="$TMP/calls.log"
cat > "$TMP/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$CALLLOG"
case "\$*" in
  *"config get-value account"*)        echo "tester@example.com"; exit 0;;
  *"billing projects describe"*)       echo "\${STUB_BILLING:-True}"; exit 0;;
  *"projects describe"*)               exit \${STUB_PROJ_RC:-0};;
  *"services list"*)                   echo "\$*" | grep -oE '[a-z]+\.googleapis\.com' | head -1; exit 0;;
  *"artifacts repositories describe"*) exit 0;;
  *"secrets describe"*)                exit \${STUB_SECRET_RC:-0};;
  *"run services describe"*"status.url"*) [ "\${STUB_NO_SVC:-0}" = "1" ] && exit 0; echo "https://svc-stub-de.a.run.app"; exit 0;;
  *"run services describe"*)           echo "True"; exit 0;;
  *) exit 0;;
esac
EOF
# curl stub：帶 Authorization → 200；control-ui-config 無 token → 401；其餘(根頁)→ STUB_HTTP
cat > "$TMP/bin/curl" <<'EOF'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *Authorization*)        echo 200; exit 0;;
  *control-ui-config*)    echo 401; exit 0;;
  *)                      echo "${STUB_HTTP:-200}"; exit 0;;
esac
EOF
chmod +x "$TMP/bin/gcloud" "$TMP/bin/curl"

run_doc() { ( cd "$TMP" && env "PATH=$TMP/bin:$PATH" "$@" bash scripts/doctor.sh ) 2>&1; }

section "情境1：完整健康 → 全通過 exit 0"
printf 'GCP_PROJECT_ID=demo\nGCP_ACCOUNT=tester@example.com\nGEMINI_API_KEY=AIzaX\nOPENCLAW_GATEWAY_TOKEN=%064d\n' 0 > "$TMP/.env"
out=$(run_doc STUB_HTTP=200); rc=$?
[[ $rc -eq 0 && "$out" == *"全部檢查通過"* ]] && ok "健康 → exit 0、全部通過" || ko "健康 → exit 0" "$(echo "$out" | tail -4)"
[[ "$out" == *"openclaw-Taiwan doctor"* ]] && ok "輸出標頭正常（無 set -u 多位元組崩潰）" || ko "無 set -u 崩潰" "$out"
assert_contains "計費檢查" "$out" "計費已啟用"
assert_contains "token 驗證 Bearer 200" "$out" "Bearer→200"

section "情境2：缺 GCP_PROJECT_ID → 標記失敗"
printf 'GCP_PROJECT_ID=\nGEMINI_API_KEY=AIzaX\n' > "$TMP/.env"
out=$(run_doc); rc=$?
[[ $rc -ne 0 ]] && ok "缺 PROJECT_ID → exit 非零" || ko "缺 PROJECT_ID → 失敗" "$out"

section "情境3：服務未部署 → 警告但本機檢查仍判定"
printf 'GCP_PROJECT_ID=demo\nGCP_ACCOUNT=t@e.com\nGEMINI_API_KEY=AIzaX\nOPENCLAW_GATEWAY_TOKEN=%064d\n' 0 > "$TMP/.env"
out=$(run_doc STUB_NO_SVC=1); rc=$?
assert_contains "服務未部署提示" "$out" "尚未部署"

section "情境4：服務 403（未開放）→ 標記失敗並提示 allow-public"
out=$(run_doc STUB_HTTP=403); rc=$?
[[ $rc -ne 0 && "$out" == *"allow-public"* ]] && ok "403 → 失敗並提示 allow-public" || ko "403 → 失敗" "$(echo "$out"|grep -i 403)"

section "情境5：無 gcloud → 只跑本機檢查"
printf 'GCP_PROJECT_ID=demo\nGEMINI_API_KEY=AIzaX\nOPENCLAW_GATEWAY_TOKEN=%064d\n' 0 > "$TMP/.env"
out=$( cd "$TMP" && env "PATH=/usr/bin:/bin" bash scripts/doctor.sh 2>&1 )
assert_contains "無 gcloud 時略過雲端檢查" "$out" "略過雲端檢查"

section "情境6：.env 缺 .env.example 的鍵 → 警告"
printf 'GCP_PROJECT_ID=demo\n' > "$TMP/.env"
out=$(run_doc);
assert_contains ".env 鍵一致性檢查存在" "$out" ".env"

finish
