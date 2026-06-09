# openclaw-Taiwan 驗收標準（Acceptance Criteria）

聚焦「小龍蝦（ClawdBot / OpenClaw）」的**功能行為**。每條 AC 以 Given/When/Then 描述，
並標註驗證方式：**dogfooding**（實際對話）、**自動化測試**（`tests/`）、**線上**（部署後）。

最後一次 dogfooding：2026-06-06，於 GCE VM（`clawdbot-vm`）以 `openclaw agent --agent main`
（`OPENCLAW_GATEWAY_URL=ws://127.0.0.1:8080` 經真實 gateway）實機對話驗證。

---

## A. 對話與模型

### AC-01 基本對話
- **Given** 已部署且 Vertex AI 模型認證正常（service account ADC，免 API 金鑰）
- **When** 使用者傳訊息
- **Then** 收到繁體中文、切題的回應，無 `turn failed` / 429
- **驗證**：✅ dogfood「現在幾點」「你叫什麼名字」皆正常回應；test_live 根頁 200

### AC-02 時間正確（台灣時區）
- **Given** `OPENCLAW_TIMEZONE=Asia/Taipei`（預設）+ 映像 `TZ=Asia/Taipei`
- **When** 問「現在台灣時間幾點」
- **Then** 回覆當下台灣時間（+08:00），非 UTC、非幻覺
- **驗證**：✅ dogfood 回「2026年6月6日晚上9點40分」（實際 CST）；test_config/integration 斷言 `userTimezone=Asia/Taipei`、`timeFormat=24`

### AC-03 模型可切換且配額穩定
- **Given** `OPENCLAW_MODEL`（現為 `google-vertex/gemini-2.5-flash`，Vertex AI / service account ADC 認證，免 API 金鑰）
- **When** 部署或覆寫模型
- **Then** Vertex GA 模型走 `aiplatform.googleapis.com`、吃 GCP 專案試用金，配額穩定不易 429；preview 版（gemini-3-flash-preview）已知配額極低
- **驗證**：✅ Vertex 已切 `google-vertex/gemini-2.5-flash`，Cloud Run/VM dogfood 正常；ADC token 直打 aiplatform endpoint=200
- **歷史**：先前用 AI Studio `google/gemini-2.5-flash` + `GEMINI_API_KEY`，因連帳單專案金鑰 429 / 免帳單金鑰被帳號層級軟封 403，已切換至 Vertex（見 [VERTEX-SETUP.md](VERTEX-SETUP.md)）

### AC-27 Vertex AI 模型認證
- **Given** `OPENCLAW_MODEL=google-vertex/gemini-2.5-flash` + 已執行 `make vertex-auth`（ADC 以 `authorized_user` 存入 Secret Manager `vertex-adc`；runtime SA 具 `roles/aiplatform.user` 與 `vertex-adc` 的 `roles/secretmanager.secretAccessor`）
- **When** 使用者對話
- **Then** entrypoint 自 Secret Manager 取出 ADC 寫到 `GOOGLE_APPLICATION_CREDENTIALS`，bot 經 Vertex 正常回覆，無 429 / 403
- **驗證**：✅ dogfood 實測通過——問身分回「我是一個由 Google 訓練的語言模型」；負向：ADC 帳號錯誤（非專案 owner / 無 aiplatform 權限）→ `403 PERMISSION_DENIED on aiplatform.endpoints.predict`，重做 `make vertex-auth` 選對帳號後恢復
- **對應測試**：[TC-27](test-cases/TC-27.md)

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
- **Given** Vertex AI 專案有圖片模型配額
- **When** 請 bot 畫圖
- **Then** 產生圖片並以 `MEDIA:` 直接顯示（需 `AGENTS.md`）
- **驗證**：⚠️ 工具已正確串接並被呼叫（活動顯示 image_generate）；實際出圖**取決於 Vertex AI 專案的圖片模型配額/試用金**（額度不足時回 429）。屬配額，非框架問題

---

## D. 存取與安全

### AC-09 公開存取 + token 保護
- **When** 存取服務
- **Then** 根頁 `/`=200；受保護端點無 token=401、正確 `Authorization: Bearer`=200
- **驗證**：✅ test_live + doctor：200 / 401 / 200

### AC-10 Dashboard 帶令牌存取
- **Given** `make dashboard-url` 取得帶 token 網址（`#token=...` fragment）；或 `make dashboard-launcher` 產生本機 `clawdbot-dashboard.html`
- **When** 雙擊 `clawdbot-dashboard.html` 直接連入；或將網址用無痕視窗開啟；或在 control UI 的 token 欄位貼上令牌
- **Then** control UI 連線成功（device auth 已豁免），token 經 `#token` fragment / 欄位 / 啟動檔任一方式帶入皆通過驗證
- **驗證**：✅ 使用者實測——`dashboard-launcher` 產生的 html 雙擊即連、token 貼欄位亦可；HTTPS secure context 需 `make vm-https`（VM）

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

### AC-14 一鍵安裝（完整持久版）
- **Given** 已填 `.env` 必填項，且已執行 `make vertex-auth`（ADC 已存入 `vertex-adc`）
- **When** `make install`
- **Then** 一鍵完整完成：啟用 API / 建映像庫 / Vertex 模型認證偵測（`[3/8]` 偵測 `vertex-adc` 已存在則繼續，未做則印出完整步驟並擋下，不中途無故中斷）/ 建置部署 Cloud Run / IAM / 公開存取 / 同時部署持久 GCE VM（持久磁碟）/ 啟用 HTTPS（vm-https）/ 產生帶令牌的 Dashboard 啟動檔；服務 Ready
- **驗證**：✅ test_install（情境 stub，含未做 vertex-auth 擋下情境）；實機 Cloud Run + VM（含持久磁碟 + HTTPS + Dashboard launcher）已部署 Ready

### AC-15 重裝 / 移除 / 健檢
- **When** `make reinstall` / `uninstall` / `teardown-all CONFIRM=yes` / `doctor` / `vm-*`
- **Then** 各自正確執行、危險操作有 CONFIRM 防呆
- **驗證**：✅ test_makefile / test_vm 防呆與冪等；`make doctor` 線上全過

---

## G. 金鑰、配額與計費（稽核新增）

### AC-16 模型供應方案陷阱（AI Studio 金鑰 → Vertex AI）
- **Given** 現以 **Vertex AI（`google-vertex/gemini-2.5-flash`）+ service account ADC** 供應模型，吃 GCP 專案試用金（免 API 金鑰）
- **When** 部署後使用者嘗試對話或生成圖片
- **Then** Vertex 走 `aiplatform.googleapis.com`、計入專案試用金，正常運作；試用金到期則換新免費 Google 帳號 / 專案重做 `make vertex-auth`（見 [VERTEX-SETUP.md](VERTEX-SETUP.md) §4）
- **驗證**：dogfooding——Vertex 部署後對話正常；`doctor` 檢查 `vertex-adc` secret 存在、runtime SA 具 `aiplatform.user`/`secretAccessor`、ADC token 打 aiplatform endpoint=200
- **歷史陷阱（已棄用 AI Studio 金鑰）**：先前用 `GEMINI_API_KEY`（AI Studio）時——連過帳單的專案即使關閉計費也不再有免費額度，金鑰回 429 `RESOURCE_EXHAUSTED`「prepayment credits depleted」；無帳單專案的免費金鑰則被 Google 帳號層級軟封 403 `project denied access`。此即切換至 Vertex 的主因
- **對應測試**：[TC-16](test-cases/TC-16.md)

### AC-22 GitHub push 與認證輪替流程驗證
- **Given** 本倉庫已推送至 GitHub（非私有），`.env`、`*-sa.json` 與 ADC 憑證檔已加入 `.gitignore`
- **When** 執行 `git status` 後 `git push`；或 Vertex ADC 需輪替（試用到期 / 換帳號）時重跑 `make vertex-auth`（重新登入 ADC 並寫入 Secret Manager `vertex-adc` 新版本）
- **Then** `git push` 不含 `.env`、機密檔案或 ADC 憑證（gitleaks 掃描無警告）；ADC 輪替後既有 Cloud Run 服務在下次容器啟動 / 重新 deploy 時才從 Secret Manager 取到新 ADC（entrypoint 取最新版本），現存修訂不會自動套用新 secret 版本
- **驗證**：`git push` 後檢查 GitHub repo 無 `.env` / ADC 檔；test_static 與 test_lint 中 gitleaks 無洩漏；重跑 `make vertex-auth` 後驗證 `gcloud secrets versions list vertex-adc` 顯示新版本；驗證重新 deploy 後容器取用新 ADC
- **理由**：source control 與認證輪替的交互易出錯（如不小心 commit `.env` / ADC、現存修訂因未重啟而續用舊 ADC）。需明確驗證流程與防呆機制有效
- **對應測試**：[TC-22](test-cases/TC-22.md)

---

## H. 成本控制與帳單管理（稽核新增）

### AC-18 靜態 IP 與持久磁碟的閒置計費驗證
- **Given** GCE VM 已部署（`make vm-deploy`），之後執行 `make vm-delete`（刪 VM 但保留磁碟與 IP）
- **When** VM 刪除後，檢查 GCP 計費與資源清單（`gcloud compute addresses list`、`gcloud compute disks list`）
- **Then** 靜態 IP（`<VM>-ip`）與持久磁碟（`<VM>-data`）仍存在並持續計費（IP 約 US$1.5/月閒置費、磁碟按 GB/月）；`make vm-teardown CONFIRM=yes` 才能完全清除計費
- **驗證**：GCP Console 或 gcloud 查詢——`gcloud compute addresses list --filter name=clawdbot-vm-ip`；`gcloud compute disks list --filter name=clawdbot-vm-data`；對比 `make vm-delete` vs `vm-teardown` 後的清單差異
- **理由**：使用者可能誤認 `make vm-delete` 會完全移除所有資源，導致月底驚訝於仍有計費。需明確文件與提示警告，並可在 `doctor` 檢查中增列「孤立 IP/磁碟」的警告
- **對應測試**：[TC-18](test-cases/TC-18.md)

### AC-19 計費帳戶關閉的連鎖反應驗證
- **Given** GCP 專案的計費帳戶已關閉或停用（`gcloud billing projects unlink PROJECT_ID`）
- **When** 嘗試執行 `make deploy` 或訪問已部署的 Cloud Run 服務
- **Then** Cloud Build 失敗（無法拉 base image），或 Cloud Run 服務因計費中斷被暫停；若用 Secret Manager 存 Gemini 金鑰，Secret 仍可讀取（若 service account 有權限）但 Cloud Run 服務因計費停用而 503；新的 API 呼叫（如 Image 生成）因配額用盡而 429
- **驗證**：測試情境——intentionally unlink billing 後重新部署→驗證 build 或 deploy 失敗；重新 link billing→驗證恢復；檢查日誌 error messages 中的計費相關提示
- **理由**：使用者或組織可能因策略原因關閉計費，需理解此舉對已部署服務的影響（不只是新建置失敗，還包括現存服務停用）。`doctor` 應增檢查「計費帳戶連結狀態」
- **對應測試**：[TC-19](test-cases/TC-19.md)

---

## I. 部署方式與連線差異（稽核新增）

### AC-17 Cloud Run 與 VM 的 Dashboard 連線差異驗證
- **Given** 分別部署 Cloud Run（`make install`）與 GCE VM（`make vm-deploy`）
- **When** 使用 Dashboard URL（`make dashboard-url` / `make vm-dashboard`）在無痕瀏覽器開啟 control UI
- **Then** Cloud Run：`https://<URL>/chat?session=main#token=...` 連線成功，Control UI 顯示，token 驗證通過；VM（HTTP）：`http://<IP>:8080/chat` 亦連線成功；VM（HTTPS 後）：`https://<domain>.nip.io/chat` 連線成功，自簽憑證警告後可進入
- **驗證**：實機驗證（Cloud Run + VM HTTP + VM HTTPS），檢查 browser console 無 CORS/origin 錯誤，control UI 加載元件無白屏
- **理由**：Cloud Run 與 VM 的 URL scheme（https vs http）、domain（run.app vs nip.io）、及 secure context 要求不同（HTTPS webhooks 需 vm-https），需明確驗證各場景連線邏輯正確
- **對應測試**：[TC-17](test-cases/TC-17.md)

---

## J. GCE VM HTTPS（稽核新增）

### AC-20 Caddy `--restart=always` 隨 VM 重啟驗證
- **Given** `make vm-https` 已執行，Caddy 容器以 `--restart=always` 啟動（`deploy/vm-https.sh` 第 52 行）
- **When** GCE VM 發生重啟（手動重啟、OS patch、斷電恢復等），或 VM console 執行 `sudo reboot`
- **Then** Caddy 容器自動跟隨重啟並在 VM 恢復後自動啟動，HTTPS 反代繼續可用；`curl https://<domain>.nip.io` 返回 200 且有有效憑證（不是重啟前的過期憑證）
- **驗證**：實機——`make vm-https` 後驗證 `https://<domain>/chat` 可用→手動 `make vm-ssh` 進 VM 執行 `sudo reboot`→等待 VM 重啟（`gcloud compute instances describe` 顯示 RUNNING）→再驗證 `https://<domain>/chat` 仍可用；檢查容器日誌 `sudo docker ps` 確認 caddy 容器 status=Up
- **理由**：`--restart=always` 是 docker 層面的策略，隨 daemon 恢復。需驗證 Container-Optimized OS 的 docker daemon 重啟後確實重拉此容器，否則 VM 重啟後 HTTPS 無法恢復
- **對應測試**：[TC-20](test-cases/TC-20.md)

### AC-26 vm-https 的步驟順序與狀態管理驗證
- **Given** GCE VM 已部署（`make vm-deploy`），現需啟用 HTTPS（`make vm-https`）
- **When** 嚴格按步驟執行：`make vm-deploy` → `make vm-https`（中間不插入其他命令；vm-https 內部會自行 update-container 設定 PUBLIC_URL）
- **Then** vm-https 能正確執行，自動 update-container 更新 `OPENCLAW_PUBLIC_URL` 為 https 版本，等待 VM 重啟完成，啟動 Caddy，驗證 HTTPS 可達；若在 vm-https 執行中途斷網或出錯，重新執行 vm-https 應冪等恢復，不會重複啟動 Caddy 或重複 update-container
- **驗證**：實機——clean start `make vm-deploy` → `make vm-https`，逐步檢查：(1) VM 重啟並回到 RUNNING；(2) clawdbot 容器的環境變數 `OPENCLAW_PUBLIC_URL` 已改為 https；(3) caddy 容器成功啟動（`docker ps` 查看）；(4) `https://<domain>/chat` 返回 200；故意中斷 vm-https（Ctrl-C）後重新執行，驗證冪等性
- **理由**：背景資訊指出「缺步驟/順序錯（如 vm-https 須先 update-container 再起 Caddy）」是已知痛點。vm-https 腳本設計已考慮此點（先 update-container 再起 Caddy），需驗證順序邏輯與冪等性確實無誤
- **對應測試**：[TC-26](test-cases/TC-26.md)

---

## K. 安全與存取控制（稽核新增）

### AC-21 IAM 分層授權驗證（grant-build-roles vs allUsers）
- **Given** 新 GCP 專案，執行 `make bootstrap`（包含 grant-build-roles）後執行 `make deploy` 與 `make allow-public`
- **When** 檢查 Cloud Run 服務的 IAM 綁定（`gcloud run services get-iam-policy ...`）與 Cloud Build service account 的角色
- **Then** Cloud Build service account（`<projectNumber>-compute@developer.gserviceaccount.com`）擁有 `roles/run.admin` + `roles/iam.serviceAccountUser`（grant-build-roles 授予），允許其建置並部署；allUsers 擁有 `roles/run.invoker`（allow-public 授予），允許公開存取；其他非 allUsers principal 無額外權限
- **驗證**：`gcloud run services get-iam-policy $SERVICE_NAME --region=$GCP_REGION` 列出所有綁定，確認 Cloud Build SA 有 run.admin，allUsers 有 run.invoker；測試——未認證的 curl 應返回 200；`gcloud run services update --no-allow-unauthenticated` 後應返回 403
- **理由**：多帳戶或多環境部署時，IAM 分層（build vs invoke）容易混淆。需明確驗證各層角色正確無洩漏，尤其是 grant-build-roles 是否被正確應用且不被意外覆蓋
- **對應測試**：[TC-21](test-cases/TC-21.md)

---

## L. 維運工具與品質保證（稽核新增）

### AC-23 doctor 健檢覆蓋面驗證
- **Given** 執行 `make doctor`（或直接 `bash scripts/doctor.sh`）
- **When** 各檢查項目逐一執行（本機工具、`.env` 設定、GCP 認證、API 啟用、映像庫、金鑰、服務狀態、token 驗證）
- **Then** 輸出列出至少 12+ 項檢查（工具、`.env`、GCP、計費、API、AR、金鑰、服務 URL、Ready 狀態、根頁、token，及現有版本可選的 HTTPS 狀態、靜態 IP、持久磁碟、webhook 配置），各項 Pass/Warn/Fail；全部 Pass 時印「全部檢查通過」；任何 Fail 時印「N 項失敗」與建議修正指令
- **驗證**：執行 `make doctor` 後計數 checkmark 數量，與 `scripts/doctor.sh` 實現的檢查項對應；故意缺失設定（如無 `.env`、無 `GCP_PROJECT_ID`、API 未啟用）後重新運行，驗證檢查能正確偵測並給出建議
- **理由**：doctor 是首道防線，需涵蓋最常見的安裝/部署失敗根因（Vertex ADC / `vertex-adc` secret / SA aiplatform 權限、計費、IAM、DNS、HTTPS）。現有 doctor 覆蓋基本項，需增加 Vertex 認證檢查（secret 存在、SA `aiplatform.user`/`secretAccessor`、ADC token 打 aiplatform=200）、計費帳號、靜態 IP 閒置警告等
- **對應測試**：[TC-23](test-cases/TC-23.md)

### AC-24 Makefile lint-trivy 指令修復
- **Given** 執行 `make build-local` 後執行 `make lint-trivy`
- **When** trivy 掃描本機建置的映像（`$(LOCAL_NAME)` = `clawdbot-local`）
- **Then** trivy 正確掃描 `clawdbot-local` 映像，輸出 HIGH/CRITICAL 漏洞清單（如有），或「無漏洞」；指令結束碼 0 表成功掃描
- **驗證**：執行 `make build-local` 後 `make lint-trivy`，驗證指令不報「映像不存在」或「invalid image reference」；手動執行 `docker images` 確認 `clawdbot-local` 存在後重試；檢查 Makefile 第 285 行 `trivy image` 指令包含正確的 `$(LOCAL_NAME)` 變數（目前被污染為數字 `905368131` 等）
- **理由**：背景資訊指出第 285 行被汙染（`trivy image ... 905368131 ...` 取代了 `$(LOCAL_NAME)`），導致掃描目標錯誤。需修復此 bug 並驗證 lint-trivy 正常運作
- **對應測試**：[TC-24](test-cases/TC-24.md)

---

## M. 使用者體驗與防呆（稽核新增）

### AC-25 按鍵與執行方式防呆（CLI 前綴處理）
- **Given** 部署完成，使用者參考 README 並嘗試執行部署或管理指令
- **When** 使用者在真實終端機或 Shell 中執行指令，或貼上含有特殊字元/前綴的指令
- **Then** 指令正確執行，不會因「按鍵格式錯誤」（如不小心把 Claude 回覆的 `!` 邏輯否定操作符視為終端機指令、或多餘空白/引號）而中斷；Makefile 與 shell scripts 的參數驗證應提供明確錯誤訊息（如「key: not found」→提示「請用 KEY=value 格式」）
- **驗證**：測試情境——(1) 未做 `make vertex-auth` 就 `make install`→驗證 `[3/8] 模型認證` 印出完整步驟並擋下（非中途無故失敗）；(2) 執行 `make vm-deploy` 缺 `GCP_PROJECT_ID`→驗證輸出「GCP_PROJECT_ID:?」；(3) 貼上包含行前綴「`! make deploy`」的指令→驗證 shell 正確解析（無邏輯否定副作用）；review README 和 cli 範例的清晰度
- **理由**：背景資訊指出已知痛點：「流程操作到一半因按鍵/執行方式不對而中斷」。防呆設計應確保參數驗證、清晰的 usage 提示，及文檔範例的準確性
- **對應測試**：[TC-25](test-cases/TC-25.md)

---

## 驗收彙整

| 區塊 | AC | 自動化 | dogfood/實機 |
|------|----|--------|--------------|
| 對話與模型 | AC-01~03 | ✅ | ✅ |
| Vertex AI 模型認證 | AC-27 | 部分 | ✅ 實測通過 |
| 記憶與身分 | AC-04~06 | ✅ | ✅ |
| 工具/功能 | AC-07 | ✅ | ✅ |
|  | AC-08 圖片 | 部分 | ⚠️ 配額依賴 |
| 存取與安全 | AC-09（token）、AC-10（Dashboard 帶令牌）、AC-11 | ✅ | ✅ |
| 頻道 | AC-12~13 | 設定層 | ☐ 手動 |
| 部署維運 | AC-14（install 完整持久版）、AC-15 | ✅ | ✅ |
| 模型供應/輪替 | AC-16（Vertex 陷阱）、AC-22（ADC 輪替） | 部分 | ⚠️ 試用金依賴 |
| 成本控制與帳單 | AC-18~19 | gcloud 查詢 | ⚠️ 需實機驗證 |
| 部署方式差異 | AC-17 | — | ☐ 實機（CR+VM HTTP/HTTPS） |
| GCE VM HTTPS | AC-20、AC-26 | — | ☐ 實機（reboot/冪等） |
| 安全與存取控制 | AC-21 | gcloud 查詢 | ☐ 實機 IAM |
| 維運工具/品保 | AC-23~24 | ✅（lint/doctor） | ✅ |
| 使用者體驗防呆 | AC-25 | ✅（參數驗證） | ✅ |

> 完整自動化矩陣見 [TEST-PLAN.md](TEST-PLAN.md)；10 個測試套件全綠。
> 各 AC 的正規測試案例（步驟、預期結果、實測記錄）見 [docs/test-cases/](test-cases/)，對應 `TC-01`~`TC-27`。
