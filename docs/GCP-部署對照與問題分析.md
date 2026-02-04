# GCP Cloud Run 部署：他人做法 vs 我們目前的問題

## 一、官方與社群的實際做法

### 1. OpenClaw 官方 Docker（docs.clawd.bot + GitHub）

- **建置方式**：**從原始碼建置**，不是 `npm install -g openclaw`。
  - 使用 `Dockerfile`：`pnpm install` → `pnpm build` → `pnpm ui:build`。
  - 產物在 **WORKDIR /app**，執行檔為 **`node dist/index.js`**。
- **啟動方式**（docker-compose.yml）：
  - `node dist/index.js gateway --bind lan --port 18789`
  - 文件註明：對外服務時要加 `--allow-unconfigured`、`--bind lan`。
- **設定與工作目錄**：
  - 設定：`~/.openclaw/`（docker-compose 掛載到 `/home/node/.openclaw`）。
  - 檔案名為 **`openclaw.json`**，不是 `clawdbot.json`。
- **使用者**：以 `USER node` 執行，HOME 為 `/home/node`。

### 2. Simon Willison（TIL：Running OpenClaw in Docker）

- 使用官方 **docker-setup.sh + docker-compose**，沒有自建 Dockerfile。
- 管理指令用：`docker compose exec openclaw-gateway node dist/index.js <subcommand>`。
- 再次確認：**可執行檔是 `node dist/index.js`**，且需從「已建置好的映像」執行。

### 3. 我們目前的做法 vs 差異

| 項目 | 官方/他人 | 我們目前 | 問題 |
|------|-----------|----------|------|
| 取得 OpenClaw | 從 repo 原始碼 build 出 `dist/` | `npm install -g openclaw` | npm 套件結構可能沒有 `dist/index.js` 或路徑不同，導致容器內找不到可執行檔、無法在 PORT 上啟動。 |
| 啟動指令 | `node dist/index.js gateway ...`（在 /app） | `openclaw gateway ...` 或 `node dist/index.js` | 若 npm 裝的沒有 dist，gateway 根本起不來 → **container failed to start**。 |
| 設定路徑 | `~/.openclaw/openclaw.json` | 已改為 `~/.openclaw/openclaw.json` | 已對齊。 |
| 綁定與 port | `--bind lan`、可 `--port 8080` | `--port $PORT --bind lan` | 正確。 |
| 容器內 gcloud | 未使用 | 曾用於組 GOOGLE_CHAT_AUDIENCE | 映像內無 gcloud 會導致 `set -e` 時腳本提早退出；已改為不呼叫 gcloud。 |

**結論**：最可能導致「container failed to start and listen on PORT」的原因是：**我們用 npm 安裝 OpenClaw，映像裡沒有與官方一致的 `dist/index.js` 可執行方式**。官方與他人都是在「已從原始碼建置好的映像」裡跑 `node dist/index.js gateway`。

---

## 二、建議修正方向

1. **Dockerfile**：改為與官方一致，**從 OpenClaw 原始碼建置**（clone repo → pnpm install → pnpm build → pnpm ui:build），讓映像內具備 `/app/dist/index.js`。
2. **Entrypoint**：維持寫入 `~/.openclaw/openclaw.json`，然後在 **WORKDIR /app** 執行：
   - `node dist/index.js gateway --allow-unconfigured --port "$PORT" --bind lan`
3. **不再依賴**：`openclaw` CLI 或 npm 全域安裝的內部路徑；只依賴「自己 build 出來的 dist/」。

這樣與官方、Simon 的做法一致，Cloud Run 才能穩定在 PORT 上啟動並通過健康檢查。

---

## 三、從本機用 CLI 連到 Cloud Run Gateway（devices list / approve）

用 `docker run --entrypoint "" ... node dist/index.js devices list` 時，**不會執行 entrypoint**，容器內沒有寫入 `~/.openclaw/openclaw.json`，CLI 會預設連到 `ws://127.0.0.1:18789`，因此會出現：

- `gateway closed (1006 abnormal closure)`、`Gateway target: ws://127.0.0.1:18789`

**解法**：`devices` 子指令支援 `--url` 與 `--token`，請改為**明確指定遠端 Gateway 的 WebSocket URL 與 token**。

- Cloud Run 對外是 HTTPS，WebSocket 要用 **`wss://`**（同一 host，path 依 OpenClaw gateway 規定）。
- 若服務 URL 為 `https://clawdbot-25031024592.asia-east1.run.app`，則 `--url` 為 `wss://clawdbot-25031024592.asia-east1.run.app`。

### 正確範例

```bash
# 列出待配對裝置（請替換為你的映像、token、Cloud Run URL）
docker run --rm --entrypoint "" \
  -e OPENCLAW_GATEWAY_TOKEN="YOUR_GATEWAY_TOKEN" \
  asia-east1-docker.pkg.dev/PROJECT_ID/clawdbot-repo/clawdbot:v1 \
  node dist/index.js devices list \
  --url "wss://YOUR_SERVICE.asia-east1.run.app" \
  --token "${OPENCLAW_GATEWAY_TOKEN}"
```

若 token 在環境變數裡，可先 export 再傳給容器：

```bash
export OPENCLAW_GATEWAY_TOKEN="1c7b52e71367a743d25b58c35ed98ab4ae66a523f44546879671d086caa35f18"
docker run --rm --entrypoint "" \
  -e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  asia-east1-docker.pkg.dev/.../clawdbot:v1 \
  node dist/index.js devices list \
  --url "wss://clawdbot-25031024592.asia-east1.run.app" \
  --token "$OPENCLAW_GATEWAY_TOKEN"
```

核准配對：

```bash
docker run --rm --entrypoint "" \
  -e OPENCLAW_GATEWAY_TOKEN="$OPENCLAW_GATEWAY_TOKEN" \
  asia-east1-docker.pkg.dev/.../clawdbot:v1 \
  node dist/index.js devices approve "<requestId>" \
  --url "wss://clawdbot-25031024592.asia-east1.run.app" \
  --token "$OPENCLAW_GATEWAY_TOKEN"
```

**重點**：`OPENCLAW_GATEWAY_URL` 環境變數在「覆寫 entrypoint 只跑 CLI」時**不會**被讀取；CLI 只認 **config 的 `gateway.remote.url`** 或指令列的 **`--url`** / **`--token`**，所以一定要在指令裡加 `--url` 和 `--token`。

### 若出現「pairing required」（1008）

遠端連線（含 CLI 與瀏覽器）預設需先完成「裝置配對」；但執行 `devices list` 的 CLI 本身也被要求配對，會形成雞生蛋。  
**解法**：在 entrypoint 寫入的 `openclaw.json` 中已加入 `gateway.controlUi.dangerouslyDisableDeviceAuth: true`，讓**僅持 token 的連線可跳過裝置配對**（僅限 Cloud Run 這類純遠端情境；見 [Security](https://docs.clawd.bot/gateway/security)）。需**重新建置並部署**映像後才會生效。

### 使用專案輔助腳本（可選）

專案內有 `scripts/devices-remote.sh`，會自動把 `OPENCLAW_GATEWAY_URL` 從 `https://` 轉成 `wss://` 並帶入 `--url` / `--token`：

```bash
export OPENCLAW_GATEWAY_TOKEN="your-token"
export OPENCLAW_GATEWAY_URL="https://clawdbot-25031024592.asia-east1.run.app"
./scripts/devices-remote.sh list
./scripts/devices-remote.sh approve "<requestId>"
```

映像預設為 `OPENCLAW_CLAWDBOT_IMAGE`，可覆寫。

---

## 四、Cloud Run 服務操作（關機／開機／重啟）

| 操作 | 指令要點 |
|------|----------|
| 關機（縮到零） | 維持 `min-instances=0`，無流量即停。 |
| 關機（不對外） | `gcloud run services update clawdbot ... --no-allow-unauthenticated` |
| 開機（常駐減斷線） | `gcloud run services update clawdbot ... --min-instances=1` |
| 重新對外 | `... --allow-unauthenticated` |
| 重啟 | `gcloud run services update ... --image=...` 或重新 build + deploy |
| 查狀態 | `gcloud run services describe clawdbot --region=... --project=...` |

完整指令與參數見專案根目錄 [README.md](../README.md#cloud-run-服務操作關機開機重啟)。
