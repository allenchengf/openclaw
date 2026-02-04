# openclaw-Taiwan

By Ian Wu, The Pocket Company

openclaw-Taiwan 是一個針對台灣開發者的 OpenClaw 部署框架，支援 GCP Cloud Run、GCE VM、Google Chat 與 LINE OA（包含群組 @ 提及）。希望台灣開發者可以一起完善這個框架。

## Features

- **Main AI Model**: Gemini 3 Flash Preview
- **Image Generation**: Nano Banana tools
- **Channels**: Google Chat（私訊 + 群組）、LINE OA（私訊 + 群組 @ 提及）
- **Deployment**: Cloud Run 或 GCE VM

## Prerequisites

1. Google Cloud Project with billing enabled
2. APIs enabled:
   - Cloud Run API
   - Cloud Build API
   - Artifact Registry API
   - Secret Manager API
3. Gemini API Key from [Google AI Studio](https://aistudio.google.com/apikey)
4. Google Chat App configured (see below)
5. LINE OA（Messaging API）Channel（若要使用 LINE）

## Setup

### 1. Configure Variables

Edit `cloudbuild.yaml` and update the substitutions:

```yaml
substitutions:
  _GCP_PROJECT_ID: your-project-id
  _GCP_REGION: asia-east1  # or your preferred region
  _AR_REPO_NAME: clawdbot-repo
  _SERVICE_NAME: clawdbot
  _TAG: v1
```

### 2. Create Artifact Registry Repository

```bash
gcloud artifacts repositories create clawdbot-repo \
  --repository-format=docker \
  --location=asia-east1 \
  --project=YOUR_PROJECT_ID
```

### 3. Store Secrets in Secret Manager

```bash
# Store Gemini API Key
echo -n "YOUR_GEMINI_API_KEY" | gcloud secrets create gemini-api-key \
  --data-file=- \
  --project=YOUR_PROJECT_ID

# Store Google Chat Service Account JSON
gcloud secrets create clawdbot-googlechat-sa \
  --data-file=path/to/service-account.json \
  --project=YOUR_PROJECT_ID
```

### 4. Configure Google Chat App

1. Go to [Google Cloud Console](https://console.cloud.google.com/apis/api/chat.googleapis.com/hangouts-chat)
2. Create a new Chat App with:
   - **App URL**: `https://YOUR_SERVICE_URL/googlechat`
   - **Slash commands** (optional)
3. Download the Service Account JSON key

### 5. LINE OA 設定（選用）

1. 到 LINE Developers Console 建立 Messaging API Channel
2. 取得以下資訊：
   - Channel Secret
   - Channel Access Token（長期有效）
3. Webhook URL 設定為：
   - `https://YOUR_DOMAIN/line`
4. 開啟「Use webhook」

### LINE OA 整合說明

- LINE 的 channel extension 由 OpenClaw 內建提供（不在本 repo 內），本專案負責部署與設定。
- 啟用方式是提供 `LINE_CHANNEL_SECRET` / `LINE_CHANNEL_ACCESS_TOKEN`，並在 `openclaw.json` 中設定 channel。
- 群組 @ 提及建議用 `groups.*.requireMention` 控制。

範例設定：
```json
{
  "channels": {
    "line": {
      "enabled": true,
      "channelAccessToken": "YOUR_TOKEN",
      "channelSecret": "YOUR_SECRET",
      "webhookPath": "/line",
      "dmPolicy": "open",
      "allowFrom": ["*"],
      "groupPolicy": "open",
      "groups": {
        "*": { "requireMention": true }
      }
    }
  }
}
```

### 6. Build and Deploy

```bash
# Build with Cloud Build（建議同時傳入 gateway token，否則容器會產生隨機 token，Dashboard/CLI 無法預知）
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_GEMINI_API_KEY="YOUR_API_KEY",_OPENCLAW_GATEWAY_TOKEN="YOUR_64CHAR_HEX_TOKEN" \
  --project=YOUR_PROJECT_ID

# Or deploy manually
gcloud run deploy clawdbot \
  --image=REGION-docker.pkg.dev/PROJECT_ID/clawdbot-repo/clawdbot:TAG \
  --region=asia-east1 \
  --platform=managed \
  --allow-unauthenticated \
  --memory=2Gi \
  --cpu=1 \
  --min-instances=1 \
  --set-env-vars="GEMINI_API_KEY=YOUR_KEY,OPENCLAW_GATEWAY_TOKEN=YOUR_GATEWAY_TOKEN" \
  --set-secrets="GOOGLE_CHAT_SERVICE_ACCOUNT_FILE=clawdbot-googlechat-sa:latest"
```

## File Structure

```
.
├── Dockerfile.cloudrun          # Docker image for Cloud Run
├── cloudbuild.yaml              # Cloud Build configuration
├── agents.md.example            # AI 指令範本（圖片格式）
├── env.example.txt              # 環境變數範本
├── docs/
│   └── GCP-部署對照與問題分析.md # 部署對照、CLI 遠端連線、pairing/token 排錯
├── scripts/
│   ├── cloudrun-entrypoint.sh   # Runtime config generator
│   └── devices-remote.sh        # 本機對遠端 Gateway 執行 devices list/approve
└── extensions/
    └── nano-banana/             # Image generation plugin
        ├── clawdbot.plugin.json
        ├── package.json
        ├── index.ts
        └── src/
            └── nano-banana-tool.ts
```

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GEMINI_API_KEY` | Your Gemini API key |
| `OPENCLAW_GATEWAY_TOKEN` | Gateway 認證用 token；部署時建議設為固定值，Dashboard 與 CLI 連線需帶此 token |
| `OPENCLAW_GATEWAY_URL` | 本機 CLI 連遠端時用（例：`https://YOUR_SERVICE.run.app`）；僅用於 `scripts/devices-remote.sh` 等 |
| `GOOGLE_CHAT_AUDIENCE` | Cloud Run service URL (auto-detected if not set) |
| `PORT` | Server port (default: 8080) |
| `LINE_CHANNEL_SECRET` | LINE OA Channel Secret |
| `LINE_CHANNEL_ACCESS_TOKEN` | LINE OA Channel Access Token |

> 請勿提交含機密的 `.env` 檔，請使用 `env.example.txt` 作為範本。

## Dashboard 與 CLI 連線

- **Dashboard**：請用帶 token 的網址開啟，例如  
  `https://YOUR_SERVICE_URL?token=YOUR_OPENCLAW_GATEWAY_TOKEN`  
  否則會出現「device identity required」或「token mismatch」。
- **本機 CLI**（如 `devices list`、`gateway health`）：需在指令中加上 `--url wss://YOUR_SERVICE_URL` 與 `--token YOUR_TOKEN`，或使用 `scripts/devices-remote.sh`。  
  詳見 [docs/GCP-部署對照與問題分析.md](docs/GCP-部署對照與問題分析.md)。

## Usage

Once deployed, you can:

1. **Chat with AI**: Send messages in Google Chat
2. **Generate Images**: Say "generate an image of a cat"
3. **Edit Images**: Send an image and say "change the background to blue"

## Demo Screenshots

以下示意 openclaw-Taiwan 在 LINE 私訊與群組中的實際互動：

![LINE demo 1](demo/1891188_0.jpg)
![LINE demo 2](demo/1891189_0.jpg)
![LINE demo 3](demo/1891190_0.jpg)

## GCE VM (Compute Engine) 部署摘要

- 建議使用 Nginx 作為反向代理，並設定 HTTPS (Let's Encrypt)
- Webhook URL：
  - Google Chat: `https://YOUR_DOMAIN/googlechat`
  - LINE: `https://YOUR_DOMAIN/line`
- 群組訊息建議設定為「需要 @ 提及」以避免被動觸發

## AGENTS.md 設定（圖片直接顯示的關鍵）

為了讓 AI 生成的圖片能**直接顯示在聊天室**（而非純文字連結），你需要在 OpenClaw workspace 建立 `AGENTS.md` 檔案。

### 原理

1. 圖片生成 skill（如 `nano-banana-pro`）會回傳 `MEDIA: https://...` 格式
2. OpenClaw 偵測到 `MEDIA:` token 後，會自動轉換成原生圖片訊息
3. 但 AI 模型可能會「優化」這個格式，把它變成 Markdown 連結
4. `AGENTS.md` 的作用是明確告訴 AI：**不要改動 `MEDIA:` 格式**

### 設定方式

```bash
# 複製範本到 OpenClaw workspace
cp agents.md.example ~/.openclaw/workspace/AGENTS.md
```

或手動建立 `~/.openclaw/workspace/AGENTS.md`，內容參考本 repo 的 `agents.md.example`。

### 驗證

設定完成後，請在聊天室測試「幫我畫一隻貓」，圖片應該直接顯示而非連結。

## Cloud Run 服務操作（關機／開機／重啟）

以下指令請將 `YOUR_PROJECT_ID`、`asia-east1`、`clawdbot` 替換為你的專案 ID、區域與服務名稱。

### 常用操作一覽

| 想做什麼 | 作法 |
|----------|------|
| **關機**（縮到零、沒流量就停） | 維持 `min-instances=0`，不要打服務即可；一段時間無流量 instance 會關掉。 |
| **關機**（不給外人連） | `gcloud run services update clawdbot --region=asia-east1 --project=YOUR_PROJECT_ID --no-allow-unauthenticated` |
| **開機**（有人連才啟動） | 直接開 Dashboard 或打服務 URL，Cloud Run 會自動冷啟動。 |
| **開機**（常駐、減少斷線） | `gcloud run services update clawdbot ... --min-instances=1` |
| **重啟**（換新修訂） | 重新 deploy 或 `gcloud run services update ... --image=...` |
| **查看狀態** | `gcloud run services describe clawdbot --region=asia-east1 --project=YOUR_PROJECT_ID` |

### 關機

```bash
# 方式一：改為需登入，一般人無法開啟（服務仍在，只是不對外開放）
gcloud run services update clawdbot \
  --region=asia-east1 \
  --project=YOUR_PROJECT_ID \
  --no-allow-unauthenticated

# 方式二：刪除服務（完全移除，要再用需重新 deploy）
# gcloud run services delete clawdbot --region=asia-east1 --project=YOUR_PROJECT_ID
```

### 開機／常駐

```bash
# 至少保留 1 個 instance，減少「縮到零後斷線」
gcloud run services update clawdbot \
  --region=asia-east1 \
  --project=YOUR_PROJECT_ID \
  --min-instances=1
```

若要改回「沒流量就縮到零」以省費：

```bash
gcloud run services update clawdbot \
  --region=asia-east1 \
  --project=YOUR_PROJECT_ID \
  --min-instances=0
```

### 重新對外開放（先前用 --no-allow-unauthenticated 關機時）

```bash
gcloud run services update clawdbot \
  --region=asia-east1 \
  --project=YOUR_PROJECT_ID \
  --allow-unauthenticated
```

### 重啟（部署新修訂）

```bash
# 用現有映像再 deploy 一次，會產生新修訂
gcloud run services update clawdbot \
  --region=asia-east1 \
  --project=YOUR_PROJECT_ID \
  --image=asia-east1-docker.pkg.dev/YOUR_PROJECT_ID/clawdbot-repo/clawdbot:v1
```

或透過 Cloud Build 重新建置並部署（見上方「Build and Deploy」）。

## Troubleshooting

- **日誌**：
  ```bash
  gcloud run services logs read clawdbot --region=asia-east1 --limit=50
  ```
- **token mismatch / pairing required / device identity required**：請用帶 token 的 Dashboard URL，並在 Cloud Run 設定固定的 `OPENCLAW_GATEWAY_TOKEN`。詳見 [docs/GCP-部署對照與問題分析.md](docs/GCP-部署對照與問題分析.md)。

## License

GPL-3.0

