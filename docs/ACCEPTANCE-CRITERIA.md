# openclaw-Taiwan 驗收標準（Acceptance Criteria）

聚焦「小龍蝦（ClawdBot / OpenClaw）」的**功能行為**。每條 AC 以 Given/When/Then 描述，
並標註驗證方式：**dogfooding**（實際對話）、**自動化測試**（`tests/`）、**線上**（部署後）。

最後一次 dogfooding：2026-06-06，於 GCE VM（`clawdbot-vm`）以 `openclaw agent --agent main`
（`OPENCLAW_GATEWAY_URL=ws://127.0.0.1:8080` 經真實 gateway）實機對話驗證。

---

## A. 對話與模型

### AC-01 基本對話
- **Given** 已部署且模型有配額
- **When** 使用者傳訊息
- **Then** 收到繁體中文、切題的回應，無 `turn failed` / 429
- **驗證**：✅ dogfood「現在幾點」「你叫什麼名字」皆正常回應；test_live 根頁 200

### AC-02 時間正確（台灣時區）
- **Given** `OPENCLAW_TIMEZONE=Asia/Taipei`（預設）+ 映像 `TZ=Asia/Taipei`
- **When** 問「現在台灣時間幾點」
- **Then** 回覆當下台灣時間（+08:00），非 UTC、非幻覺
- **驗證**：✅ dogfood 回「2026年6月6日晚上9點40分」（實際 CST）；test_config/integration 斷言 `userTimezone=Asia/Taipei`、`timeFormat=24`

### AC-03 模型可切換且配額穩定
- **Given** `OPENCLAW_MODEL`（預設 `google/gemini-2.5-flash`）
- **When** 部署或覆寫模型
- **Then** GA 模型配額穩定不易 429；preview 版（gemini-3-flash-preview）已知配額極低
- **驗證**：✅ 金鑰打 API：2.5-flash=200、3-preview=429；Cloud Run/VM 已切 2.5-flash

---

## B. 記憶與身分

### AC-04 身分記憶讀取
- **Given** workspace `IDENTITY.md` 已寫入身分
- **When** 問「你叫什麼名字」
- **Then** 回覆設定過的身分
- **驗證**：✅ dogfood 回「我叫**小龍蝦大將軍**」

### AC-05 記憶跨重啟持久（GCE VM）
- **Given** `make vm-deploy`（持久磁碟掛載 `/root/.openclaw`）
- **When** 容器/VM 重啟
- **Then** `IDENTITY.md` / `openclaw.sqlite` 內容保留
- **驗證**：✅ VM 重啟後 `IDENTITY.md`「小龍蝦大將軍」、sqlite 皆保留；test_vm 驗 `--container-mount-disk=/root/.openclaw`

### AC-06 記憶搜尋不報錯
- **Given** `OPENCLAW_MEMORY_PROVIDER=none`（預設，關鍵字記憶）
- **When** gateway 啟動 / 記憶同步
- **Then** 無 `No API key for provider openai`、無 `chunks_vec` 錯誤
- **驗證**：✅ VM 啟動日誌無記憶錯誤；test_integration 斷言無 openai/chunks_vec 錯誤

---

## C. 工具與功能

### AC-07 提醒 / Cron
- **Given** `cron.enabled=true`（預設）
- **When** 請 bot「設定 N 分鐘後提醒」
- **Then** 成功設定、無 `Cron tool error`
- **驗證**：✅ dogfood 回「已幫你設定兩分鐘後喝水的提醒」；test_config/integration 斷言 `cron.enabled=true`

### AC-08 圖片生成（Nano Banana）
- **Given** 金鑰有圖片模型配額
- **When** 請 bot 畫圖
- **Then** 產生圖片並以 `MEDIA:` 直接顯示（需 `AGENTS.md`）
- **驗證**：⚠️ 工具已正確串接並被呼叫（活動顯示 image_generate）；實際出圖**取決於 Gemini 圖片配額**（免費配額低時回 429）。屬金鑰配額，非框架問題

---

## D. 存取與安全

### AC-09 公開存取 + token 保護
- **When** 存取服務
- **Then** 根頁 `/`=200；受保護端點無 token=401、正確 `Authorization: Bearer`=200
- **驗證**：✅ test_live + doctor：200 / 401 / 200

### AC-10 Dashboard 連線
- **Given** `make dashboard-url` 取得帶 token 網址（fragment）
- **When** 用無痕視窗開啟
- **Then** control UI 連線成功（device auth 已豁免）
- **驗證**：✅ 使用者實測連入；HTTPS secure context 需 `make vm-https`（VM）

### AC-11 機密不外洩
- **Then** `.env`、`*-sa.json`、token 不進 git / 映像 / build context
- **驗證**：✅ gitleaks 無洩漏；test_static 三份 ignore 一致；entrypoint 日誌遮蔽 token/apiKey

---

## E. 頻道（需外部設定，手動驗收）

### AC-12 Google Chat
- **When** Chat App 綁定 `https://<URL>/googlechat`
- **Then** 私訊 / 群組 @ 提及收到回覆
- **驗證**：☐ 手動（需建立 Chat App）；設定層 test_config 驗 webhookPath/audience

### AC-13 LINE OA
- **When** 填 `LINE_CHANNEL_SECRET/ACCESS_TOKEN` 並設 webhook `https://<URL>/line`
- **Then** 私訊 / 群組 @ 提及收到回覆
- **驗證**：☐ 手動（需 LINE Channel）；設定層 test_config 驗 line 頻道 + requireMention

---

## F. 部署與維運

### AC-14 一鍵安裝
- **When** 填 `.env` 3 必填項 + `make install`
- **Then** 自動完成 API/映像庫/金鑰/部署/URL/IAM，服務 Ready
- **驗證**：✅ test_install（7 情境 stub）；實機 Cloud Run + VM 已部署 Ready

### AC-15 重裝 / 移除 / 健檢
- **When** `make reinstall` / `uninstall` / `teardown-all CONFIRM=yes` / `doctor` / `vm-*`
- **Then** 各自正確執行、危險操作有 CONFIRM 防呆
- **驗證**：✅ test_makefile / test_vm 防呆與冪等；`make doctor` 線上全過

---

## 驗收彙整

| 區塊 | AC | 自動化 | dogfood/實機 |
|------|----|--------|--------------|
| 對話與模型 | AC-01~03 | ✅ | ✅ |
| 記憶與身分 | AC-04~06 | ✅ | ✅ |
| 工具/功能 | AC-07 | ✅ | ✅ |
|  | AC-08 圖片 | 部分 | ⚠️ 配額依賴 |
| 存取與安全 | AC-09~11 | ✅ | ✅ |
| 頻道 | AC-12~13 | 設定層 | ☐ 手動 |
| 部署維運 | AC-14~15 | ✅ | ✅ |

> 完整自動化矩陣見 [TEST-PLAN.md](TEST-PLAN.md)；10 個測試套件全綠。
