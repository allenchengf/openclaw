# openclaw（小龍蝦/ClawdBot）部署框架 — QA 總結報告

- 報告日期：2026-06-09
- 倉庫：`/Users/allenchen/project/demo/openclaw/repo`（部署/維運框架，非 openclaw 本體）
- 現役環境：
  - Cloud Run：`https://clawdbot-475727900579.asia-east1.run.app`
  - GCE VM HTTPS：`https://34-81-189-176.nip.io`（Caddy + nip.io 自動憑證，持久磁碟掛 `/root/.openclaw`）
  - 模型 `google/gemini-2.5-flash`，`OPENCLAW_MEMORY_PROVIDER=none`，TZ `Asia/Taipei`，cron 啟用
- 驗證原則：全程唯讀 / stub gcloud / 本機 docker，未對任何線上 GCP 資源做寫入或變更

---

## 1. 摘要：本次補齊內容

- 補齊 **11 條 Acceptance Criteria（AC）**，覆蓋部署框架的安裝、部署、VM 生命週期、HTTPS/TLS、token 鑑權、金鑰輪替、GitHub push、doctor 健檢、lint/安全掃描等關鍵維運面向。
- 新增 **11 個正規 test case 檔**，將上述 AC 對應到可執行的測試與線上驗證點。
- 實際執行：
  - 8 套 shell 測試套件（唯讀 / stub gcloud）：合計 **250 passed, 1 failed, 1 skipped**。
  - 5 項 Cloud Run 線上唯讀檢查、9 項 VM/Cloud Run 存取與痛點重現檢查、3 項 model/IAM 檢查、1 項 Docker 整合測試（21 子項全綠）。
- 對 4 條核心維運 flow 做對抗式完整性驗證，並修復已知 Makefile `lint-trivy` 汙染 bug。

---

## 2. Traceability 矩陣（AC ↔ Test Case ↔ 執行結果）

| AC | 描述 | 對應 Test Case | 執行檢查 / 套件 | 結果 |
|----|------|----------------|-----------------|------|
| AC-install | `make install` 一鍵安裝六步編排齊全、順序正確、fail-fast | TC-01 | `test_install.sh`、`test_makefile.sh`、`make -n` | PASS（流程通過；測試工具自身 1 誤報） |
| AC-vm-deploy | GCE VM 部署：全新建立、冪等不重建、缺金鑰 fail-fast、持久磁碟掛 `/root/.openclaw` | TC-02 | `test_vm.sh` | PASS（18/0/0） |
| AC-tls-valid | VM HTTPS 憑證有效（免 `-k`，`ssl_verify_result:0`） | TC-07 | `vm-https-cert-valid` | PASS |
| AC-vm-https-order | `vm-https.sh` 須先 update-container 再起 Caddy | TC-02 / TC-07 | 讀檔驗證 `deploy/vm-https.sh` 步驟順序 | PASS |
| AC-token-auth | control-ui-config.json 帶 Bearer→200、不帶→401（VM 與 Cloud Run 一致） | TC-04-03 / TC-04-04 | `vm-config-*`、`cloudrun-config-*` | PASS |
| AC-dashboard-access | 帶 `#token` 無痕網址可連 VM HTTPS dashboard；無 token 端卡「需要驗證」 | TC-04 | `painpoint-*` 系列 curl | PASS（隱憂：`make vm-dashboard` 輸出 http:8080） |
| AC-doctor | `make doctor` 健檢可完整跑完，token/根頁皆通 | TC-08 | `test_doctor.sh`、`make doctor`（線上） | PASS（rollout 期間 Ready=Unknown 誤判隱憂） |
| AC-secret-rotate | Gemini 金鑰輪替：secret-set-gemini → deploy → VM 同步 → 改 .env → 重驗 | TC-09-06 | `test_makefile.sh`、`make -n` 展開 | **FAIL**（文件 `make vm-update-container` 為不存在 target） |
| AC-github-push | GitHub push：機密不入 git、PAT/HTTPS remote、`!` 前綴防呆 | TC-09-07 | `test_lint.sh`、`git ls-files`/`.gitignore` | PASS |
| AC-lint-security | shellcheck / hadolint / gitleaks 全綠，無工具缺失 | TC-10 | `test_lint.sh` | PASS（19/0/0） |
| AC-config-integrity | 容器設定正確性：token、allowedOrigins、google 模型、Asia/Taipei、cron、memory=none | TC-11 | `test_integration.sh` | PASS（21/0/0） |
| AC-model-iam | Cloud Run `allUsers→run.invoker`；compute SA 具 run.admin + iam.serviceAccountUser | TC-05 / TC-06 | `model-iam-*` | PASS（IAM 兩項通過） |
| AC-gemini-key | Gemini 免費額度金鑰可用（generateContent 回 200） | TC-09 | `model-iam-gemini-key` | **FAIL**（HTTP 403 PERMISSION_DENIED） |

---

## 3. 執行結果統計

- **總計：26 項**（8 shell 套件 + 5 Cloud Run + 9 VM/痛點 + 3 model-IAM + 1 Docker 整合）
- **PASS：23 項**
- **FAIL：2 項**
- **SKIP：1 項**

> 補充：shell 套件內部子斷言合計為 **250 passed, 1 failed, 1 skipped**（其中 `test_install.sh` 的 1 個失敗子斷言即下方 FAIL-1）。

### FAIL 項目（2）

| # | 項目 | 原因 |
|---|------|------|
| FAIL-1 | `test_install.sh` 情境4（happy path）『順序：deploy→allow-public』斷言（`tests/test_install.sh:74` order_ok） | **測試工具誤報（false positive）**，非 install 流程缺陷。`order_ok` 用 `grep ... | head -1` 只取第一個匹配，`add-iam-policy-binding` 在 bootstrap 的 grant-build-roles（call log line 4）就先出現，遠早於 allow-public（line 9），導致 `head -1` 抓到錯誤的綁定。實際 call log 順序正確：builds submit(8) → add-iam-policy-binding allUsers(9) → update(11)。建議把 needle 改為更精確的 `run services add-iam-policy-binding` 或 `member=allUsers`。 |
| FAIL-2 | `model-iam-gemini-key`（Gemini 免費額度金鑰 generateContent） | HTTP **403 PERMISSION_DENIED**「Your project has been denied access. Please contact support.」。非預期的 429「prepayment credits depleted」，而是整個專案層級被拒絕存取，金鑰目前不可用。建議調查 / 更換金鑰所屬專案（記憶註記免費金鑰位於 `clawdbot-gemini-free-4088`）。 |

### SKIP 項目（1）

| # | 項目 | 原因 |
|---|------|------|
| SKIP-1 | `painpoint-auth-mode-note`（config body 是否暴露 auth.mode/token 欄位） | 說明性檢查，無硬性期望。授權純由 HTTP 層 Bearer 強制（不帶=401、帶=200），body 未對外暴露 auth/token/mode 欄位（grep 無命中），故僅以狀態碼佐證授權。 |

> 另：`test_static.sh` 內部有 1 個 skipped 子項（cloudbuild.yaml 完整 YAML 解析，因未安裝 PyYAML），不計入 26 項頂層統計。

---

## 4. 流程完整性對抗式驗證結論

### Flow A — VM Dashboard 存取（使用者痛點）
- **可端到端走完：是**　**斷點：none**
- 三項核心斷言全通過：(1) `curl /` → 200；(2) 帶 Bearer token 打 `/__openclaw/control-ui-config.json` → 200 並含真實 JSON；(3) 不帶 token → 401。
- 憑證有效（`ssl_verify_result:0`，免 `-k`；Let's Encrypt，notBefore Jun 9 2026 / notAfter Sep 7 2026，為新憑證非過期）。
- 痛點已重現並釐清：Cloud Run 與 VM 兩端 `/chat?session=main` HTML shell 皆回 200，但前端初始化需呼叫受保護的 config API；無 `#token` 的網址前端拿不到設定而顯示「需要驗證」。`#token` fragment 由前端 JS 取出後以 Bearer 帶入 API，使其得到 200。兩端授權行為完全一致，差異僅在網址是否攜帶 token fragment。
- `vm-https.sh` 順序正確：[2/4] update-container（先做、會重啟 VM）→ [3/4] 重啟後才 `docker run caddy`（`--restart=always`，`reverse_proxy localhost:8080`），不會中斷。
- **唯一隱憂（usability，非硬中斷）**：`make vm-dashboard`（Makefile 第 203-206 行）輸出 `http://$(IP):8080/chat?session=main#token=...`，是 HTTP:8080 而非文件主推的 `https://<ip>.nip.io` 安全網址。雖能連（8080=200），但與「無痕開 HTTPS nip.io」流程不一致，且 Control UI 在非 secure context 下部分功能可能受限。建議改輸出 nip.io HTTPS 網址以對齊文件。
- **判定：PASS**

### Flow B — `make install` 一鍵安裝
- **可端到端走完：是**　**斷點：none（無流程缺步驟/順序錯誤）**
- 六步編排完整：[1/6] 確保 gateway token → [2/6] bootstrap（enable-apis + create-repo + grant-build-roles）→ [3/6] Gemini 金鑰三擇一（皆無則 fail-fast exit 1）→ [4/6] deploy（builds submit + allow-public）→ [5/6] refresh-url → [6/6] doctor（`|| true` 不致命）。
- `check-env` 為硬性前置閘門（無 .env / 缺 `GCP_PROJECT_ID` 立即 exit 1 且不呼叫任何 gcloud）；缺金鑰在部署前 fail-fast，不觸發 builds submit。
- 唯一失敗 = 測試工具自身誤報（見 FAIL-1），實際 gcloud 呼叫順序 bootstrap→secret→deploy→allow-public→refresh-url 與設計一致。
- **判定：PASS**（被測流程通過；建議修 `tests/test_install.sh:44-45` 的 order_ok needle，僅動測試檔）

### Flow C — Gemini 金鑰輪替（TC-09-06）＋ GitHub push（TC-09-07）
- **可端到端走完：否**　**斷點：金鑰輪替的 VM 同步步驟**
- **硬中斷點**：TC-09-06 第 4 步指示執行 `make vm-update-container`，但 Makefile 根本沒有此 target。實測 `make -n vm-update-container` → `No rule to make target`（exit 2）。使用者照文件逐字操作會在 VM 同步處硬報錯中斷，且此時 Cloud Run 已 deploy 但 VM 仍用舊金鑰，造成三處不一致。
  - 正確 target 是 `make vm-deploy`（內部 `deploy/gce-deploy.sh` 執行 `gcloud compute instances update-container`，自 Secret/或 .env `GEMINI_API_KEY` 帶入新金鑰）。
  - 錯誤 target 名稱出現於：`TC-09-operations.md` 第 6、11、134、140 行 + `docs/ACCEPTANCE-CRITERIA.md` 第 182 行，共 5 處需改為 `make vm-deploy`。
  - 次要瑕疵：TC-09-06 第 4 步括號註「順序上須在重啟 Caddy 之前」實屬 TC-02 的 vm-https 順序，貼在此處易誤導（非硬中斷）。
- 金鑰輪替其餘步驟正確：`secret-set-gemini KEY=` 展開正確、缺 KEY fail-fast、`make deploy` 用 Cloud Build substitutions 帶入 `_GEMINI_API_KEY`、改 .env、curl/status 重驗、403 vs 429 分辨皆標註清楚。
- **GitHub push 流程：PASS**：`.gitignore` 已含 `.env`/`.env.*`/`*-sa.json`；`git ls-files` 無機密檔被追蹤；remote 為 HTTPS（PAT 相容）；`test_lint.sh` 19 passed（gitleaks 無洩漏）；「`!` 前綴只能在 Claude 對話框、不可貼進真實終端機」與「先改 Secret 再 deploy」「在哪執行」標註齊全。
- **判定：FAIL（金鑰輪替流程有硬中斷點，需修文件 5 處）；GitHub push 流程 PASS**

### Flow D — `make doctor` 健檢
- **可端到端走完：是**　**斷點：Cloud Run「Ready condition」判定（`scripts/doctor.sh` 第 69-70 行）**
- 流程完整跑完不中斷，但第一次以 exit 1 結束，回報「✗ 服務未就緒 └─ Unknown」。
- 根因：當下有新 revision `clawdbot-00005-rqv` 正在佈署，`conditions[0]`(Ready) status=Unknown「Provisioning revision instances...」，但 traffic 100% 仍在舊 revision `clawdbot-00004-2km`，故根頁 200、token Bearer→200、無 token→401 全部正常（服務實際健康）。連跑 5 次 Ready 穩定為 Unknown（非瞬時抖動）。約數分鐘後 rollout 收斂，再跑 `make doctor` 即「全部檢查通過」EXIT=0 —— 具時間相依 flaky 特性。
- `doctor.sh` 第 70 行對 Ready!=True 一律 `bad()`（硬失敗 / exit 1），未在「舊 revision 仍 100% serving + 根頁/token 皆通」時降級為 warn。`test_doctor.sh` 第 27 行把 Ready 寫死 True，從未涵蓋 rollout 中 Unknown 情境，故 stub 測試抓不到此真實案例。
- 建議修正：traffic 指向的 revision 為 Ready 且根頁可達時，把 Ready=Unknown（rollout 中）降級為 warn；或改判 `status.traffic` 對應 revision 的就緒狀態。並補 `test_doctor` stub 情境（Ready=Unknown + 根頁 200）。
- **判定：PASS（流程不中斷）；含一個會誤判中途失敗的 flaky 瑕疵，建議修 `scripts/doctor.sh:69-70`**

---

## 5. 修復項：Makefile `lint-trivy` bug（已修正完成）

第 285 行的 `lint-trivy` 指令原被垃圾數字汙染，導致 `$(LOCAL_NAME)` 變數遺失。

**修正前（第 285 行）：**
```
	@trivy image --scanners vuln,secret --severity HIGH,CRITICAL 905368131 905368131 12 62 79 80 81 701 33 98 100 204 250 395 398 399LOCAL_NAME) 2>/dev/null || echo "先 make build-local"
```

**修正後（第 285 行，已驗證）：**
```
	@trivy image --scanners vuln,secret --severity HIGH,CRITICAL $(LOCAL_NAME) 2>/dev/null || echo "先 make build-local"
```

> 此 bug 與本次 4 條核心 flow 無關（不阻斷 install / 金鑰輪替 / push / doctor），屬獨立修正項，現已套用。

---

## 6. 待辦 / 手動項

| # | 項目 | 動作 | 嚴重度 |
|---|------|------|--------|
| TODO-1 | **TC-09-06 / ACCEPTANCE-CRITERIA.md 的 `make vm-update-container`** | 5 處（TC-09-operations.md 第 6/11/134/140 行 + ACCEPTANCE-CRITERIA.md 第 182 行）改為 `make vm-deploy`；移除 TC-09-06 第 4 步誤植的 Caddy 順序註記 | 高（硬中斷使用者最在意的痛點） |
| TODO-2 | **Gemini 金鑰 403 PERMISSION_DENIED** | 調查 / 更換金鑰所屬專案（免費金鑰位於 `clawdbot-gemini-free-4088`）；確認非帳單專案以取得免費額度 | 高（模型無法生成） |
| TODO-3 | **`tests/test_install.sh:44-45` order_ok 誤報** | needle 由 `add-iam-policy-binding` 改為 `run services add-iam-policy-binding` 或 `member=allUsers`，避免抓到 grant-build-roles 的綁定 | 中（誤導維運者，僅動測試檔） |
| TODO-4 | **`scripts/doctor.sh:69-70` rollout 期間 Ready=Unknown 誤判** | Ready=Unknown 但 traffic revision 就緒 + 根頁可達時降級為 warn；補對應 stub 情境 | 中（flaky，rollout 期間誤報失敗） |
| TODO-5 | **`make vm-dashboard` 輸出 http://IP:8080** | 改輸出 `https://<ip>.nip.io` HTTPS 網址以對齊文件並符合 secure context | 低（一致性瑕疵，非中斷） |
| TODO-6 | **頻道 / 圖片配額等運維設定** | 確認對話頻道綁定與圖片生成配額；如需多媒體功能另行開通額度 | 待確認 |
| TODO-7 | **PyYAML 未安裝** | 如需 `test_static.sh` 的 cloudbuild.yaml 完整 YAML 解析，於測試環境裝 PyYAML（目前 skip） | 低 |
| TODO-8 | **.env 的 `OPENCLAW_PUBLIC_URL` 與現役 URL 字面不一致** | `.env` 記為 `clawdbot-2kxprlv3fa-de.a.run.app`，與稽核標準 URL 不同字面但指向同一服務；doctor 用 gcloud 動態查 status.url 不受影響，建議統一以免混淆 | 低 |
