# TC-11：頻道（Google Chat／LINE）測試案例

本文件涵蓋 openclaw（小龍蝦／ClawdBot）部署框架在「頻道」面向的正規測試案例，範圍包含 **Google Chat（`/googlechat` webhook 路徑）** 與 **LINE（`/line` webhook 路徑）** 兩個外部訊息頻道。驗證分兩層：

1. **設定層（自動驗）**：頻道啟用旗標、audience／群組政策、DM 政策、雙金鑰要求、Service Account 檔案偵測等可由 `control-ui-config.json`（線上唯讀 curl）或 `.env.example` / `gen-config.mjs`（本機唯讀）自動判定。
2. **功能面（手動驗收）**：真正在 Google Chat App 或 LINE Bot 內發訊、@mention、DM 等實際對話互動，需由人在對應通訊軟體中操作，屬手動驗收，無對應自動化輸出。

本領域目前現役狀態：模型 `google-vertex/gemini-2.5-flash`（已切到 Vertex AI，免 API 金鑰；`GEMINI_API_KEY` 選填）、`OPENCLAW_MEMORY_PROVIDER=none`、TZ `Asia/Taipei`、cron 啟用。Google Chat 預期已啟用；LINE 預期未啟用（雙金鑰未填）。

> **重要斷點提醒（使用者最大痛點）**
> - Claude 對話框中以 `!` 前綴執行 bash（如 `!curl ...`）與「真實終端機」不同。**請勿把帶 `!` 的指令貼進真實終端機**——在 zsh／bash 中 `!` 會觸發歷史展開或被當邏輯否定而導致指令中斷。下列「本機終端機」步驟一律是「不含 `!` 前綴」的純指令。
> - `control-ui-config.json` 受 token 保護：所有線上頻道設定查詢都**必須**帶 `Authorization: Bearer <gateway token>`，否則回 401 而非 config 內容，會讓 grep 全部誤判為 FAIL。
> - 設定漂移防護：`gen-config.mjs` 是頻道設定的單一真實來源；手改線上設定後若沒回寫產生器，下次部署會被覆蓋。

---

### TC-11-01：Google Chat 頻道啟用狀態（`GOOGLECHAT_ENABLED=true`）
- **對應 AC**：AC-channel-googlechat-enabled
- **前置作業**：
  - Cloud Run 服務 `clawdbot` 已部署且 ready（標準 URL：`https://clawdbot-475727900579.asia-east1.run.app`）。
  - 已知 gateway token：``。
  - 本機已安裝 `curl`，可連外。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -o '"googlechat"' | wc -l
     ```
  2. 觀察輸出數字（預期 `1`，代表 config 中存在 `googlechat` 頻道鍵）。
- **預計成果**：輸出 `1`，代表 Google Chat 頻道已在線上設定中啟用並出現。
- **實際成果**：依賴外部設定（線上 `control-ui-config.json` 即時內容）。execJson 已驗證帶正確 token 對該端點回 200（live-cloudrun `cloudrun-config-with-token` actual=200，status=pass），但未對 `googlechat` 鍵做字串擷取統計，無對應 actual 數字。需由驗收者於本機終端機實跑上列指令確認輸出為 `1`。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。斷點提醒：務必帶 token，否則回 401，grep 永遠得 `0` 而誤判 FAIL。權限軸線＝HTTP token 正向。

---

### TC-11-02：Google Chat audience 設定（`/googlechat` 路徑）
- **對應 AC**：AC-channel-googlechat-audience
- **前置作業**：同 TC-11-01（Cloud Run ready、gateway token、本機 `curl`）。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -q 'googlechat.*audience' && echo 'OK' || echo 'FAIL'
     ```
  2. 觀察輸出 `OK` 或 `FAIL`。
- **預計成果**：輸出 `OK`，代表 Google Chat 頻道設定中含 audience 受眾設定。
- **實際成果**：依賴外部設定（線上 config 即時內容）。execJson 僅驗證該端點授權狀態碼（帶 token=200／不帶=401），未對 `googlechat.*audience` 字串做比對，無對應 actual。需由驗收者於本機終端機實跑確認輸出 `OK`。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。`grep` 為單行同列比對，若 audience 與 googlechat 不在同一輸出行（JSON 經 pretty-print 換行）可能誤判，必要時改用 `python -m json.tool` 解析或 `grep -z`。權限軸線＝HTTP token 正向。

---

### TC-11-03：LINE 頻道設定鍵齊備（`.env.example` 含雙金鑰欄位）
- **對應 AC**：AC-channel-line-keys-template
- **前置作業**：
  - 已 clone 倉庫至本機 `/Users/allenchen/project/demo/openclaw/repo`。
  - 本機具 `grep`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴；注意需在倉庫根目錄）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && grep '^LINE_CHANNEL_SECRET=' .env.example && grep '^LINE_CHANNEL_ACCESS_TOKEN=' .env.example | wc -l
     ```
  2. 觀察是否同時印出 `LINE_CHANNEL_SECRET=` 行，且最後 `wc -l` 為 `1`（兩鍵皆存在）。
- **預計成果**：兩個 LINE 金鑰欄位（`LINE_CHANNEL_SECRET`、`LINE_CHANNEL_ACCESS_TOKEN`）皆存在於 `.env.example` 範本中。
- **實際成果**：手動驗證。本次靜態檢查（`test_static.sh` 72 passed / 0 failed，status=pass）已涵蓋設定漂移與必填鍵防護，且本機 `.env.example` 第 64–65 行確含 `LINE_CHANNEL_SECRET=` 與 `LINE_CHANNEL_ACCESS_TOKEN=` 兩鍵；惟 execJson 無此精確指令的逐字 actual 輸出，需由驗收者本機實跑確認。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。純本機靜態檢查，無權限門檻。斷點提醒：務必先 `cd` 進倉庫根，否則 `.env.example` 找不到。

---

### TC-11-04：LINE 頻道未啟用——線上未填雙金鑰（負向／預設停用）
- **對應 AC**：AC-channel-line-disabled-default
- **前置作業**：
  - 倉庫根目錄存在實際 `.env`（部署用，非範本）。
  - 本機具 `grep`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && grep 'LINE_CHANNEL_SECRET\|LINE_CHANNEL_ACCESS_TOKEN' .env | grep -v '^#' | wc -l
     ```
  2. 觀察輸出數字（預期 `0`，代表 `.env` 中沒有未註解的 LINE 金鑰，LINE 維持停用）。
- **預計成果**：輸出 `0`，代表現役部署未啟用 LINE 頻道（與 TC-11-05 的 `SKIPPED (LINE disabled)` 預期一致）。
- **實際成果**：依賴外部設定（本機 `.env` 實際內容，含敏感金鑰，未納入 execJson）。需由驗收者於本機終端機實跑確認輸出 `0`。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。此為負向案例——驗證「未配置時即停用」。`.env` 含真實金鑰，請勿外流。權限軸線＝本機檔案讀取。

---

### TC-11-05：LINE 群組政策 `requireMention`——LINE 停用時應 SKIP（負向對照）
- **對應 AC**：AC-channel-line-group-policy
- **前置作業**：同 TC-11-01（Cloud Run ready、gateway token、本機 `curl`）。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -q 'requireMention' && echo 'OK' || echo 'SKIPPED (LINE disabled)'
     ```
  2. 觀察輸出（預期 `SKIPPED (LINE disabled)`，因 LINE 未啟用，config 不含 `requireMention`）。
- **預計成果**：輸出 `SKIPPED (LINE disabled)`，與 TC-11-04 的 LINE 停用結論一致。若 LINE 啟用則應改驗證群組需 @mention 才回應（`requireMention=true`）。
- **實際成果**：依賴外部設定（線上 config 即時內容）。execJson 僅驗證該端點授權狀態碼，未對 `requireMention` 字串做比對，無對應 actual。需由驗收者本機實跑確認輸出 `SKIPPED (LINE disabled)`。
- **判定**：⏭️SKIP
- **備註**：唯讀、可逆。此案例本質為「LINE 停用 → 略過群組政策驗證」，故預期即 SKIP；判定標 SKIP 以反映其設計語意。權限軸線＝HTTP token 正向。

---

### TC-11-06：Google Chat DM 政策（`policy=open`）
- **對應 AC**：AC-channel-googlechat-dm-policy
- **前置作業**：同 TC-11-01（Cloud Run ready、gateway token、本機 `curl`）。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -q '"policy":\s*"open"' && echo 'OK' || echo 'FAIL'
     ```
  2. 觀察輸出 `OK` 或 `FAIL`。
- **預計成果**：輸出 `OK`，代表 Google Chat DM（一對一私訊）政策為 `open`（任何人可私訊機器人）。
- **實際成果**：依賴外部設定（線上 config 即時內容）。execJson 僅驗證授權狀態碼，未對 `"policy":"open"` 字串做比對，無對應 actual。需由驗收者本機實跑確認輸出 `OK`。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。斷點提醒：`grep` 帶 `\s*` 為 BRE/ERE 行為差異，部分 `grep` 不支援 `\s`；若誤判 FAIL 可改 `grep -E '"policy":[[:space:]]*"open"'`。權限軸線＝HTTP token 正向。

---

### TC-11-07：Google Chat Service Account 檔案設定（自動偵測 vs 明確指定）
- **對應 AC**：AC-channel-googlechat-sa-file
- **前置作業**：
  - 倉庫根目錄存在 `.env.example`。
  - 本機具 `grep`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && grep 'GOOGLE_CHAT_SERVICE_ACCOUNT_FILE' .env.example | wc -l
     ```
  2. 觀察輸出數字（預期 `0`，代表範本未顯式列出該鍵——SA 檔走自動偵測而非要求手填路徑）。
- **預計成果**：輸出 `0`，代表 `.env.example` 不含 `GOOGLE_CHAT_SERVICE_ACCOUNT_FILE` 鍵；Google Chat 的 Service Account 走自動偵測（如 ADC／預設 SA），不需使用者手動指定檔案路徑。
- **實際成果**：手動驗證。靜態檢查套件（`test_static.sh` 72 passed / 0 failed，status=pass）涵蓋 `.env.example` 鍵一致性與設定漂移防護；惟此精確 grep 計數指令無對應逐字 actual，需由驗收者本機實跑確認輸出 `0`。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。設計語意為「期望值＝0」的反向斷言（不該出現該鍵）。權限軸線＝本機檔案讀取。

---

### TC-11-08：設定漂移防護——`gen-config.mjs` 正確產生 Google Chat 頻道設定
- **對應 AC**：AC-channel-config-drift、AC-config-generator-channels
- **前置作業**：
  - 倉庫根目錄存在 `deploy/gen-config.mjs`（已確認檔案存在，可執行）。
  - 本機已安裝 `node`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴；以環境變數注入測試 token 與 `GOOGLECHAT_ENABLED=true`）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && OPENCLAW_GATEWAY_TOKEN=test123 GOOGLECHAT_ENABLED=true node deploy/gen-config.mjs --stdout 2>&1 | grep -c 'googlechat'
     ```
  2. 觀察輸出數字（預期 `1`，代表產生器在 `GOOGLECHAT_ENABLED=true` 時於設定中產出 `googlechat` 頻道）。
- **預計成果**：輸出 `1`，代表設定產生器能正確依旗標產生 Google Chat 頻道區塊，防止手改線上設定造成漂移。
- **實際成果**：手動驗證（依賴本機 `node` 執行產生器）。execJson 中設定產生器單元測試 `test_config.sh`（25 passed / 0 failed，status=pass）整體通過，已涵蓋 token／URL／頻道／記憶／時區／寫檔各案例；惟此精確 grep 計數指令無逐字 actual，需由驗收者本機實跑確認輸出 `1`。
- **判定**：🖐️手動
- **備註**：唯讀、可逆（`--stdout` 僅輸出不寫檔）。斷點提醒：`grep -c` 計數的是「含 googlechat 的行數」而非出現次數，若 JSON 同一行多次出現仍計 1 行；必要時改 `grep -o 'googlechat' | wc -l` 核對。權限軸線＝本機執行。

---

### TC-11-09：Google Chat 實際對話互動（功能面手動驗收）
- **對應 AC**：AC-channel-googlechat-e2e
- **前置作業**：
  - Google Chat App（小龍蝦）已在 Google Workspace 完成設定，webhook 指向 `https://clawdbot-475727900579.asia-east1.run.app/googlechat`。
  - 驗收者具可存取該 Chat App 的 Google 帳號。
  - 後端模型 `google-vertex/gemini-2.5-flash` 可用（已切到 Vertex AI，靠 service account/使用者 ADC 認證，免 API 金鑰；`GEMINI_API_KEY` 選填。Vertex 走 `aiplatform.googleapis.com`，不受舊 AI Studio 金鑰 403/429 影響，詳見 `docs/VERTEX-SETUP.md`）。
- **測試步驟**：
  1. 在「Google Chat 用戶端」（網頁或 App，非終端機、非 Claude 輸入框）開啟與小龍蝦的 DM。
  2. 直接輸入一句訊息（如「你好」）送出。
  3. 在群組中加入機器人並 @mention 它送出一句訊息，觀察是否依政策回應。
- **預計成果**：DM 收到模型回覆；群組中 @mention 後收到回覆。回覆語言／時區符合設定（繁中、Asia/Taipei）。
- **實際成果**：手動驗證（功能面 E2E，無對應自動化）。前置依賴：現役已切到 Vertex AI（`google-vertex/gemini-2.5-flash`，靠 ADC 認證），不再受舊 AI Studio `AIza` 金鑰 403 PERMISSION_DENIED 阻斷；功能驗收前須確認 Vertex ADC 已就緒（`make vertex-auth` 完成、Secret Manager `vertex-adc` 存在、runtime SA 具 `roles/aiplatform.user` 與 `secretAccessor`），詳見 `docs/VERTEX-SETUP.md`，否則對話會因 provider auth 失敗。
- **判定**：🖐️手動
- **備註**：功能面、可逆（純對話）。已知前置斷點：Vertex ADC 須就緒（憑證所屬帳號需對專案有 Vertex 權限），否則回覆會因 `Provider google-vertex has auth issue` 失敗；GCP 試用金到期則需換帳號重跑 `make vertex-auth`。權限軸線＝Google Workspace 帳號 + Vertex ADC。

---

## 彙總

| 判定 | 數量 |
|------|------|
| ✅PASS | 0 |
| ❌FAIL | 0 |
| ⏭️SKIP | 1 |
| 🖐️手動 | 8 |
| **合計** | **9** |

> 說明：本領域絕大多數 check 為「線上 config 字串比對」或「本機精確指令計數」，execJson 雖證實了授權狀態碼（200/401）與整套靜態／設定／整合測試全綠，但未保留各頻道 check 的逐字 grep 輸出，故對應案例標為 🖐️手動（依賴外部設定／需本機實跑）。TC-11-05 依設計語意（LINE 停用→略過群組政策）標 ⏭️SKIP。功能面 E2E（TC-11-09）另受 Gemini 金鑰 403 阻斷，須先換金鑰。
