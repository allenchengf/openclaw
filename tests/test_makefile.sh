#!/usr/bin/env bash
# Makefile 編排 / 負面 / 冪等性測試（用 stub gcloud/docker，不觸碰雲端）。
# 覆蓋：check-env、gen-token 冪等、teardown-all 防呆、install fail-fast、
#       .env 尾端空白防呆($(strip))、make -n 解析、help/DEFAULT_GOAL。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "═══ Makefile 編排/負面/冪等 (test_makefile) ═══"

command -v make >/dev/null 2>&1 || { skip "全部" "no make"; finish; exit $?; }

# 沙箱：複製需要的檔案 + stub PATH
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$REPO_ROOT/Makefile" "$TMP/Makefile"
cp "$REPO_ROOT/.env.example" "$TMP/.env.example"
mkdir -p "$TMP/scripts" "$TMP/deploy" "$TMP/bin"
cp "$REPO_ROOT/scripts/doctor.sh" "$TMP/scripts/" 2>/dev/null || true
cp "$REPO_ROOT/deploy/cloudbuild.yaml" "$TMP/deploy/" 2>/dev/null || true

CALLLOG="$TMP/calls.log"; : > "$CALLLOG"
cat > "$TMP/bin/gcloud" <<EOF
#!/usr/bin/env bash
echo "gcloud \$*" >> "$CALLLOG"
case "\$*" in
  *"secrets describe"*) exit \${STUB_SECRET_RC:-0};;
  *"builds submit"*)    exit 0;;
  *) exit 0;;
esac
EOF
cat > "$TMP/bin/docker" <<EOF
#!/usr/bin/env bash
echo "docker \$*" >> "$CALLLOG"; exit 0
EOF
chmod +x "$TMP/bin/gcloud" "$TMP/bin/docker"
export PATH="$TMP/bin:$PATH"

mk() { ( cd "$TMP" && make "$@" ) 2>&1; }
mkrc() { ( cd "$TMP" && make "$@" >/dev/null 2>&1 ); }

section "check-env 負面/正面"
rm -f "$TMP/.env"
out=$(mk check-env); rc=$?
[[ $rc -ne 0 && "$out" == *"找不到 .env"* ]] && ok "無 .env → 失敗並提示 cp" || ko "無 .env → 失敗" "$out"
printf 'GCP_PROJECT_ID=\nOPENCLAW_GATEWAY_TOKEN=\n' > "$TMP/.env"
out=$(mk check-env); rc=$?
[[ $rc -ne 0 && "$out" == *"GCP_PROJECT_ID 未設"* ]] && ok "空 PROJECT_ID → 失敗" || ko "空 PROJECT_ID → 失敗" "$out"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\n' > "$TMP/.env"
out=$(mk check-env); rc=$?
[[ $rc -eq 0 && "$out" == *"OK"* ]] && ok "完整 .env → 通過" || ko "完整 .env → 通過" "$out"

section "gen-token 冪等性"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=\n' > "$TMP/.env"
mkrc gen-token
n1=$(grep -c '^OPENCLAW_GATEWAY_TOKEN=' "$TMP/.env")
v1=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$TMP/.env" | cut -d= -f2)
[[ "$n1" -eq 1 ]] && ok "就地替換（單一 token 行）" || ko "就地替換" "行數=$n1"
[[ "$v1" =~ ^[0-9a-f]{64}$ ]] && ok "token 為 64 hex" || ko "token 為 64 hex" "v=$v1"
mkrc gen-token
n2=$(grep -c '^OPENCLAW_GATEWAY_TOKEN=' "$TMP/.env")
[[ "$n2" -eq 1 ]] && ok "重跑仍單一行（冪等）" || ko "重跑仍單一行" "行數=$n2"
[[ ! -f "$TMP/.env.bak" ]] && ok "無殘留 .env.bak" || ko "無殘留 .env.bak"
# append 模式（無 token 行）
printf 'GCP_PROJECT_ID=demo\n' > "$TMP/.env"
mkrc gen-token
grep -qE '^OPENCLAW_GATEWAY_TOKEN=[0-9a-f]{64}$' "$TMP/.env" && ok "無 token 行時 append" || ko "無 token 行時 append"

section "teardown-all 防呆（未帶 CONFIRM 不得呼叫 gcloud delete）"
printf 'GCP_PROJECT_ID=demo\n' > "$TMP/.env"; : > "$CALLLOG"
out=$(mk teardown-all); rc=$?
[[ $rc -ne 0 && "$out" == *"CONFIRM=yes"* ]] && ok "無 CONFIRM → 拒絕" || ko "無 CONFIRM → 拒絕" "$out"
grep -q "delete" "$CALLLOG" && ko "未呼叫任何刪除" "$(cat "$CALLLOG")" || ok "未呼叫任何刪除"
: > "$CALLLOG"; mkrc teardown-all CONFIRM=yes
grep -q "run services delete" "$CALLLOG" && ok "CONFIRM=yes → 執行刪除" || ko "CONFIRM=yes → 執行刪除"

section "install fail-fast：google/* 模型缺 Gemini 金鑰不得部署（Vertex 預設則免金鑰）"
# 明確用 google/* 模型才觸發金鑰需求；預設已改 Vertex(google-vertex/*) 免金鑰
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nOPENCLAW_MODEL=google/gemini-2.5-flash\nGEMINI_API_KEY=\n' > "$TMP/.env"; : > "$CALLLOG"
out=$(STUB_SECRET_RC=1 mk install); rc=$?
[[ $rc -ne 0 && "$out" == *"找不到 Gemini 金鑰"* ]] && ok "缺金鑰 → fail fast" || ko "缺金鑰 → fail fast" "$out"
grep -q "builds submit" "$CALLLOG" && ko "未觸發 builds submit" "$(grep builds "$CALLLOG")" || ok "未觸發 builds submit"

section ".env 行內註解防呆（\$(strip) 不污染 IMAGE）"
printf 'GCP_PROJECT_ID=demo\nGCP_REGION=asia-east1   # 區域\n' > "$TMP/.env"
# 附加臨時 target 取得「展開後」的 IMAGE 值
printf '\n_print_image:\n\t@printf "%%s" "$(IMAGE)"\n' >> "$TMP/Makefile"
img=$( cd "$TMP" && make _print_image 2>/dev/null )
exp="asia-east1-docker.pkg.dev/demo/clawdbot-repo/clawdbot:v1"
assert_eq "IMAGE 無空白污染（strip 生效）" "$exp" "$img"
# 還原 Makefile（移除臨時 target，避免影響後續 -n 解析測試）
cp "$REPO_ROOT/Makefile" "$TMP/Makefile"

section "make -n 可解析所有 target（無語法/展開錯誤）"
printf 'GCP_PROJECT_ID=demo\nOPENCLAW_GATEWAY_TOKEN=tok\nGEMINI_API_KEY=k\n' > "$TMP/.env"
targets=$(grep -oE '^[a-zA-Z0-9_-]+:.*## ' "$TMP/Makefile" | sed 's/:.*//' | sort -u)
bad=0
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  ( cd "$TMP" && make -n "$t" >/dev/null 2>&1 ) || { bad=$((bad+1)); echo "      └─ make -n $t 失敗"; }
done <<< "$targets"
[[ $bad -eq 0 ]] && ok "所有 target make -n 解析通過" || ko "所有 target make -n 解析通過" "$bad 個失敗"

section "help 與 DEFAULT_GOAL"
out=$(mk)              # 無參數 → 預設 help
[[ "$out" == *"install"* && "$out" == *"doctor"* ]] && ok "無參數 make 顯示 help（含 install/doctor）" || ko "DEFAULT_GOAL=help" "$out"

section "VM 生命週期防呆（vm-teardown / vm-delete）"
printf 'GCP_PROJECT_ID=demo\nGCE_VM_NAME=clawdbot-vm\n' > "$TMP/.env"; : > "$CALLLOG"
out=$(mk vm-teardown); rc=$?
[[ $rc -ne 0 && "$out" == *"CONFIRM=yes"* ]] && ok "vm-teardown 無 CONFIRM → 拒絕" || ko "vm-teardown 無 CONFIRM → 拒絕" "$out"
grep -qE "instances delete|disks delete|addresses delete" "$CALLLOG" && ko "未刪任何資源" "$(cat "$CALLLOG")" || ok "未刪任何資源"
: > "$CALLLOG"; mkrc vm-teardown CONFIRM=yes
grep -q "instances delete" "$CALLLOG" && grep -q "disks delete" "$CALLLOG" && grep -q "addresses delete" "$CALLLOG" && ok "CONFIRM=yes → 刪 VM+磁碟+IP" || ko "CONFIRM=yes → 全刪"
: > "$CALLLOG"; mkrc vm-delete
grep -q "instances delete" "$CALLLOG" && ok "vm-delete 刪 instance" || ko "vm-delete 刪 instance"
grep -qE "disks delete|addresses delete" "$CALLLOG" && ko "vm-delete 保留磁碟與IP（記憶不丟）" "$(cat "$CALLLOG")" || ok "vm-delete 保留磁碟與IP（記憶不丟）"

section "孤兒鍵 / 設定漂移防護"
grep -q 'GOOGLE_CHAT_SA_SECRET' "$REPO_ROOT/.env.example" && ko "已移除孤兒鍵 GOOGLE_CHAT_SA_SECRET" || ok "已移除孤兒鍵 GOOGLE_CHAT_SA_SECRET"

finish
