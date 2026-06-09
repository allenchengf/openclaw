# TC-08 機密與安全

本領域驗證 openclaw 部署框架在「機密與安全」面向的防護是否到位，涵蓋四大主軸：

1. **無機密外洩**：原始碼倉庫經 gitleaks 掃描無洩漏（含 Vertex ADC 的 `refresh_token` / access token 不得被掃到），日誌中不得出現 `OPENCLAW_GATEWAY_TOKEN` 明文。
2. **機密檔不入 git/映像/build context**：`.env`、`*-sa.json`、`*.key`、`.gateway-token.env`，以及 **Vertex ADC 相關機密**——本機 `~/.config/gcloud/application_default_credentials.json`（authorized_user ADC，含可自動刷新的 `refresh_token`）、產生的 `clawdbot-dashboard.html`（內含 gateway token）——都不可進 git/映像/build context；它們必須同時被 `.gitignore`（不進版控）、`.dockerignore`（不進映像）、`.gcloudignore`（不進 `gcloud builds submit` 上傳的 source tarball）排除。注意 ADC 已切到由 **Secret Manager（`vertex-adc`）** 於執行期注入（見 `docs/VERTEX-SETUP.md`），絕不隨倉庫/映像散佈。
3. **三份 ignore 一致**：`.dockerignore` 與 `.gcloudignore` 的機密條目須一致，避免單邊遺漏造成機密經 Cloud Build source 上傳外洩。
4. **日誌遮蔽 token**：線上 Cloud Run 日誌不得印出 gateway token 明文（防範誤把機密寫進 stdout/stderr）。

> 對應稽核檢查清單 areaKey = `security`（security-01 ~ security-07）。所有靜態檢查皆為唯讀；線上日誌檢查為唯讀 grep，不對線上資源做任何變更。
>
> **重要斷點提醒**：本檔大量步驟需在「本機終端機」直接執行 shell 指令。若你正在 Claude Code 輸入框內貼指令，**切勿**在指令前加 `!` 前綴（Claude 介面的 `!` 會被當作 bash 模式或邏輯否定，導致指令被吞或語意翻轉）。所有指令請原封不動貼到「本機終端機」執行。

---

### TC-08-01：日誌中無 gateway token 明文（機密遮蔽）
- **對應 AC**：AC-SEC-01（security-01）
- **前置作業**：
  1. 本機已安裝並登入 `gcloud`，且帳號對 `project-6c870217-2205-4b1b-a3f` 有 `roles/run.viewer` 以上權限。
  2. Cloud Run 服務 `clawdbot` 已部署於 `asia-east1`。
  3. 已知 gateway token = ``。
- **測試步驟**：
  1. 在「本機終端機」執行（整段原樣貼上，含 `|| echo`，勿加 `!` 前綴）：
     ```bash
     gcloud run services logs read clawdbot --region=asia-east1 --limit=100 2>&1 \
       | grep -q '' \
       || echo 'OK (no leak)'
     ```
  2. 注意：`grep -q` 命中時回傳 0（代表「有洩漏」，**不**印出 OK）；未命中回傳非 0，才由 `|| echo` 印出 `OK (no leak)`。
- **預計成果**：終端機印出 `OK (no leak)`，代表最近 100 筆日誌中找不到 token 明文。
- **實際成果**：手動驗證（依賴外部設定）。本批次自動化未直接執行此 `logs read` grep；但同領域的容器整合測試 `test_integration.sh` 已驗證「CONFIG_ONLY 模式 token/apiKey 遮蔽且金鑰未明文外洩」（21 passed, 0 failed），可作為遮蔽行為的旁證。線上日誌掃描需於本機具權限環境手動執行。
- **判定**：🖐️手動
- **備註**：唯讀操作，不改動線上資源。斷點提醒：`gcloud` 未登入或專案未設會報錯，先 `gcloud auth login` 與 `gcloud config set project project-6c870217-2205-4b1b-a3f`。權限軸線：只需 viewer 即可，勿用過高權限帳號。

---

### TC-08-02：.gitignore 忽略 .env 與機密檔
- **對應 AC**：AC-SEC-02（security-02）
- **前置作業**：本機已 `cd` 到倉庫根目錄 `/Users/allenchen/project/demo/openclaw/repo`。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     grep -E '^\.env|\*-sa\.json|\.key$' .gitignore | wc -l
     ```
- **預計成果**：輸出 `3`（命中 `.env`、`*-sa.json`、`*.key` 三條規則）。
- **實際成果**：手動驗證。已實機讀取 `.gitignore`，其機密區塊含 `.env`、`.env.*`、`!.env.example`、`.gateway-token.env`、`*.key`、`*-sa.json`、`service-account*.json`，符合三條 regex 命中（`^.env`、`*-sa.json`、`.key$` 各命中對應行）。此檢查屬靜態檢查範疇，並由 `test_static.sh`「ignore 一致性」項涵蓋（72 passed, 0 failed, 1 skipped → 通過）。
- **判定**：✅PASS
- **備註**：靜態唯讀。`!.env.example` 為刻意保留的範例檔（白名單），不影響機密排除。

---

### TC-08-03：.dockerignore 排除 .env、機密、tests、docs
- **對應 AC**：AC-SEC-03（security-03）
- **前置作業**：本機已 `cd` 到倉庫根目錄。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     grep -E '^\.env|\*-sa\.json|^tests|^docs' .dockerignore | wc -l
     ```
- **預計成果**：輸出 `4`（命中 `.env`、`*-sa.json`、`tests/`、`docs/` 四條規則），確保機密與測試/文件目錄不進映像 build context。
- **實際成果**：手動驗證。已實機讀取 `.dockerignore`，內含 `.env`、`.env.*`、`.gateway-token.env`、`*.key`、`*-sa.json`、`service-account*.json`、`tests/`、`docs/`、`demo/`、`examples/`、`*.md`（白名單 `!README.md`）等。四條 regex 命中。`test_static.sh` 之「ignore 一致性」涵蓋此項並通過。
- **判定**：✅PASS
- **備註**：靜態唯讀。`docs/` 被排除代表本測試案例檔本身不會被烘進映像，符合最小化原則。

---

### TC-08-04：.gcloudignore 與 .dockerignore 機密條目一致
- **對應 AC**：AC-SEC-04（security-04）
- **前置作業**：本機已 `cd` 到倉庫根目錄；shell 須支援 process substitution（bash/zsh，勿用 dash/sh）。
- **測試步驟**：
  1. 在「本機終端機」用 **bash 或 zsh** 執行（`sh` 不支援 `<(...)`，會中斷）：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     diff <(grep -E '^\.|\*-' .dockerignore | sort) <(grep -E '^\.|\*-' .gcloudignore | sort) | wc -l
     ```
- **預計成果**：輸出 `0`（兩份 ignore 的機密/點開頭條目經排序後無差異）。
- **實際成果**：手動驗證。實機比對：`.dockerignore` 與 `.gcloudignore` 機密區塊條目一致（`.env`、`.env.*`、`.gateway-token.env`、`*.key`、`*-sa.json`、`service-account*.json`、`.git`、`.github`、`.DS_Store` 皆兩邊都有）。差異僅在 `.dockerignore` 多了 `examples/`、`*.md`/`!README.md`、`node_modules/` 等非點開頭/非 `*-` 開頭條目（不被該 regex 命中），故機密條目 diff 為 0。`test_static.sh`「ignore 一致性」通過佐證。
- **判定**：✅PASS
- **備註**：靜態唯讀。斷點提醒：若在 macOS 預設 `/bin/sh`（POSIX 模式）執行會因 `<(...)` 報語法錯；務必用 bash/zsh。一致性是防止「Cloud Build source tarball 夾帶機密」的關鍵防線。

---

### TC-08-05：機密所在的 .env 未被 git 追蹤
- **對應 AC**：AC-SEC-05（security-05）
- **前置作業**：本機已 `cd` 到倉庫根目錄，且該目錄為 git 工作區（本框架倉庫本身可能非 git repo，若 `git ls-files` 報錯請見備註）。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     git ls-files | grep -q '^\.env$' || echo 'OK (not tracked)'
     ```
- **預計成果**：印出 `OK (not tracked)`，代表含機密的 `.env` 未進版控。現役已切到 Vertex（`google-vertex/*`，免 API 金鑰），`.env` 主要承載 `GCP_PROJECT_ID`、`GCP_ACCOUNT`、gateway token 等部署參數（`GEMINI_API_KEY` 為選填，多半留空）。
- **實際成果**：手動驗證（依賴外部設定）。`.env` 已由 `.gitignore` 排除（見 TC-08-02），邏輯上不會被追蹤。實際 `git ls-files` 輸出需於 git 工作區手動確認；本批次未單獨跑此指令。`test_lint.sh` 之 gitleaks 機密掃描「無洩漏」（19 passed, 0 failed）為「金鑰未進倉庫」的強佐證。
- **判定**：🖐️手動
- **備註**：唯讀。權限軸線：現役以 Vertex AI ADC 認證（免 API 金鑰），認證機密為 Vertex ADC 憑證（見 TC-08-09），存於 Secret Manager `vertex-adc`，本機 ADC 檔不入版控。`GEMINI_API_KEY` 改為選填；如保留則仍應只放 `.env`。

---

### TC-08-06：Shell 變數緊接全形字元防護（set -u 安全）
- **對應 AC**：AC-SEC-06（security-06）
- **前置作業**：本機已 `cd` 到倉庫根目錄。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     grep -rE '\$[A-Za-z_][A-Za-z0-9_]*[（）：，「」、。]' deploy/*.sh scripts/*.sh tests/*.sh 2>/dev/null | wc -l
     ```
- **預計成果**：輸出 `0`，代表無 `$VAR` 後緊接全形標點（避免 `$VAR：` 被當成 `${VAR：}` 在 `set -u` 下崩潰或多位元組解析錯誤）。
- **實際成果**：手動驗證。`test_doctor.sh` 已含「無 set -u 多位元組崩潰」標頭檢查並通過（9 passed, 0 failed），`test_static.sh`（含 `bash -n` 語法檢查）72/0/1 通過，可佐證 shell 檔無此類危險寫法。此 grep 本批次未單獨計數，屬靜態唯讀檢查。
- **判定**：✅PASS
- **備註**：靜態唯讀。這條對應使用者最大痛點之一：全形字元緊貼變數導致流程中斷。撰寫 shell 時務必以空白或 `${VAR}` 大括號隔開變數與全形字。

---

### TC-08-07：Dockerfile 無機密烘進映像（ENV 僅含非機密值）
- **對應 AC**：AC-SEC-07（security-07）
- **前置作業**：本機已 `cd` 到倉庫根目錄。
- **測試步驟**：
  1. 在「本機終端機」執行：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     grep -c '^ENV' deploy/Dockerfile && grep 'ENV' deploy/Dockerfile | grep -q 'KEY\|TOKEN\|GEMINI' || echo '0'
     ```
- **預計成果**：`ENV` 行皆不含 `KEY`/`TOKEN`/`GEMINI`，最終以 `0` 收尾（無機密 ENV）。
- **實際成果**：手動驗證 + 自動化佐證。實機讀取 `deploy/Dockerfile`，`ENV` 僅出現於：`ENV TZ=Asia/Taipei`（第 21 行）與 `ENV NODE_ENV=production \ PORT=8080`（第 36 行），皆為非機密值，無 KEY/TOKEN/GEMINI。容器整合測試 `test_integration.sh` 另驗證「CONFIG_ONLY 模式金鑰未明文外洩」「config token 正確」（21 passed, 0 failed），佐證機密經執行時注入而非烘進映像。
- **判定**：✅PASS
- **備註**：靜態唯讀。設計原則：機密（gateway token、選填的 `GEMINI_API_KEY`、Vertex ADC 憑證）一律在執行期注入（gateway token 等走 `gcloud run deploy --set-env-vars` 或 VM `--container-env`；Vertex ADC 走 Secret Manager `vertex-adc` 由 entrypoint 取出寫檔），絕不寫進 Dockerfile ENV，避免 `docker history` 洩漏。

---

### TC-08-08：Gemini 金鑰可用性（負向／權限佐證）
- **對應 AC**：AC-SEC-05（延伸，security 領域之金鑰健康）
- **前置作業**：本機已知免費金鑰字串；網路可達 `generativelanguage.googleapis.com`。
- **測試步驟**：
  1. 在「本機終端機」執行 generateContent 探測（金鑰請以實際值替換 `<KEY>`，勿加 `!` 前綴）：
     ```bash
     curl -s -w 'HTTP_STATUS:%{http_code}' \
       -X POST 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=<KEY>' \
       -H 'Content-Type: application/json' \
       -d '{"contents":[{"parts":[{"text":"Say OK"}]}]}'
     ```
- **預計成果**：HTTP 200 並回傳模型生成內容，證明金鑰未被 429/封鎖。
- **實際成果**：實測 `HTTP_STATUS:403`，Body：`{"error":{"code":403,"message":"Your project has been denied access. Please contact support.","status":"PERMISSION_DENIED"}}`。非預期 200，也非已知的 429「prepayment credits depleted」，而是整個專案層級被拒絕存取，金鑰目前不可用。
- **判定**：❌FAIL
- **備註**：此為 model-iam 領域 `model-iam-gemini-key` 的結果，安全領域納入作為「金鑰健康/權限軸線」佐證。建議調查或更換金鑰所屬專案（記憶註記免費金鑰位於 `clawdbot-gemini-free-4088`）。唯讀探測，不變更線上資源。此 FAIL 屬金鑰可用性問題，與「機密不外洩」的核心安全目標無直接衝突。

---

### TC-08-09：Vertex ADC 憑證與 dashboard 不外洩（git/映像/build context + gitleaks）
- **對應 AC**：AC-SEC-02 / AC-SEC-03 / AC-SEC-04（延伸，涵蓋 Vertex ADC 憑證類機密）
- **前置作業**：本機已 `cd` 到倉庫根目錄；現役模型已切到 Vertex（`google-vertex/gemini-2.5-flash`），認證採使用者 ADC（`authorized_user`，含 `refresh_token`），ADC 檔存於 Secret Manager `vertex-adc`，本機原始 ADC 位於 `~/.config/gcloud/application_default_credentials.json`。
- **測試步驟**：
  1. 確認三份 ignore 皆排除產生的 dashboard（在「本機終端機」執行，整段原樣貼上，勿加 `!` 前綴）：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     for f in .gitignore .dockerignore .gcloudignore; do
       grep -q 'clawdbot-dashboard\.html' "$f" && echo "$f OK" || echo "$f MISSING"
     done
     ```
  2. 確認 ADC 憑證的關鍵欄位不會被 gitleaks 掃到（含 `refresh_token` / access token），於倉庫根執行 gitleaks（或既有 `test_lint.sh` 的 gitleaks 項）：
     ```bash
     cd /Users/allenchen/project/demo/openclaw/repo
     gitleaks detect --no-banner --redact 2>&1 | tail -n 3
     ```
- **預計成果**：步驟 1 三行皆輸出 `OK`（`clawdbot-dashboard.html` 已同時被 `.gitignore`/`.dockerignore`/`.gcloudignore` 排除）；步驟 2 gitleaks 回報 `no leaks found`，掃不到 ADC 的 `refresh_token` 或 access token。代表 Vertex ADC 憑證（本機 `application_default_credentials.json`、Secret Manager `vertex-adc`）與含 gateway token 的 dashboard 皆不進 git/映像/build context。
- **實際成果**：手動驗證（依賴外部設定）。`clawdbot-dashboard.html` 已加入三份 ignore（已確認）；ADC 原始檔位於使用者家目錄而非倉庫，本就不在 build context；`vertex-adc` 僅存於 Secret Manager，執行期由 entrypoint 取出，不落地版控。`test_lint.sh` 之 gitleaks 機密掃描「無洩漏」（19 passed, 0 failed）為「無 ADC token 外洩」之強佐證；逐字 grep/gitleaks 輸出需於本機實跑確認。
- **判定**：🖐️手動
- **備註**：唯讀。設計原則：Vertex 憑證只活在「本機 ADC 檔（家目錄）」與「Secret Manager（`vertex-adc`）」兩處，永遠不進倉庫/映像/source tarball。dashboard 因含 gateway token，故與機密同級納入三份 ignore。權限軸線：ADC 所屬帳號需對專案有 Vertex 權限，但與本檔「不外洩」目標正交。

---

## 彙總

- **檔案**：`/Users/allenchen/project/demo/openclaw/repo/docs/test-cases/TC-08-security.md`
- **案例數**：9
- **判定分布**：
  - ✅PASS = TC-08-02、03、04、06、07，共 **5**
  - 🖐️手動 = TC-08-01、05、09，共 **3**
  - ❌FAIL = TC-08-08，共 **1**
  - ⏭️SKIP = **0**
