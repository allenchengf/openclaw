# openclaw-Taiwan — 部署與維運入口
# 所有設定來自 .env（複製 .env.example）。執行 `make` 或 `make help` 看全部指令。

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# 載入 .env（若存在）並匯出給 recipe 使用
ifneq (,$(wildcard ./.env))
include .env
export
endif

# ── 衍生變數 ───────────────────────────────────────────────────────────
GCP_REGION      ?= asia-east1
AR_REPO_NAME    ?= clawdbot-repo
SERVICE_NAME    ?= clawdbot
IMAGE_TAG       ?= v1
OPENCLAW_VERSION?= 2026.6.1
MIN_INSTANCES   ?= 1
MEMORY          ?= 2Gi
CPU             ?= 1
OPENCLAW_MODEL  ?= google/gemini-3-flash-preview

# 防呆：去除值的前後空白（避免 .env 行內註解殘留空白污染衍生變數）
$(foreach v,GCP_PROJECT_ID GCP_REGION GCP_ACCOUNT AR_REPO_NAME SERVICE_NAME IMAGE_TAG OPENCLAW_VERSION MIN_INSTANCES MEMORY CPU OPENCLAW_MODEL OPENCLAW_GATEWAY_TOKEN OPENCLAW_PUBLIC_URL GOOGLECHAT_ENABLED LINE_CHANNEL_SECRET LINE_CHANNEL_ACCESS_TOKEN,$(eval $(v) := $(strip $($(v)))))

IMAGE = $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/$(AR_REPO_NAME)/$(SERVICE_NAME):$(IMAGE_TAG)
GCLOUD = gcloud --project=$(GCP_PROJECT_ID) $(if $(GCP_ACCOUNT),--account=$(GCP_ACCOUNT),)
LOCAL_NAME ?= clawdbot-local
LOCAL_PORT ?= 18080

# Gemini 金鑰：.env 有值就用，否則自 Secret Manager 取
define resolve_gemini
$(if $(GEMINI_API_KEY),$(GEMINI_API_KEY),$$($(GCLOUD) secrets versions access latest --secret=gemini-api-key 2>/dev/null))
endef

.PHONY: help
help: ## 顯示所有指令
	@echo "openclaw-Taiwan 維運指令："
	@grep -hE '^[a-zA-Z0-9_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "目前設定：project=$(GCP_PROJECT_ID) region=$(GCP_REGION) service=$(SERVICE_NAME) tag=$(IMAGE_TAG)"

# ── 前置檢查 ───────────────────────────────────────────────────────────
.PHONY: check-env
check-env: ## 檢查 .env 必填項
	@test -f .env || { echo "✗ 找不到 .env，請先：cp .env.example .env"; exit 1; }
	@test -n "$(GCP_PROJECT_ID)" || { echo "✗ GCP_PROJECT_ID 未設"; exit 1; }
	@test -n "$(OPENCLAW_GATEWAY_TOKEN)" || echo "⚠ OPENCLAW_GATEWAY_TOKEN 未設（部署時會自動產生隨機值，Dashboard 無法預知）"
	@echo "✓ .env OK（project=$(GCP_PROJECT_ID)）"

.PHONY: gen-token
gen-token: ## 產生 64 字元 gateway token 並寫回 .env
	@tok=$$(openssl rand -hex 32); \
	if grep -q '^OPENCLAW_GATEWAY_TOKEN=' .env 2>/dev/null; then \
	  sed -i.bak "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$$tok|" .env && rm -f .env.bak; \
	else echo "OPENCLAW_GATEWAY_TOKEN=$$tok" >> .env; fi; \
	echo "✓ 已寫入 .env：OPENCLAW_GATEWAY_TOKEN=$$tok"

# ── GCP 前置資源 ───────────────────────────────────────────────────────
.PHONY: enable-apis
enable-apis: check-env ## 啟用必要 GCP API
	$(GCLOUD) services enable run.googleapis.com cloudbuild.googleapis.com \
	  artifactregistry.googleapis.com secretmanager.googleapis.com

.PHONY: create-repo
create-repo: check-env ## 建立 Artifact Registry 映像庫
	$(GCLOUD) artifacts repositories create $(AR_REPO_NAME) \
	  --repository-format=docker --location=$(GCP_REGION) || true

.PHONY: secret-set-gemini
secret-set-gemini: check-env ## 把 Gemini 金鑰存入 Secret Manager（用法：make secret-set-gemini KEY=AIza...）
	@test -n "$(KEY)" || { echo "✗ 請提供 KEY，例如：make secret-set-gemini KEY=AIza..."; exit 1; }
	@printf '%s' "$(KEY)" | $(GCLOUD) secrets create gemini-api-key --data-file=- 2>/dev/null \
	  || printf '%s' "$(KEY)" | $(GCLOUD) secrets versions add gemini-api-key --data-file=-
	@echo "✓ gemini-api-key 已更新"

# ── 部署 ───────────────────────────────────────────────────────────────
.PHONY: bootstrap
bootstrap: enable-apis create-repo ## 一次完成前置（啟用 API + 建映像庫）

.PHONY: deploy
deploy: check-env ## 建置映像並部署到 Cloud Run（Cloud Build）
	@GEMINI="$(strip $(resolve_gemini))"; \
	$(GCLOUD) builds submit --config=deploy/cloudbuild.yaml . \
	  --substitutions="^|^_GCP_PROJECT_ID=$(GCP_PROJECT_ID)|_GCP_REGION=$(GCP_REGION)|_AR_REPO_NAME=$(AR_REPO_NAME)|_SERVICE_NAME=$(SERVICE_NAME)|_TAG=$(IMAGE_TAG)|_OPENCLAW_VERSION=$(OPENCLAW_VERSION)|_GEMINI_API_KEY=$$GEMINI|_OPENCLAW_GATEWAY_TOKEN=$(OPENCLAW_GATEWAY_TOKEN)|_OPENCLAW_PUBLIC_URL=$(OPENCLAW_PUBLIC_URL)|_OPENCLAW_MODEL=$(OPENCLAW_MODEL)|_MIN_INSTANCES=$(MIN_INSTANCES)|_MEMORY=$(MEMORY)|_CPU=$(CPU)|_GOOGLECHAT_ENABLED=$(GOOGLECHAT_ENABLED)|_LINE_CHANNEL_SECRET=$(LINE_CHANNEL_SECRET)|_LINE_CHANNEL_ACCESS_TOKEN=$(LINE_CHANNEL_ACCESS_TOKEN)"
	@$(MAKE) --no-print-directory allow-public

.PHONY: allow-public
allow-public: check-env ## 補上 allUsers→run.invoker（--allow-unauthenticated 常在 Cloud Build 失效）
	$(GCLOUD) run services add-iam-policy-binding $(SERVICE_NAME) \
	  --region=$(GCP_REGION) --member=allUsers --role=roles/run.invoker

.PHONY: min-instances
min-instances: check-env ## 設定常駐實例數（用法：make min-instances N=1）
	$(GCLOUD) run services update $(SERVICE_NAME) --region=$(GCP_REGION) --min-instances=$(or $(N),$(MIN_INSTANCES))

.PHONY: refresh-url
refresh-url: check-env ## 取得實際 Cloud Run URL、寫回 .env，並重設服務環境變數
	@u=$$($(GCLOUD) run services describe $(SERVICE_NAME) --region=$(GCP_REGION) --format='value(status.url)'); \
	test -n "$$u" || { echo "✗ 取不到 URL"; exit 1; }; \
	sed -i.bak "s|^OPENCLAW_PUBLIC_URL=.*|OPENCLAW_PUBLIC_URL=$$u|" .env && rm -f .env.bak; \
	$(GCLOUD) run services update $(SERVICE_NAME) --region=$(GCP_REGION) \
	  --update-env-vars=OPENCLAW_PUBLIC_URL=$$u; \
	echo "✓ OPENCLAW_PUBLIC_URL=$$u（已寫回 .env 並更新服務）"

# ── 生命週期：一鍵安裝 / 重裝 / 移除 / 健檢 ───────────────────────────
.PHONY: install
install: check-env ## 一鍵安裝：前置→金鑰→部署→補 URL→開放（KEY=AIza... 可選）
	@echo "▶ [1/6] 確保 gateway token"
	@test -n "$(OPENCLAW_GATEWAY_TOKEN)" || $(MAKE) --no-print-directory gen-token
	@echo "▶ [2/6] 啟用 API + 建立映像庫"
	@$(MAKE) --no-print-directory bootstrap
	@echo "▶ [3/6] Gemini 金鑰"
	@if [ -n "$(KEY)" ]; then $(MAKE) --no-print-directory secret-set-gemini KEY=$(KEY); \
	 elif [ -n "$(GEMINI_API_KEY)" ]; then echo "  使用 .env 的 GEMINI_API_KEY"; \
	 elif $(GCLOUD) secrets describe gemini-api-key >/dev/null 2>&1; then echo "  使用既有 secret gemini-api-key"; \
	 else echo "✗ 找不到 Gemini 金鑰：請 make install KEY=AIza... 或在 .env 設 GEMINI_API_KEY"; exit 1; fi
	@echo "▶ [4/6] 建置並部署"
	@$(MAKE) --no-print-directory deploy
	@echo "▶ [5/6] 取得實際 URL 並更新服務"
	@$(MAKE) --no-print-directory refresh-url
	@echo "▶ [6/6] 健康檢查"
	@$(MAKE) --no-print-directory doctor || true
	@echo "✅ 安裝完成。Dashboard：" && $(MAKE) --no-print-directory dashboard-url

.PHONY: reinstall
reinstall: check-env ## 重新安裝：刪除服務後重新部署（保留映像庫與金鑰）
	@echo "▶ 移除既有服務"
	@$(MAKE) --no-print-directory uninstall || true
	@echo "▶ 重新部署"
	@$(MAKE) --no-print-directory deploy
	@$(MAKE) --no-print-directory refresh-url
	@$(MAKE) --no-print-directory doctor || true
	@echo "✅ 重新安裝完成"

.PHONY: uninstall
uninstall: check-env ## 刪除 Cloud Run 服務（保留映像庫與金鑰）
	$(GCLOUD) run services delete $(SERVICE_NAME) --region=$(GCP_REGION) --quiet || true

.PHONY: teardown-all
teardown-all: check-env ## ⚠ 全部移除：服務+映像庫+金鑰（需 CONFIRM=yes）
	@test "$(CONFIRM)" = "yes" || { echo "✗ 危險操作，請加 CONFIRM=yes"; exit 1; }
	-$(GCLOUD) run services delete $(SERVICE_NAME) --region=$(GCP_REGION) --quiet
	-$(GCLOUD) artifacts repositories delete $(AR_REPO_NAME) --location=$(GCP_REGION) --quiet
	-$(GCLOUD) secrets delete gemini-api-key --quiet
	@echo "✓ 已全部移除"

.PHONY: doctor
doctor: ## 功能檢測：本機工具 + GCP 前置 + 服務健康 + token 驗證
	@bash scripts/doctor.sh

# ── 觀測 ───────────────────────────────────────────────────────────────
.PHONY: url
url: check-env ## 顯示服務 URL
	@$(GCLOUD) run services describe $(SERVICE_NAME) --region=$(GCP_REGION) --format='value(status.url)'

.PHONY: dashboard-url
dashboard-url: check-env ## 顯示帶 token 的 Dashboard 網址（fragment 形式）
	@u=$$($(GCLOUD) run services describe $(SERVICE_NAME) --region=$(GCP_REGION) --format='value(status.url)'); \
	echo "$$u/chat?session=main#token=$(OPENCLAW_GATEWAY_TOKEN)"; \
	echo "（建議用無痕視窗開啟，避免舊 token 快取）"

.PHONY: status
status: check-env ## 顯示服務狀態
	@$(GCLOUD) run services describe $(SERVICE_NAME) --region=$(GCP_REGION) \
	  --format='table(status.url, status.latestReadyRevisionName, spec.template.metadata.annotations["autoscaling.knative.dev/minScale"]:label=MIN)'

.PHONY: logs
logs: check-env ## 讀取最近日誌（N=行數，預設 50）
	@$(GCLOUD) run services logs read $(SERVICE_NAME) --region=$(GCP_REGION) --limit=$(or $(N),50)

# ── 本機（Docker）────────────────────────────────────────────────────
.PHONY: build-local
build-local: ## 本機建置映像
	docker build -f deploy/Dockerfile --build-arg OPENCLAW_VERSION=$(OPENCLAW_VERSION) -t $(LOCAL_NAME) .

.PHONY: run-local
run-local: build-local ## 本機啟動容器（http://localhost:$(LOCAL_PORT)）
	-docker rm -f $(LOCAL_NAME) >/dev/null 2>&1
	docker run -d --name $(LOCAL_NAME) -p $(LOCAL_PORT):8080 \
	  -e OPENCLAW_GATEWAY_TOKEN=$(OPENCLAW_GATEWAY_TOKEN) \
	  -e OPENCLAW_PUBLIC_URL=http://localhost:$(LOCAL_PORT) \
	  -e GEMINI_API_KEY=local-test $(LOCAL_NAME)
	@echo "✓ http://localhost:$(LOCAL_PORT)/chat?session=main#token=$(OPENCLAW_GATEWAY_TOKEN)"

.PHONY: stop-local
stop-local: ## 停止並移除本機容器
	-docker rm -f $(LOCAL_NAME)

# ── 測試 ───────────────────────────────────────────────────────────────
.PHONY: test
test: ## 執行完整測試（static + config + integration）
	@bash tests/run.sh

.PHONY: test-static
test-static: ## 靜態檢查（bash 語法 / YAML / JSON / 結構）
	@bash tests/test_static.sh

.PHONY: test-config
test-config: ## 單元測試：設定產生器
	@bash tests/test_config.sh

.PHONY: test-docs
test-docs: ## 文件正確性（README/.env.example 與實作一致）
	@bash tests/test_docs.sh

.PHONY: test-makefile
test-makefile: ## Makefile 編排/負面/冪等（stub gcloud）
	@bash tests/test_makefile.sh

.PHONY: test-install
test-install: ## make install 多情境測試（stub gcloud）
	@bash tests/test_install.sh

.PHONY: test-integration
test-integration: ## 整合測試：build 映像 → 啟動 → smoke（需 docker）
	@bash tests/test_integration.sh

.PHONY: test-live
test-live: ## 對已部署的 Cloud Run 服務做煙霧測試
	@bash tests/test_live.sh

# ── 清理 ───────────────────────────────────────────────────────────────
.PHONY: clean
clean: ## 清理本機測試容器與暫存
	-docker rm -f $(LOCAL_NAME) clawdbot-test >/dev/null 2>&1
	-rm -rf tests/.tmp
	@echo "✓ cleaned"
