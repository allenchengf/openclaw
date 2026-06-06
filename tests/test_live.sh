#!/usr/bin/env bash
# 對「已部署的 Cloud Run 服務」做煙霧測試。
# 從 .env 讀 OPENCLAW_PUBLIC_URL 與 OPENCLAW_GATEWAY_TOKEN（或由環境傳入）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

echo "═══ 線上煙霧測試 (test_live) ═══"

# 載入 .env（若有）
[[ -f .env ]] && set -a && source .env && set +a

URL="${OPENCLAW_PUBLIC_URL:-}"
TOK="${OPENCLAW_GATEWAY_TOKEN:-}"
if [[ -z "$URL" || -z "$TOK" ]]; then
  skip "全部" "未設定 OPENCLAW_PUBLIC_URL / OPENCLAW_GATEWAY_TOKEN"; finish; exit $?
fi
if ! curl -s -o /dev/null --max-time 8 "$URL/" 2>/dev/null; then
  skip "全部" "$URL 無法連線"; finish; exit $?
fi

code() { curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$@"; }

section "服務可用性 ($URL)"
assert_eq "根頁 /=200" "200" "$(code "$URL/")"

section "token 驗證"
assert_eq "control-ui-config 正確 Bearer=200" "200" "$(code -H "Authorization: Bearer $TOK" "$URL/__openclaw/control-ui-config.json")"
assert_eq "control-ui-config 無 token=401"     "401" "$(code "$URL/__openclaw/control-ui-config.json")"

finish
