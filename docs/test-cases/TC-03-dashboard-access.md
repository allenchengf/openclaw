# TC-03 Dashboard 存取流程測試案例

本檔涵蓋 openclaw（小龍蝦/ClawdBot）部署框架中「Dashboard 存取流程」此一核心痛點領域的正規測試案例。範圍包含：Cloud Run 與 GCE VM 兩種部署形態的 dashboard 行為差異、gateway token 透過 URL `#fragment`（而非 query string）攜帶的機制、無痕視窗使用情境、使用者最常踩到的「開啟網址後顯示『需要驗證』」失敗重現與正確做法、以及 device-auth 豁免說明。

關鍵設計事實（供判讀各案例）：
- 兩種部署端（Cloud Run / VM）的伺服器端授權邏輯**完全一致**：`/__openclaw/control-ui-config.json` 不帶 token → 401、帶正確 Bearer token → 200、帶錯誤 token → 401。
- `/chat?session=main` 的 HTML shell 本身在兩端皆回 200（頁面可下載）；但前端初始化必須先成功呼叫受保護的 config API。沒有 token 時 config API 回 401，導致 UI 顯示「需要驗證」。
- token 放在 URL 的 `#fragment`（例：`...#token=<64hex>`）而非 query，是因為 fragment 不會送到伺服器、不進 access log，由前端 JS 取出後改以 `Authorization: Bearer` 帶入 API 請求。
- 現役 gateway token：``（64 hex）。
- Cloud Run 標準 URL：`https://clawdbot-475727900579.asia-east1.run.app`；VM HTTPS：`https://34-81-189-176.nip.io`（Caddy + nip.io 自動憑證，TLS 可信，免 `-k`）。

斷點提醒（使用者最大痛點）：本檔所有 `curl` 指令都在**本機終端機**直接貼上執行，**不要**在前面加 `!`；Claude 對話框中的 `!` 前綴是 Claude 專用語法，貼進真實終端機會被 shell 當成「上一指令展開／邏輯否定」而破壞指令。瀏覽器相關步驟請在**無痕視窗**操作以排除舊 cookie/快取干擾。

---

### TC-03-ACCESS-01：Cloud Run dashboard 頁面（HTML shell）可達回 200
- **對應 AC**：AC-access-01
- **前置作業**：
  1. 本機可連外網路。
  2. 已安裝 `curl`。
  3. Cloud Run 服務 `clawdbot` 已部署且 `allUsers→roles/run.invoker`（公開可呼叫）。
- **測試步驟**：
  1. 在**本機終端機**直接貼上以下指令（注意：行首沒有 `!`）：
     ```
     curl -s https://clawdbot-475727900579.asia-east1.run.app/chat?session=main -o /dev/null -w '%{http_code}'
     ```
  2. 讀取輸出的 HTTP 狀態碼。
- **預計成果**：輸出 `200`，代表 dashboard 的 HTML shell 可被匿名下載（頁面外殼公開，授權發生在後續 config API）。
- **實際成果**：`HTTP:200`（live-vm-access / `painpoint-cloudrun-chat-no-token`：HTML 頁面本身可達回 200）。同端根路徑亦 200（live-cloudrun / `cloudrun-root`：actual `200`）。
- **判定**：✅PASS
- **備註**：HTML 回 200 不等於 UI 可用；UI 是否能初始化取決於後續 config API 能否拿到 token（見 TC-03-ACCESS-05）。唯讀操作，可逆，無權限變更。

---

### TC-03-ACCESS-02：VM HTTPS dashboard 頁面可達且 TLS 憑證可信
- **對應 AC**：AC-access-02
- **前置作業**：
  1. 本機可連外網路。
  2. VM `clawdbot-vm` 已啟動，Caddy 已就緒（流程順序：須先 `update-container` 再起 Caddy，順序錯會無法取得憑證）。
  3. nip.io 對應 IP 解析正常（`34-81-189-176.nip.io` → `34.81.189.176`）。
- **測試步驟**：
  1. 在**本機終端機**貼上以下指令（行首無 `!`）：
     ```
     curl -sS -o /dev/null -w 'HTTP:%{http_code} ssl_verify_result:%{ssl_verify_result}' --max-time 15 https://34-81-189-176.nip.io/
     ```
  2. 確認狀態碼與 TLS 驗證結果。
  3. （對照）若要驗 `/chat?session=main` 頁面：
     ```
     curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 'https://34-81-189-176.nip.io/chat?session=main'
     ```
- **預計成果**：根路徑回 `HTTP:200` 且 `ssl_verify_result:0`（憑證受信任，**不需** `-k`）；`/chat` 頁面回 `200`。
- **實際成果**：`HTTP:200 ssl_verify_result:0`（live-vm-access / `vm-https-cert-valid`：actual「未使用 -k 即成功，Caddy+nip.io 自動憑證受信任」）；根路徑 `HTTP:200`（`vm-https-root`）；`/chat?session=main` `HTTP:200`（`painpoint-vm-chat-token-fragment`）。
- **判定**：✅PASS
- **備註**：稽核清單 access-02 的指令使用了 `-k`（略過 TLS 驗證）仍會 200，但實測憑證本就可信，正式驗證建議不加 `-k` 以同時確認憑證有效。斷點：Caddy 啟動順序錯誤會導致憑證未簽發而連線失敗——這是 VM 端最常見的中斷點。唯讀操作。

---

### TC-03-ACCESS-03：config API 無 token 回 401（負向／權限閘門）
- **對應 AC**：AC-access-03
- **前置作業**：
  1. 本機可連外網路。
  2. Cloud Run 服務已部署。
  3. 不攜帶任何 `Authorization` 標頭。
- **測試步驟**：
  1. 在**本機終端機**貼上（行首無 `!`）：
     ```
     curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  2. 讀取狀態碼。
  3. （對照 VM 端，驗證兩端一致）：
     ```
     curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 https://34-81-189-176.nip.io/__openclaw/control-ui-config.json
     ```
- **預計成果**：兩端皆回 `401`，證明 config API 受 token 保護、預設拒絕匿名存取。
- **實際成果**：Cloud Run `401`（live-cloudrun / `cloudrun-config-no-token`：actual `401`；live-vm-access / `cloudrun-config-without-token`：`HTTP:401`）；VM `HTTP:401`（live-vm-access / `vm-config-without-token`）。
- **判定**：✅PASS
- **備註**：這正是使用者痛點的伺服器端根因——沒有 token 時 UI 拿不到設定。授權純由 HTTP 層 Bearer 檢查強制，config body 不對外暴露 auth.mode/token 欄位。唯讀操作。

---

### TC-03-ACCESS-04：config API 正確 Bearer token 回 200，錯誤 token 回 401
- **對應 AC**：AC-access-04、AC-access-05
- **前置作業**：
  1. 本機可連外網路。
  2. 已知現役 64-hex gateway token。
  3. Cloud Run 服務已部署。
- **測試步驟**：
  1. 在**本機終端機**貼上「正確 token」指令（行首無 `!`，token 為單行請勿換行）：
     ```
     curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  2. 接著在**本機終端機**貼上「錯誤 token」指令：
     ```
     curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer wrongtoken12345' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  3. 比對兩者狀態碼。
- **預計成果**：正確 token → `200`；錯誤 token → `401`。
- **實際成果**：正確 token `200`（live-cloudrun / `cloudrun-config-with-token`：actual `200`；live-vm-access / `cloudrun-config-with-token`：`HTTP:200`）；VM 端正確 token 亦 `HTTP:200`（`vm-config-with-token`）。錯誤 token 的專屬 live 檢查未列入 execJson（access-05 為稽核清單項，無對應已執行結果）→ **依賴外部設定**：錯誤 token 401 行為與「無 token 401」同屬 HTTP 層強制拒絕，可由 TC-03-ACCESS-03 的 401 結果與 docker-integration / `test-04`（actual 含「錯誤 Bearer=401」）佐證，但針對線上 Cloud Run 的 `wrongtoken12345` 案例本次未單獨執行。
- **判定**：🖐️手動（正確 token=200 已 PASS；線上錯誤 token=401 需手動補測，目前由整合測試「錯誤 Bearer=401」間接佐證）
- **備註**：token 為敏感資料，貼指令時避免落入共用 shell history（可於指令前加空格，視 `HISTCONTROL=ignorespace`）。唯讀操作，不變更授權。

---

### TC-03-ACCESS-05：重現「需要驗證」失敗並用 #token fragment 正確存取（核心痛點）
- **對應 AC**：AC-access-01、AC-access-02、AC-access-03、AC-access-04
- **前置作業**：
  1. 一台可開瀏覽器的機器，使用**無痕視窗**（排除舊 cookie/快取）。
  2. 已知現役 64-hex gateway token。
  3. Cloud Run 或 VM dashboard 已部署。
- **測試步驟**：
  1. 【重現失敗】在**無痕瀏覽器**網址列輸入**不帶 token** 的網址並開啟：
     `https://clawdbot-475727900579.asia-east1.run.app/chat?session=main`
     觀察頁面：HTML 載入但 UI 顯示「需要驗證」。
  2. 【佐證根因】在**本機終端機**貼上（行首無 `!`）確認 config API 匿名為 401：
     ```
     curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  3. 【正確做法】在**無痕瀏覽器**網址列改用**帶 `#token` fragment** 的網址（`#` 後的內容不會送到伺服器，由前端 JS 取出）：
     `https://clawdbot-475727900579.asia-east1.run.app/chat?session=main#token=`
     觀察頁面：UI 正常初始化，不再顯示「需要驗證」。
  4. （VM 對照）同法以 `https://34-81-189-176.nip.io/chat?session=main#token=<同上>` 開啟。
- **預計成果**：步驟 1 重現「需要驗證」（config API 匿名 401）；步驟 3 帶 `#token` 後前端以 `Authorization: Bearer` 取得 config 200，UI 可用。差異純粹在「網址是否攜帶 token fragment」，與伺服器授權邏輯無關（兩端一致）。
- **實際成果**：頁面層級為**手動驗證**（瀏覽器 UI 呈現需人工觀察）。API 層佐證已自動化並 PASS：匿名 config API `401`（`cloudrun-config-no-token` / `vm-config-without-token`）、帶 token `200`（`cloudrun-config-with-token` / `vm-config-with-token`）、`/chat` HTML 兩端皆 `200`（`painpoint-cloudrun-chat-no-token`、`painpoint-vm-chat-token-fragment`）。execJson 明述：「VM 帶 #token 無痕網址可用之原因——fragment 由前端 JS 取出後以 Bearer 帶入受保護 config API」。
- **判定**：🖐️手動（瀏覽器 UI 需人工確認；底層 API 行為皆已自動驗證 PASS）
- **備註**：最大斷點集中於此——(a) token 必須放 `#fragment` 不能放 `?query`（query 會進 log 且前端不讀）；(b) 終端機指令行首切勿加 `!`；(c) 用無痕視窗避免舊狀態干擾。可逆：關閉分頁即結束 session，token 不留在伺服器 log。

---

### TC-03-ACCESS-06：.env 未設 OPENCLAW_PUBLIC_URL 時走預設值行為（靜態／設定漂移）
- **對應 AC**：AC-access-06
- **前置作業**：
  1. 位於 repo 根目錄 `/Users/allenchen/project/demo/openclaw/repo`。
  2. 存在 `.env`（或確認其未設 `OPENCLAW_PUBLIC_URL`）。
- **測試步驟**：
  1. 在**本機終端機**於 repo 根目錄貼上（行首無 `!`）：
     ```
     grep '^OPENCLAW_PUBLIC_URL=' .env || echo 'NOTSET'
     ```
  2. 觀察輸出。
- **預計成果**：輸出 `NOTSET`，代表未顯式設定，部署時由 gen-config 走 Cloud Run 自動 URL 之預設行為（allowedOrigins 由公開 URL 推導）。
- **實際成果**：**手動驗證**（execJson 未含此 grep 的單項 actual）。相關佐證：docker-integration / `test-04`（actual 含「config token 正確、allowedOrigins 含公開 URL」），且 test_config（25 passed）涵蓋 URL/頻道等 gen-config 案例全綠，間接支持預設值行為正確。
- **判定**：🖐️手動（需於本機 repo 執行 grep 確認；設定產生器邏輯已由 test_config 全綠覆蓋）
- **備註**：屬靜態設定檢查，無線上副作用。注意 allowedOrigins 若與實際 public URL 不符會造成前端跨域被擋，間接表現為「需要驗證」假象。

---

### TC-03-ACCESS-07：.env 的 OPENCLAW_GATEWAY_TOKEN 為 64 hex（token 格式守門）
- **對應 AC**：AC-access-07
- **前置作業**：
  1. 位於 repo 根目錄。
  2. 存在 `.env` 且含 `OPENCLAW_GATEWAY_TOKEN`。
- **測試步驟**：
  1. 在**本機終端機**於 repo 根目錄貼上（行首無 `!`）：
     ```
     grep '^OPENCLAW_GATEWAY_TOKEN=' .env | cut -d= -f2 | wc -c
     ```
  2. 觀察字元數（64 hex + 換行符 = 65）。
- **預計成果**：輸出 `65`（64 個 hex 字元加上 `wc -c` 計入的換行符），代表 token 長度正確。
- **實際成果**：**手動驗證**（execJson 未含此 grep 的單項 actual）。相關佐證：test_config（25 passed，含 token 案例）、test_makefile（22 passed，含 gen-token 冪等）、docker-integration / `test-04`（actual 含「config token 正確」與「金鑰未明文外洩」）皆綠，間接支持 token 格式/產生邏輯正確。
- **判定**：🖐️手動（需於本機 repo 執行 grep 確認；token 產生/冪等已由 test_config、test_makefile 覆蓋）
- **備註**：靜態檢查、無線上副作用。token 是 dashboard 存取的唯一鑰匙，格式錯誤會直接導致 config API 全程 401。勿將 token 提交進版控（gitleaks 掃描於 test_lint 19 passed 中已通過，無洩漏）。

---

### TC-03-ACCESS-08：device-auth 豁免路徑說明（公開資源不需 token）
- **對應 AC**：AC-access-01、AC-access-03
- **前置作業**：
  1. 本機可連外網路。
  2. Cloud Run / VM 已部署。
- **測試步驟**：
  1. 在**本機終端機**貼上（行首無 `!`）確認公開根路徑與 HTML shell 不需 token 即可達：
     ```
     curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/
     ```
  2. 對照受保護 config API 仍需 token（見 TC-03-ACCESS-03）。
- **預計成果**：公開資源（`/`、`/chat` HTML shell、靜態資產）回 `200`，屬 device-auth 豁免範圍；唯有 `/__openclaw/control-ui-config.json` 等控制 API 強制 Bearer。豁免邊界清楚：頁面外殼公開、控制資料受保護。
- **實際成果**：根路徑 `200`（live-cloudrun / `cloudrun-root`：actual `200`）；`/chat` HTML `200`（`painpoint-cloudrun-chat-no-token`、`painpoint-vm-chat-token-fragment`）；對照受保護 API 匿名 `401`（`cloudrun-config-no-token`、`vm-config-without-token`）。豁免邊界已由「公開頁 200 / 控制 API 401」對照證實。
- **判定**：✅PASS
- **備註**：device-auth 豁免讓 dashboard 頁面可被無痕視窗直接開啟（才有機會在前端讀取 `#token`）；若連 HTML shell 都鎖死，使用者將無法載入讀取 token 的 JS。豁免範圍與受保護範圍的分界即是「需要驗證」現象的根本設計。唯讀操作。
