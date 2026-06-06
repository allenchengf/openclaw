#!/usr/bin/env bash
# 靜態檢查：檔案結構、bash 語法、JS 語法、YAML / JSON 合法性。
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$REPO_ROOT"

echo "═══ 靜態檢查 (test_static) ═══"

section "best-practice 檔案結構"
for f in README.md LICENSE Makefile .env.example .gitignore .dockerignore .gcloudignore \
         deploy/Dockerfile deploy/cloudbuild.yaml deploy/entrypoint.sh deploy/gen-config.mjs \
         deploy/gce-deploy.sh deploy/vm-https.sh scripts/devices-remote.sh scripts/doctor.sh tests/run.sh; do
  [[ -f "$f" ]] && ok "存在 $f" || ko "存在 $f" "缺少檔案"
done
[[ ! -f Dockerfile.cloudrun ]] && ok "舊路徑已移除 Dockerfile.cloudrun" || ko "舊路徑已移除 Dockerfile.cloudrun"

section "bash 語法 (bash -n)"
while IFS= read -r f; do
  assert_cmd "bash -n $f" bash -n "$f"
done < <(find deploy scripts tests -name '*.sh' 2>/dev/null)

section "JS 語法 (node --check)"
assert_cmd "node --check gen-config.mjs" node --check deploy/gen-config.mjs

section "YAML 合法性 (cloudbuild.yaml)"
if command -v python3 >/dev/null 2>&1 && python3 -c "import yaml" >/dev/null 2>&1; then
  assert_cmd "cloudbuild.yaml 可解析(PyYAML)" python3 -c "import yaml; yaml.safe_load(open('deploy/cloudbuild.yaml'))"
elif command -v gcloud >/dev/null 2>&1; then
  # 退而求其次：用 Python 內建簡易檢查（縮排與 key: 結構）+ 行尾無 tab
  assert_cmd "cloudbuild.yaml 無 tab 縮排" bash -c "! grep -Pq '\t' deploy/cloudbuild.yaml"
  skip "cloudbuild.yaml 完整 YAML 解析" "未安裝 PyYAML（pip install pyyaml）"
else
  skip "cloudbuild.yaml YAML 解析" "無 python3+PyYAML"
fi

section ".env.example 鍵值格式"
bad=$(grep -vE '^\s*(#.*)?$' .env.example | grep -vE '^[A-Z][A-Z0-9_]*=' || true)
[[ -z "$bad" ]] && ok ".env.example 全為 KEY=VALUE / 註解" || ko ".env.example 行格式" "$bad"

section ".gitignore 確實忽略機密"
assert_contains ".gitignore 含 .env" "$(cat .gitignore)" ".env"
assert_contains ".gitignore 含 token 檔" "$(cat .gitignore)" ".gateway-token.env"

section "Makefile 可解析"
assert_cmd "make help" make help

section "部署設定漂移防護（DRIFT-01：頻道 env 必須傳遞）"
cb=$(cat deploy/cloudbuild.yaml)
for v in GOOGLECHAT_ENABLED LINE_CHANNEL_SECRET LINE_CHANNEL_ACCESS_TOKEN OPENCLAW_MEMORY_PROVIDER; do
  assert_contains "cloudbuild --set-env-vars 含 $v" "$cb" "$v="
  assert_contains "cloudbuild 宣告 substitution _$v" "$cb" "_$v"
done
mkf=$(cat Makefile)
for v in _GOOGLECHAT_ENABLED _LINE_CHANNEL_SECRET _LINE_CHANNEL_ACCESS_TOKEN _OPENCLAW_MEMORY_PROVIDER; do
  assert_contains "Makefile deploy 帶入 $v" "$mkf" "$v="
done

section "port 一致性（Dockerfile ↔ cloudbuild）"
df=$(cat deploy/Dockerfile)
assert_contains "Dockerfile EXPOSE 8080" "$df" "EXPOSE 8080"
assert_contains "Dockerfile PORT=8080"   "$df" "PORT=8080"
assert_contains "cloudbuild --port=8080" "$cb" "--port=8080"

section "三份 ignore 機密條目一致"
for f in .gitignore .dockerignore .gcloudignore; do
  c=$(cat "$f")
  for pat in ".env" "*-sa.json" "*.key" "service-account*.json" ".gateway-token.env"; do
    assert_contains "$f 含 $pat" "$c" "$pat"
  done
done

section ".env.example 無行內註解（make include footgun 防護）"
inline=$(grep -nE '^[A-Z][A-Z0-9_]*=.+[[:space:]]#' .env.example || true)
[[ -z "$inline" ]] && ok ".env.example 值行無行內註解" || ko ".env.example 值行無行內註解" "$inline"

section "shell 變數緊接全形字元防護（set -u 解析陷阱）"
# $var 後緊接 CJK/全形括號會被 bash 當成變數名一部分 → set -u 報 unbound。應改用 ${var}。
hits=$(grep -rnE '\$[A-Za-z_][A-Za-z0-9_]*[（）：，「」、。]' deploy/*.sh scripts/*.sh tests/*.sh 2>/dev/null || true)
[[ -z "$hits" ]] && ok "無 \$var 緊接全形字元（應用 \${var}）" || ko "無 \$var 緊接全形字元" "$hits"

section "選用 linter"
if command -v shellcheck >/dev/null 2>&1; then
  assert_cmd "shellcheck entrypoint" shellcheck -S error deploy/entrypoint.sh
else
  skip "shellcheck" "未安裝（brew install shellcheck）"
fi
if command -v hadolint >/dev/null 2>&1; then
  assert_cmd "hadolint Dockerfile" hadolint deploy/Dockerfile
else
  skip "hadolint" "未安裝（brew install hadolint）"
fi

finish
