# TC-01 Cloud Run 部署與一鍵安裝 測試案例

本檔涵蓋 openclaw（小龍蝦／ClawdBot）部署框架中「Cloud Run 部署與一鍵安裝」領域的正規測試案例。範圍為 `make bootstrap / install / install-cloudrun / deploy / refresh-url / allow-public / grant-build-roles` 的完整流程與**步驟順序**。

此領域的核心鏈路（見 `Makefile` install target）已自舊版「6 步 Cloud Run-only」升級為**「8 步完整持久版」**，依序為：
`[1/8] gen-token → [2/8] bootstrap（enable-apis 含 aiplatform/compute API + create-repo + grant-build-roles，runtime SA 授 roles/aiplatform.user）→ [3/8] 模型認證（Vertex 偵測 vertex-adc，未做 make vertex-auth 會印完整步驟並擋下）→ [4/8] deploy（builds submit + 自動 allow-public）→ [5/8] refresh-url → [6/8] GCE VM 部署（vm-deploy）→ [7/8] vm-https（Caddy 簽 nip.io 憑證）→ [8/8] doctor + 產生帶令牌的 Dashboard 啟動檔（launcher）`。
其中 `deploy` 內部會在 `builds submit` 完成後自動呼叫 `allow-public`（Makefile 第 98 行），因為 Cloud Build 的 `--allow-unauthenticated` 常失效，需另以 `add-iam-policy-binding allUsers→run.invoker` 補上。
另提供 `make install-cloudrun`（只裝 Cloud Run，即原 6 步流程：token → bootstrap → 模型認證 → deploy → refresh-url → doctor，不含 VM／vm-https／launcher），供只需無狀態端點、不需 VM 持久記憶的情境使用。
**模型供應已切換為 Vertex AI**：`OPENCLAW_MODEL=google-vertex/gemini-2.5-flash`，靠 service account / 使用者 ADC 認證（存於 Secret Manager `vertex-adc`），`GEMINI_API_KEY` 改為**選填**（Vertex 路徑免 API 金鑰）。詳見 `docs/VERTEX-SETUP.md`。

**操作斷點與使用者最大痛點提醒（務必逐項遵守，否則流程會中途斷掉）**：
- 所有 `make`／`gcloud`／`curl` 指令一律在**本機終端機（zsh）**執行，工作目錄為 `/Users/allenchen/project/demo/openclaw/repo`。
- **切勿**把 Claude 輸入框中以 `!` 前綴顯示的指令連同 `!` 一起貼進真實終端機；`!` 在 zsh／bash 會觸發歷史展開或被當成邏輯否定，導致指令失敗或執行到非預期內容。在終端機只貼 `!` 後面的純指令。
- 開啟 Dashboard／chat 頁面時，必須使用「帶 `#token=...` fragment」的網址（用無痕瀏覽器），否則前端拿不到受保護的 `control-ui-config.json`（無 token 一律 401）而顯示「需要驗證」。

---

### TC-DEPLOY-01：make deploy 觸發 Cloud Build 並部署映像，服務根路徑回 200
- **對應 AC**：AC-09、AC-14
- **前置作業**：
  - 已完成 `make bootstrap`（API 已啟用，含 `aiplatform.googleapis.com`／`compute.googleapis.com`；Artifact Registry 映像庫已建；Cloud Build SA 具部署權限；runtime SA 已授 `roles/aiplatform.user`）。
  - 已完成模型認證 `make vertex-auth`（ADC 已存入 Secret Manager `vertex-adc`、runtime SA 具 `secretmanager.secretAccessor`）；模型為 `google-vertex/gemini-2.5-flash`。
  - `.env` 必填項齊備：`GCP_PROJECT_ID`、`OPENCLAW_GATEWAY_TOKEN`；`GEMINI_API_KEY` 為**選填**（Vertex 路徑免 API 金鑰）。
  - 本機已安裝並登入 `gcloud`（`gcloud auth login` 完成、已設定預設專案）。
- **測試步驟**：
  1. 在**本機終端機**執行：`cd /Users/allenchen/project/demo/openclaw/repo`
  2. 在**本機終端機**執行：`make deploy 2>&1 | tee /tmp/deploy.log`（會觸發 `gcloud builds submit` 並於成功後自動跑 `allow-public`）
  3. 等候約 10 秒讓 revision 就緒：`sleep 10`
  4. 在**本機終端機**執行：`curl -s https://clawdbot-475727900579.asia-east1.run.app/ -w '\nHTTP Status: %{http_code}\n'`
- **預計成果**：`make deploy` 成功（builds submit 完成、映像推到 Artifact Registry、部署新 revision），根路徑回 `HTTP Status: 200`。
- **實際成果**：唯讀佐證 PASS — `curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/` 實測 actual=`200`（live-cloudrun / cloudrun-root，status=pass）。`make deploy` 本身為 live/寫入動作，未於本輪重跑（依賴外部設定），但部署後端點 200 已實測。
- **判定**：✅PASS（端點 200 已實測；deploy 寫入步驟本輪未重跑）
- **備註**：可逆——重跑 `make deploy` 會新增 revision，可用 `make reinstall` 重建或 `make uninstall` 移除。`make url`／`make status` 回報的 URL 為 `clawdbot-2kxprlv3fa-de.a.run.app`，與稽核標準 URL `clawdbot-475727900579.asia-east1.run.app` 字面不同但指向同一健康服務，非異常。

### TC-DEPLOY-02：部署後服務進入 Ready=True 且最少實例 >= 1
- **對應 AC**：AC-14、AC-15
- **前置作業**：TC-DEPLOY-01 已成功部署；`gcloud` 已登入且 region=`asia-east1`。
- **測試步驟**：
  1. 在**本機終端機**執行就緒狀態查詢：`gcloud run services describe clawdbot --region=asia-east1 --format='value(status.conditions[0].status)'`
  2. 在**本機終端機**執行最少實例查詢：`gcloud run services describe clawdbot --region=asia-east1 --format='value(spec.template.metadata.annotations["autoscaling.knative.dev/minScale"])'`
  3. 或以唯讀彙整指令觀察：`make status`（內部呼叫 describe 顯示 URL／LATEST_READY_REVISION／MIN）
- **預計成果**：步驟 1 輸出 `True`；步驟 2 輸出 `1`（防冷啟動）。
- **實際成果**：以 `make status` 唯讀佐證 PASS — actual：`URL https://clawdbot-2kxprlv3fa-de.a.run.app  clawdbot-00003-tkj  MIN=1`（live-cloudrun / make-status，status=pass），顯示最新就緒 revision 存在且 MIN=1。`conditions[0].status` 的直接 describe 未於本輪單獨執行，依賴外部設定，但 status 已證實服務就緒且常駐。
- **判定**：✅PASS（最少實例=1、最新 revision 就緒已實測）
- **備註**：MIN 由 `MIN_INSTANCES` 控制；可用 `make min-instances N=1` 調整。權限軸線：describe 為唯讀（`run.viewer` 即可）。

### TC-DEPLOY-03：公開存取（allUsers→run.invoker）已自動補上，且 token 閘門正確
- **對應 AC**：AC-09
- **前置作業**：服務已部署；持有 gateway token `62f0930c...0bcf377`；使用無痕瀏覽器或終端機 curl。
- **測試步驟**：
  1. 在**本機終端機**驗證公開可呼叫（無授權標頭應仍能存取根頁）：`curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/`
  2. 在**本機終端機**帶正確 token 取設定：`curl -s -o /dev/null -w '%{http_code}' -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json`
  3. 在**本機終端機**不帶 token 取設定（應被擋）：`curl -s -o /dev/null -w '%{http_code}' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json`
  4. 在**本機終端機**確認 IAM 綁定：`gcloud run services get-iam-policy clawdbot --region=asia-east1`
- **預計成果**：步驟 1 根頁 200；步驟 2 帶 token 回 200；步驟 3 無 token 回 401；步驟 4 bindings 含 `allUsers / roles/run.invoker`。
- **實際成果**：全部 PASS — 根頁 actual=`200`（cloudrun-root）；帶 token actual=`200`（cloudrun-config-with-token）；無 token actual=`401`（cloudrun-config-no-token）；IAM actual=`members: allUsers, role: roles/run.invoker`（model-iam / model-iam-run-invoker，status=pass）。
- **備註**：`--allow-unauthenticated` 在 Cloud Build 常失效，故 `deploy` 末段自動跑 `allow-public`（Makefile 第 98 行）。權限軸線：`allow-public` 需 `run.admin`。痛點提醒——Dashboard 須用帶 `#token=` 的無痕網址，前端才會把 fragment 以 Bearer 帶入 config API；否則 401 顯示「需要驗證」。

### TC-DEPLOY-04：grant-build-roles 授予 Cloud Build SA 部署權限（新專案必需）
- **對應 AC**：AC-14
- **前置作業**：全新或未授權專案；`gcloud` 已登入且具 `resourcemanager.projects.setIamPolicy`（通常為 Owner／IAM Admin）。
- **測試步驟**：
  1. 在**本機終端機**執行：`cd /Users/allenchen/project/demo/openclaw/repo && make grant-build-roles`（內部以 projectNumber 推導 `<num>-compute@developer.gserviceaccount.com` 並綁 `roles/run.admin` 與 `roles/iam.serviceAccountUser`）
  2. 在**本機終端機**驗證：`gcloud projects get-iam-policy <GCP_PROJECT_ID>` 並確認 compute 預設 SA 同時出現在 `roles/run.admin` 與 `roles/iam.serviceAccountUser` 兩個 binding。
- **預計成果**：compute 預設 SA 同時擁有 `roles/run.admin` 與 `roles/iam.serviceAccountUser`，後續 `make deploy` 才不會因權限被拒。
- **實際成果**：PASS — actual：compute 預設 SA `475727900579-compute@developer.gserviceaccount.com` 同時出現在 `roles/run.admin` 與 `roles/iam.serviceAccountUser` 兩個 binding（並另持有 `cloudbuild.builds.builder`）（model-iam / model-iam-compute-sa-roles，status=pass）。授予指令本身為冪等寫入，本輪以唯讀 get-iam-policy 佐證最終狀態。
- **判定**：✅PASS（兩個目標角色皆已具備）
- **備註**：`bootstrap` 會串接 `enable-apis（含 aiplatform/compute API）→ create-repo → grant-build-roles（含 runtime SA 授 roles/aiplatform.user 供 Vertex 用）`（Makefile 第 91 行），新專案首次部署前必跑。權限軸線：此 target 改的是「專案層級 IAM」，與 `allow-public` 改的「服務層級 IAM」不同。

### TC-DEPLOY-05：make install 一鍵安裝的步驟順序——deploy 必須在 allow-public 之前（負向／順序斷言）
- **對應 AC**：AC-14
- **前置作業**：以 stub `gcloud`（不碰線上資源）執行 `tests/test_install.sh` 的情境4 happy path；本機已安裝 bash 與測試框架。
- **測試步驟**：
  1. 在**本機終端機**執行：`cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_install.sh`
  2. 觀察情境4（happy path）三項斷言：(a) 自動 allow-public 被呼叫、(b) builds submit 觸發部署、(c) **順序** order_ok 'builds submit' 'add-iam-policy-binding'（`tests/test_install.sh:74`）。
- **預計成果**：三項皆 PASS——install（8 步完整持久版）編排順序為 `... → [4/8] deploy(builds submit) → 自動 allow-public(add-iam-policy-binding) → [5/8] refresh-url → [6/8] vm-deploy → [7/8] vm-https → [8/8] doctor+launcher`，即 builds submit 紀錄應排在 add-iam-policy-binding 之前。
- **實際成果**：❌FAIL — actual：`20 passed, 1 failed, 0 skipped (exit 1)`。失敗項即情境4 的「順序：deploy→allow-public」order_ok 斷言（`tests/test_install.sh:74`）。值得注意：同情境的「自動 allow-public」（add-iam-policy-binding 有被呼叫）與「builds submit 觸發部署」兩項各自皆 PASS，只有驗證先後順序的 order_ok 失敗——表示 stub 紀錄中 builds submit 並未排在 add-iam-policy-binding 之前（test-install.sh，status=fail）。
- **判定**：❌FAIL
- **備註**：疑為 install／deploy target 編排順序或 stub 記錄順序問題。建議檢查 `Makefile` deploy（第 94–98 行）中 `builds submit` 與末段 `$(MAKE) allow-public` 的相對紀錄順序。`builds submit → allow-public` 同屬完整持久版第 `[4/8] deploy` 步內部，順序斷言與 6→8 步升級無關。此為唯一未綠項，其餘 install 情境（check-env 擋下、模型認證 fail-fast、token 自動產生）皆通過。斷點提醒：在真實終端機跑 `make install`（8 步完整持久版）時，若中途因 `!` 誤貼，或未先 `make vertex-auth`（步驟 `[3/8] 模型認證` 偵測不到 Secret `vertex-adc` 會印出完整步驟並擋下），須先完成 vertex-auth 再重跑；若只需 Cloud Run 可改用 `make install-cloudrun`。

### TC-DEPLOY-06：部署設定漂移防護——cloudbuild 含全部頻道環境變數且 port 一致
- **對應 AC**：AC-12、AC-13、AC-14
- **前置作業**：本機 repo 工作樹乾淨；無需 gcloud。
- **測試步驟**：
  1. 在**本機終端機**檢查頻道變數齊備：`grep -c 'GOOGLECHAT_ENABLED\|LINE_CHANNEL_SECRET\|LINE_CHANNEL_ACCESS_TOKEN' deploy/cloudbuild.yaml`
  2. 在**本機終端機**檢查 port 一致：`grep -c 'EXPOSE 8080' deploy/Dockerfile`（應為 1）與 `grep -c '\--port=8080' deploy/cloudbuild.yaml`（應為 1）
  3. 在**本機終端機**執行靜態測試套件：`bash tests/test_static.sh`
- **預計成果**：步驟 1 計數為 `3`（三個頻道變數皆在 `--set-env-vars`）；步驟 2 兩者皆 `1`（Dockerfile EXPOSE 與 cloudbuild --port 都是 8080）；步驟 3 靜態套件 0 failed。
- **實際成果**：PASS — `tests/test_static.sh` actual：`72 passed, 0 failed, 1 skipped (exit 0)`，含「設定漂移防護」「port 一致性」檢查；唯一 skip 為 cloudbuild.yaml 完整 YAML 解析（未安裝 PyYAML，非失敗）（shell-suites / test_static.sh，status=pass）。手動 grep 佐證：cloudbuild.yaml `--set-env-vars` 含 `GOOGLECHAT_ENABLED/LINE_CHANNEL_SECRET/LINE_CHANNEL_ACCESS_TOKEN`（第 88 行），Dockerfile `EXPOSE 8080`（第 42 行）、cloudbuild `--port=8080`（第 86 行）皆各 1。
- **判定**：✅PASS
- **備註**：此案為唯讀靜態檢查，可隨時重跑、完全可逆。漂移防護用意：避免某次手動 `gcloud run deploy` 後 cloudbuild.yaml 與線上 env-vars 不同步而漏帶頻道變數。

### TC-DEPLOY-07：本機 build-local 可成功建置映像（離線建置防護）
- **對應 AC**：AC-14
- **前置作業**：本機 Docker daemon 已啟動（`docker info` OK）。
- **測試步驟**：
  1. 在**本機終端機**確認 daemon：`docker info`
  2. 在**本機終端機**執行：`cd /Users/allenchen/project/demo/openclaw/repo && make build-local 2>&1 | grep -q 'Successfully tagged' && echo 'OK' || echo 'FAIL'`
  3. 進一步以整合測試驗證 build+run+smoke：`bash tests/test_integration.sh`
- **預計成果**：步驟 2 輸出 `OK`（映像建置成功）；步驟 3 整合測試全綠。
- **實際成果**：PASS（以整合測試佐證）— `docker info` => DAEMON_OK；`bash tests/test_integration.sh` actual：`21 passed, 0 failed, 0 skipped (exit 0)`，涵蓋 docker build 成功、CONFIG_ONLY 金鑰遮蔽、gateway listening、根頁 200／無 token 401／正確 Bearer 200／錯誤 Bearer 401、config token 與 allowedOrigins 正確、config validate 通過、google 模型解析、Asia/Taipei 時區、cron 啟用（docker-integration / test-04，status=pass）。`make build-local` 單獨指令未於本輪單獨擷取 `Successfully tagged`，但整合測試已實際完成 docker build。
- **判定**：✅PASS（整合測試含 build 已實測通過）
- **備註**：唯讀本機 docker，未碰線上 GCP。可逆——產生的本機映像可 `docker rmi` 清除。

### TC-DEPLOY-08：refresh-url 取得實際 URL、寫回 .env 並更新服務環境變數
- **對應 AC**：AC-09、AC-14
- **前置作業**：服務已部署；`.env` 存在且含 `OPENCLAW_PUBLIC_URL=` 行；`gcloud` 已登入。
- **測試步驟**：
  1. 在**本機終端機**執行：`cd /Users/allenchen/project/demo/openclaw/repo && make refresh-url`（內部 describe 取 `status.url`，`sed` 寫回 `.env`，再 `gcloud run services update --update-env-vars=OPENCLAW_PUBLIC_URL=...`）
  2. 在**本機終端機**唯讀確認 URL：`make url`
  3. 確認 allowedOrigins 已含實際 URL（無 403 CORS）：`curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json | grep -q 'allowedOrigins' && echo OK || echo FAIL`
- **預計成果**：`make refresh-url` 取到非空 URL、寫回 .env 並更新服務 env；`make url` 回報該 URL；config 含 `allowedOrigins`。
- **實際成果**：以唯讀步驟佐證 PASS — `make url` actual：`https://clawdbot-2kxprlv3fa-de.a.run.app`（live-cloudrun / make-url，status=pass）。`allowedOrigins` 經整合測試確認「config token 正確、allowedOrigins 含公開 URL」（docker-integration / test-04，status=pass）。`make refresh-url` 為 live 寫入動作，本輪未重跑（依賴外部設定），但其輸入（URL）與輸出（config allowedOrigins）皆已唯讀佐證健康。
- **判定**：✅PASS（URL 讀取與 allowedOrigins 已實測；refresh-url 寫入步驟本輪未重跑）
- **備註**：`refresh-url` 會以 `sed -i.bak` 改寫 .env（隨即刪 .bak），屬可逆的就地修改。若取不到 URL 會 `exit 1`（Makefile 第 112 行）。斷點提醒：在真實終端機執行時勿手動編輯到 `OPENCLAW_PUBLIC_URL=` 行的格式，否則 sed 比對失敗。

---

## 彙總

- **檔案**：`/Users/allenchen/project/demo/openclaw/repo/docs/test-cases/TC-01-deploy-cloudrun.md`
- **案例數**：8
- **判定分布**：✅PASS 7、❌FAIL 1（TC-DEPLOY-05 install 順序斷言）、⏭️SKIP 0、🖐️手動 0
