# TC-09：維運流程測試案例（status/logs/url、Vertex 身份驗證/換帳號、GitHub push）

本文件涵蓋 openclaw（小龍蝦／ClawdBot）部署框架在「維運流程」面向的正規測試案例，聚焦三個日常維運子領域：

1. **唯讀狀態與觀測**：`make status`／`make logs`／`make url`／`make dashboard-url`，用於確認 Cloud Run 服務存活、抓取最近日誌、取得服務與 Dashboard 連線網址；以及對應的 VM 端 `make vm-logs`／`make vm-ssh`。皆為唯讀操作，不變更線上資源。
2. **Vertex AI 身份驗證／換帳號流程**：已由 AI Studio API 金鑰切換到 **Vertex AI**（模型 `google-vertex/gemini-2.5-flash`，走 ADC 認證、免 API 金鑰）。一次性身份驗證以 `make vertex-auth` 完成 4 步（ADC login → set-quota-project → 存 Secret `vertex-adc` → 授權 runtime SA）。試用額度到期時，換一個新的免費 Google 帳號並重做 `make vertex-auth` 即可續用。容器 `entrypoint.sh` 啟動時會自動從 Secret Manager（`vertex-adc`）取出 ADC 憑證，故 Cloud Run（無狀態）與 VM 皆免人工塞憑證。
3. **GitHub push 流程**：避免把 Claude 對話框的 `!` 前綴貼進真實終端機、機密檔（`.env`／`*-sa.json`）不入 git、PAT（Personal Access Token）認證 push。

> **重要斷點提醒（使用者最大痛點）**
> - **`!` 前綴只在 Claude 對話框有意義**：在 Claude 對話框輸入 `!cmd` 是「跑 bash」的捷徑；但若把帶 `!` 的字串原封不動貼進「真實終端機（zsh／bash）」，`!` 會被當成歷史展開（`!git` 展開成上一條 git 指令）或在條件式裡被當成邏輯否定，導致指令被改寫而中斷。**下列「本機終端機」步驟一律是不含 `!` 前綴的純指令。**
> - **`make vertex-auth` 會開瀏覽器**：步驟 [1] ADC login 須選用 `.env` 裡 `GCP_ACCOUNT`（即專案 owner）那個帳號登入並同意授權；選錯帳號會在實打 Vertex 時回 `403 PERMISSION_DENIED on aiplatform.endpoints.predict`。
> - **認證軸線陷阱**：Vertex 走 `aiplatform.googleapis.com`，吃 GCP 專案試用金；ADC 帳號錯誤的 403（aiplatform.endpoints.predict）與舊式 AI Studio 路的 403（generativelanguage、project denied）是不同故障，需分辨。

---

### TC-09-01：`make status` 唯讀檢查 Cloud Run 服務狀態
- **對應 AC**：AC-15、AC-23
- **前置作業**：
  - 本機已安裝並登入 `gcloud`，`.env` 內 `GCP_PROJECT_ID` 正確。
  - Cloud Run 服務 `clawdbot` 已部署且 ready。
  - 工作目錄為 repo 根：`/Users/allenchen/project/demo/openclaw/repo`。
- **測試步驟**：
  1. 在「本機終端機」執行（純指令，勿加 `!` 前綴）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && make status
     ```
  2. 觀察輸出是否含 `clawdbot` 服務的 URL、最新就緒 revision 與 MIN（最少實例數）。
- **預計成果**：先印 `.env OK`，接著輸出表頭 `URL / LATEST_READY_REVISION_NAME / MIN`，含 `clawdbot` 服務一列且 MIN≥1（防冷啟動）。稽核 `ops-02`（`grep -q 'clawdbot'`）應得 `OK`。
- **實際成果**：PASS。execJson live-cloudrun `make-status` actual＝`✓ .env OK（project=project-6c870217-2205-4b1b-a3f）` 後接 `URL ... MIN` 表頭、`https://clawdbot-2kxprlv3fa-de.a.run.app  clawdbot-00003-tkj  1`，status=pass。
- **判定**：✅PASS
- **備註**：唯讀、可逆。注意 `make url/status` 回報的 URL（`clawdbot-2kxprlv3fa-de.a.run.app`）與稽核標準 URL（`clawdbot-475727900579.asia-east1.run.app`）字面不同，但指向同一服務、皆健康，非異常。權限軸線＝唯讀 GCP 讀取。

---

### TC-09-02：`make url` 與 `make dashboard-url` 取得連線網址
- **對應 AC**：AC-10、AC-17
- **前置作業**：
  - 同 TC-09-01 的 `gcloud`／`.env`／Cloud Run 前提。
  - 已知 gateway token：``（dashboard-url 會把 `#token=...` fragment 附在網址末端）。
- **測試步驟**：
  1. 在「本機終端機」執行（純指令）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && make url
     ```
  2. 在「本機終端機」執行取得含 token 的 Dashboard 網址：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && make dashboard-url
     ```
  3. 將 `make dashboard-url` 輸出的完整網址（含 `#token=...`）複製到「無痕瀏覽器」開啟，確認 Control UI 正常載入而非顯示「需要驗證」。
- **預計成果**：`make url` 輸出純 Cloud Run 服務 URL；`make dashboard-url` 輸出 `https://<URL>/chat?session=main#token=...`，貼入無痕瀏覽器後 UI 正常初始化。
- **實際成果**：`make url` 部分＝PASS（execJson live-cloudrun `make-url` actual＝`✓ .env OK...` 後接 `https://clawdbot-2kxprlv3fa-de.a.run.app`，status=pass）。`make dashboard-url` 自動化未單獨執行，但「帶 `#token` fragment 的網址可正常載入 UI」之機制已由 live-vm-access 佐證：`/chat` HTML 回 200、`control-ui-config.json` 帶 token 回 200、不帶回 401（fragment 由前端 JS 取出後以 Bearer 帶入 config API）。第 3 步無痕瀏覽器開啟＝🖐️手動。
- **判定**：✅PASS（`make url` 部分）；第 3 步 🖐️手動
- **備註**：斷點提醒——只貼「不含 `#token`」的純 `/chat` 網址會出現「需要驗證」，務必複製 `make dashboard-url` 的「完整」輸出（含 fragment）。token 為敏感值，貼網址時避免外流到共享畫面。

---

### TC-09-03：`make logs N=50` 抓取最近 Cloud Run 日誌
- **對應 AC**：AC-15、AC-23
- **前置作業**：
  - 同 TC-09-01 的 `gcloud`／`.env`／Cloud Run 前提，且帳號具讀取 Cloud Logging 權限。
  - Cloud Run 服務已有日誌產生（至少被呼叫過一次）。
- **測試步驟**：
  1. 在「本機終端機」執行（純指令，`N=50` 控制行數，勿加 `!` 前綴）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && make logs N=50
     ```
  2. 觀察輸出是否為非空的日誌行（稽核 `ops-01` 以 `head -1 | wc -c` 驗證首行非空，expected＝`1`、即首行至少 1 字元）。
- **預計成果**：輸出最近約 50 行 Cloud Run 日誌，首行非空。
- **實際成果**：依賴外部設定（手動驗證）。execJson 各群組未包含 `make logs` 的線上執行結果（live-cloudrun 僅含 url/status，未跑 logs），故無對應 actual 可填。需在本機具 Cloud Logging 讀權限時手動執行驗證。
- **判定**：🖐️手動
- **備註**：唯讀。若回空，多半是時間窗內無流量或日誌權限不足，而非服務異常；可先用 TC-09-01 `make status` 確認服務 ready。權限軸線＝Cloud Logging 讀取。

---

### TC-09-04：VM 端日誌與 SSH 存取（`make vm-logs` / `make vm-ssh`）
- **對應 AC**：AC-05、AC-15
- **前置作業**：
  - GCE VM `clawdbot-vm` 已部署於 `asia-east1-b` 且狀態 RUNNING。
  - 本機 `gcloud compute ssh` 可連入該 VM（已設定 OS Login 或 SSH 金鑰）。
- **測試步驟**：
  1. 在「本機終端機」確認 VM 為 RUNNING（純指令）：
     ```
     gcloud compute instances describe clawdbot-vm --zone=asia-east1-b --format='value(status)'
     ```
  2. 在「本機終端機」抓取 VM 容器日誌（等同 `make vm-logs` 內部行為）：
     ```
     gcloud compute ssh clawdbot-vm --zone=asia-east1-b --command='docker logs $(docker ps -q --filter ancestor=asia-east1-docker.pkg.dev/demo-gemini/clawdbot-repo/clawdbot:v1) 2>&1 | tail -5'
     ```
  3. 如需進入 VM 互動操作，使用 `make vm-ssh`（內部即 `gcloud compute ssh`）；勿把 Claude 對話框的 `!`-前綴指令貼進 VM shell。
- **預計成果**：第 1 步輸出 `RUNNING`（稽核 `ops-05`＝OK）；第 2 步輸出最後 5 行容器日誌（稽核 `ops-06` 以 `wc -l` 驗證＝`5`）。
- **實際成果**：依賴外部設定（手動驗證）。execJson 未含 `ops-05`／`ops-06` 的線上執行結果（live-vm-access 群組驗的是 HTTPS／token 行為，未跑 vm SSH／vm-logs），無對應 actual。VM 線上 HTTPS 健康度旁證：live-vm-access `vm-https-root` actual＝`HTTP:200`、`vm-https-cert-valid` actual＝`ssl_verify_result:0`（status=pass），顯示 VM 服務本身存活。
- **判定**：🖐️手動（VM HTTPS 存活旁證為 ✅PASS）
- **備註**：唯讀。斷點提醒——VM 端 docker 容器標籤須與部署版本一致（`...clawdbot:v1`），版本不符會使 `docker ps --filter ancestor=` 抓不到容器而日誌為空。權限軸線＝Compute SSH。

---

### TC-09-05：Vertex AI 可用性驗證（ADC token 直打 aiplatform，區分帳號錯誤 403）
- **對應 AC**：AC-16、AC-22、AC-23
- **前置作業**：
  - 已執行 `make vertex-auth`（ADC 須為 `.env` 裡 `GCP_ACCOUNT` 的專案 owner 帳號）。
  - 本機 `gcloud`、`curl`，可連外。`<PROJ>` 為 `GCP_PROJECT_ID`。
- **測試步驟**：
  1. 在「本機終端機」用 ADC token 直打 Vertex `generateContent`（純指令，`<PROJ>` 換成專案 ID，勿加 `!` 前綴）：
     ```
     TOK=$(gcloud auth application-default print-access-token); curl -s -w 'HTTP_STATUS:%{http_code}' -X POST 'https://aiplatform.googleapis.com/v1/projects/<PROJ>/locations/global/publishers/google/models/gemini-2.5-flash:generateContent' -H "Authorization: Bearer $TOK" -H 'Content-Type: application/json' -d '{"contents":[{"role":"user","parts":[{"text":"Say OK"}]}]}'
     ```
  2. 依回應狀態碼分類：`200`＝Vertex 可用；`403 PERMISSION_DENIED on aiplatform.endpoints.predict`＝ADC 憑證帳號對該專案無 Vertex 權限（多半是登入到非 owner 帳號）。必要時 `curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$TOK"` 查 `email` 確認帳號。
- **預計成果**：Vertex 可用時回 `HTTP 200` 並含模型生成內容。
- **實際成果**：❌FAIL（已實測）。當 ADC 用到非 owner 帳號 `ccie16595` 時，aiplatform 回 `403 PERMISSION_DENIED on aiplatform.endpoints.predict`——並非配額/帳單問題，而是憑證綁到錯誤的 Google 帳號。重做 `make vertex-auth` 選對 owner 帳號（`GCP_ACCOUNT`）後可恢復 200。
- **判定**：❌FAIL
- **備註**：斷點提醒——務必分辨 Vertex 的 403（`aiplatform.endpoints.predict`，根因＝ADC 帳號不對，解法重做 `make vertex-auth`）與舊式 AI Studio 路的 403（`generativelanguage`、project denied，已淘汰不再使用）。此測試只讀模型 API，不變更任何資源。權限軸線＝Vertex AI ADC 憑證帳號／`aiplatform.user`。
- **舊備註（已淘汰，保留供對照）**：先前 Gemini 金鑰方案須分辨 403（專案被拒，需換專案／聯繫支援）與 429（額度耗盡，需用無帳單歷史專案的免費金鑰）；此 AI Studio 路徑已隨切換到 Vertex AI 而停用。

---

### TC-09-06：Vertex AI 身份驗證／換帳號流程（make vertex-auth 4 步 + entrypoint 自動取 ADC）
- **對應 AC**：AC-16、AC-22
- **前置作業**：
  - `.env` 內 `GCP_PROJECT_ID`、`GCP_ACCOUNT`（專案 owner 帳號）正確。
  - 本機 `gcloud` 已安裝、可開瀏覽器完成 ADC 登入；具 Secret Manager 寫入與 Cloud Run 更新權限。
  - 工作目錄為 repo 根。
- **測試步驟**：
  1. 在「本機終端機」執行一次性身份驗證（純指令，勿加 `!` 前綴），它會逐步完成 4 步並印出每步實際指令：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && make vertex-auth
     ```
     - **[1] 登入 ADC**：`gcloud auth application-default login --account=<GCP_ACCOUNT>`（會開瀏覽器；務必選 `.env` 的 `GCP_ACCOUNT`、即專案 owner 帳號登入並同意授權）。
     - **[2] 設 quota 專案**：`gcloud auth application-default set-quota-project <GCP_PROJECT_ID>`（使用者 ADC 打 API 需指定 quota project）。
     - **[3] 存入 Secret**：將 `~/.config/gcloud/application_default_credentials.json` 以 `gcloud secrets create/versions add vertex-adc --data-file=...` 寫入 Secret Manager（`make vertex-auth` 自動做）。
     - **[4] 授權 SA**：`gcloud secrets add-iam-policy-binding vertex-adc --member=serviceAccount:<SA> --role=roles/secretmanager.secretAccessor`，讓 runtime SA 能讀取（`make vertex-auth` 自動做）。
  2. 在「本機終端機」確認 secret 已建立：
     ```
     gcloud secrets versions list vertex-adc
     ```
  3. 重新部署使 Vertex 認證生效（容器 `entrypoint.sh` 啟動時會自動從 Secret Manager 取出 `vertex-adc` 寫到 `GOOGLE_APPLICATION_CREDENTIALS`，故 deploy 後即自動套用，毋須人工塞憑證）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && make deploy
     ```
  4. VM 端同步：在「本機終端機」執行 `make vm-deploy`（VM 容器 entrypoint 同樣自動從 `vertex-adc` 取 ADC）。
  5. **換免費帳號續用（試用額度到期時）**：用新的免費 Google 帳號建立／切換 GCP 專案，更新 `.env` 的 `GCP_PROJECT_ID`、`GCP_ACCOUNT`，**重做 `make vertex-auth`**（用新帳號登入 ADC），再 `make install` / `make deploy`。
  6. 重新跑 TC-09-05 的 ADC token `curl` 與 `make status`，確認新修訂上線且 aiplatform 回 200。
- **預計成果**：`vertex-adc` 出現新版本；runtime SA 取得 `secretmanager.secretAccessor`；deploy 後容器 entrypoint 自動取得 ADC，Cloud Run／VM 兩端皆以 Vertex 認證運作；模型呼叫回 200。
- **實際成果**：依賴外部設定（手動驗證）。此為破壞性／寫入流程，execJson 全程未執行任何寫入或變更（所有群組註明唯讀／stub），故無對應 actual。前置依賴：ADC 須登入正確的 owner 帳號，否則 TC-09-05 會回 403（已實測 ccie16595 帳號錯誤的 403）；切換到 Vertex AI 後，對話生成本身已實測可正常回繁中（見 TC-05-06 PASS）。
- **判定**：🖐️手動（依賴外部設定）
- **備註**：斷點提醒——(1) `make vertex-auth` 步驟 [1] 會開瀏覽器，務必選對 owner 帳號；選錯會在實打時回 `403 PERMISSION_DENIED on aiplatform.endpoints.predict`；(2) 因 entrypoint 啟動時自動從 Secret Manager 取 ADC，故只需確保 `vertex-adc` 已更新並重新部署，毋須像舊金鑰流程那樣三處手動同步；(3) 換免費帳號續用＝改 `.env` 帳號/專案後重做 `make vertex-auth`。權限軸線＝Secret Manager 寫入（`vertex-adc`）+ runtime SA `aiplatform.user` + Cloud Run/VM 部署。

---

### TC-09-07：GitHub push 流程——機密不入 git + PAT 認證（避免 `!` 前綴誤用）
- **對應 AC**：AC-11、AC-22、AC-25
- **前置作業**：
  - 本倉庫已設定 GitHub remote（非私有 repo），`.env` 與 `*-sa.json` 已列入 `.gitignore`。
  - 已備妥 GitHub PAT（Personal Access Token），具 `repo` 範圍。
  - 工作目錄為 repo 根。
- **測試步驟**：
  1. 在「本機終端機」先檢視待提交內容，**確認沒有機密檔被追蹤**（純指令，勿加 `!` 前綴）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && git status
     ```
     確認輸出中「不」出現 `.env` 或 `*-sa.json`。
  2. 在「本機終端機」push（PAT 認證：當提示 Username 輸入 GitHub 帳號、Password 貼上 PAT，或使用已快取的 credential helper）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && git push origin main
     ```
  3. **斷點防呆**：若你是從 Claude 對話框複製到含 `! git push ...` 的指令，貼進真實終端機前「務必刪掉開頭的 `! ` 與空白」；`!` 在 zsh／bash 會觸發歷史展開導致指令被改寫。
  4. push 後到 GitHub repo 網頁確認無 `.env` 或 `*-sa.json`。
- **預計成果**：`git push` 成功且不含任何機密檔；GitHub repo 無 `.env`／`*-sa.json`；gitleaks 掃描無洩漏。
- **實際成果**：「機密不入 git／gitleaks 無洩漏」部分＝✅PASS：execJson shell-suites `test_lint.sh` actual＝`19 passed, 0 failed`，內含「gitleaks 無洩漏」；`test_static.sh` actual＝`72 passed, 0 failed, 1 skipped`，含 ignore 一致性（`.gitignore` 涵蓋機密檔）。實際 `git push` 與 PAT 互動認證＝🖐️手動（依賴外部 GitHub 認證，非自動化範圍）。
- **判定**：✅PASS（gitleaks／ignore 一致性）；`git push`+PAT 🖐️手動
- **備註**：最大痛點防呆——`!` 前綴只在 Claude 對話框有效，貼進真實終端機前必刪。可逆性：push 前的 `git status` 為唯讀檢查，可安全反覆執行。權限軸線＝GitHub PAT。

---

### TC-09-08：維運指令參數防呆（缺 `KEY=` / 缺 `GCP_PROJECT_ID` / `!` 前綴解析）
- **對應 AC**：AC-25
- **前置作業**：
  - 工作目錄為 repo 根；本機可執行 `make`。
  - 此為負向／防呆案例，刻意以錯誤用法觸發 Makefile 的參數驗證。
- **測試步驟**：
  1. 在「本機終端機」故意「缺 `KEY=`」執行（直接把金鑰當位置參數貼上，純指令）：
     ```
     cd /Users/allenchen/project/demo/openclaw/repo && make secret-set-gemini AIzaSyXXXX
     ```
     預期被擋下並提示用 `KEY=value` 格式。
  2. 在「本機終端機」故意「缺 `GCP_PROJECT_ID`」執行 VM 部署，預期 `check-env` 擋下並印出缺項。
  3. 驗證 `!` 前綴解析：在「本機終端機」實際把 `! make help` 這種帶前綴字串貼入，觀察 shell 行為（zsh 多半報歷史展開錯誤），藉此確認「不該帶 `!` 進真實終端機」；正確做法是只貼 `make help`。
- **預計成果**：缺 `KEY=` 與缺 `GCP_PROJECT_ID` 皆被 fail-fast 擋下並給出明確錯誤訊息；`make help` 正常列出 >10 條指令（稽核 `ops-08`＝OK）。
- **實際成果**：✅PASS。execJson shell-suites `test_makefile.sh` actual＝`22 passed, 0 failed`，明列涵蓋 `check-env`、`gen-token 冪等`、`teardown 防呆`、`install fail-fast`、`VM 生命週期防呆`；`test_install.sh` 亦涵蓋「check-env 擋下／fail-fast」（actual＝`20 passed, 1 failed`，唯一失敗為 happy-path 順序斷言，與本防呆案例無關）。`make help` 指令列舉由 `test_docs.sh` actual＝`65 passed, 0 failed` 旁證（README／make target 章節齊全）。第 3 步 `!` 前綴實貼觀察＝🖐️手動。
- **判定**：✅PASS（參數防呆／fail-fast）；第 3 步 🖐️手動
- **備註**：呼應使用者最大痛點。`test_install.sh` 的唯一 FAIL（happy path `builds submit` 須排在 `add-iam-policy-binding` 之前的順序斷言，tests/test_install.sh:74）屬安裝編排順序問題，非本維運防呆領域，已在 TC-14／安裝領域追蹤。權限軸線＝本機 make（無線上副作用）。

---

## 本領域稽核對照（ops checks）

| check id | 說明 | 對應 TC | 本檔判定依據 |
|----------|------|---------|--------------|
| ops-01 | `make logs N=50` 首行非空 | TC-09-03 | 🖐️手動（execJson 無線上 logs 結果） |
| ops-02 | `make status` 含 clawdbot | TC-09-01 | ✅PASS（live-cloudrun make-status） |
| ops-03 | `make doctor` 健檢通過 | TC-09-01／05（健檢面） | 🖐️手動（execJson 無 doctor 線上結果） |
| ops-04 | `make min-instances N=1` | TC-09-01（MIN 旁證） | ✅PASS 旁證（make-status MIN=1） |
| ops-05 | `make vm-ssh` VM RUNNING | TC-09-04 | 🖐️手動（VM HTTPS 200 旁證 PASS） |
| ops-06 | `make vm-logs` 讀容器日誌 | TC-09-04 | 🖐️手動 |
| ops-07 | `make clean` 清測試容器 | （安裝領域，非本檔重點） | 未於本檔列為獨立 TC |
| ops-08 | `make help` >10 條指令 | TC-09-08 | ✅PASS 旁證（test_docs/help） |

---

## 本檔判定彙總

- 總計 test case：8 個（TC-09-01 ~ TC-09-08）。
- ✅PASS：4（TC-09-01、TC-09-02、TC-09-07、TC-09-08，後三者含「手動」子步驟但主判定為 PASS）。
- ❌FAIL：1（TC-09-05 Vertex ADC 帳號錯誤回 403 PERMISSION_DENIED on aiplatform.endpoints.predict；重做 `make vertex-auth` 選對 owner 帳號後可恢復）。
- 🖐️手動／依賴外部設定：3（TC-09-03、TC-09-04、TC-09-06）。
- ⏭️SKIP：0。
