# TC-06 記憶與身分 測試案例

本檔涵蓋 openclaw（小龍蝦/ClawdBot）部署框架在「記憶與身分」領域的正規測試案例。範圍包含：

1. **身分讀取（IDENTITY）**：機器人啟動時應能讀取身分／使用者／記憶設定檔（`IDENTITY.md`、`USER.md`、`MEMORY.md`）。
2. **VM 跨重啟持久**：GCE VM `clawdbot-vm` 以持久磁碟掛載 `/root/.openclaw`，記憶檔（sqlite + `.md`）須在容器／VM 重啟後仍存在；對照 Cloud Run 為「無狀態設計」，本就不跨重啟。
3. **`OPENCLAW_MEMORY_PROVIDER=none` 不報錯**：預設記憶 provider 為 `none`（免金鑰），記憶搜尋（memorySearch）停用，容器啟動日誌不應出現 `No API key found for provider openai`，且運行期不應出現 openai embedding / `chunks_vec` 記憶錯誤。

> 重要操作斷點提醒（使用者最大痛點）：
> 1. 凡標示「本機終端機」的指令，請直接貼進你電腦的 Terminal/iTerm 執行；切勿貼進 Claude 輸入框。
> 2. 本檔所有指令皆「不含」`!` 前綴，照抄即可。切勿把 Claude REPL 的 `!` 前綴貼進真實終端機，否則 `!` 會被當成 shell 的 history expansion 或邏輯否定而中斷流程。
> 3. control-ui 網址必須攜帶 `#token=...` fragment，否則前端拿不到設定而顯示「需要驗證」。
> 4. VM 相關 `gcloud compute ssh` 指令需 SSH 金鑰與專案權限；無對應自動化結果者標「依賴外部設定」或「手動」。

---

### TC-06-01：記憶 provider 預設為 none（免金鑰，本機 .env 驗證）
- **對應 AC**：AC-mem-01
- **前置作業**：
  - 本機已 clone 倉庫，當前目錄含 `.env` 檔。
  - `.env` 已產生（若無，先跑 `make` 相關設定流程產生）。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄，勿加 `!` 前綴）：
     ```
     grep '^OPENCLAW_MEMORY_PROVIDER=' /Users/allenchen/project/demo/openclaw/repo/.env | cut -d= -f2
     ```
  2. 觀察輸出值是否為 `none`。
- **預計成果**：輸出 `none`，代表記憶 provider 為免金鑰預設，不需 openai embedding 金鑰。
- **實際成果**：手動驗證（本領域稽核 check `memory-01` 為 `live:false`，execJson 未提供其獨立 actual）。佐證：前置 `grep` 已確認本機 `.env` 第 20 行為 `OPENCLAW_MEMORY_PROVIDER=none`；且 docker 整合測試 `test-04`（status=pass）明示「memorySearch 預設停用(none)」。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。此為一切「免金鑰、不報 openai 錯」行為的根因設定。

---

### TC-06-02：記憶搜尋停用——線上 config 中 memorySearch.enabled=false（Cloud Run）
- **對應 AC**：AC-mem-02
- **前置作業**：
  - 本機已安裝 `curl`。
  - 已知 gateway token：``。
  - Cloud Run 服務在線：`https://clawdbot-475727900579.asia-east1.run.app`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄，勿加 `!` 前綴）：
     ```
     curl -s -H 'Authorization: Bearer ' https://clawdbot-475727900579.asia-east1.run.app/__openclaw/control-ui-config.json 2>&1 | grep -o '"enabled":\s*false' | wc -l
     ```
  2. 觀察計數是否為 `1`（即 config 內含 `"enabled": false`，對應 memorySearch 停用）。
- **預計成果**：輸出 `1`，代表 provider=none 時記憶搜尋被停用。
- **實際成果**：依賴外部設定／手動驗證。execJson 未提供 `memory-02` 此 grep 的獨立 actual；但同端 `control-ui-config.json` 帶正確 token 回 200（`cloudrun-config-with-token` actual=200, pass）已證明 config API 可讀取，配合 docker 整合測試 `test-04`（pass）確認「memorySearch 預設停用(none)」，可間接佐證 enabled=false。grep 命中計數本身為手動驗證。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。需帶 token，否則 config API 回 401。

---

### TC-06-03：容器啟動日誌無「No API key found for provider openai」錯誤（Cloud Run）
- **對應 AC**：AC-mem-03
- **前置作業**：
  - 本機已安裝並登入 `gcloud`，active project 指向部署專案（`project-6c870217-2205-4b1b-a3f` / 編號 475727900579）。
  - 具備 Cloud Run logs 唯讀權限。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄，勿加 `!` 前綴）：
     ```
     gcloud run services logs read clawdbot --region=asia-east1 --limit=50 2>&1 | grep -c 'No API key found' || echo '0'
     ```
  2. 觀察輸出是否為 `0`。
- **預計成果**：輸出 `0`，代表 provider=none 下不會因缺 openai 金鑰而報錯。
- **實際成果**：依賴外部設定／手動驗證。execJson 未直接提供 `memory-03` 的 gcloud logs actual；但 docker 整合測試 `test-04`（status=pass）已明確驗證容器內「無 openai embedding 金鑰錯誤、無 chunks_vec 記憶錯誤」，與本案期望一致。線上 Cloud Run logs 計數為手動驗證。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。日誌讀取不影響服務。此即「provider=none 免金鑰不報錯」設計的線上佐證點。

---

### TC-06-04：運行期無 openai embedding／chunks_vec 記憶錯誤（容器整合測試，自動化）
- **對應 AC**：AC-mem-03、AC-id-01
- **前置作業**：
  - 本機已啟動 Docker daemon（`docker info` 可成功）。
  - 倉庫含 `tests/test_integration.sh`。
- **測試步驟**：
  1. 在「本機終端機」執行（確認 daemon）：
     ```
     docker info
     ```
  2. 在「本機終端機」執行整合測試：
     ```
     bash /Users/allenchen/project/demo/openclaw/repo/tests/test_integration.sh
     ```
  3. 觀察最後一行結果與 exit code，並確認子項目含「無 openai embedding 金鑰錯誤」「無 chunks_vec 記憶錯誤」。
- **預計成果**：全綠（0 failed），且明確驗證 `OPENCLAW_HOME` 回歸防護下無 openai embedding 與 chunks_vec 記憶錯誤、`openclaw config validate` 通過、memorySearch 預設停用。
- **實際成果**：`docker info => DAEMON_OK`。`bash tests/test_integration.sh` 輸出全綠，最後一行「結果：21 passed, 0 failed, 0 skipped」，exit code=0。子項目確認：`openclaw config validate` 通過、解析到 google 模型、`userTimezone=Asia/Taipei`、`cron.enabled=true`、memorySearch 預設停用(none)、無 openai embedding 金鑰錯誤、無 chunks_vec 記憶錯誤。（對應 execJson `docker-integration` / `test-04`，status=pass）
- **判定**：✅PASS
- **備註**：唯讀本機 docker，未碰線上 GCP 資源。此為本領域「不報 openai/chunks_vec 錯」最強的自動化佐證。

---

### TC-06-05：VM 持久磁碟記憶檔存在——sqlite + IDENTITY/USER/MEMORY.md（身分讀取與持久根基）
- **對應 AC**：AC-id-01、AC-mem-04
- **前置作業**：
  - 本機已安裝並登入 `gcloud`，具 `compute.instances` SSH 權限與對應 SSH 金鑰。
  - VM `clawdbot-vm` 在 zone `asia-east1-b` 運行中，持久磁碟掛載於 `/root/.openclaw`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄，勿加 `!` 前綴；首次 SSH 可能需建立金鑰，依 gcloud 提示完成）：
     ```
     gcloud compute ssh clawdbot-vm --zone=asia-east1-b --command='ls -la /root/.openclaw/ | grep -E "\.(db|sqlite|md)$"' 2>&1 | wc -l
     ```
  2. 觀察輸出計數是否為 `3`（對應 sqlite/db 檔 + `IDENTITY.md`/`USER.md`/`MEMORY.md` 之類的 `.md` 身分／記憶檔）。
- **預計成果**：輸出 `3`，代表 VM 持久磁碟上身分與記憶檔皆存在，IDENTITY 可被讀取。
- **實際成果**：依賴外部設定／手動驗證。execJson 未提供 `memory-04` 的 `gcloud compute ssh` actual（`live-vm-access` 群組僅含 HTTPS／config API 之 curl 唯讀檢查，未含 SSH 進機）。佐證：`test_vm.sh`（status=pass，18 passed）已涵蓋「掛載持久磁碟到 `/root/.openclaw`」與「VM 已存在改 update-container 的冪等性」，間接支持持久磁碟掛載正確。檔案實際列表須以 SSH 手動驗證。
- **判定**：🖐️手動
- **備註**：唯讀（僅 `ls`），可逆。斷點提醒：此指令需在「本機終端機」執行，且 `gcloud compute ssh` 首次需互動建立金鑰——勿貼進 Claude 輸入框。權限軸線：需 IAM 的 SSH／OS Login 權限。

---

### TC-06-06：VM 跨重啟記憶持久——持久磁碟掛載與冪等 update-container（自動化部署測試）
- **對應 AC**：AC-mem-04、AC-mem-05
- **前置作業**：
  - 本機已 clone 倉庫，含 `tests/test_vm.sh`（使用 stub gcloud，不碰線上資源）。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```
     bash /Users/allenchen/project/demo/openclaw/repo/tests/test_vm.sh
     ```
  2. 觀察結果是否 0 failed，並確認涵蓋「掛載持久磁碟到 /root/.openclaw」「VM 已存在改 update-container 的冪等不重建」。
- **預計成果**：全綠（0 failed），證明部署流程正確將持久磁碟掛到 `/root/.openclaw`，且 VM 已存在時走 update-container 而非重建（記憶不被清空），達成跨重啟持久。
- **實際成果**：結果「18 passed, 0 failed, 0 skipped」，exit 0。涵蓋掛載持久磁碟到 `/root/.openclaw`、VM 已存在改 update-container 的冪等性。（對應 execJson `shell-suites` / `test_vm.sh`，status=pass）
- **判定**：✅PASS
- **備註**：stub gcloud，唯讀、未碰線上資源。斷點提醒：真實重新部署 VM 時，順序須「先 update-container 再起 Caddy」（vm-https 流程），順序錯會中斷。本案僅驗證編排邏輯，不實際重啟線上 VM。

---

### TC-06-07：Cloud Run 記憶不跨重啟（無狀態設計，對照組）
- **對應 AC**：AC-mem-06
- **前置作業**：
  - 理解設計前提：Cloud Run 為無狀態容器，重啟／改版（revision）後本地檔案不保留；持久記憶須改用 VM `/root/.openclaw` 持久磁碟。
- **測試步驟**：
  1. 在「本機終端機」執行（此為設計聲明，無實際線上副作用）：
     ```
     echo 'By design - Cloud Run stateless, use VM for persistence'
     ```
  2. （概念驗證）對照 TC-06-06：需要記憶跨重啟者應部署於 VM，而非依賴 Cloud Run。
- **預計成果**：輸出 `By design - Cloud Run stateless, use VM for persistence`，明示 Cloud Run 不負責記憶持久，符合架構分工。
- **實際成果**：手動驗證（稽核 check `memory-06` 為 `live:false` 的設計聲明，execJson 未提供獨立 actual）。佐證：`make status`（pass）顯示 Cloud Run `MIN=1`（防冷啟動但仍無狀態）；持久需求由 VM 持久磁碟（TC-06-05／06）承接。
- **判定**：🖐️手動
- **備註**：純設計聲明，無副作用、完全可逆。權限軸線：無。此 case 用於釐清「Cloud Run 記憶遺失」非 bug 而是預期行為。

---

### TC-06-08：gen-config.mjs 記憶 provider 參數解析（負向／設定產生器）
- **對應 AC**：AC-mem-01、AC-cfg-02
- **前置作業**：
  - 本機已安裝 `node`，倉庫含 `deploy/gen-config.mjs`。
- **測試步驟**：
  1. 在「本機終端機」執行（單行照抄，勿加 `!` 前綴）：
     ```
     OPENCLAW_GATEWAY_TOKEN=test123 node /Users/allenchen/project/demo/openclaw/repo/deploy/gen-config.mjs 2>&1 | grep -o '"provider":\s*"none"' | wc -l
     ```
  2. 觀察計數。稽核期望為 `0`——即未明示帶入 memory provider 時，產生的設定不會硬編出 `"provider": "none"` 欄位（provider 行為由 `OPENCLAW_MEMORY_PROVIDER` 環境變數於運行期決定，而非寫死在 gen-config 輸出）。
- **預計成果**：輸出 `0`，代表 gen-config 不會硬編 `"provider":"none"`；記憶 provider 為運行期環境變數驅動。
- **實際成果**：手動驗證（稽核 check `memory-05` 為 `live:false`，execJson 未提供其獨立 actual）。佐證：`test_config.sh`（status=pass，25 passed，含「記憶」案例）與 `test_static.sh`（pass，含「設定漂移防護」）已涵蓋 gen-config 各案例與設定不漂移；本案 grep 計數本身為手動驗證。
- **判定**：🖐️手動
- **備註**：唯讀、可逆。負向用意：確認設定產生器不把 provider 寫死，避免與 `.env` 的 `OPENCLAW_MEMORY_PROVIDER` 失同步。

---

### TC-06-09：身分讀取與記憶設定整體回歸（config validate，自動化交叉佐證）
- **對應 AC**：AC-id-01、AC-mem-02、AC-mem-03
- **前置作業**：
  - 本機已啟動 Docker daemon。
  - 倉庫含 `tests/test_integration.sh`（同 TC-06-04 套件，本案聚焦設定正確性與身分／記憶相關欄位）。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```
     bash /Users/allenchen/project/demo/openclaw/repo/tests/test_integration.sh
     ```
  2. 觀察輸出中與身分／記憶相關之子項目：`openclaw config validate` 通過、`OPENCLAW_HOME` 回歸防護、memorySearch 預設停用(none)、無 openai embedding／chunks_vec 錯誤。
- **預計成果**：全綠，`OPENCLAW_HOME` 正確指向記憶／身分根目錄、config validate 通過、記憶相關設定無誤。
- **實際成果**：「21 passed, 0 failed, 0 skipped」，exit 0。含 `OPENCLAW_HOME` 回歸防護（config validate、google 模型解析、Asia/Taipei 時區、cron 啟用、memorySearch 預設停用、無 openai embedding 與 chunks_vec 記憶錯誤）。（對應 execJson `docker-integration` / `test-04`，status=pass）
- **判定**：✅PASS
- **備註**：唯讀本機 docker。本案與 TC-06-04 同源但聚焦「身分／記憶根目錄（OPENCLAW_HOME）與設定驗證」軸線，作為身分讀取的自動化交叉佐證。

---

## 判定彙總

| 判定 | 數量 | 對應 TC |
|------|------|---------|
| ✅PASS | 3 | TC-06-04、TC-06-06、TC-06-09 |
| ❌FAIL | 0 | — |
| ⏭️SKIP | 0 | — |
| 🖐️手動 | 6 | TC-06-01、TC-06-02、TC-06-03、TC-06-05、TC-06-07、TC-06-08 |

合計 9 個 test case。其中 3 個有對應自動化結果（皆 PASS），6 個為手動／依賴外部設定（線上 gcloud logs、VM SSH、需帶 token 的線上 grep、設計聲明、gen-config grep 等 execJson 未提供獨立 actual 之項目）。

> 共通斷點提醒：所有指令在「本機終端機」執行，照抄勿加 `!` 前綴；VM 重新部署遵循「先 update-container 再起 Caddy」順序；存取受保護 API 須帶 `Authorization: Bearer <token>` 或網址 `#token=` fragment。
