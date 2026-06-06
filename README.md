# openclaw-Taiwan 🦞

> 針對台灣開發者的 **OpenClaw** 一鍵部署框架 —— Google Cloud Run / GCE VM、Google Chat 與 LINE OA（含群組 @ 提及）、Gemini 模型與圖片生成。

[![Platform](https://img.shields.io/badge/deploy-Cloud%20Run-blue)](https://cloud.google.com/run)
[![Model](https://img.shields.io/badge/model-Gemini%202.5%20Flash-orange)](https://ai.google.dev/)
[![License](https://img.shields.io/badge/license-GPL--3.0-green)](LICENSE)

---

## 目錄

- [特色](#特色)
- [架構](#架構)
- [專案結構](#專案結構)
- [需求](#需求)
- [從零開始：建立 GCP 資源](#從零開始建立-gcp-資源)
- [快速開始](#快速開始)
- [設定參考（.env）](#設定參考env)
- [Make 指令一覽](#make-指令一覽)
- [頻道設定](#頻道設定)
- [Dashboard / 網頁聊天](#dashboard--網頁聊天)
- [測試](#測試)
- [維運](#維運)
- [疑難排解](#疑難排解)
- [安全性](#安全性)
- [貢獻](#貢獻)
- [授權](#授權)

---

## 特色

- **主模型**：Gemini 2.5 Flash（GA、配額穩定；可由 `OPENCLAW_MODEL` 切換，如 `google/gemini-3-flash-preview`）
- **圖片生成**：Nano Banana 擴充
- **頻道**：Google Chat（私訊 + 群組）、LINE OA（私訊 + 群組 @ 提及）
- **部署**：Cloud Run（預設）或 GCE VM
- **維運**：單一 `Makefile` 入口、`.env` 集中設定、完整自動化測試

### 設計重點

| 決策 | 原因 |
|------|------|
| **npm 預編譯安裝** OpenClaw（非原始碼 build） | 從原始碼編譯時 `tsdown/rolldown` 會在 Cloud Build 內 **OOM 卡死**；npm 套件已含 gateway/channels/UI，建置 30 分鐘卡死 → 約 3 分鐘成功 |
| **以 node 產生設定 JSON**（`deploy/gen-config.mjs`） | 取代 shell heredoc 字串拼接，正確跳脫、可單元測試（先前 token/origin bug 即源於字串拼接） |
| **`.env` + `Makefile`** 集中參數 | 一處設定、一致指令；機密不進 git |

---

## 架構

```
                         ┌──────────────────────────────────────────┐
  Google Chat ──webhook─▶│              Cloud Run                    │
  LINE OA     ──webhook─▶│   ┌────────────────────────────────────┐ │
  瀏覽器 Dashboard ─wss─▶│   │  OpenClaw gateway (npm, :8080)      │ │
                         │   │   ├─ /googlechat  /line  webhook    │ │
                         │   │   ├─ control UI / webchat (token)   │ │──▶ Gemini API
                         │   │   └─ nano-banana 圖片生成擴充        │ │
                         │   └────────────────────────────────────┘ │
                         │   entrypoint.sh → gen-config.mjs           │
                         └──────────────────────────────────────────┘
                                   ▲ Secret Manager: gemini-api-key
```

---

## 專案結構

```
.
├── README.md                  # 本文件
├── LICENSE / CONTRIBUTING.md
├── Makefile                   # 維運入口（讀 .env）
├── .env.example               # 設定範本（複製為 .env）
├── .gitignore / .dockerignore / .gcloudignore
├── deploy/
│   ├── Dockerfile             # Cloud Run 映像（npm 安裝 openclaw）
│   ├── cloudbuild.yaml        # build → push → deploy
│   ├── entrypoint.sh          # 產生設定 + 啟動 gateway
│   ├── gen-config.mjs         # 設定產生器（可單元測試）
│   └── gce-deploy.sh          # GCE VM 部署（持久記憶）
├── scripts/
│   └── devices-remote.sh      # 本機對遠端 gateway 執行 devices list/approve
├── extensions/
│   └── nano-banana/           # 圖片生成擴充
├── tests/
│   ├── run.sh                 # 測試總指揮
│   ├── lib.sh                 # 斷言輔助
│   ├── test_static.sh         # 靜態檢查（結構/語法/YAML/漂移/全形字元）
│   ├── test_docs.sh           # README/.env.example 與實作一致性
│   ├── test_config.sh         # 設定產生器單元測試（gen-config）
│   ├── test_makefile.sh       # Makefile 編排/負面/冪等（stub）
│   ├── test_install.sh        # make install 多情境（stub）
│   ├── test_vm.sh             # GCE VM 部署多情境（stub）
│   ├── test_doctor.sh         # doctor 健檢多情境（stub）
│   ├── test_integration.sh    # 映像 build + 啟動 + 記憶回歸 smoke
│   └── test_live.sh           # 對已部署服務煙霧測試
├── examples/
│   └── agents.md.example      # AGENTS.md 範本（圖片直接顯示用）
└── docs/                      # 部署對照與排錯筆記
```

---

## 需求

- 本機：`gcloud`、`make`、`docker`、`node`、`openssl`、`curl`
- 一個 Google 帳號（可建立 GCP 專案）
- Gemini API Key（下方步驟 5 取得）

---

## 從零開始：建立 GCP 資源

第一次使用、手上還沒有任何 GCP 資源時，照下面做。**只有「建專案 / 開計費 / 裝 gcloud / 取金鑰」需要手動**；其餘（啟用 API、建 Artifact Registry、存金鑰）`make install` 會自動完成。

### 1. 建立 GCP 專案並啟用計費
1. 進 [Google Cloud Console](https://console.cloud.google.com/) → 頂部專案選單 → **新增專案**（記下 **專案 ID**，如 `openclaw-taiwan-123456`）。
2. 左側 **帳單** → 連結一個帳單帳戶（Cloud Run / Artifact Registry 需要計費）。

### 2. 安裝並登入 gcloud
```bash
# macOS：brew install --cask google-cloud-sdk（或見官方安裝頁）
gcloud auth login
gcloud config set project YOUR_PROJECT_ID
```

### 3.（選用）安裝本機工具
```bash
# macOS（make 通常隨 Xcode Command Line Tools；docker 用 Docker Desktop）
brew install node jq
```

### 4. 取得程式碼
```bash
git clone <repo> && cd openclaw-taiwan
```

### 5. 取得 Gemini API Key
1. 開 [Google AI Studio – API Key](https://aistudio.google.com/apikey)，用同一個 Google 帳號登入。
2. **Create API key** → 建議選「在現有 GCP 專案中建立」並選你步驟 1 的專案（圖片生成需綁定計費專案的配額）。
3. 複製金鑰（`AIza...` 開頭）。

### 6. 填 `.env` 後一鍵安裝
```bash
cp .env.example .env
$EDITOR .env          # 填：GCP_PROJECT_ID、GCP_ACCOUNT、GEMINI_API_KEY（共 3 項）
make install          # 自動：啟用API → 建Artifact Registry → 存金鑰 → 建置部署 → 補URL/IAM → 健檢
```

> `make install` 自動執行的等同：`make bootstrap`（`gcloud services enable run/cloudbuild/artifactregistry/secretmanager` + 建 `clawdbot-repo` 映像庫）、部署、`make allow-public`、`make doctor`。手動逐步見 [快速開始 › 進階](#快速開始)。

---

## 快速開始

### 🚀 最短路徑（一鍵安裝，給第一次使用的同學）

只需在 `.env` 填 **3 個必填項**，其餘自動處理：

```bash
git clone <repo> && cd openclaw-taiwan
cp .env.example .env
$EDITOR .env          # 填：GCP_PROJECT_ID、GCP_ACCOUNT、GEMINI_API_KEY

make install          # 一鍵：token→啟用API→建庫→部署→補URL→開放→健檢
```

完成後會印出 Dashboard 網址。`make install` 會自動：
1. 產生 gateway token（若未填）
2. 啟用必要 API + 建立 Artifact Registry
3. 使用 `.env` 的 `GEMINI_API_KEY`（或 `make install KEY=AIza...`、或既有 Secret）
4. 建置並部署到 Cloud Run
5. 取得實際 URL 並更新服務（control UI / Chat audience 需正確 URL）
6. 補上 `allUsers→run.invoker`（`--allow-unauthenticated` 在 Cloud Build 常失效）
7. 執行 `make doctor` 健康檢查

### 驗證與日常

```bash
make doctor           # 功能檢測（本機工具 + GCP 前置 + 服務健康 + token）
make status           # 服務狀態
make dashboard-url    # 帶 token 的 Dashboard 網址（用無痕視窗開）
make test             # 完整自動化測試
```

### 重新安裝 / 移除

```bash
make reinstall            # 刪除服務後重新部署（保留映像庫與金鑰）
make uninstall            # 只刪 Cloud Run 服務
make teardown-all CONFIRM=yes   # ⚠ 全部移除：服務 + 映像庫 + 金鑰
```

### 進階（逐步，等同 install 的分解）

```bash
make gen-token            # 產生 gateway token
make bootstrap            # 啟用 API + 建映像庫
make secret-set-gemini KEY=AIza...   # 金鑰存入 Secret Manager（選用）
make deploy               # 建置 + 部署 + allow-public
make refresh-url          # 取得實際 URL 寫回 .env 並更新服務
```

---

## 設定參考（.env）

| 變數 | 說明 | 預設 |
|------|------|------|
| `GCP_PROJECT_ID` | GCP 專案 ID | — |
| `GCP_REGION` | 區域 | `asia-east1` |
| `GCP_ACCOUNT` | gcloud 帳號（多帳號區分） | — |
| `AR_REPO_NAME` | Artifact Registry 庫名 | `clawdbot-repo` |
| `SERVICE_NAME` | Cloud Run 服務名 | `clawdbot` |
| `IMAGE_TAG` | 映像標籤 | `v1` |
| `OPENCLAW_VERSION` | npm openclaw 版本 | `2026.6.1` |
| `MIN_INSTANCES` | 常駐實例數（1=減少冷啟動/回覆中斷） | `1` |
| `MEMORY` / `CPU` | 資源配置 | `2Gi` / `1` |
| `GEMINI_API_KEY` | 留空則自 Secret Manager 取 | （空） |
| `OPENCLAW_MODEL` | 主模型（GA 配額穩定；preview 版配額極低易 429） | `google/gemini-2.5-flash` |
| `OPENCLAW_MEMORY_PROVIDER` | 記憶 embedding：`none`(關鍵字,免金鑰最穩)/`gemini`(語意,需向量表)/`openai` | `none` |
| `OPENCLAW_TIMEZONE` | 時區（AI 提示中的現在時間） | `Asia/Taipei` |
| `GCE_ZONE` / `GCE_VM_NAME` / `GCE_MACHINE_TYPE` / `GCE_DATA_DISK_SIZE` | GCE VM 部署參數 | `<region>-b` / `clawdbot-vm` / `e2-small` / `10GB` |
| `OPENCLAW_GATEWAY_TOKEN` | 64 字元 hex；Dashboard/CLI 驗證 | （`make gen-token`） |
| `OPENCLAW_PUBLIC_URL` | 對外 URL（allowedOrigins/audience） | （`make refresh-url`） |
| `GOOGLECHAT_ENABLED` | 是否啟用 Google Chat | `true` |
| `LINE_CHANNEL_SECRET` / `LINE_CHANNEL_ACCESS_TOKEN` | 兩者皆填才啟用 LINE | （空） |

---

## Make 指令一覽

```bash
make help            # 列出全部指令
make bootstrap       # 啟用 API + 建立映像庫
make gen-token       # 產生並寫入 gateway token
make deploy          # 建置 + 部署 + allow-public
make refresh-url     # 取得實際 URL 寫回 .env 並更新服務
make status / logs   # 查狀態 / 讀日誌（logs N=100）
make min-instances N=1   # 設常駐實例
make url / dashboard-url # 取服務網址 / 帶 token 的 Dashboard 網址
make build-local / run-local / stop-local  # 本機 Docker
make test            # 完整測試（static/docs/config/makefile/install/vm/doctor/integration）
make secret-set-gemini KEY=...  # 更新 Gemini 金鑰
make allow-public    # 補 allUsers→run.invoker
make clean           # 清理本機容器/暫存

# GCE VM（持久記憶）
make vm-deploy       # 部署/更新 VM（COS + 持久磁碟掛載 ~/.openclaw）
make vm-ip / vm-dashboard / vm-status / vm-logs / vm-ssh
make vm-delete       # 刪 VM（保留磁碟與 IP，記憶不丟）
make vm-teardown CONFIRM=yes   # ⚠ 連磁碟與 IP 一起刪（記憶遺失）
```

---

## 頻道設定

### Google Chat

1. 開啟 [Google Chat API 設定](https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat)
2. 建立 Chat App，**App URL** 設為：`https://<你的服務URL>/googlechat`
3. （選用）若需 Service Account 驗證，下載 JSON 並存入 Secret：
   ```bash
   gcloud secrets create clawdbot-googlechat-sa --data-file=path/to/sa.json --project=$GCP_PROJECT_ID
   ```
   並在 Cloud Run 掛載到 `/secrets/google-chat-sa/key.json`（entrypoint 會自動偵測）。

### LINE OA（選用）

1. [LINE Developers](https://developers.line.biz/console/) 建立 Messaging API Channel
2. 取得 **Channel Secret** 與 **Channel Access Token**（長期）
3. 填入 `.env` 的 `LINE_CHANNEL_SECRET` / `LINE_CHANNEL_ACCESS_TOKEN`，`make deploy`
4. Webhook URL 設為：`https://<你的服務URL>/line`，並開啟「Use webhook」

> 圖片要**直接顯示在聊天室**（而非純連結），請把 `examples/agents.md.example` 複製到 OpenClaw workspace 的 `AGENTS.md`。

---

## Dashboard / 網頁聊天

OpenClaw 內建 control UI（`/`）與網頁聊天（`/chat`）。

```bash
make dashboard-url    # 印出 https://.../chat?session=main#token=<TOKEN>
```

⚠️ **務必用無痕視窗開啟**：control UI 會把 token 快取在 localStorage，殘留的舊 token 會造成「驗證不相符（token_mismatch）」。token 透過 `#token=` fragment 帶入最穩。

> **遠端 Dashboard 的限制**：OpenClaw 對遠端瀏覽器要求裝置配對；本框架以 `dangerouslyDisableDeviceAuth` 讓「僅持 token 的瀏覽器 control UI」可連（適用 Cloud Run 純遠端情境）。CLI 等其他遠端客戶端仍需配對，詳見 [docs/](docs/)。

---

## 記憶與持久化（重要）

OpenClaw 有長期記憶系統（學習偏好、身分、專案），存於 `~/.openclaw`：
`state/openclaw.sqlite` 與 workspace 的 `IDENTITY.md` / `USER.md` / `MEMORY.md`。

兩個關鍵注意點：

1. **記憶搜尋的 embedding provider** → OpenClaw 內建記憶引擎預設用 OpenAI embedding，未設 `OPENAI_API_KEY` 會出現 `Memory Search ❌ ERROR`（`sync failed: No API key found for provider "openai"`）。
   本框架**預設 `OPENCLAW_MEMORY_PROVIDER=none`**（關鍵字記憶 + `MEMORY.md`，完全免金鑰、最穩定，記憶仍跨重啟保留）。
   進階：設 `OPENCLAW_MEMORY_PROVIDER=gemini` 用 Gemini 金鑰做語意記憶（需 `gemini-embedding-001` 向量表 `chunks_vec` 可用，slim 映像可能缺）。

2. **Cloud Run 是無狀態的** → `~/.openclaw` 在容器重啟（換修訂 / 縮放 / 冷啟動）後**全部重置**，所以 bot 會「忘記」剛取的名字、`MEMORY.md` 顯示 Missing。

| 部署方式 | 記憶持久性 |
|----------|------------|
| Cloud Run（`make install`） | ⚠ 單一常駐實例存活期間有記憶；**重啟即重置** |
| **GCE VM（`make vm-deploy`）** | ✅ 持久磁碟掛載 `~/.openclaw`，**跨容器/VM 重啟保留** |

### GCE VM 部署（持久記憶，推薦長期使用）

```bash
# .env 已含 GCE_ZONE / GCE_VM_NAME / GCE_MACHINE_TYPE / GCE_DATA_DISK_SIZE 預設
make vm-deploy        # 靜態IP → 防火牆 → 持久磁碟 → COS VM 跑容器(掛載 ~/.openclaw)
make vm-dashboard     # 取得帶 token 的 Dashboard 網址（http://VM_IP:8080，無痕開）
make vm-logs          # 看容器日誌
```

- 記憶存在持久磁碟 `clawdbot-vm-data`，掛載到容器 `/root/.openclaw`；`make vm-delete` 重建 VM 後記憶仍在。
- VM 採固定外部 IP（webhook 穩定）。**正式上線的 Google Chat / LINE webhook 與 Dashboard 安全內容（secure context）需 HTTPS** → 建議在 VM 前加反向代理（Caddy / Nginx + Let's Encrypt，需網域）。
- 成本：VM 為常時計費（`e2-small` 約 US$13/月）；不用時 `make vm-delete`（保留磁碟）即可省運算費。

## 測試

完全用本機可得工具（`bash`/`node`/`docker`），缺 `shellcheck`/`hadolint`/`PyYAML` 會自動略過。

```bash
make test              # 完整：static/docs/config/makefile/install/vm/doctor/lint/integration
make test-static       # 結構 / 語法 / YAML / ignore 一致性 / 設定漂移防護 / 全形字元
make test-docs         # README / .env.example 與實作一致性
make test-config       # 設定產生器單元測試（gen-config.mjs 各分支）
make test-makefile     # Makefile 編排 / 負面 / 冪等（stub gcloud，不碰雲端）
make test-install      # make install 多情境（7 情境，stub gcloud）
make test-vm           # GCE VM 部署多情境（stub gcloud）
make test-doctor       # doctor 健檢多情境（stub gcloud）
make test-lint         # 業界 lint/安全掃描：shellcheck + hadolint + gitleaks
make lint-trivy        # trivy 容器映像漏洞 + 機密掃描（需先 make build-local）
make test-integration  # build 映像 → 啟動 → HTTP/token / 記憶回歸 smoke
make test-live         # 對已部署服務煙霧測試（讀 .env 的 URL+token）
make doctor            # 功能檢測（本機 + GCP 前置 + 服務健康 + token）

bash tests/run.sh --no-docker   # 跳過整合測試
bash tests/run.sh --live        # 額外跑線上測試
```

> 業界主流工具：`brew install shellcheck hadolint gitleaks trivy`。`make test` 會跑 shellcheck/hadolint/gitleaks（未裝則略過）；`trivy` 因較重獨立為 `make lint-trivy`（其回報的 base 映像 / 上游相依 CVE 屬資訊性）。

完整的測試矩陣（QA 工作流程窮舉 600+ 案例、驗收標準與手動清單）見 **[docs/TEST-PLAN.md](docs/TEST-PLAN.md)**。

測試涵蓋：檔案結構合規、所有腳本語法、設定產生器各分支、Makefile 一鍵安裝/重裝/移除/健檢的編排與負面與冪等、`.env` 行內註解防呆、部署設定漂移防護（頻道 env 必須傳遞）、映像可建置與啟動、token 經 `Authorization: Bearer` 的 200/401 行為、容器內設定正確性、已部署服務健康。

---

## 維運

| 操作 | 指令 |
|------|------|
| 查狀態 | `make status` |
| 讀日誌 | `make logs`（`make logs N=100`） |
| 常駐（減少斷線） | `make min-instances N=1` |
| 縮到零省費 | `make min-instances N=0` |
| 重新部署 | `make deploy` |
| 不對外開放 | `gcloud run services update $SERVICE_NAME --no-allow-unauthenticated --region=$GCP_REGION` |
| 重新對外 | `make allow-public` |

---

## 疑難排解

| 症狀 | 原因 / 解法 |
|------|------------|
| **建置卡在 `pnpm build` / tsdown 數十分鐘** | 從原始碼編譯會 OOM。本框架已改用 npm 預編譯安裝，勿改回原始碼 build |
| **403 Forbidden（`server: Google Frontend`）** | Cloud Run IAM 缺 `allUsers`。執行 `make allow-public`。注意：這是 Google 前端擋的，不是 app |
| **403（openclaw 自身回傳）** | control UI `allowedOrigins` 未含公開 URL。`make refresh-url` 後重新部署 |
| **Dashboard「驗證不相符 / token_mismatch」** | 瀏覽器快取舊 token。用**無痕視窗** + `make dashboard-url` 的 fragment 網址 |
| **回覆失敗 / 跑很久出不來 / `turn failed`（429 RESOURCE_EXHAUSTED）** | Gemini 模型配額用盡。preview 版（`gemini-3-flash-preview`）免費配額極低；改用 GA 的 `gemini-2.5-flash`（預設）：`OPENCLAW_MODEL` 設定後重新部署 |
| **回覆有時中斷/空白** | 縮到零時 SIGTERM 中斷。設 `make min-instances N=1` |
| **Memory Search ❌ ERROR**（`No API key for provider openai`） | 記憶 embedding 預設走 OpenAI。本框架預設 `OPENCLAW_MEMORY_PROVIDER=none`（關鍵字記憶，免金鑰）；舊部署請重新 `make deploy`/`make vm-deploy` |
| **bot 忘記名字 / `MEMORY.md` Missing** | Cloud Run 無狀態，記憶不跨重啟。改用 `make vm-deploy`（GCE VM + 持久磁碟）|
| **記憶 `no such table: chunks_vec`** | gemini 向量索引需 chunks_vec 表（slim 映像易缺）。用預設 `OPENCLAW_MEMORY_PROVIDER=none`（關鍵字記憶，免向量）|
| **Cron tool error（設提醒失敗）** | cron 未啟用。本框架預設 `cron.enabled=true`；舊部署重新 `make deploy`/`make vm-deploy` |
| **時間顯示 UTC / 不對** | 預設 `OPENCLAW_TIMEZONE=Asia/Taipei` + 映像 `TZ=Asia/Taipei`；舊部署重新部署 |
| **圖片生成 429（resource exhausted）** | Gemini 圖片配額限制。用綁定計費專案的標準 `AIza` 金鑰，並注意免費圖片配額很低 |
| **CLI 連遠端 gateway** | 用 `scripts/devices-remote.sh`，或加 `--url wss://... --token ...` |

更多排錯見 [docs/GCP-部署對照與問題分析.md](docs/GCP-部署對照與問題分析.md)。

---

## 安全性

- **機密不進 git**：`.env`、`*-sa.json`、`.gateway-token.env` 已列入 `.gitignore`；`.dockerignore`/`.gcloudignore` 確保不進映像與 build context
- **Gemini 金鑰**建議存於 Secret Manager（`make secret-set-gemini`）
- **gateway token** 請用 `make gen-token` 產生足夠長度的隨機值，勿沿用其他 gateway 的 token
- `dangerouslyDisableDeviceAuth` / `dangerouslyAllowHostHeaderOriginFallback` 是為了 Cloud Run 純遠端可用性而開；若改用 GCE VM 或 IAP，請考慮關閉並改用裝置配對 / trusted-proxy

---

## 貢獻

歡迎 PR！請見 [CONTRIBUTING.md](CONTRIBUTING.md)。提交前請跑：

```bash
make test
```

---

## 授權

[GPL-3.0](LICENSE)
