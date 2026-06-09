# TC-04：不同權限 User 的存取驗證測試案例

本文件涵蓋 openclaw（小龍蝦／ClawdBot）部署框架在「存取權限」面向的正規測試案例，分為三條權限軸線：

1. **HTTP 層級**：匿名（無 token）一律 401、持正確 gateway Bearer token 回 200、loopback／本機開發來源（localhost:8080、127.0.0.1:8080）允許；以及前端 `#token` fragment 機制如何影響 `/chat` 介面初始化。
2. **GCP IAM 層級**：Cloud Run 對 `allUsers` 授予 `roles/run.invoker`（公開可呼叫，授權交由應用層 token 把關）、Cloud Build／compute 預設 SA 具備部署所需角色（`run.admin`、`iam.serviceAccountUser`）。
3. **機密與設定保護**：service account 金鑰檔（`*-sa.json`）不入 git、`GCP_ACCOUNT` 正確帶入 gcloud 指令。

所有線上檢查均為唯讀（curl 狀態碼、`gcloud ... get-iam-policy`），未對線上資源做任何寫入或變更。

> **重要斷點提醒（使用者最大痛點）**
> - Claude 對話框中以 `!` 前綴執行 bash（如 `!curl ...`）與「真實終端機」不同。**請勿把帶 `!` 的指令貼進真實終端機**，在 zsh／bash 中 `!` 會被當成歷史展開或邏輯否定，導致指令被誤解而中斷。下列「本機終端機」步驟一律是「不含 `!` 前綴」的純指令。
> - Cloud Run 與 VM 兩端的 `control-ui-config.json` 授權行為完全一致：帶 token=200、不帶=401。差異不在伺服器，而在於你開的網址是否攜帶 `#token=...` fragment（由前端 JS 取出後改以 `Authorization: Bearer` 帶入 API）。沒有 fragment 的純 `/chat` 網址，HTML shell 雖回 200，但前端拿不到 config 而顯示「需要驗證」。

---

### TC-04-01：HTTP 層 token 鑑權——帶正確 Bearer token 回 200
- **對應 AC**：AC-auth-01、AC-auth-token-positive
- **前置作業**：
  - Cloud Run 服務 `clawdbot` 已部署且 ready（標準 URL：`https://clawdbot-475727900579.asia-east1.run.app`）。
  - 已知 gateway token：``。
  - 本機已安裝 `curl`，可連外。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  2. 觀察輸出的 HTTP 狀態碼。
- **預計成果**：輸出 `200`，代表受保護的 config API 在帶正確 Bearer token 時放行。
- **實際成果**：`200`（execJson live-vm-access `cloudrun-config-with-token` 與 live-cloudrun `cloudrun-config-with-token` 皆 actual=200，status=pass）。
- **判定**：✅PASS
- **備註**：唯讀，可逆（不變更任何資源）。權限軸線＝HTTP token 正向。token 為敏感值，貼指令時注意不要外流到共享畫面。

---

### TC-04-02：HTTP 層 token 鑑權——匿名（無 token）回 401
- **對應 AC**：AC-auth-01、AC-auth-anon-deny
- **前置作業**：
  - 同 TC-04-01 的 Cloud Run 服務與本機 `curl`。
  - 本次刻意「不」帶 `Authorization` 標頭，模擬匿名／無權限 user。
- **測試步驟**：
  1. 在「本機終端機」執行（單行，勿加 `!` 前綴）：
     ```
     curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json
     ```
  2. 觀察輸出的 HTTP 狀態碼。
- **預計成果**：輸出 `401`，代表匿名存取受保護 config API 被拒。
- **實際成果**：`401`（execJson live-cloudrun `cloudrun-config-no-token` 與 live-vm-access `cloudrun-config-without-token` 皆 actual=401，status=pass）。
- **判定**：✅PASS
- **備註**：負向案例，驗證授權在 HTTP 層強制。權限軸線＝HTTP 匿名拒絕。config 回應 body 未對外暴露 `auth.mode`／token 欄位，狀態碼即唯一可佐證的授權證據。

---

### TC-04-03：VM 端（Caddy + nip.io HTTPS）token 鑑權與憑證有效性
- **對應 AC**：AC-auth-01、AC-auth-vm-parity、AC-tls-valid
- **前置作業**：
  - GCE VM `clawdbot-vm` 已透過 Caddy + nip.io 提供 HTTPS：`https://34-81-189-176.nip.io`。
  - VM 端 `control-ui-config.json` 與 Cloud Run 共用同一 gateway token。
  - 本機 `curl`，可連外。
- **測試步驟**：
  1. 在「本機終端機」驗證 HTTPS 根路徑可達且憑證可信（**不加 `-k`**，勿加 `!` 前綴）：
     ```
     curl -sS -o /dev/null -w 'HTTP:%{http_code} ssl_verify_result:%{ssl_verify_result}' --max-time 15 https://34-81-189-176.nip.io/
     ```
  2. 在「本機終端機」驗證帶 token 的 config API 回 200：
     ```
     curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 -H 'Authorization: Bearer ' https://34-81-189-176.nip.io/__openclaw/control-ui-config.json
     ```
  3. 在「本機終端機」驗證不帶 token 的 config API 回 401：
     ```
     curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 https://34-81-189-176.nip.io/__openclaw/control-ui-config.json
     ```
- **預計成果**：步驟1 回 `HTTP:200 ssl_verify_result:0`（憑證受信任，無需 `-k`）；步驟2 回 `HTTP:200`；步驟3 回 `HTTP:401`。VM 與 Cloud Run 授權行為一致。
- **實際成果**：步驟1＝`HTTP:200 ssl_verify_result:0`（`vm-https-cert-valid` status=pass，Caddy+nip.io 自動憑證受信任）；步驟2＝`HTTP:200`（`vm-config-with-token` status=pass）；步驟3＝`HTTP:401`（`vm-config-without-token` status=pass）。
- **判定**：✅PASS
- **備註**：VM 端授權與 Cloud Run 完全一致。斷點提醒：操作 vm-https 流程時須「先 `update-container` 再起 Caddy」，順序錯會導致憑證／反向代理起不來。唯讀，可逆。

---

### TC-04-04：痛點重現——`/chat` 無 `#token` fragment 時前端要求驗證
- **對應 AC**：AC-auth-frontend-fragment、AC-painpoint-chat-url
- **前置作業**：
  - Cloud Run 與 VM 兩端 `/chat?session=main` 頁面均可達。
  - 一個「無痕瀏覽器」視窗（避免既有快取／token）。
  - 本機 `curl` 作為狀態碼佐證。
- **測試步驟**：
  1. 在「無痕瀏覽器」開啟不含 fragment 的網址：`https://clawdbot-475727900579.asia-east1.run.app/chat?session=main`，觀察頁面是否顯示「需要驗證」。
  2. 在「本機終端機」以 curl 佐證 HTML shell 本身可達（單行，勿加 `!` 前綴）：
     ```
     curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 'https://clawdbot-475727900579.asia-east1.run.app/chat?session=main'
     ```
  3. 在「無痕瀏覽器」改開帶 fragment 的 VM 網址：`https://34-81-189-176.nip.io/chat?session=main#token=`，觀察 UI 是否正常初始化。
- **預計成果**：步驟1 頁面雖載入（HTML 200）但因前端呼叫 config API 無 token 得 401，顯示「需要驗證」；步驟2 curl 回 `HTTP:200`（HTML shell 可下載）；步驟3 帶 `#token` 時前端以 Bearer 取得 config 200，UI 正常。
- **實際成果**：步驟2＝`HTTP:200`（`painpoint-cloudrun-chat-no-token` status=pass，佐證同端 config API 不帶 token 回 401、帶回 200，故無 `#token` 網址前端拿不到設定而要求驗證）；步驟3 對照組 VM `/chat?session=main` 頁面＝`HTTP:200`（`painpoint-vm-chat-token-fragment` status=pass，差異在於網址是否攜帶 token fragment 而非伺服器授權邏輯）。瀏覽器內 UI 顯示文字屬手動目視確認。
- **判定**：✅PASS（curl 狀態碼佐證部分；瀏覽器 UI 文字為 🖐️手動目視）
- **備註**：這是使用者最大痛點之一——「網址要帶 `#token` fragment 才能用」。fragment（`#` 之後）不會送到伺服器，純由前端 JS 讀取後改以 `Authorization: Bearer` 帶入 API。請在「無痕瀏覽器」完整貼上含 `#token=...` 的網址，勿在終端機把網址當指令執行。

---

### TC-04-05：GCP IAM——Cloud Run `allUsers` 具 `roles/run.invoker`（公開可呼叫）
- **對應 AC**：AC-auth-02、AC-iam-run-invoker
- **前置作業**：
  - 已 `gcloud auth login` 並設定專案 `project-6c870217-2205-4b1b-a3f`（即 `475727900579`）。
  - 具讀取 IAM policy 的權限。
- **測試步驟**：
  1. 在「本機終端機」執行（勿加 `!` 前綴）：
     ```
     gcloud run services get-iam-policy clawdbot --region=asia-east1 --format='value(bindings[*].members[*])'
     ```
     或完整 policy：
     ```
     gcloud run services get-iam-policy clawdbot --region=asia-east1 --project=project-6c870217-2205-4b1b-a3f
     ```
  2. 確認 bindings 中含 `members: allUsers` 且 `role: roles/run.invoker`。
- **預計成果**：輸出含 `allUsers` 與 `roles/run.invoker`，代表服務在網路層公開可呼叫（授權改由應用層 token 把關）。
- **實際成果**：通過。`bindings: - members: - allUsers, role: roles/run.invoker, etag: BwZTymAVsv4=, version: 1`（execJson model-iam `model-iam-run-invoker` actual 確認 allUsers 具 roles/run.invoker，status=pass）。
- **判定**：✅PASS
- **備註**：權限軸線＝IAM 公開呼叫。設計上「網路公開＋應用層 token」分工：網路層放行任何人到達，真正的存取控制由 TC-04-01/02 的 Bearer token 完成。唯讀。

---

### TC-04-06：GCP IAM——compute 預設 SA 具部署所需角色（`run.admin` + `iam.serviceAccountUser`）
- **對應 AC**：AC-iam-deploy-sa、AC-cloudbuild-sa
- **前置作業**：
  - 已 `gcloud auth login` 並設定專案 `project-6c870217-2205-4b1b-a3f`。
  - compute 預設 SA：`475727900579-compute@developer.gserviceaccount.com`。
- **測試步驟**：
  1. 在「本機終端機」執行（勿加 `!` 前綴）：
     ```
     gcloud projects get-iam-policy project-6c870217-2205-4b1b-a3f
     ```
  2. 確認 `475727900579-compute@developer.gserviceaccount.com` 同時出現在 `roles/run.admin` 與 `roles/iam.serviceAccountUser` 兩個 binding。
- **預計成果**：compute 預設 SA 同時擁有 `roles/run.admin` 與 `roles/iam.serviceAccountUser`（並具 `cloudbuild.builds.builder`），符合 Cloud Build → Cloud Run 部署所需權限。
- **實際成果**：通過。compute 預設 SA `475727900579-compute@developer.gserviceaccount.com` 出現在 `roles/run.admin` 及 `roles/iam.serviceAccountUser` 兩個 binding，並同時持有 `cloudbuild.builds.builder`（execJson model-iam `model-iam-compute-sa-roles` status=pass）。
- **判定**：✅PASS
- **備註**：權限軸線＝部署 SA。若缺 `iam.serviceAccountUser`，Cloud Build 部署 Cloud Run 會在「act as service account」階段失敗。唯讀。

---

### TC-04-07：機密保護——service account 金鑰檔不入 git（`.gitignore` 含 `*-sa.json`）
- **對應 AC**：AC-auth-06、AC-secret-no-leak
- **前置作業**：
  - 位於倉庫根目錄 `/Users/allenchen/project/demo/openclaw/repo`。
- **測試步驟**：
  1. 在「本機終端機」執行（勿加 `!` 前綴）：
     ```
     grep -q '\*-sa.json' /Users/allenchen/project/demo/openclaw/repo/.gitignore && echo OK || echo FAIL
     ```
- **預計成果**：輸出 `OK`，代表 `.gitignore` 已忽略 SA 金鑰檔樣式，防止金鑰外洩進版控。
- **實際成果**：手動／靜態驗證涵蓋。execJson 無此單一 check 的獨立 actual，但 shell-suites `test_lint.sh`（19 passed，gitleaks 無洩漏）與 `test_static.sh`（72 passed，含 ignore 一致性檢查）整體通過，間接佐證機密未外洩、ignore 規則一致。判定以此為據。
- **判定**：🖐️手動（依賴靜態/lint 套件間接佐證；建議補一條對應 `auth-06` 的明確自動斷言）
- **備註**：權限軸線＝機密保護。gitleaks 已實測無洩漏（`test_lint.sh` 全綠）。可在 CI 加入此 grep 斷言將其轉為 ✅PASS。唯讀。

---

### TC-04-08：設定正確性——`GCP_ACCOUNT` 正確帶入 gcloud 指令
- **對應 AC**：AC-auth-05、AC-config-account
- **前置作業**：
  - 位於倉庫根目錄 `/Users/allenchen/project/demo/openclaw/repo`，存在 `Makefile`。
- **測試步驟**：
  1. 在「本機終端機」執行（勿加 `!` 前綴）：
     ```
     grep -q 'GCP_ACCOUNT' /Users/allenchen/project/demo/openclaw/repo/Makefile && echo OK || echo FAIL
     ```
- **預計成果**：輸出 `OK`，代表 Makefile 使用 `GCP_ACCOUNT` 變數帶入 gcloud（避免用到非預期帳號）。
- **實際成果**：手動／靜態驗證涵蓋。execJson 無此單一 check 的獨立 actual，但 shell-suites `test_makefile.sh`（22 passed，含 check-env）與 `test_static.sh`（72 passed）整體通過，間接佐證 Makefile 結構與環境變數檢查正常。判定以此為據。
- **判定**：🖐️手動（依賴 Makefile/static 套件間接佐證；建議補一條對應 `auth-05` 的明確自動斷言）
- **備註**：權限軸線＝帳號正確性。已知 gotcha：Makefile 第 285 行 `lint-trivy` 指令被汙染（`trivy image ... 905368131 ...` 取代了 `$(LOCAL_NAME)`），雖不直接影響 `GCP_ACCOUNT`，但驗證 Makefile 時請一併留意該行。唯讀。

---

### TC-04-09：HTTP 層——允許的來源（allowedOrigins）含 Cloud Run URL 與本機 loopback
- **對應 AC**：AC-auth-03、AC-auth-04、AC-cors-origins
- **前置作業**：
  - Cloud Run 服務已部署，持有 gateway token。
  - 本機 `curl`。
- **測試步驟**：
  1. 在「本機終端機」驗證 allowedOrigins 含 Cloud Run 實際 URL（單行，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json | grep -o '"allowedOrigins":\[[^]]*\]' | grep -q 'clawdbot.*run.app' && echo OK || echo FAIL
     ```
  2. 在「本機終端機」驗證 allowedOrigins 含本機 loopback（localhost:8080）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json | grep -q 'localhost:8080' && echo OK || echo FAIL
     ```
- **預計成果**：兩步驟皆輸出 `OK`——allowedOrigins 同時涵蓋 Cloud Run 線上 URL 與本機開發 loopback（localhost:8080／127.0.0.1:8080）。
- **實際成果**：依賴外部設定／間接佐證。execJson 未針對 `auth-03`／`auth-04`（allowedOrigins 內容）提供獨立 live actual——且 live-vm-access 註記「config 回應 body 未對外暴露 auth.mode/token 等欄位」，allowedOrigins 是否於 body 可見需以實際回應確認。整合測試 `test_integration.sh`（21 passed）有驗證「容器內 config token 正確、allowedOrigins 含公開 URL」，間接佐證 loopback 與公開 URL 設定存在。判定以此為據。
- **判定**：🖐️手動（依賴外部設定：需以線上實際 config body 確認；整合測試已間接佐證 allowedOrigins 含公開 URL 與本機來源）
- **備註**：權限軸線＝CORS 來源白名單。本機開發（localhost:8080／127.0.0.1:8080）支持是讓 loopback 流量可初始化 UI 的關鍵；缺它會在本地開發時被 CORS 擋下。唯讀。
