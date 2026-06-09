# TC-02 GCE VM 部署與 HTTPS 正規測試案例

本檔涵蓋 openclaw（小龍蝦／ClawdBot）「部署/維運框架」中 **GCE VM 部署與 HTTPS 反向代理** 領域的正規測試案例（區碼 `TC-02-VM`）。

領域範圍：

- `make vm-deploy`（`deploy/gce-deploy.sh`）：以 COS VM + `create-with-container` 部署，掛載持久磁碟到 `/root/.openclaw`，靜態 IP（`clawdbot-vm-ip`）、防火牆（`clawdbot-8080`，tcp:8080）冪等沿用。VM 已存在時改走 `update-container`（不重建、磁碟與 IP 不丟）。
- `make vm-https`（`deploy/vm-https.sh`）：以 Caddy 容器在 host network 綁 80/443，反代到 clawdbot 容器（localhost:8080），透過 nip.io（`<dash-ip>.nip.io`）+ Let's Encrypt 自動取得受信任憑證。
- `make vm-status`：唯讀回報 VM `name/status/IP`。
- 記憶持久化：`/root/.openclaw/openclaw.json` 與 sqlite 跨 VM 重啟保留（AC-05）。
- token 閘門：`/__openclaw/control-ui-config.json` 帶 Bearer 回 200、不帶回 401（AC-09）。

**領域最大斷點（必讀）**：`vm-https.sh` 的執行順序是 **先 `update-container`（會重啟 VM）→ 等 VM RUNNING 且 8080 可達 → 才在 VM 上啟動 Caddy**。若把 Caddy 先起再做 update-container，重啟會把 Caddy 容器打斷；Caddy 必須以 `--restart=always` 啟動，VM 重啟後才會自動回來。下列操作型步驟一律標明「在哪裡執行」，避免把含 `!`／`▶` 前綴的 Claude 輸出貼進真實終端機而被當邏輯否定或語法錯誤而中斷。

執行環境約定：

- **本機終端機**：指 macOS 上 `cd /Users/allenchen/project/demo/openclaw/repo` 後直接執行的 `make`／`gcloud`／`curl`／`bash tests/*.sh`。所有指令逐字貼入，**不要**保留任何 Claude 介面才有的 `!` 前綴或 `▶`/`✓` 裝飾字元。
- **VM 內（透過 SSH）**：以 `gcloud compute ssh clawdbot-vm --zone=asia-east1-b --command='...'` 帶入，不要手動進 shell 再貼多行。
- **無痕瀏覽器**：僅用於人工驗證 Dashboard，需貼「帶 `#token=` fragment 的完整網址」。

固定參數：專案 `project-6c870217-2205-4b1b-a3f`／編號 `475727900579`、VM `clawdbot-vm`、zone `asia-east1-b`、region `asia-east1`、靜態 IP `34.81.189.176`、HTTPS 網域 `34-81-189-176.nip.io`、gateway token ``。

---

### TC-02-VM-01：全新部署 VM 並掛載持久磁碟到 /root/.openclaw（正向／編排）
- **對應 AC**：AC-05、AC-14
- **前置作業**：
  - 本機終端機已 `cd /Users/allenchen/project/demo/openclaw/repo`，`.env` 內含 `GCP_PROJECT_ID / OPENCLAW_GATEWAY_TOKEN / GEMINI/Google 金鑰`（`make check-env` 通過）。
  - 具 `gcloud` 並登入有 compute 權限的帳號。
  - 此案以 stub gcloud 自動驗證編排，不碰線上資源。
- **測試步驟**：
  1. 在 **本機終端機** 執行：`bash tests/test_vm.sh`
  2. 觀察「全新部署」情境是否走 `create-with-container` 並帶 `--container-mount-disk=mount-path=/root/.openclaw,name=clawdbot-vm-data`。
- **預計成果**：test_vm 全綠（0 failed）；斷言確認新建 VM 使用 `create-with-container` 且掛載持久磁碟到 `/root/.openclaw`。
- **實際成果**：`bash tests/test_vm.sh` → 18 passed, 0 failed, 0 skipped（exit 0）。涵蓋「掛載持久磁碟到 /root/.openclaw」。
- **判定**：✅PASS
- **備註**：持久磁碟 `clawdbot-vm-data` 即記憶跨重啟的根；不可改掛載點，否則 AC-05 失效。stub 測試，可逆、唯讀。

---

### TC-02-VM-02：VM 已存在時冪等改走 update-container（不重建／不丟磁碟與 IP）
- **對應 AC**：AC-14、AC-15
- **前置作業**：同 TC-02-VM-01；stub gcloud 模擬「VM 已存在」分支。
- **測試步驟**：
  1. 在 **本機終端機** 執行：`bash tests/test_vm.sh`
  2. 觀察「VM 已存在」情境是否改走 `update-container` 而非 `create-with-container`（不重建）。
- **預計成果**：重複部署時偵測到 VM 已存在，改 `update-container`，靜態 IP 與持久磁碟沿用，不重建。
- **實際成果**：`bash tests/test_vm.sh` → 18 passed, 0 failed, 0 skipped（exit 0）。明列涵蓋「VM 已存在改 update-container 的冪等性」。
- **判定**：✅PASS
- **備註**：冪等性是維運安全閥；`make vm-delete` 也只刪 VM、保留磁碟與 IP（記憶不丟）。stub 測試，可逆。

---

### TC-02-VM-03：缺金鑰時 vm-deploy fail-fast（負向）
- **對應 AC**：AC-14、AC-11
- **前置作業**：本機終端機在 repo 目錄；stub gcloud；故意移除/留空必要金鑰（Google/Gemini）。
- **測試步驟**：
  1. 在 **本機終端機** 執行：`bash tests/test_vm.sh`（含「缺金鑰 fail-fast」情境）。
- **預計成果**：缺金鑰時部署提早失敗並回非 0，不會帶著空金鑰把容器推上線。
- **實際成果**：`bash tests/test_vm.sh` → 18 passed, 0 failed, 0 skipped（exit 0），情境含「缺金鑰 fail-fast」。
- **判定**：✅PASS
- **備註**：fail-fast 避免上線後才 403/429；金鑰不入映像、不外洩（AC-11）。stub 測試，可逆。

---

### TC-02-VM-04：VM 已部署且狀態為 RUNNING（線上正向）
- **對應 AC**：AC-14、AC-15
- **前置作業**：具線上讀取權限的 `gcloud`；VM `clawdbot-vm` 已存在。對應稽核 check `vm-01`。
- **測試步驟**：
  1. 在 **本機終端機** 執行（整行貼入，勿加 `!` 前綴）：
     `gcloud compute instances describe clawdbot-vm --zone=asia-east1-b --format='value(status)'`
  2. 或執行 `make vm-status` 看 `name/status/IP` 一覽。
- **預計成果**：輸出 `RUNNING`。
- **實際成果**：依賴外部設定（線上 gcloud）。本輪 execJson 未提供 `vm-01`（instances describe status）之 actual；屬唯讀線上檢查，需手動執行驗證。
- **判定**：🖐️手動
- **備註**：唯讀、不破壞。若非 RUNNING 先查配額/計費是否被關（記憶 gotcha：計費關閉會使資源停擺）。

---

### TC-02-VM-05：VM 持久磁碟正確掛載且記憶檔存在（線上正向／AC-05 核心）
- **對應 AC**：AC-05、AC-06
- **前置作業**：線上 `gcloud` + SSH 權限；VM RUNNING。對應稽核 check `vm-03`、`vm-06`。
- **測試步驟**：
  1. 在 **本機終端機** 確認磁碟來源含 `clawdbot-vm-data`（整行貼入）：
     `gcloud compute instances describe clawdbot-vm --zone=asia-east1-b --format='value(disks[0].source)' | grep -q 'clawdbot-vm-data' && echo OK || echo FAIL`
  2. 在 **本機終端機** 透過 SSH 確認記憶檔存在（整行貼入，`--command` 內字串原樣）：
     `gcloud compute ssh clawdbot-vm --zone=asia-east1-b --command='test -f /root/.openclaw/openclaw.json && echo OK || echo FAIL'`
- **預計成果**：步驟 1 輸出 `OK`；步驟 2 輸出 `OK`（記憶檔在持久磁碟上，跨重啟保留）。
- **實際成果**：依賴外部設定（線上 SSH/describe）。本輪 execJson 未提供 `vm-03`/`vm-06` 之 actual；需手動執行驗證。test_vm 已於 stub 層驗證掛載點 `/root/.openclaw` 正確（見 TC-02-VM-01）。
- **判定**：🖐️手動
- **備註**：此為 AC-05「記憶跨重啟持久」的線上鐵證；唯讀。`OPENCLAW_MEMORY_PROVIDER=none` 下記憶靠 `~/.openclaw` 檔案而非向量庫。

---

### TC-02-VM-06：VM 容器執行中且 8080 HTTP 可達（線上正向）
- **對應 AC**：AC-09、AC-14
- **前置作業**：VM RUNNING；防火牆 `clawdbot-8080`（tcp:8080）開放。對應稽核 check `vm-04`、`vm-05`、`vm-07`。
- **測試步驟**：
  1. 在 **本機終端機** 確認防火牆協定（整行貼入）：
     `gcloud compute firewall-rules describe clawdbot-8080 --format='value(allowed[0].IPProtocol)'`
  2. 在 **本機終端機** 確認容器執行中（SSH，整行貼入）：
     `gcloud compute ssh clawdbot-vm --zone=asia-east1-b --command='docker ps --format "table {{.Image}}" | grep clawdbot'`
  3. 在 **本機終端機** 打 HTTP 根路徑（整行貼入）：
     `curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://34.81.189.176:8080/`
- **預計成果**：步驟 1 輸出 `tcp`；步驟 2 命中 clawdbot 映像（1 行）；步驟 3 回 `200`。
- **實際成果**：依賴外部設定（線上）。本輪 execJson 未提供 `vm-04/05/07` 之 actual；惟同等 HTTPS 層證據已於 live-vm-access 取得：`https://34-81-189-176.nip.io/` 回 HTTP:200（見 TC-02-VM-08），間接佐證 8080 後端與容器健康。HTTP:8080 直連需手動驗證。
- **判定**：🖐️手動
- **備註**：唯讀。8080 為對外埠（容器內 listen 8080）；Caddy 啟用後對外建議改走 443。

---

### TC-02-VM-07：vm-https 順序斷點——必須先 update-container 再起 Caddy（斷點／編排）
- **對應 AC**：AC-10、AC-15
- **前置作業**：本機終端機在 repo 目錄；`make check-env` 通過；VM 已部署。可閱讀 `deploy/vm-https.sh` 第 33-55 行確認順序。
- **測試步驟**：
  1. 在 **本機終端機** 執行整個流程（**只此一行**，勿手動拆步、勿加 `!` 前綴）：`make vm-https`
  2. 對照腳本內建順序：`[1/4]` 開防火牆 80/443 → `[2/4]` `instances update-container`（會重啟 VM）並輪詢等 `status=RUNNING` 且 `http://IP:8080/` 可達 → `[3/4]` 重啟完成後才 `docker run -d --name caddy --restart=always --network host ...` 起 Caddy。
  3. **負向對照（僅驗證觀念，勿在線上手動逆序操作）**：若先起 Caddy 再 `update-container`，VM 重啟會中斷 Caddy；正確流程靠「先 update 後 Caddy + `--restart=always`」避免此斷點。
- **預計成果**：`make vm-https` 依 `update-container → 等 RUNNING/8080 → 起 Caddy` 順序完成，最終 nip.io HTTPS 可達。Caddy 以 `--restart=always` 啟動，VM 重啟後自動回來。
- **實際成果**：依賴外部設定（會變更線上 VM，本輪未執行寫入）。腳本 `deploy/vm-https.sh:33-55` 已固化此順序（第 33 行註解「update-container 會重啟 VM；故須在啟動 Caddy 之前完成」；第 52 行 `--restart=always`）。順序正確性以唯讀程式碼審查確認；線上端到端需手動跑一次 `make vm-https`。
- **判定**：🖐️手動
- **備註**：**本領域最大斷點**。切勿把 Claude 顯示的 `▶ [2/4] ...` 等裝飾行貼進終端機；只貼 `make vm-https`。流程不可逆性低（可重跑，冪等），但逆序會導致 Caddy 被重啟打斷而誤判失敗。

---

### TC-02-VM-08：VM HTTPS 根路徑可達且憑證受信任（線上正向／Caddy + nip.io）
- **對應 AC**：AC-10
- **前置作業**：`make vm-https` 已成功；nip.io 解析正常；80/443 連通且 Let's Encrypt 憑證已簽發。對應稽核 check `vm-08` 與 live `vm-https-root`／`vm-https-cert-valid`。
- **測試步驟**：
  1. 在 **本機終端機** 驗證 HTTPS 可達（**不加 `-k`**，整行貼入）：
     `curl -sS -o /dev/null -w 'HTTP:%{http_code} ssl_verify_result:%{ssl_verify_result}' --max-time 15 https://34-81-189-176.nip.io/`
  2. （可選，VM 內確認 Caddy 容器在跑）在 **本機終端機** 執行 SSH：
     `gcloud compute ssh clawdbot-vm --zone=asia-east1-b --command='docker ps --format "table {{.Names}}" | grep caddy'`
- **預計成果**：步驟 1 回 `HTTP:200 ssl_verify_result:0`（不加 `-k` 即通過，憑證受信任）；步驟 2 命中 `caddy`（1 行）。
- **實際成果**：`HTTP:200 ssl_verify_result:0`（exit=0；未使用 `-k` 即成功，Caddy+nip.io 自動憑證受信任）。同時 `https://34-81-189-176.nip.io/` 根路徑回 HTTP:200。（步驟 2 的 SSH `caddy` 檢查 `vm-08` 本輪未提供 actual，需手動驗證。）
- **判定**：✅PASS
- **備註**：`ssl_verify_result:0` 是 secure context（Dashboard 需要）成立的關鍵。唯讀。若 cert 未簽發，先查 nip.io 解析與 80/443 防火牆。

---

### TC-02-VM-09：VM 受保護 config API 的 token 閘門（線上正向＋負向）
- **對應 AC**：AC-09
- **前置作業**：VM HTTPS 已就緒；已知 gateway token。對應 live check `vm-config-with-token`／`vm-config-without-token`。
- **測試步驟**：
  1. 在 **本機終端機** 帶正確 Bearer token（整行貼入）：
     `curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 -H 'Authorization: Bearer ' https://34-81-189-176.nip.io/__openclaw/control-ui-config.json`
  2. 在 **本機終端機** 不帶 token（整行貼入）：
     `curl -s -o /dev/null -w 'HTTP:%{http_code}' --max-time 15 https://34-81-189-176.nip.io/__openclaw/control-ui-config.json`
- **預計成果**：步驟 1 回 `HTTP:200`；步驟 2 回 `HTTP:401`。
- **實際成果**：帶 token → `HTTP:200 (exit=0)`；不帶 token → `HTTP:401 (exit=0)`。token 閘門正常，與 Cloud Run 兩端授權行為一致。
- **判定**：✅PASS
- **備註**：授權純由 HTTP 層 Bearer 強制，config body 不外露 `auth.mode/token`。唯讀。

---

### TC-02-VM-10：使用者痛點重現——無痕 Dashboard 需帶 #token fragment（手動驗證）
- **對應 AC**：AC-10、AC-09
- **前置作業**：VM HTTPS 就緒；token 閘門已驗（TC-02-VM-09）。對應 live check `painpoint-vm-chat-token-fragment`。
- **測試步驟**：
  1. 在 **本機終端機** 取得帶 token 的 Dashboard 網址：`make vm-dashboard`（輸出形如 `http://IP:8080/chat?session=main#token=...`；HTTPS 版請把主機換成 `https://34-81-189-176.nip.io`）。
  2. 在 **無痕瀏覽器** 貼入 **帶 `#token=` fragment 的完整 HTTPS 網址**（例：`https://34-81-189-176.nip.io/chat?session=main#token=62f0930c...0bcf377`），確認 UI 正常初始化。
  3. 對照：在 **無痕瀏覽器** 貼 **不帶 fragment** 的網址（`https://34-81-189-176.nip.io/chat?session=main`），確認頁面 HTML 可下載（200）但 UI 顯示「需要驗證」。
- **預計成果**：帶 `#token=` 時 UI 正常（前端讀 fragment 後以 Bearer 取得 config 200）；不帶時頁面回 200 但 UI 因 config API 401 而要求驗證。
- **實際成果**：`https://34-81-189-176.nip.io/chat?session=main` 頁面回 `HTTP:200`；佐證同端 config API 帶 token 回 200、不帶回 401，差異在於網址是否攜帶 token fragment 而非伺服器授權邏輯。瀏覽器端 UI 行為屬人工觀察，需手動驗證。
- **判定**：🖐️手動
- **備註**：痛點根因——fragment（`#token=`）由前端 JS 讀取後改以 `Authorization: Bearer` 帶入受保護 API；**務必在無痕視窗貼「完整含 fragment」的網址**。唯讀。
