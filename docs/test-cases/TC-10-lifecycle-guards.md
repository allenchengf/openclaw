# TC-10 生命週期與危險操作防呆 測試案例

本檔涵蓋 openclaw（小龍蝦／ClawdBot）部署框架中「**生命週期與危險操作防呆**」領域的正規測試案例。範圍為 `make reinstall / uninstall / teardown-all / vm-delete / vm-teardown` 等可逆與不可逆操作的**防呆閘門（guard）**與**冪等性（idempotency）**，並涵蓋一鍵安裝鏈路（`install`，已升級為 8 步完整持久版；另有只裝 Cloud Run 的 `install-cloudrun`）的 fail-fast 與前置檢查（`check-env`）。所有破壞性流程均以 **stub gcloud** 驗證指令編排與 call log，**完全不觸碰線上資源**。模型供應已切換為 Vertex AI（`google-vertex/gemini-2.5-flash`，認證見 `make vertex-auth`）。

此領域的核心防呆設計（見 `Makefile`）：
- `check-env`（第 47–52 行）：缺 `.env` → 退出且印「找不到 .env」；缺 `GCP_PROJECT_ID` → 退出且印「GCP_PROJECT_ID 未設」。所有部署／生命週期 target 都以 `check-env` 為前置，是第一道防呆。
- `teardown-all`（第 152–158 行）與 `vm-teardown`（第 224–230 行）：第一行 `@test "$(CONFIRM)" = "yes" || { echo "✗ 危險操作..."; exit 1; }`，缺 `CONFIRM=yes` 一律拒絕、不呼叫任何 `gcloud delete`。**不可逆**（含刪映像庫／金鑰／持久磁碟／靜態 IP，記憶將遺失）。
- `uninstall`（第 148–150 行）、`vm-delete`（第 220–222 行）：**可逆／低風險**——只刪服務或 VM 實例，**保留**映像庫、金鑰、持久磁碟與靜態 IP（記憶不丟），且以 `|| true` 容忍不存在（冪等友善）。
- `reinstall`（第 138–146 行）：`uninstall（|| true）→ deploy → refresh-url → doctor（|| true）`，即「刪服務後重新部署」。
- `gen-token`（第 54–60 行）：以 `sed -i` 就地替換既有行，故**行數冪等**（連跑多次仍只有一行 `OPENCLAW_GATEWAY_TOKEN=`），但**值非冪等**（每次 `openssl rand` 產生新值）。

**操作斷點與使用者最大痛點提醒（務必逐項遵守，否則流程會中途斷掉）**：
- 所有 `make`／`gcloud`／`bash tests/*.sh` 指令一律在**本機終端機（zsh）**執行，工作目錄為 `/Users/allenchen/project/demo/openclaw/repo`。
- **切勿**把 Claude 輸入框中以 `!` 前綴顯示的指令連同 `!` 一起貼進真實終端機；`!` 在 zsh／bash 會觸發歷史展開或被當成邏輯否定，導致指令失敗或執行到非預期內容。在終端機只貼 `!` 後面的純指令。
- `CONFIRM=yes` 必須與 `make target` 寫在**同一行**（`make teardown-all CONFIRM=yes`）；分行或漏打會被防呆擋下（這是預期，但容易誤判為「指令壞了」）。
- 破壞性 target（`teardown-all`／`vm-teardown`）在**線上真實環境**執行不可逆，本檔所有破壞性步驟一律以 **stub gcloud**（test_makefile.sh 提供的假 gcloud + call log）驗證，**禁止**對 ncu 現役專案執行。

---

### TC-LIFECYCLE-01：缺 `.env` 時 `check-env` 第一道防呆擋下
- **對應 AC**：AC-20（生命週期前置檢查）
- **前置作業**：
  - 工作目錄存在但無 `.env`（或在無 `.env` 的目錄如 `/tmp` 執行）。
  - 已安裝 GNU make。
- **測試步驟**：
  1. 在**本機終端機**執行（稽核清單 lifecycle-01 指令）：
     `rm -f .env.tmp && (cd /tmp && make check-env 2>&1 || true) | grep -q '找不到 .env' && echo 'OK' || echo 'FAIL'`
  2. 觀察輸出是否為 `OK`。
- **預計成果**：`check-env` 因 `test -f .env` 失敗而 `exit 1`，且 stderr/stdout 含「✗ 找不到 .env，請先：cp .env.example .env」；包裝判斷輸出 `OK`。
- **實際成果**：由 `tests/test_makefile.sh`「check-env 負面/正面」段（22 passed, 0 failed, 0 skipped, exit 0）自動覆蓋並通過——缺 `.env` 時 `check-env` 退出並印出「找不到 .env」。
- **判定**：✅PASS
- **備註**：第一道防呆，不可逆操作前的必經閘門。注意 `make` 必須在「真的沒有 `.env`」的目錄執行才能重現；在 repo 根目錄（已有 `.env`）會通過而非擋下。

---

### TC-LIFECYCLE-02：`.env` 存在但 `GCP_PROJECT_ID` 未設時擋下
- **對應 AC**：AC-20
- **前置作業**：
  - 一個只含空 `GCP_PROJECT_ID` 的 `.env`（如 `/tmp/.env`）。
- **測試步驟**：
  1. 在**本機終端機**執行（稽核清單 lifecycle-02 指令）：
     `printf 'GCP_PROJECT_ID=\nGEMINI_API_KEY=test\n' > /tmp/.env && (cd /tmp && make check-env 2>&1 || true) | grep -q 'GCP_PROJECT_ID 未設' && echo 'OK' || echo 'FAIL'`
  2. 觀察輸出是否為 `OK`。
- **預計成果**：`check-env` 通過 `test -f .env` 但因 `test -n "$(GCP_PROJECT_ID)"` 為空而 `exit 1`，印出「✗ GCP_PROJECT_ID 未設」；包裝判斷輸出 `OK`。
- **實際成果**：由 `tests/test_makefile.sh`「check-env 負面/正面」段自動覆蓋並通過（同 TC-01 套件，22/0/0 exit 0）——空 `GCP_PROJECT_ID` 被擋下並印「GCP_PROJECT_ID 未設」。
- **判定**：✅PASS
- **備註**：`OPENCLAW_GATEWAY_TOKEN` 未設只 **warn 不擋**（部署時自動產生隨機值，但 Dashboard 無法預知 token），與 `GCP_PROJECT_ID` 的硬擋不同，屬刻意設計。

---

### TC-LIFECYCLE-03：一鍵安裝缺 Vertex ADC（vertex-adc）時 fail-fast 並印出完整步驟
- **對應 AC**：AC-21（install 缺模型認證即早失敗）
- **前置作業**：
  - `.env` 具 `GCP_PROJECT_ID`、`OPENCLAW_GATEWAY_TOKEN`，模型為 `google-vertex/gemini-2.5-flash`，但尚未做 `make vertex-auth`、Secret Manager 無 `vertex-adc`、本機亦無可用 ADC（以 stub gcloud 模擬 `secrets describe vertex-adc` 失敗）。
- **測試步驟**：
  1. 在**本機終端機**以 stub gcloud 執行 install 鏈路（由 `tests/test_install.sh` 編排）：
     `cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_install.sh`
  2. 對應稽核清單 lifecycle-03 的設計斷言（live-only，本機以 stub 表達）：
     `echo 'Design: install fail-fast on missing vertex-adc, prints make vertex-auth steps (live-only test)'`
- **預計成果**：`install`（8 步完整持久版）第 `[3/8] 模型認證` 步在偵測不到 Secret `vertex-adc` 且無本機 ADC 時，**印出完整 `make vertex-auth` 步驟並擋下**（`exit 1`），**不會**進到 `[4/8] deploy`（即 stub call log 無 `builds submit`）。
- **實際成果**：由 `tests/test_install.sh`（20 passed, 1 failed, 0 skipped, exit 1）覆蓋——「check-env 擋下、fail-fast、token 自動產生」等情境通過；唯一失敗為情境4 happy path 的「順序：deploy→allow-public」斷言（與本案的 fail-fast 無關，見 TC-LIFECYCLE-08）。fail-fast 行為本身 PASS。
- **判定**：✅PASS
- **備註**：Vertex 路徑免 API 金鑰，`GEMINI_API_KEY` 為選填；模型認證以 ADC（存於 Secret `vertex-adc`）為準。已在本機 `gcloud auth application-default login` 過者，`make install` 會自動偵測本機 ADC 並呼叫 `make vertex-store-adc` 存入 Secret，無需手動。fail-fast 只擋「完全沒有 vertex-adc 也沒有本機 ADC」，無法擋「ADC 存在但帳號無 aiplatform 權限」（後者屬 403，見 `docs/VERTEX-SETUP.md` 排錯對照）。若只需 Cloud Run 可改用 `make install-cloudrun`（同樣需先完成模型認證）。

---

### TC-LIFECYCLE-04：`teardown-all` 缺 `CONFIRM=yes` 時拒絕（不可逆防呆）
- **對應 AC**：AC-22（破壞性操作雙重確認）
- **前置作業**：
  - 使用 `tests/test_makefile.sh` 提供的 stub gcloud 與 call log（`$CALLLOG`），**禁止**對線上專案執行。
- **測試步驟**：
  1. 在**本機終端機**執行整套 Makefile 防呆測試：
     `cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_makefile.sh`
  2. 觀察「teardown-all 防呆」段：先不帶 `CONFIRM` 跑 `make teardown-all`，再帶 `CONFIRM=yes` 跑 `make teardown-all CONFIRM=yes`（後者在 stub 下執行）。
  3. 對應稽核清單 lifecycle-07 設計斷言：
     `echo 'Design: teardown-all requires CONFIRM=yes (destructive safety)'`
- **預計成果**：
  - 不帶 `CONFIRM`：`rc != 0` 且輸出含 `CONFIRM=yes`，**call log 無任何 `gcloud delete`**。
  - 帶 `CONFIRM=yes`（stub）：call log 出現 `run services delete`（及 artifacts/secrets delete）。
- **實際成果**：由 `tests/test_makefile.sh`「teardown-all 防呆」段自動覆蓋並通過（22 passed, 0 failed, 0 skipped, exit 0）——「無 CONFIRM → 拒絕」與「CONFIRM=yes → 執行刪除」皆 PASS。
- **判定**：✅PASS
- **備註**：**不可逆**——`teardown-all` 連同刪除 Cloud Run 服務、Artifact Registry 映像庫、Secret Manager 的 `gemini-api-key`。`CONFIRM=yes` 必須與 target 寫**同一行**；漏打或分行會被擋下（預期行為，勿誤判為指令壞掉）。線上絕不可對 ncu 現役專案執行。

---

### TC-LIFECYCLE-05：`vm-teardown` 缺 `CONFIRM=yes` 時拒絕；帶確認則刪 VM+磁碟+IP
- **對應 AC**：AC-22、AC-23（VM 記憶持久性風險告知）
- **前置作業**：
  - 使用 `tests/test_makefile.sh` 的 stub gcloud 與 call log，**禁止**對線上 `clawdbot-vm` 執行（持久磁碟掛 `/root/.openclaw`，刪除即遺失記憶）。
- **測試步驟**：
  1. 在**本機終端機**執行：
     `cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_makefile.sh`
  2. 觀察「VM 生命週期防呆（vm-teardown / vm-delete）」段：不帶 `CONFIRM` 的 `make vm-teardown`，與帶 `CONFIRM=yes` 的 `make vm-teardown CONFIRM=yes`（stub）。
  3. 對應稽核清單 lifecycle-08 設計斷言：
     `echo 'Design: vm-teardown requires CONFIRM=yes (destructive safety)'`
- **預計成果**：
  - 不帶 `CONFIRM`：`rc != 0` 且輸出含 `CONFIRM=yes`，call log 無 `instances delete`。
  - 帶 `CONFIRM=yes`（stub）：call log 同時出現 `instances delete`、`disks delete`、`addresses delete`（VM＋持久磁碟＋靜態 IP 全刪）。
- **實際成果**：由 `tests/test_makefile.sh`「VM 生命週期防呆」段自動覆蓋並通過（22/0/0 exit 0）——「vm-teardown 無 CONFIRM → 拒絕」與「CONFIRM=yes → 刪 VM+磁碟+IP」皆 PASS。
- **判定**：✅PASS
- **備註**：**最高風險、不可逆**——刪除持久磁碟 `clawdbot-vm-data` 等同永久遺失 VM 上的 openclaw 記憶（`/root/.openclaw`）。線上需先確認已無保留價值再執行。

---

### TC-LIFECYCLE-06：`vm-delete` 可逆性——只刪 VM 實例，保留磁碟與靜態 IP（記憶不丟）
- **對應 AC**：AC-23（可逆生命週期：記憶持久）
- **前置作業**：
  - 使用 `tests/test_makefile.sh` 的 stub gcloud 與 call log。
- **測試步驟**：
  1. 在**本機終端機**執行：
     `cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_makefile.sh`
  2. 觀察「VM 生命週期防呆」段中 `make vm-delete`（stub）的 call log 內容。
- **預計成果**：call log 出現 `instances delete`，但**不得**出現 `disks delete` 或 `addresses delete`（持久磁碟與靜態 IP 保留，下次 `vm-deploy` 重掛回 `/root/.openclaw`，記憶不丟）。
- **實際成果**：由 `tests/test_makefile.sh`「VM 生命週期防呆」段自動覆蓋並通過（22/0/0 exit 0）——「vm-delete 刪 instance」與「vm-delete 保留磁碟與 IP（記憶不丟）」皆 PASS。
- **判定**：✅PASS
- **備註**：`vm-delete` 無需 `CONFIRM`（低風險可逆）；與 `vm-teardown` 的關鍵差異即「是否刪持久磁碟與 IP」。`vm-deploy` 已驗證 VM 已存在時走 `update-container` 而非重建（見 `tests/test_vm.sh`，18/0/0），故刪→重建鏈路冪等友善。痛點提醒：`vm-https` 須先 `vm-deploy`/`update-container` 再起 Caddy，順序錯會中斷。

---

### TC-LIFECYCLE-07：`gen-token` 行數冪等，但值非冪等（破壞性風險告知）
- **對應 AC**：AC-24（token 生命週期）
- **前置作業**：
  - repo 根目錄具 `.env`，內含一行 `OPENCLAW_GATEWAY_TOKEN=`。
- **測試步驟**：
  1. 在**本機終端機**驗證行數冪等（稽核清單 lifecycle-05）：
     `grep -c '^OPENCLAW_GATEWAY_TOKEN=' .env`（預期 `1`）
  2. 連跑兩次 `make gen-token` 後再次 `grep -c`，確認仍為 `1`（由 `tests/test_makefile.sh`「gen-token 冪等性」段執行）。
  3. 對應稽核清單 lifecycle-06 的破壞性風險設計斷言：
     `echo 'WARNING: gen-token produces new value each run - documented risk'`
- **預計成果**：`grep -c` 輸出 `1`；連跑兩次後行數仍為 `1`（`sed -i` 就地替換不新增行）；但 token **值**每次更換（`openssl rand -hex 32`）。
- **實際成果**：由 `tests/test_makefile.sh`「gen-token 冪等性」段自動覆蓋並通過（22/0/0 exit 0）——「重跑仍單一行（冪等）」PASS。值非冪等屬已知並文件化之風險（每次新值）。
- **判定**：✅PASS
- **備註**：**破壞性風險**——重跑 `gen-token` 會使既有 Dashboard 連結（含舊 `#token=`）失效，且部署中的服務需重新部署才會採用新 token。現役 token=``；維運時除非要輪替 token，否則勿手動重跑 `gen-token`。

---

### TC-LIFECYCLE-08：`reinstall` 編排——先 `uninstall` 後重新 `deploy`（含 deploy→allow-public 順序）
- **對應 AC**：AC-21、AC-25（重新安裝鏈路）
- **前置作業**：
  - 使用 stub gcloud；`.env` 三必填齊備。
- **測試步驟**：
  1. 在**本機終端機**執行 install／編排測試：
     `cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_install.sh`
  2. 檢視 `reinstall`／`install` happy path 的 call log 順序：`uninstall（run services delete，|| true）→ deploy（builds submit）→ allow-public（add-iam-policy-binding allUsers）→ refresh-url`。
- **預計成果**：`reinstall` 先呼叫 `run services delete`（容忍不存在），再 `builds submit` 部署，且 `builds submit` 應**排在** `add-iam-policy-binding` 之前（deploy→allow-public）。
- **實際成果**：`tests/test_install.sh`（20 passed, **1 failed**, exit 1）——「自動 allow-public（`add-iam-policy-binding` 有被呼叫）」與「`builds submit` 觸發部署」各自 PASS，但驗證兩者**先後順序**的 `order_ok 'builds submit' 'add-iam-policy-binding'`（`tests/test_install.sh:74`）**失敗**：stub call log 中 `builds submit` 未排在 `add-iam-policy-binding` 之前。
- **判定**：❌FAIL
- **備註**：此為本領域唯一失敗項。`builds submit`／`allow-public` 兩動作皆有發生，僅相對順序斷言不符——疑為 Makefile `install`／`deploy` target 中 `deploy` 與 `allow-public` 的編排順序、或 stub 記錄順序問題（`deploy` 第 98 行於 `builds submit` 後才 `$(MAKE) allow-public`，理論上順序正確，建議檢查 stub 記錄時序與並行）。修復前 `reinstall`／`install` 的「deploy 先於 allow-public」不可視為已驗證。

---

### TC-LIFECYCLE-09：`uninstall` 可逆性——只刪服務，保留映像庫與金鑰，且容忍不存在
- **對應 AC**：AC-25
- **前置作業**：
  - 使用 stub gcloud 與 call log。
- **測試步驟**：
  1. 在**本機終端機**執行：
     `cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_makefile.sh`
  2. 觀察 `make uninstall`（stub）的 call log，並驗證服務不存在時仍以 `|| true` 正常退出（rc=0）。
- **預計成果**：call log 出現 `run services delete`，但**不得**出現 `artifacts repositories delete` 或 `secrets delete`（映像庫與 `gemini-api-key` 保留）；服務不存在時不報錯（冪等）。
- **實際成果**：手動驗證（佐證）。`tests/test_makefile.sh` 整套 22/0/0 exit 0 通過，涵蓋 teardown/VM 生命週期防呆；`uninstall` 「只刪服務、保留映像庫與金鑰、`|| true` 容忍不存在」之獨立斷言未在執行結果 JSON 中單列，依 Makefile 第 148–150 行設計（僅 `run services delete ... || true`）判定符合預期，線上行為需手動以 stub 或唯讀觀察確認。
- **判定**：🖐️手動
- **備註**：`uninstall` 為 `reinstall` 的第一步且以 `|| true` 包裹（首次安裝或服務已不存在時不致中斷）。可逆——映像庫與金鑰留存，重新 `deploy` 即可復原；與 `teardown-all` 的不可逆全刪明確區分。

---

### TC-LIFECYCLE-10：`teardown-all` 全刪鏈路完整性（CONFIRM=yes 下刪服務+映像庫+金鑰）
- **對應 AC**：AC-22
- **前置作業**：
  - 使用 stub gcloud 與 call log，**禁止**線上執行。
- **測試步驟**：
  1. 在**本機終端機**執行 `cd /Users/allenchen/project/demo/openclaw/repo && bash tests/test_makefile.sh`，觀察帶 `CONFIRM=yes` 的 `teardown-all` call log。
- **預計成果**：call log 至少出現 `run services delete`；依 Makefile 第 155–157 行另應嘗試 `artifacts repositories delete` 與 `secrets delete gemini-api-key`（皆以 `-` 前綴容忍失敗）。
- **實際成果**：手動驗證（佐證）。`tests/test_makefile.sh` 的 teardown 防呆段已驗證「CONFIRM=yes → 執行刪除（`run services delete`）」PASS（套件 22/0/0 exit 0）；但「同時刪映像庫＋金鑰」三項齊全的細項未在執行結果 JSON 中單列，依 Makefile 第 155–157 行設計判定符合（三條 delete 皆以 `-` 容錯排列），完整三刪需手動檢視 stub call log 確認。
- **判定**：🖐️手動
- **備註**：與 vm-teardown 並列為最高風險。`-` 前綴（make 的忽略錯誤）讓任一資源不存在時仍續刪其餘，確保「全部移除」語意；但也代表部分失敗不會中止，線上執行後務必 `make status`／`make doctor` 複查殘留。
