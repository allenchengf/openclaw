#!/usr/bin/env bash
# 文件正確性測試：README / .env.example 與實作一致（指令、路徑、變數無錯）。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT" || exit 1

echo "═══ 文件正確性 (test_docs) ═══"

README=README.md

section "README 不得引用已搬移/刪除的舊路徑"
for old in "Dockerfile.cloudrun" "scripts/cloudrun-entrypoint.sh" "env.example.txt"; do
  if grep -q "$old" "$README"; then ko "無舊路徑 $old"; else ok "無舊路徑 $old"; fi
done

section "README markdown 連結指向的本地檔案都存在"
# 抓 ](target) 內容（支援中文檔名）；略過 http/mailto/純錨點，去除 #fragment
links=$(grep -oE '\]\([^)]+\)' "$README" | sed -E 's/^\]\(//; s/\)$//')
while IFS= read -r l; do
  [[ -z "$l" ]] && continue
  case "$l" in http*|mailto:*|\#*) continue;; esac
  t="${l%%#*}"                       # 去掉錨點
  [[ -z "$t" ]] && continue
  if [[ -e "$t" ]]; then ok "連結存在 $t"; else ko "連結存在 $t" "README 連結但檔案不存在"; fi
done <<< "$links"

section "README 提到的 make 指令都是有效 target"
targets=$(grep -oE '^[a-zA-Z0-9_-]+:' Makefile | sed 's/://' | sort -u)
mk=$(grep -oE 'make [a-z][a-z0-9-]+' "$README" | awk '{print $2}' | sort -u)
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  if grep -qx "$t" <<< "$targets"; then ok "make $t 存在"; else ko "make $t 存在" "README 提到但 Makefile 無此 target"; fi
done <<< "$mk"

section "關鍵 Makefile target 有被 README 記錄"
for t in install reinstall uninstall doctor deploy test; do
  if grep -q "make $t" "$README"; then ok "README 記錄 make $t"; else ko "README 記錄 make $t"; fi
done

section ".env.example 必填鍵都在 README 設定表"
for k in GCP_PROJECT_ID GCP_ACCOUNT GEMINI_API_KEY OPENCLAW_GATEWAY_TOKEN OPENCLAW_PUBLIC_URL; do
  if grep -q "$k" "$README"; then ok "README 記載 $k"; else ko "README 記載 $k"; fi
done

section "README 安裝/配置流程章節齊全"
for sec in "快速開始" "設定參考" "頻道設定" "測試" "疑難排解"; do
  if grep -q "${sec}" "$README"; then ok "含章節 ${sec}"; else ko "含章節 ${sec}"; fi
done
grep -q "cp .env.example .env" "$README" && ok "含複製 .env 步驟" || ko "含複製 .env 步驟"
grep -q "make install" "$README" && ok "含一鍵安裝指令" || ko "含一鍵安裝指令"

finish
