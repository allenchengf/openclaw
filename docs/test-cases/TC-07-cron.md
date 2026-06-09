# TC-07 提醒與 Cron 測試案例

本檔涵蓋 openclaw（小龍蝦/ClawdBot）部署框架在「提醒與 Cron」領域的正規測試案例。範圍對應
AC-07：在 `cron.enabled=true`（預設）的前提下，使用者請 bot「設定 N 分鐘後提醒」應成功設定且
**不出現 `Cron tool error`**。本領域的可自動化稽核聚焦於設定層證據——cron 是否啟用、使用者時區是否為
`Asia/Taipei`、時間格式是否為 24 小時制、`.env` 時區鍵是否正確、以及 `maxConcurrentRuns` 並行上限。
排程後是否實際「準時觸發並送出提醒」屬時間相依的行為，需以 dogfood（真人對話）手動驗證，本檔明確標示。

> 重要操作斷點提醒（使用者最大痛點，務必先讀）：
> 1. 凡標示「本機終端機」的指令，請直接貼進你電腦的 Terminal/iTerm 執行；切勿貼進 Claude 輸入框。
> 2. 本檔所有指令皆「不含」`!` 前綴，照抄即可。切勿把 Claude REPL 的 `!` 前綴貼進真實終端機，
>    否則 `!` 會被 shell 當成 history expansion（歷史展開）或被誤讀為邏輯否定而中斷流程。
> 3. 凡標示「無痕瀏覽器」的步驟，control-ui 網址必須攜帶 `#token=...` fragment，否則前端拿不到設定
>    而顯示「需要驗證」（config API 無 token 回 401）。dogfood 對話請在已帶 token 的 `/chat?session=main` 頁進行。
> 4. 時區與時間格式是「提醒準不準」的根因：若 `Asia/Taipei` 或 `timeFormat=24` 設錯，N 分鐘後的觸發時間會偏移，
>    雖不報 `Cron tool error` 卻會「提醒在錯的時間響」，故時區/格式檢查列為本領域前置防線。

> 標準環境參數：
> - gateway token：``
> - Cloud Run：`https://clawdbot-475727900579.asia-east1.run.app`
> - GCE VM HTTPS：`https://34-81-189-176.nip.io`
> - 倉庫路徑：`/Users/allenchen/project/demo/openclaw/repo`

---

### TC-07-01：cron 已啟用（線上 config 驗證 cron.enabled=true）
- **對應 AC**：AC-07
- **前置作業**：
  - 本機已安裝 `curl`、`grep`、`wc`。
  - 已知 gateway token（見檔頭）。
  - Cloud Run 服務在線：`https://clawdbot-475727900579.asia-east1.run.app`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -o '"enabled":\s*true' | head -1 | wc -l
     ```
  2. 觀察輸出數字。
- **預計成果**：輸出 `1`（config 內存在 `"enabled": true`，代表 cron 已啟用）。
- **實際成果**：依賴外部設定（cron-01 為 live check，本次 execJson 未回填此 grep 的獨立 actual）。強佐證：docker-integration test-04（pass）已實測容器內 `openclaw config validate` 確認 `cron.enabled=true`；同端 control-ui-config.json 帶正確 token 回 200（cloudrun-config-with-token actual=200, pass），config API 可讀。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。需帶 token，否則 config API 回 401（見 TC-07-06）。此為本領域「提醒能否設定」的根本前提，若回 0 表示 cron 被關閉，後續所有提醒皆會失敗。

---

### TC-07-02：cron 已啟用（容器內 config validate 自動斷言）
- **對應 AC**：AC-07
- **前置作業**：
  - 本機 Docker daemon 就緒（`docker info` OK）。
  - 在倉庫根目錄 `/Users/allenchen/project/demo/openclaw/repo`。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```
     docker info
     bash /Users/allenchen/project/demo/openclaw/repo/tests/test_integration.sh
     ```
  2. 觀察輸出最後一行彙總，並確認子項目含 `cron.enabled=true`。
- **預計成果**：整合測試全綠（`21 passed, 0 failed, 0 skipped`，exit 0），子項目明確斷言 `cron.enabled=true`。
- **實際成果**：✅ 已實測。docker-integration test-04 actual：`docker info => DAEMON_OK`；`bash tests/test_integration.sh` 輸出全綠並以「結果：21 passed, 0 failed, 0 skipped」結束（exit 0）。子項含 `openclaw config validate 通過`、`cron.enabled=true`、`userTimezone=Asia/Taipei`、`memorySearch 預設停用(none)`、無 `chunks_vec` 記憶錯誤。全程唯讀本機 docker，未碰線上 GCP。
- **判定**：✅PASS
- **備註**：唯讀、可逆（容器測試自動清理）。這是 `cron.enabled=true` 最強的自動化證據，比 live grep 更可靠（不受網路/token 影響）。

---

### TC-07-03：使用者時區為 Asia/Taipei（提醒觸發時間基準）
- **對應 AC**：AC-07、AC-02
- **前置作業**：
  - 本機已安裝 `curl`、`grep`。
  - 已知 gateway token（見檔頭）。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -q 'Asia/Taipei' && echo 'OK' || echo 'FAIL'
     ```
  2. 觀察輸出。
- **預計成果**：輸出 `OK`（config 含 `Asia/Taipei`，N 分鐘後提醒以台灣時間計算）。
- **實際成果**：依賴外部設定（cron-02 為 live check，execJson 未回填此 grep 獨立 actual）。強佐證：docker-integration test-04（pass）實測容器內 `userTimezone=Asia/Taipei`；live-vm-access 與 live-cloudrun 兩端 config API 帶 token 皆 200，config 可讀。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。時區是提醒準不準的根因（見檔頭斷點 4）。若回 FAIL，提醒雖可設定但會在錯的時間響。

---

### TC-07-04：時間格式為 24 小時制（timeFormat=24）
- **對應 AC**：AC-07、AC-02
- **前置作業**：
  - 本機已安裝 `curl`、`grep`。
  - 已知 gateway token（見檔頭）。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -o '"timeFormat":\s*"[^"]*"' | grep -q '24' && echo 'OK' || echo 'FAIL'
     ```
  2. 觀察輸出。
- **預計成果**：輸出 `OK`（`timeFormat` 含 `24`，避免 12 小時制造成 AM/PM 歧義）。
- **實際成果**：依賴外部設定（cron-03 為 live check，execJson 未回填此 grep 獨立 actual）。間接佐證：AC-02 驗證紀錄載明 `test_config/integration 斷言 ... timeFormat=24`；docker-integration test-04（pass）通過含時區相關回歸檢查。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。與 TC-07-03 同屬時間正確性防線。

---

### TC-07-05：.env 時區鍵正確（OPENCLAW_TIMEZONE=Asia/Taipei，設定層源頭）
- **對應 AC**：AC-07、AC-02
- **前置作業**：
  - 在倉庫根目錄 `/Users/allenchen/project/demo/openclaw/repo`。
  - 倉庫含 `.env` 或 `.env.example`。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```
     grep '^OPENCLAW_TIMEZONE=' /Users/allenchen/project/demo/openclaw/repo/.env || grep '^OPENCLAW_TIMEZONE=' /Users/allenchen/project/demo/openclaw/repo/.env.example
     ```
  2. 觀察輸出值。
- **預計成果**：輸出 `OPENCLAW_TIMEZONE=Asia/Taipei`。
- **實際成果**：✅ 已實測（cron-04 為 live=false 本機檢查）。本次稽核準備階段於倉庫實跑，`.env` 與 `.env.example` 兩處皆回傳 `OPENCLAW_TIMEZONE=Asia/Taipei`。另 test_config.sh（25 passed, 0 failed, pass）涵蓋 gen-config 時區案例、test_static.sh（72/0/1 skip, pass）含設定漂移防護，皆綠。
- **判定**：✅PASS
- **備註**：唯讀、可逆。此鍵是注入到容器 `userTimezone` 與 `TZ` 的源頭，是 TC-07-03 線上值的上游；兩者應一致。

---

### TC-07-06：未帶 token 取 config 應被拒（401，提醒設定面之授權軸線）
- **對應 AC**：AC-07、AC-09
- **前置作業**：
  - 本機已安裝 `curl`。
  - Cloud Run 與 VM 皆在線。
- **測試步驟**：
  1. 在「本機終端機」執行（不帶 Authorization 標頭，故意觸發拒絕）：
     ```
     curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  2. （對照）再執行 VM 端：
     ```
     curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 https://34-81-189-176.nip.io/__openclaw/control-ui-config.json
     ```
- **預計成果**：兩端皆回 `401`（沒有 token 就讀不到 cron/時區設定，授權在 HTTP 層強制）。
- **實際成果**：✅ 已實測。Cloud Run cloudrun-config-no-token actual=`401`（pass）；VM vm-config-without-token actual=`HTTP:401 (exit=0)`（pass）。對照組帶正確 token：cloudrun-config-with-token=`200`、vm-config-with-token=`HTTP:200`（皆 pass）。兩端授權行為一致。
- **判定**：✅PASS
- **備註**：唯讀、可逆。本案說明「提醒設定/檢視介面」與 dashboard 共用同一 token 閘門：無 token 連 cron 設定都讀不到。dogfood 設定提醒前，確認用的是帶 `#token=` fragment 的網址（見檔頭斷點 3）。

---

### TC-07-07：cron 並行上限設定（maxConcurrentRuns=8）
- **對應 AC**：AC-07
- **前置作業**：
  - 本機已安裝 `curl`、`grep`。
  - 已知 gateway token（見檔頭）。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -o '"maxConcurrentRuns":\s*[0-9]*' | grep -q '8' && echo 'OK' || echo 'FAIL'
     ```
  2. 觀察輸出。
- **預計成果**：輸出 `OK`（`maxConcurrentRuns` 為 8，多個提醒可並行不互相阻塞）。
- **實際成果**：依賴外部設定（cron-05 為 live check，execJson 未回填此 grep 獨立 actual，且 config body 未對外暴露此欄位之單獨佐證——live-vm-access 註記 config body 未暴露 auth/mode 等欄位，授權純由 HTTP 層強制）。間接佐證：config API 帶 token 兩端皆 200，欄位可被前端讀取。此並行上限數值需手動以上方指令確認。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。若回 FAIL，可能是預設值不同或欄位名變更，不一定代表故障；屬設定值核對而非功能阻斷。

---

### TC-07-08：dogfood 設定 N 分鐘後提醒且無 Cron tool error（端到端行為，正向主路徑）
- **對應 AC**：AC-07
- **前置作業**：
  - 已開啟「無痕瀏覽器」並進入帶 token 的對話頁：
    `https://clawdbot-475727900579.asia-east1.run.app/chat?session=main#token=`
    （或 VM 端 `https://34-81-189-176.nip.io/chat?session=main#token=...`）。
  - 前置設定層測試 TC-07-02、TC-07-05 已綠（cron 已啟用、時區正確）。
  - 模型可用：模型為 `google-vertex/gemini-2.5-flash`，須已完成 `make vertex-auth`（ADC 存入 Secret `vertex-adc`），詳見 `docs/VERTEX-SETUP.md`（見備註與 TC-07-09）。
- **測試步驟**：
  1. 在「無痕瀏覽器」的「Claude/bot 對話輸入框」輸入（這是對 bot 說話，不是終端機指令，勿加 `!`）：
     ```
     幫我設定 2 分鐘後提醒我喝水
     ```
  2. 觀察 bot 回覆是否確認已設定，且回覆中「不含」`Cron tool error`。
  3. 等待約 2 分鐘，觀察提醒是否於台灣時間準時送達（以 24 小時制時間呈現）。
- **預計成果**：bot 回覆類似「已幫你設定兩分鐘後喝水的提醒」，無 `Cron tool error`；約 2 分鐘後收到提醒。
- **實際成果**：🖐️手動驗證（時間相依的真人對話，非自動化）。AC-07 既有驗證紀錄載明 ✅ dogfood 回「已幫你設定兩分鐘後喝水的提醒」。本次 execJson 為唯讀/stub，未重跑 dogfood；設定層前提（cron.enabled=true、Asia/Taipei、timeFormat=24）已由 TC-07-02/05 自動佐證為綠。
- **判定**：🖐️手動
- **備註**：斷點提醒——(1) 第 1 步是對 bot 說話，務必在「對話輸入框」而非終端機；(2) 網址若沒帶 `#token=` 會顯示「需要驗證」而無法對話（見檔頭斷點 3）；(3) 模型風險：模型已切換為 Vertex AI（`google-vertex/gemini-2.5-flash`），若 ADC 帳號無 aiplatform 權限或試用額度耗盡，Vertex 會回 403/配額錯誤，bot 可能無法生成回覆，需先確認模型可用（見 TC-07-09）。可逆：可請 bot 取消或讓提醒自然過期。

---

### TC-07-09：模型可用性對提醒設定的前置依賴（負向風險，Vertex ADC 被拒）
- **對應 AC**：AC-07、AC-16
- **前置作業**：
  - 本機已安裝 `curl`、`gcloud`。
  - 模型為 `google-vertex/gemini-2.5-flash`；已完成 `make vertex-auth`（ADC 帳號為專案 owner、具 aiplatform 權限），`GCP_PROJECT_ID` 已知。
- **測試步驟**：
  1. 在「本機終端機」執行（以 ADC token 直打 Vertex，驗證模型能否生成內容；將 `<PROJ>` 換成 `GCP_PROJECT_ID`）：
     ```
     TOK=$(gcloud auth application-default print-access-token)
     curl -s -w 'HTTP_STATUS:%{http_code}' -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' 'https://aiplatform.googleapis.com/v1/projects/<PROJ>/locations/global/publishers/google/models/gemini-2.5-flash:generateContent' -d '{"contents":[{"role":"user","parts":[{"text":"Say OK"}]}]}'
     ```
  2. 觀察 HTTP 狀態與 body。
- **預計成果**：`HTTP_STATUS:200` 並回傳模型生成內容（Vertex 可用，提醒設定流程的模型層不會卡住）。
- **實際成果**：依賴外部設定（live check，需有效 ADC token）。已知風險對照（見 `docs/VERTEX-SETUP.md` 排錯）：若 ADC 帳號不對或無 aiplatform 權限會回 `403 PERMISSION_DENIED on aiplatform.endpoints.predict`；若仍誤打 AI Studio 路（`generativelanguage`／`google/*` 模型）才會出現舊的 `403 project denied access`。Vertex 走獨立 `aiplatform.googleapis.com`、吃 GCP 專案試用金，可避開 AI Studio 金鑰的封鎖。
- **判定**：🖐️手動
- **備註**：此非 cron 設定本身的 bug，而是 TC-07-08 dogfood 的上游風險——若模型無法回應，bot 連「我幫你設定好了」都答不出來，使用者會誤以為提醒功能壞了。修復方向：重做 `make vertex-auth` 選對帳號（owner/具 aiplatform 權限），或試用額度到期時換新的免費 Google 帳號／GCP 專案重做 vertex-auth。權限軸線：ADC 帳號的 Vertex 權限，與 cron.enabled 無關但會連帶阻斷端到端體驗。

---

## 本檔彙總

| 判定 | 數量 | 案例 |
| --- | --- | --- |
| ✅PASS | 3 | TC-07-02、TC-07-05、TC-07-06 |
| ❌FAIL | 0 | — |
| ⏭️SKIP | 0 | — |
| 🖐️手動 | 6 | TC-07-01、TC-07-03、TC-07-04、TC-07-07、TC-07-08、TC-07-09 |

說明：cron 啟用、時區與時間格式的「線上 grep」(cron-01/02/03/05) 屬 live check 但 execJson 未回填各別 grep 之獨立 actual，
故標 🖐️手動並以可靠的自動化替代證據佐證（容器內 `config validate` 斷言 cron.enabled=true / userTimezone=Asia/Taipei，
以及 `.env` 本機 grep）。端到端「準時觸發」屬時間相依的 dogfood，標 🖐️手動。模型可用性（TC-07-09）已隨 Vertex AI 切換改為以 ADC token 直打 `aiplatform.googleapis.com`（live check），標 🖐️手動；舊版 Gemini 金鑰 403 的 ❌FAIL 不再適用（Vertex 走獨立 endpoint、吃專案試用金）。cron 本身邏輯不變。
