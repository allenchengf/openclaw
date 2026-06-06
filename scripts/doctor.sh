#!/usr/bin/env bash
# 功能檢測（health / function check）：本機工具 → GCP 前置 → 服務健康 → token 驗證。
# 由 `make doctor` 呼叫，也可獨立執行：bash scripts/doctor.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ -f .env ]] && { set -a; source .env; set +a; }

if [[ -t 1 ]]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; Z=$'\033[0m'; else G=; R=; Y=; Z=; fi
FAIL=0
ok()   { echo "  ${G}✓${Z} $1"; }
bad()  { echo "  ${R}✗${Z} $1"; [[ -n "${2:-}" ]] && echo "      └─ $2"; FAIL=$((FAIL+1)); }
warn() { echo "  ${Y}∼${Z} $1"; [[ -n "${2:-}" ]] && echo "      └─ $2"; }

GCP_REGION="${GCP_REGION:-asia-east1}"
AR_REPO_NAME="${AR_REPO_NAME:-clawdbot-repo}"
SERVICE_NAME="${SERVICE_NAME:-clawdbot}"
GCLOUD=(gcloud)
[[ -n "${GCP_PROJECT_ID:-}" ]] && GCLOUD+=(--project="$GCP_PROJECT_ID")
[[ -n "${GCP_ACCOUNT:-}" ]] && GCLOUD+=(--account="$GCP_ACCOUNT")

echo "═══ openclaw-Taiwan doctor ═══"

echo ""; echo "▸ 本機工具"
for t in gcloud docker node make openssl; do
  command -v "$t" >/dev/null 2>&1 && ok "$t 已安裝" || { [[ "$t" == docker ]] && warn "$t 未安裝（僅本機測試需要）" || bad "$t 未安裝"; }
done

echo ""; echo "▸ .env 設定"
if [[ -f .env ]]; then ok ".env 存在"; else bad ".env 不存在" "cp .env.example .env"; fi
[[ -n "${GCP_PROJECT_ID:-}" ]] && ok "GCP_PROJECT_ID=$GCP_PROJECT_ID" || bad "GCP_PROJECT_ID 未設"
if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
  [[ ${#OPENCLAW_GATEWAY_TOKEN} -eq 64 ]] && ok "OPENCLAW_GATEWAY_TOKEN（64 hex）" || warn "OPENCLAW_GATEWAY_TOKEN 長度非 64（建議 make gen-token）"
else warn "OPENCLAW_GATEWAY_TOKEN 未設（make gen-token）"; fi
# .env 與 .env.example 鍵一致性
if [[ -f .env && -f .env.example ]]; then
  miss=$(comm -23 <(grep -oE '^[A-Z][A-Z0-9_]*' .env.example | sort -u) <(grep -oE '^[A-Z][A-Z0-9_]*' .env | sort -u) | tr '\n' ' ')
  [[ -z "$miss" ]] && ok ".env 涵蓋 .env.example 所有鍵" || warn ".env 缺少鍵：$miss"
fi

if ! command -v gcloud >/dev/null 2>&1; then
  echo ""; echo "（無 gcloud，略過雲端檢查）"; echo ""; [[ $FAIL -eq 0 ]] && echo "結果：本機檢查通過" || echo "結果：$FAIL 項失敗"; exit $((FAIL>0))
fi

echo ""; echo "▸ GCP 認證與專案"
acct=$(gcloud config get-value account 2>/dev/null)
[[ -n "$acct" ]] && ok "gcloud 已登入（${acct}）" || bad "gcloud 未登入" "gcloud auth login"
if [[ -n "${GCP_PROJECT_ID:-}" ]]; then
  if "${GCLOUD[@]}" projects describe "$GCP_PROJECT_ID" >/dev/null 2>&1; then ok "可存取專案 $GCP_PROJECT_ID"; else bad "無法存取專案 $GCP_PROJECT_ID"; fi
  be=$("${GCLOUD[@]}" billing projects describe "$GCP_PROJECT_ID" --format='value(billingEnabled)' 2>/dev/null)
  [[ "$be" == "True" ]] && ok "計費已啟用" || bad "計費未啟用" "Cloud Run 需要計費"
fi

echo ""; echo "▸ GCP 前置資源"
for api in run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com; do
  if "${GCLOUD[@]}" services list --enabled --filter="config.name=$api" --format='value(config.name)' 2>/dev/null | grep -q "$api"; then ok "API $api"; else warn "API $api 未啟用" "make enable-apis"; fi
done
if "${GCLOUD[@]}" artifacts repositories describe "$AR_REPO_NAME" --location="$GCP_REGION" >/dev/null 2>&1; then ok "Artifact Registry $AR_REPO_NAME"; else warn "映像庫 $AR_REPO_NAME 不存在" "make create-repo"; fi
if [[ -n "${GEMINI_API_KEY:-}" ]]; then ok "Gemini 金鑰（來自 .env）"; \
elif "${GCLOUD[@]}" secrets describe gemini-api-key >/dev/null 2>&1; then ok "Gemini 金鑰（Secret Manager）"; \
else bad "找不到 Gemini 金鑰" "make secret-set-gemini KEY=... 或在 .env 設 GEMINI_API_KEY"; fi

echo ""; echo "▸ Cloud Run 服務健康"
url=$("${GCLOUD[@]}" run services describe "$SERVICE_NAME" --region="$GCP_REGION" --format='value(status.url)' 2>/dev/null)
if [[ -z "$url" ]]; then
  warn "服務 $SERVICE_NAME 尚未部署" "make install / make deploy"
else
  ready=$("${GCLOUD[@]}" run services describe "$SERVICE_NAME" --region="$GCP_REGION" --format='value(status.conditions[0].status)' 2>/dev/null)
  [[ "$ready" == "True" ]] && ok "服務 Ready（${url}）" || bad "服務未就緒" "$ready"
  rc=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url/" 2>/dev/null)
  [[ "$rc" == "200" ]] && ok "根頁可達（200）" || bad "根頁回應 $rc" "可能需 make allow-public"
  if [[ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    a=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -H "Authorization: Bearer $OPENCLAW_GATEWAY_TOKEN" "$url/__openclaw/control-ui-config.json" 2>/dev/null)
    n=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "$url/__openclaw/control-ui-config.json" 2>/dev/null)
    [[ "$a" == "200" ]] && ok "token 驗證（Bearer→200）" || bad "token 驗證失敗（Bearer→${a}）"
    [[ "$n" == "401" ]] && ok "無 token 受保護（→401）" || warn "無 token 回應 ${n}（預期 401）"
  fi
fi

echo ""
if [[ $FAIL -eq 0 ]]; then echo "${G}結果：全部檢查通過 ✅${Z}"; exit 0; else echo "${R}結果：$FAIL 項失敗 ❌${Z}"; exit 1; fi
