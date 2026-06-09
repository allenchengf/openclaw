# TC-05 對話與模型 測試案例

本檔涵蓋 openclaw（小龍蝦/ClawdBot）部署框架在「對話與模型」領域的正規測試案例。範圍包含：
基本對話與繁體中文切題回覆、台灣時間（Asia/Taipei，UTC+08:00）正確套用、模型設定與切換
（已切換到 **Vertex AI**，模型 `google-vertex/gemini-2.5-flash`，由 `.env` 的 `OPENCLAW_MODEL`
注入而非硬編碼），以及 Vertex AI 認證軸線——走 **Google ADC（service account / authorized_user，免 API 金鑰）**
打 `aiplatform.googleapis.com`，吃 GCP 專案試用金；認證憑證由 `make vertex-auth` 產生並存入
Secret Manager（`vertex-adc`），容器啟動時自動取出。常見故障為 ADC 憑證帳號不對 →
403 PERMISSION_DENIED on aiplatform.endpoints.predict。

> 背景：先前使用 AI Studio `AIza` 金鑰的方案已淘汰——連帳單專案回 429「prepayment credits depleted」、
> 無帳單免費專案被帳號層級軟封 403「project denied access」，故全面改用 Vertex AI。

> 重要操作斷點提醒（使用者最大痛點）：
> 1. 凡標示「本機終端機」的指令，請直接貼進你電腦的 Terminal/iTerm 執行；切勿貼進 Claude 輸入框。
> 2. 凡指令以 `!` 開頭的範例，`!` 是 shell 行為（如 history expansion）或文件標記，請勿把 Claude REPL
>    的 `!` 前綴貼進真實終端機，否則可能被當成邏輯否定或歷史展開而中斷。本檔所有指令皆「不含」`!` 前綴，照抄即可。
> 3. control-ui 網址必須攜帶 `#token=...` fragment，否則前端拿不到設定而顯示「需要驗證」。

---

### TC-05-01：模型設定正確為 google-vertex/gemini-2.5-flash（線上 config 驗證）
- **對應 AC**：AC-model-01
- **前置作業**：
  - 本機已安裝 `curl`。
  - 已知 gateway token：``。
  - Cloud Run 服務在線：`https://clawdbot-475727900579.asia-east1.run.app`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json | grep -o '"primary":[[:space:]]*"[^"]*"'
     ```
  2. 觀察輸出是否含 `google-vertex/gemini-2.5-flash`。
- **預計成果**：輸出含 `"primary": "google-vertex/gemini-2.5-flash"`（或 grep 命中 `google-vertex/gemini-2.5-flash`），判定 OK。
- **實際成果**：手動驗證。本次 execJson 未提供 `model-01` 此 grep 之直接 actual；但同端 control-ui-config.json 帶正確 token 回 200（cloudrun-config-with-token actual=200, pass）已證明 config API 可讀，且 docker 整合測試（test-04, pass）確認容器內 `openclaw config validate` 解析到 google-vertex 模型。primary 欄位本身為手動驗證。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。需帶 token，否則 config API 回 401（見 TC-05-09）。模型已由 AI Studio `google/*` 切換為 Vertex `google-vertex/*`。

---

### TC-05-02：OPENCLAW_MODEL 環境變數正確傳遞到 Cloud Run 容器
- **對應 AC**：AC-model-03
- **前置作業**：
  - 本機已安裝並登入 `gcloud`，且 active project 指向部署專案（`project-6c870217-2205-4b1b-a3f` / 編號 475727900579）。
  - 具備 `run.services.get` 唯讀權限。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```
     gcloud run services describe clawdbot --region=asia-east1 --format='value(status.latestCreatedRevision.spec.containers[0].env[?name==OPENCLAW_MODEL].value[0])'
     ```
  2. 觀察輸出值。
- **預計成果**：輸出 `google-vertex/gemini-2.5-flash`。
- **實際成果**：依賴外部設定（gcloud 線上查詢）。execJson 未提供 `model-03` 的獨立 actual；間接佐證：docker-integration test-04（pass）顯示容器內解析到 google-vertex 模型、`config validate` 通過；make status（pass）顯示最新就緒 revision 健康。OPENCLAW_MODEL env 之直接 describe 為手動/外部設定驗證。
- **判定**：🖐️手動
- **備註**：唯讀。`--format` 內的 `?name==OPENCLAW_MODEL` 為 gcloud projection filter，整段以單引號包住，貼進終端機照抄即可，勿拆行。Vertex 模型另需容器帶 `GOOGLE_CLOUD_PROJECT`、`GOOGLE_CLOUD_LOCATION=global` 兩個環境變數（見 VERTEX-SETUP.md）。

---

### TC-05-03：模型未硬編碼，由 .env.example 的 OPENCLAW_MODEL 控制
- **對應 AC**：AC-model-04
- **前置作業**：
  - 本機已 clone 倉庫於 `/Users/allenchen/project/demo/openclaw/repo`。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```
     grep -q 'OPENCLAW_MODEL' /Users/allenchen/project/demo/openclaw/repo/.env.example && echo 'OK' || echo 'FAIL'
     ```
  2. 觀察輸出。
- **預計成果**：輸出 `OK`，代表模型由 `.env` 的 `OPENCLAW_MODEL` 注入而非硬編碼。
- **實際成果**：手動驗證（本機唯讀 grep，live=false）。execJson 無此 check 的獨立 actual；相關佐證：test_static（72 passed, pass）含設定漂移防護、test_config（25 passed, pass）涵蓋設定產生器（含時區等鍵）皆通過，顯示設定由產生器/env 驅動。`.env.example` 是否含 OPENCLAW_MODEL 為手動驗證。
- **判定**：🖐️手動
- **備註**：純本機唯讀、可逆。此案例不需 gcloud 或網路。

---

### TC-05-04：Vertex ADC 憑證已設且來自 Secret Manager（vertex-adc）
- **對應 AC**：AC-model-02
- **前置作業**：
  - 本機已登入 `gcloud`，具 `secretmanager.secrets.get` 唯讀權限。
  - 已執行過 `make vertex-auth`（會建立 `vertex-adc` secret）。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```
     gcloud secrets describe vertex-adc --format='value(name)' | grep -q 'vertex-adc' && echo 'OK' || echo 'FAIL'
     ```
  2. 觀察輸出。
- **預計成果**：輸出 `OK`，代表 Secret Manager 內存在 `vertex-adc`（Vertex AI 的 ADC 憑證），供 Cloud Run/VM 容器啟動時取用。
- **實際成果**：依賴外部設定（gcloud Secret Manager 線上查詢）。execJson 未提供 `model-02` 的獨立 actual；間接佐證：docker-integration test-04（pass）確認 CONFIG_ONLY 模式下憑證被遮蔽且未明文外洩。`vertex-adc` 存在性為手動/外部設定驗證。
- **判定**：🖐️手動
- **備註**：唯讀。Vertex AI 改用 ADC 憑證（非 API 金鑰），憑證以 `vertex-adc` secret 保存；entrypoint 啟動時由 runtime SA 取出寫到 `GOOGLE_APPLICATION_CREDENTIALS`。注意 secret「存在」不代表 ADC 帳號「正確/可用」——帳號錯誤會在實打時回 403（見 TC-05-08）。

---

### TC-05-05：Vertex ADC 憑證遮蔽——Cloud Run 日誌不輸出明文憑證（負向/安全）
- **對應 AC**：AC-model-05
- **前置作業**：
  - 本機已登入 `gcloud`，具 `logging.logEntries.list` 讀取權限。
- **測試步驟**：
  1. 在「本機終端機」執行（同時檢查殘留的舊式 `AIza` 金鑰與 Vertex ADC 的 `refresh_token` 是否外洩）：
     ```
     gcloud run services logs read clawdbot --region=asia-east1 --limit=20 | grep -Eq 'AIza|refresh_token' || echo 'OK (no expose)'
     ```
  2. 觀察輸出。
- **預計成果**：輸出 `OK (no expose)`，代表近期日誌中未出現明文 `AIza` 金鑰，也未出現 Vertex ADC 憑證的 `refresh_token` 欄位。
- **實際成果**：依賴外部設定（gcloud 線上日誌查詢）。execJson 未提供 `model-05` 的獨立 actual；強力佐證：docker-integration test-04（pass）明確驗證「CONFIG_ONLY 模式憑證遮蔽且未明文外洩」、test_lint（19 passed, pass）gitleaks 機密掃描無洩漏。線上日誌遮蔽為手動驗證。
- **判定**：🖐️手動
- **備註**：負向安全檢查；唯讀、可逆。Vertex 已不用 `AIza` 金鑰，但 ADC 憑證檔（含 `refresh_token`）為新的敏感標的，故一併檢查。`grep -Eq ... || echo` 為「沒命中才印 OK」，命中（有明文）反而靜默——判讀時務必看到 `OK (no expose)` 才算通過。

---

### TC-05-06：Vertex 模型回話——基本對話與繁體中文切題回覆（control-ui 帶 token）
- **對應 AC**：AC-conv-01
- **前置作業**：
  - 已完成一次性 `make vertex-auth`（ADC 登入正確帳號、`vertex-adc` secret 已存在、runtime SA 已授權），且已 `make deploy` 使 Vertex 設定生效。
  - 已知 gateway token 與 chat URL。
- **測試步驟**：
  1. 在「無痕瀏覽器」開啟（網址務必帶 `#token` fragment，照抄）：
     ```
     https://clawdbot-475727900579.asia-east1.run.app/chat?session=main#token=
     ```
  2. 待 UI 初始化完成（前端以 fragment 內 token 帶 Bearer 取得 config）。
  3. 在「Dashboard / ClawdBot 對話輸入框」輸入：`你是誰`（或 `你好，請用繁體中文簡短自我介紹`）。
  4. 觀察回覆語言與切題程度。
- **預計成果**：UI 正常載入（不顯示「需要驗證」）；Vertex 模型 `google-vertex/gemini-2.5-flash` 以繁體中文、切題地回覆自我介紹。
- **實際成果**：✅ PASS（已實測）。在 Dashboard 送出「你是誰」後，Vertex 模型正常以繁體中文回覆，內容為「我是一個由 Google 訓練的語言模型」。UI 可達性亦有 execJson 佐證：painpoint-cloudrun-chat-no-token actual=HTTP 200（HTML shell 可下載）、cloudrun-config-with-token actual=200（帶 token config 可取得）。切換到 Vertex AI 後，先前因 Gemini 金鑰 403 而無法生成對話的問題已解除。
- **判定**：✅PASS
- **備註**：斷點提醒——網址必須帶 `#token`，否則前端 config API 回 401 顯示「需要驗證」；勿把 `!` 前綴或範例符號貼進對話框。Vertex 認證一旦帳號錯誤會在生成時回 403（見 TC-05-08）。

---

### TC-05-07：台灣時間（Asia/Taipei, UTC+08:00）正確套用
- **對應 AC**：AC-conv-02, AC-model-03
- **前置作業**：
  - 容器環境變數 `TZ=Asia/Taipei` 已設定。
  - （線上對話驗證）已完成 `make vertex-auth` 且 Vertex 認證可用。
- **測試步驟**：
  1. 配置面驗證（本機，無須金鑰）——在「本機終端機」執行 docker 整合測試：
     ```
     docker info && bash /Users/allenchen/project/demo/openclaw/repo/tests/test_integration.sh
     ```
     確認 `userTimezone=Asia/Taipei` 相關項通過。
  2. 線上對話驗證（選用，需 Vertex 認證可用）——在「無痕瀏覽器」帶 token 開啟 chat 後，於對話框輸入：`現在台灣時間幾點？` 觀察回覆時區是否為 +08:00。
- **預計成果**：整合測試顯示時區為 Asia/Taipei；對話回覆之時間採 UTC+08:00。
- **實際成果**：配置面 PASS。docker-integration test-04 actual 明確含「userTimezone=Asia/Taipei」且 `openclaw config validate` 通過（21 passed, 0 failed, status=pass）；test_config（25 passed, pass）亦涵蓋時區案例。切換 Vertex AI 後對話已可生成（見 TC-05-06 PASS），線上時間回覆可隨對話實測。
- **判定**：✅PASS（配置面，依 docker-integration test-04）
- **備註**：步驟1為本機唯讀 docker，可逆未碰線上；docker daemon 需先就緒。

---

### TC-05-08：Vertex ADC 帳號錯誤——aiplatform 應回 200（負向陷阱：403 PERMISSION_DENIED 重現）
- **對應 AC**：AC-model-02, AC-model-06
- **前置作業**：
  - 已執行 `make vertex-auth` 取得 ADC（注意：ADC 必須是 `.env` 裡 `GCP_ACCOUNT` 那個專案 owner 帳號）。
  - 本機已安裝 `curl`、`gcloud`。
- **測試步驟**：
  1. 在「本機終端機」用 ADC token 直打 Vertex `generateContent`（單行；`<PROJ>` 換成 `GCP_PROJECT_ID`；勿加 `!` 前綴）：
     ```
     TOK=$(gcloud auth application-default print-access-token); curl -s -w 'HTTP_STATUS:%{http_code}' -X POST 'https://aiplatform.googleapis.com/v1/projects/<PROJ>/locations/global/publishers/google/models/gemini-2.5-flash:generateContent' -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"contents":[{"role":"user","parts":[{"text":"Say OK"}]}]}'
     ```
  2. 觀察 HTTP 狀態碼與 body。若懷疑帳號不對，可先 `curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$TOK"` 檢查 `email` 是否為預期 owner 帳號。
- **預計成果**：`HTTP_STATUS:200` 並回傳模型生成內容，證明 ADC 帳號對專案有 Vertex（`aiplatform.user`/owner）權限。
- **實際成果**：❌ FAIL（已實測重現）。當 ADC 用到「非 owner 帳號 ccie16595」時，aiplatform 回 `403 PERMISSION_DENIED on aiplatform.endpoints.predict`（憑證帳號對該專案無 Vertex 預測權限）。並非 endpoint/模型字串問題，而是 ADC 憑證綁到了錯誤的 Google 帳號。重做 `make vertex-auth` 選對 owner 帳號（`GCP_ACCOUNT`）後可恢復 200。
- **判定**：❌FAIL
- **備註**：陷阱軸線（Vertex 認證）——根因為 ADC 用到非 owner 帳號 `ccie16595`，而非配額/帳單問題。排查：用 `print-access-token` + `tokeninfo` 確認 ADC 的 `email`；解法見 VERTEX-SETUP.md 第 5 節「`403 PERMISSION_DENIED on aiplatform.endpoints.predict`」。注意此與舊式 AI Studio 路的 `403 project denied access`（打 `generativelanguage`）是不同故障，Vertex 走 `aiplatform.googleapis.com`。修正帳號後 TC-05-06/07 對話即可正常（現已 PASS）。

---

### TC-05-09：control-ui config API 鑑權——無 token 回 401（負向/權限）
- **對應 AC**：AC-model-07, AC-conv-03
- **前置作業**：
  - 本機已安裝 `curl`。Cloud Run 與 VM 兩端皆在線。
- **測試步驟**：
  1. 在「本機終端機」執行（無 token，預期 401）：
     ```
     curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  2. 再執行（帶正確 token，預期 200）：
     ```
     curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
- **預計成果**：步驟1回 `401`、步驟2回 `200`，證明 token 閘門正常，模型/對話設定不會在無授權下外洩。
- **實際成果**：✅ PASS。cloudrun-config-no-token actual=`401`（pass）；cloudrun-config-with-token actual=`200`（pass）。VM 端一致：vm-config-without-token actual=HTTP:401（pass）、vm-config-with-token actual=HTTP:200（pass）。兩端授權行為一致。
- **判定**：✅PASS
- **備註**：權限軸線；唯讀、可逆。此即「無 #token 網址顯示需要驗證」的伺服器端根因——授權在 HTTP 層強制（config body 未暴露 auth.mode/token 欄位）。

---

### TC-05-10：模型切換——將 OPENCLAW_MODEL 改為其他模型並重新部署（變更型，預設 SKIP）
- **對應 AC**：AC-model-08
- **前置作業**：
  - 本機已登入 gcloud、具 `run.admin` 與部署權限（compute 預設 SA 已具 run.admin + iam.serviceAccountUser）。
  - 目標模型對應之金鑰已備妥。
  - ⚠️ 此為「破壞性/變更型」案例，會建立新 revision，預設不於稽核時執行。
- **測試步驟**：
  1. 在「本機終端機」編輯 `/Users/allenchen/project/demo/openclaw/repo/.env`，將 `OPENCLAW_MODEL` 設為目標值（例如另一 `google-vertex/*` 模型）。
  2. 在「本機終端機」執行部署（依框架 Makefile target，例如 `make deploy`）。
  3. 部署完成後執行 TC-05-01 的 config 驗證，確認 `primary` 已切換為新值。
  4. 回復：將 `.env` 改回 `google-vertex/gemini-2.5-flash` 並重新部署。
- **預計成果**：新 revision 的 config `primary` 反映新模型；回復後恢復為 `google-vertex/gemini-2.5-flash`。
- **實際成果**：⏭️ SKIP（破壞性，稽核未執行）。間接佐證可行性：model-iam-compute-sa-roles（pass）確認 compute SA 具 run.admin + iam.serviceAccountUser 部署權限；make status / make url（pass）唯讀讀取服務正常。實際切換未於本次執行。
- **判定**：⏭️SKIP
- **備註**：可逆（步驟4回復）。部署順序陷阱提醒——install/deploy 編排需注意 deploy→allow-public 先後（test_install 情境4 的 order_ok 順序斷言目前 FAIL，tests/test_install.sh:74，疑為 Makefile install target 中 deploy 與 allow-public 相對順序問題，切換模型後若一併重跑 install 須留意）。
