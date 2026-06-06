#!/usr/bin/env bash
# 整合測試：用 deploy/Dockerfile build 映像 → 啟動容器 → smoke。
# 驗證重構後的映像仍能正確啟動 gateway、token 驗證行為正確。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

echo "═══ 整合測試 (test_integration) ═══"

if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  skip "全部" "docker 不可用"; finish; exit $?
fi

IMG=clawdbot-test
NAME=clawdbot-test
PORT=18099
TOK="testtoken0000111122223333444455556666777788889999aaaabbbbcccc1234"
URL="http://localhost:$PORT"
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
cleanup

section "建置映像 (deploy/Dockerfile)"
if docker build -q -f deploy/Dockerfile --build-arg OPENCLAW_VERSION="${OPENCLAW_VERSION:-2026.6.1}" -t "$IMG" . >/tmp/clawdbot-build-test.log 2>&1; then
  ok "docker build 成功"
else
  ko "docker build 成功" "見 /tmp/clawdbot-build-test.log"; finish; exit $?
fi

section "CONFIG_ONLY 模式（不啟動 gateway 只產生設定）"
co=$(docker run --rm -e OPENCLAW_GATEWAY_TOKEN="$TOK" -e CLAWDBOT_CONFIG_ONLY=1 "$IMG" 2>&1)
assert_contains "印出 config 路徑" "$co" "Config written"
assert_contains "token 已遮蔽顯示"  "$co" '"token": "***"'
assert_contains "正常結束訊息"      "$co" "exiting without starting gateway"

section "啟動 gateway 容器"
docker run -d --name "$NAME" -p "$PORT:8080" \
  -e OPENCLAW_GATEWAY_TOKEN="$TOK" \
  -e OPENCLAW_PUBLIC_URL="$URL" \
  -e GEMINI_API_KEY="local-test" "$IMG" >/dev/null
# 等待 gateway listening（最多 ~60s）
ready=0
for _ in $(seq 1 30); do
  if docker logs "$NAME" 2>&1 | grep -q "http server listening"; then ready=1; break; fi
  if [[ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != "true" ]]; then break; fi
  sleep 2
done
[[ $ready -eq 1 ]] && ok "gateway 已 listening" || { ko "gateway 已 listening" "$(docker logs "$NAME" 2>&1 | tail -5)"; finish; exit $?; }

code() { curl -s -o /dev/null -w '%{http_code}' "$@"; }
section "HTTP 行為"
assert_eq "根頁 /=200"                              "200" "$(code "$URL/")"
assert_eq "control-ui-config 無 token=401"          "401" "$(code "$URL/__openclaw/control-ui-config.json")"
assert_eq "control-ui-config 正確 Bearer=200"        "200" "$(code -H "Authorization: Bearer $TOK" "$URL/__openclaw/control-ui-config.json")"
assert_eq "control-ui-config 錯誤 Bearer=401"        "401" "$(code -H "Authorization: Bearer wrong" "$URL/__openclaw/control-ui-config.json")"

section "容器內設定正確性"
cfg=$(docker exec "$NAME" cat /root/.openclaw/openclaw.json 2>/dev/null)
assert_contains "config token 正確" "$cfg" "$TOK"
assert_contains "allowedOrigins 含公開URL" "$cfg" "$URL"

finish
