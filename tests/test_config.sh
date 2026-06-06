#!/usr/bin/env bash
# 單元測試：deploy/gen-config.mjs 產生的設定（用 node 跑、jq 斷言）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

echo "═══ 設定產生器單元測試 (test_config) ═══"

command -v node >/dev/null 2>&1 || { skip "全部" "no node"; finish; exit $?; }

GEN="deploy/gen-config.mjs"
TOK="aaaabbbbccccddddeeeeffff0000111122223333444455556666777788889999"
# 用 node eval 取值：$2 為 JS 存取式（如 .a.b、.arr[0]、.m["*"].x），免 jq 依賴
jget() { node -e 'let d=JSON.parse(require("fs").readFileSync(0,"utf8"));let v=eval("d"+process.argv[1]);console.log(v==null?"null":typeof v==="object"?JSON.stringify(v):v)' "$2" <<<"$1"; }

section "案例1：僅 token（預設值）"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" node "$GEN" --stdout 2>/dev/null)
assert_cmd "輸出為合法 JSON" bash -c "node -e 'JSON.parse(process.argv[1])' \"\$0\"" "$out"
assert_eq "auth.mode=token"        "token" "$(jget "$out" '.gateway.auth.mode')"
assert_eq "auth.token 正確寫入"     "$TOK"  "$(jget "$out" '.gateway.auth.token')"
assert_eq "model 預設"             "google/gemini-3-flash-preview" "$(jget "$out" '.agents.defaults.model.primary')"
assert_eq "deviceAuth 已豁免"       "true"  "$(jget "$out" '.gateway.controlUi.dangerouslyDisableDeviceAuth')"
assert_contains "googlechat 啟用"   "$out"  '"googlechat"'

section "案例2：OPENCLAW_PUBLIC_URL 帶入 allowedOrigins / audience"
URL="https://svc-abc-de.a.run.app"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" OPENCLAW_PUBLIC_URL="$URL" node "$GEN" --stdout 2>/dev/null)
assert_eq "allowedOrigins[0]=公開URL"  "$URL"               "$(jget "$out" '.gateway.controlUi.allowedOrigins[0]')"
assert_eq "googlechat audience 正確"   "$URL/googlechat"    "$(jget "$out" '.channels.googlechat.audience')"

section "案例3：GOOGLECHAT_ENABLED=false"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" GOOGLECHAT_ENABLED=false node "$GEN" --stdout 2>/dev/null)
assert_not_contains "無 googlechat 區塊" "$out" '"googlechat"'

section "案例4：LINE 雙金鑰 → 啟用 LINE 頻道"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" LINE_CHANNEL_SECRET=s LINE_CHANNEL_ACCESS_TOKEN=t node "$GEN" --stdout 2>/dev/null)
assert_contains "含 line 頻道"        "$out" '"line"'
assert_eq "line requireMention=true" "true" "$(jget "$out" '.channels.line.groups["*"].requireMention')"

section "案例5：Service Account 檔"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" GOOGLE_CHAT_SERVICE_ACCOUNT_FILE=/secrets/sa.json node "$GEN" --stdout 2>/dev/null)
assert_eq "serviceAccountFile 帶入" "/secrets/sa.json" "$(jget "$out" '.channels.googlechat.serviceAccountFile')"

section "案例6：缺 token → 失敗退出"
assert_fail "無 token 應 exit 非零" bash -c "OPENCLAW_GATEWAY_TOKEN='' node '$GEN' --stdout"

section "案例7：自訂模型"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" OPENCLAW_MODEL="google/gemini-2.5-flash" node "$GEN" --stdout 2>/dev/null)
assert_eq "model 可覆寫" "google/gemini-2.5-flash" "$(jget "$out" '.agents.defaults.model.primary')"

section "案例9：記憶 embedding provider（預設 none，免金鑰最穩）"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" node "$GEN" --stdout 2>/dev/null)
assert_eq "預設 none → 停用 memorySearch" "false" "$(jget "$out" '.agents.defaults.memorySearch.enabled')"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" GEMINI_API_KEY=AIzaMEMKEY OPENCLAW_MEMORY_PROVIDER=gemini node "$GEN" --stdout 2>/dev/null)
assert_eq "gemini → provider"             "gemini"               "$(jget "$out" '.agents.defaults.memorySearch.provider')"
assert_eq "gemini → model"                "gemini-embedding-001" "$(jget "$out" '.agents.defaults.memorySearch.model')"
assert_eq "gemini → remote.apiKey"        "AIzaMEMKEY"           "$(jget "$out" '.agents.defaults.memorySearch.remote.apiKey')"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" OPENCLAW_MEMORY_PROVIDER=openai node "$GEN" --stdout 2>/dev/null)
assert_eq "openai 可覆寫" "openai" "$(jget "$out" '.agents.defaults.memorySearch.provider')"

section "案例10：時區與 Cron"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" node "$GEN" --stdout 2>/dev/null)
assert_eq "userTimezone 預設 Asia/Taipei" "Asia/Taipei" "$(jget "$out" '.agents.defaults.userTimezone')"
assert_eq "timeFormat=24"                 "24"          "$(jget "$out" '.agents.defaults.timeFormat')"
assert_eq "cron.enabled=true"             "true"        "$(jget "$out" '.cron.enabled')"
out=$(OPENCLAW_GATEWAY_TOKEN="$TOK" OPENCLAW_TIMEZONE=America/Chicago node "$GEN" --stdout 2>/dev/null)
assert_eq "時區可覆寫"                     "America/Chicago" "$(jget "$out" '.agents.defaults.userTimezone')"

section "案例8：寫入檔案模式"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
OPENCLAW_GATEWAY_TOKEN="$TOK" OPENCLAW_CONFIG_PATH="$tmp/openclaw.json" node "$GEN" >/dev/null 2>&1
[[ -f "$tmp/openclaw.json" ]] && ok "已寫入指定路徑" || ko "已寫入指定路徑"
assert_cmd "寫出的檔為合法 JSON" node -e "JSON.parse(require('fs').readFileSync('$tmp/openclaw.json','utf8'))"

finish
