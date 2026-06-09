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
OPENCLAW_MODEL  ?= google-vertex/gemini-2.5-flash
OPENCLAW_MEMORY_PROVIDER ?= none
# Vertex AI（model 為 google-vertex/* 時）：免 API 金鑰，靠 runtime SA ADC，吃專案試用金。
GOOGLE_CLOUD_PROJECT  ?= $(GCP_PROJECT_ID)
GOOGLE_CLOUD_LOCATION ?= global

# 防呆：去除值的前後空白（避免 .env 行內註解殘留空白污染衍生變數）
$(foreach v,GCP_PROJECT_ID GCP_REGION GCP_ACCOUNT AR_REPO_NAME SERVICE_NAME IMAGE_TAG OPENCLAW_VERSION MIN_INSTANCES MEMORY CPU OPENCLAW_MODEL OPENCLAW_MEMORY_PROVIDER GOOGLE_CLOUD_PROJECT GOOGLE_CLOUD_LOCATION OPENCLAW_GATEWAY_TOKEN OPENCLAW_PUBLIC_URL GOOGLECHAT_ENABLED LINE_CHANNEL_SECRET LINE_CHANNEL_ACCESS_TOKEN,$(eval $(v) := $(strip $($(v)))))

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
	  artifactregistry.googleapis.com secretmanager.googleapis.com \
	  compute.googleapis.com aiplatform.googleapis.com

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

# ── Vertex AI 身份驗證（google-vertex/* 模型必做一次；組織禁 SA 金鑰故用使用者 ADC）──
ADC_FILE_LOCAL = $(HOME)/.config/gcloud/application_default_credentials.json

.PHONY: vertex-auth
vertex-auth: check-env ## Vertex 身份驗證一次性設定：ADC 登入→設 quota→存 Secret→授權（google-vertex 模型必做）
	@echo "═══ Vertex AI 身份驗證設定（一次性；換免費帳號續用時需重做）═══"
	@echo "說明：google-vertex 模型用 Application Default Credentials(ADC) 認證 Vertex AI。"
	@echo "      組織政策禁止建立 SA 金鑰，故採『使用者 ADC』。共 4 步，每步都會顯示實際指令。"
	@echo ""
	@echo "▶ [前置] 確保必要 API 已啟用（secretmanager / compute / aiplatform；全新專案必需）"
	@$(MAKE) --no-print-directory enable-apis
	@echo "▶ [1/4] 登入 ADC（會開瀏覽器，請務必選用 $(GCP_ACCOUNT)）"
	@echo "    執行：gcloud auth application-default login --account=$(GCP_ACCOUNT)"
	@gcloud auth application-default login --account=$(GCP_ACCOUNT)
	@echo "▶ [2/4] 設定 quota / 計費歸屬專案"
	@echo "    執行：gcloud auth application-default set-quota-project $(GCP_PROJECT_ID)"
	@gcloud auth application-default set-quota-project $(GCP_PROJECT_ID)
	@echo "▶ [3/4] 驗證 ADC 帳號正確並存入 Secret Manager"
	@$(MAKE) --no-print-directory vertex-store-adc
	@echo "✅ Vertex 身份驗證完成。現在可執行：make install"

.PHONY: vertex-store-adc
vertex-store-adc: check-env ## 將本機 ADC 憑證存入 Secret Manager(vertex-adc) 並授予 runtime SA 讀取權
	@test -s "$(ADC_FILE_LOCAL)" || { echo "✗ 找不到 ADC 憑證 $(ADC_FILE_LOCAL)；請先 make vertex-auth（或 gcloud auth application-default login --account=$(GCP_ACCOUNT)）"; exit 1; }
	@email=$$($(GCLOUD) auth application-default print-access-token >/dev/null 2>&1 && curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$$($(GCLOUD) auth application-default print-access-token 2>/dev/null)" | python3 -c "import sys,json;print(json.load(sys.stdin).get('email',''))" 2>/dev/null); \
	 echo "  ADC 帳號：$${email:-未知}"; \
	 if [ -n "$$email" ] && [ "$$email" != "$(GCP_ACCOUNT)" ]; then \
	   echo "  ⚠ ADC 帳號($$email) 與 .env 的 GCP_ACCOUNT($(GCP_ACCOUNT)) 不同；該帳號需對專案有 Vertex(aiplatform.user) 權限，否則回 403。"; \
	 fi
	@echo "  確保 Secret Manager API 已啟用"
	@$(GCLOUD) services enable secretmanager.googleapis.com >/dev/null 2>&1 || true
	@echo "  存入 Secret Manager: vertex-adc"
	@$(GCLOUD) secrets create vertex-adc --data-file="$(ADC_FILE_LOCAL)" 2>/dev/null \
	  || $(GCLOUD) secrets versions add vertex-adc --data-file="$(ADC_FILE_LOCAL)"
	@num=$$($(GCLOUD) projects describe $(GCP_PROJECT_ID) --format='value(projectNumber)'); \
	 sa="$$num-compute@developer.gserviceaccount.com"; \
	 $(GCLOUD) secrets add-iam-policy-binding vertex-adc --member=serviceAccount:$$sa --role=roles/secretmanager.secretAccessor >/dev/null; \
	 echo "✓ vertex-adc 已存入並授權 $$sa 讀取（entrypoint 啟動時自動取用）"

# ── 部署 ───────────────────────────────────────────────────────────────
.PHONY: grant-build-roles
grant-build-roles: check-env ## 授予 Cloud Build 服務帳號部署 Cloud Run 的權限（新專案必需）
	@num=$$($(GCLOUD) projects describe $(GCP_PROJECT_ID) --format='value(projectNumber)'); \
	sa="$$num-compute@developer.gserviceaccount.com"; \
	echo "  授予 $$sa：run.admin + iam.serviceAccountUser + aiplatform.user(Vertex)"; \
	$(GCLOUD) projects add-iam-policy-binding $(GCP_PROJECT_ID) --member=serviceAccount:$$sa --role=roles/run.admin --condition=None >/dev/null; \
	$(GCLOUD) projects add-iam-policy-binding $(GCP_PROJECT_ID) --member=serviceAccount:$$sa --role=roles/iam.serviceAccountUser --condition=None >/dev/null; \
	$(GCLOUD) projects add-iam-policy-binding $(GCP_PROJECT_ID) --member=serviceAccount:$$sa --role=roles/aiplatform.user --condition=None >/dev/null; \
	echo "✓ Cloud Build 部署 + Vertex AI 權限已授予"

.PHONY: bootstrap
bootstrap: enable-apis create-repo grant-build-roles ## 一次完成前置（啟用 API + 建映像庫 + 授予 Build 部署權限）

.PHONY: deploy
deploy: check-env ## 建置映像並部署到 Cloud Run（Cloud Build）
	@GEMINI="$(strip $(resolve_gemini))"; \
	$(GCLOUD) builds submit --config=deploy/cloudbuild.yaml . \
	  --substitutions="^|^_GCP_PROJECT_ID=$(GCP_PROJECT_ID)|_GCP_REGION=$(GCP_REGION)|_AR_REPO_NAME=$(AR_REPO_NAME)|_SERVICE_NAME=$(SERVICE_NAME)|_TAG=$(IMAGE_TAG)|_OPENCLAW_VERSION=$(OPENCLAW_VERSION)|_GEMINI_API_KEY=$$GEMINI|_OPENCLAW_GATEWAY_TOKEN=$(OPENCLAW_GATEWAY_TOKEN)|_OPENCLAW_PUBLIC_URL=$(OPENCLAW_PUBLIC_URL)|_OPENCLAW_MODEL=$(OPENCLAW_MODEL)|_OPENCLAW_MEMORY_PROVIDER=$(OPENCLAW_MEMORY_PROVIDER)|_GOOGLE_CLOUD_PROJECT=$(GOOGLE_CLOUD_PROJECT)|_GOOGLE_CLOUD_LOCATION=$(GOOGLE_CLOUD_LOCATION)|_MIN_INSTANCES=$(MIN_INSTANCES)|_MEMORY=$(MEMORY)|_CPU=$(CPU)|_GOOGLECHAT_ENABLED=$(GOOGLECHAT_ENABLED)|_LINE_CHANNEL_SECRET=$(LINE_CHANNEL_SECRET)|_LINE_CHANNEL_ACCESS_TOKEN=$(LINE_CHANNEL_ACCESS_TOKEN)"
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
install: check-env ## 一鍵完整安裝：Cloud Run + VM(持久記憶) + HTTPS + 帶令牌Dashboard 啟動檔
	@echo "▶ [1/8] 確保 gateway token"
	@test -n "$(OPENCLAW_GATEWAY_TOKEN)" || $(MAKE) --no-print-directory gen-token
	@echo "▶ [2/8] 啟用 API + 映像庫 + Build/Vertex 權限"
	@$(MAKE) --no-print-directory bootstrap
	@echo "▶ [3/8] 模型認證（model=$(OPENCLAW_MODEL)）"
	@case "$(OPENCLAW_MODEL)" in \
	  google-vertex/*) \
	    echo "  Vertex AI 模式（用 Google service account ADC 認證，免 Gemini API 金鑰，吃專案試用金）"; \
	    if $(GCLOUD) secrets describe vertex-adc >/dev/null 2>&1; then \
	      echo "  ✓ Secret vertex-adc 已存在 → 容器啟動時自動取用 ADC（無需動作）"; \
	    elif [ -s "$$HOME/.config/gcloud/application_default_credentials.json" ]; then \
	      echo "  偵測到本機 ADC 憑證 → 存入 Secret Manager 並授權"; \
	      $(MAKE) --no-print-directory vertex-store-adc; \
	    else \
	      echo ""; \
	      echo "  ✗ Vertex 需要先在 Google 完成一次性身份驗證（ADC），目前尚未設定。"; \
	      echo "    ───────────────────────────────────────────────────────────"; \
	      echo "    請先執行：  make vertex-auth"; \
	      echo "    它會逐步帶你完成（每步都會顯示指令）："; \
	      echo "      [1] gcloud auth application-default login --account=$(GCP_ACCOUNT)"; \
	      echo "          → 會開瀏覽器，請選用 $(GCP_ACCOUNT) 登入並同意授權"; \
	      echo "      [2] gcloud auth application-default set-quota-project $(GCP_PROJECT_ID)"; \
	      echo "          → 設定 API 配額/計費歸屬專案"; \
	      echo "      [3] 將產生的 ADC 憑證存入 Secret Manager（vertex-adc）"; \
	      echo "      [4] 授予 runtime service account 讀取該 secret 的權限"; \
	      echo "    完成後再重新執行：make install"; \
	      echo "    ───────────────────────────────────────────────────────────"; \
	      exit 1; \
	    fi;; \
	  *) if [ -n "$(KEY)" ]; then $(MAKE) --no-print-directory secret-set-gemini KEY=$(KEY); \
	     elif [ -n "$(GEMINI_API_KEY)" ]; then echo "  使用 .env 的 GEMINI_API_KEY"; \
	     elif $(GCLOUD) secrets describe gemini-api-key >/dev/null 2>&1; then echo "  使用既有 secret gemini-api-key"; \
	     else echo "✗ 找不到 Gemini 金鑰（model=$(OPENCLAW_MODEL) 需要）：make install KEY=AIza... 或 .env 設 GEMINI_API_KEY；Vertex(google-vertex/*) 則免"; exit 1; fi;; \
	esac
	@echo "▶ [4/8] 建置並部署 Cloud Run"
	@$(MAKE) --no-print-directory deploy
	@echo "▶ [5/8] 取得 Cloud Run URL 並更新服務"
	@$(MAKE) --no-print-directory refresh-url
	@echo "▶ [6/8] 部署 GCE VM（持久記憶，跨重啟保留）"
	@$(MAKE) --no-print-directory vm-deploy
	@echo "▶ [7/8] VM HTTPS 反向代理（Caddy + Let's Encrypt via nip.io）"
	@$(MAKE) --no-print-directory vm-https
	@echo "▶ [8/8] 健康檢查 + 產生帶令牌 Dashboard 啟動檔"
	@$(MAKE) --no-print-directory doctor || true
	@$(MAKE) --no-print-directory dashboard-launcher
	@echo "✅ 完整安裝完成（Cloud Run + VM + HTTPS + Dashboard 啟動檔）"

.PHONY: install-cloudrun
install-cloudrun: check-env ## 只裝 Cloud Run（不含 VM/HTTPS；無狀態、記憶不持久）
	@test -n "$(OPENCLAW_GATEWAY_TOKEN)" || $(MAKE) --no-print-directory gen-token
	@$(MAKE) --no-print-directory bootstrap
	@$(MAKE) --no-print-directory deploy
	@$(MAKE) --no-print-directory refresh-url
	@$(MAKE) --no-print-directory doctor || true
	@$(MAKE) --no-print-directory dashboard-launcher

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

.PHONY: dashboard-launcher
dashboard-launcher: check-env ## 產生帶令牌、雙擊即連的 Dashboard 啟動檔（VM HTTPS 優先，避免複製貼上掉 #token）
	@bash deploy/gen-dashboard-launcher.sh

.PHONY: status
status: check-env ## 顯示服務狀態
	@$(GCLOUD) run services describe $(SERVICE_NAME) --region=$(GCP_REGION) \
	  --format='table(status.url, status.latestReadyRevisionName, spec.template.metadata.annotations["autoscaling.knative.dev/minScale"]:label=MIN)'

.PHONY: logs
logs: check-env ## 讀取最近日誌（N=行數，預設 50）
	@$(GCLOUD) run services logs read $(SERVICE_NAME) --region=$(GCP_REGION) --limit=$(or $(N),50)

# ── GCE VM 部署（持久記憶）────────────────────────────────────────────
GCE_ZONE         ?= $(GCP_REGION)-b
GCE_VM_NAME      ?= clawdbot-vm
GCE_MACHINE_TYPE ?= e2-small

.PHONY: vm-https
vm-https: check-env ## 為 VM 接上 HTTPS 反向代理（Caddy + Let's Encrypt via nip.io）
	@bash deploy/vm-https.sh

.PHONY: vm-deploy
vm-deploy: check-env ## 部署/更新 GCE VM（COS + 持久磁碟，記憶跨重啟保留）
	@bash deploy/gce-deploy.sh

.PHONY: vm-ip
vm-ip: check-env ## 顯示 VM 外部 IP / 服務 URL
	@ip=$$($(GCLOUD) compute addresses describe $(GCE_VM_NAME)-ip --region=$(GCP_REGION) --format='value(address)' 2>/dev/null); \
	echo "http://$$ip:8080"

.PHONY: vm-dashboard
vm-dashboard: check-env ## VM 的帶 token Dashboard 網址（HTTPS via nip.io，已 vm-https）
	@ip=$$($(GCLOUD) compute addresses describe $(GCE_VM_NAME)-ip --region=$(GCP_REGION) --format='value(address)' 2>/dev/null); \
	dash=$${ip//./-}; \
	echo "https://$$dash.nip.io/chat?session=main#token=$(OPENCLAW_GATEWAY_TOKEN)"; \
	echo "（需先 make vm-https；建議用無痕視窗開啟。或用 make dashboard-launcher 產生雙擊啟動檔）"

.PHONY: vm-status
vm-status: check-env ## VM 狀態
	@$(GCLOUD) compute instances describe $(GCE_VM_NAME) --zone=$(GCE_ZONE) \
	  --format='table(name,status,networkInterfaces[0].accessConfigs[0].natIP:label=IP)' 2>&1

.PHONY: vm-logs
vm-logs: check-env ## 讀取 VM 容器日誌（透過 SSH）
	@$(GCLOUD) compute ssh $(GCE_VM_NAME) --zone=$(GCE_ZONE) --command='docker logs $$(docker ps -q --filter ancestor=$(IMAGE)) 2>&1 | tail -$(or $(N),50)' 2>&1

.PHONY: vm-ssh
vm-ssh: check-env ## SSH 進入 VM
	@$(GCLOUD) compute ssh $(GCE_VM_NAME) --zone=$(GCE_ZONE)

.PHONY: vm-delete
vm-delete: check-env ## 刪除 VM（保留持久磁碟與靜態 IP，記憶不丟）
	$(GCLOUD) compute instances delete $(GCE_VM_NAME) --zone=$(GCE_ZONE) --quiet || true

.PHONY: vm-teardown
vm-teardown: check-env ## ⚠ 刪除 VM + 持久磁碟 + 靜態 IP（需 CONFIRM=yes，記憶將遺失）
	@test "$(CONFIRM)" = "yes" || { echo "✗ 危險操作，請加 CONFIRM=yes"; exit 1; }
	-$(GCLOUD) compute instances delete $(GCE_VM_NAME) --zone=$(GCE_ZONE) --quiet
	-$(GCLOUD) compute disks delete $(GCE_VM_NAME)-data --zone=$(GCE_ZONE) --quiet
	-$(GCLOUD) compute addresses delete $(GCE_VM_NAME)-ip --region=$(GCP_REGION) --quiet
	@echo "✓ VM 全部移除"

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

.PHONY: test-vm
test-vm: ## GCE VM 部署多情境測試（stub gcloud）
	@bash tests/test_vm.sh

.PHONY: test-lint
test-lint: ## 業界 lint/安全掃描（shellcheck/hadolint/gitleaks）
	@bash tests/test_lint.sh

.PHONY: lint-trivy
lint-trivy: ## trivy 掃描容器映像漏洞+機密（需先 build-local）
	@trivy image --scanners vuln,secret --severity HIGH,CRITICAL $(LOCAL_NAME) 2>/dev/null || echo "先 make build-local"

.PHONY: test-doctor
test-doctor: ## doctor 健檢多情境測試（stub gcloud）
	@bash tests/test_doctor.sh

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
