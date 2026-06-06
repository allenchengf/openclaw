# openclaw-Taiwan 測試計畫（QA Test Matrix）
> 由多代理 QA 工作流程窮舉產生，共 **456** 個測試案例（10 維度），其中可自動化 **395** 個。
自動化測試實作於 `tests/`，以 `make test` 執行。本文件為完整清單與驗收標準（AC）。

## 自動化測試套件對應
| 套件 | 範圍 |
|------|------|
| `tests/test_static.sh` | 檔案結構、bash/JS 語法、YAML、ignore 一致性、port/設定漂移防護、.env 格式 |
| `tests/test_docs.sh` | README / .env.example 與實作一致性 |
| `tests/test_config.sh` | `gen-config.mjs` 設定產生器各分支（單元）|
| `tests/test_makefile.sh` | Makefile 編排 / 負面 / 冪等（stub gcloud）|
| `tests/test_integration.sh` | 映像 build → 啟動 gateway → HTTP/token smoke |
| `tests/test_live.sh` + `make doctor` | 已部署服務健康與 token 驗證 |

## 測試矩陣（依維度）

### Configuration-gen-config (deploy/gen-config.mjs)（50）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| GENCFG-01 | 僅 token：輸出為合法 JSON | unit | P0 | ✅ | stdout 可被 JSON.parse 解析無誤；exit 0。已覆蓋於 test_config.sh 案例1。 |
| GENCFG-02 | auth.mode 固定為 token | unit | P0 | ✅ | = "token"。已覆蓋 test_config 案例1。 |
| GENCFG-03 | token 正確寫入 auth.token | unit | P0 | ✅ | 等於傳入的 token 原值。已覆蓋 test_config 案例1。 |
| GENCFG-04 | 缺 token（未設環境變數）→ exit 非零 | unit | P0 | ✅ | exit code !=0（=1），stderr 含 "OPENCLAW_GATEWAY_TOKEN is required"，stdout 無 JSON 輸出。部分覆蓋（案例6用空字串，未測完全 unset 與 stderr 訊息）。 |
| GENCFG-05 | token 為空字串 → 視為缺值並失敗 | unit | P0 | ✅ | exit !=0（!token 對空字串為真）。已覆蓋 test_config 案例6。 |
| GENCFG-06 | model 預設值 | unit | P1 | ✅ | = "google/gemini-3-flash-preview"。已覆蓋 test_config 案例1。 |
| GENCFG-07 | 自訂 model 可覆寫 | unit | P1 | ✅ | = 傳入值。已覆蓋 test_config 案例7。 |
| GENCFG-08 | OPENCLAW_MODEL 為空字串 → 回退預設 | unit | P2 | ✅ | = "google/gemini-3-flash-preview"（// 對空字串回退）。新增缺口：未覆蓋。 |
| GENCFG-09 | OPENCLAW_PUBLIC_URL 預設值 | unit | P1 | ✅ | allowedOrigins[0]="https://clawdbot.asia-east1.run.app"，audience="https://clawdbot.asia-east1.run.app/googlechat"。新增缺口：未 |
| GENCFG-10 | OPENCLAW_PUBLIC_URL 帶入 allowedOrigins[0] | unit | P0 | ✅ | = 該 URL。已覆蓋 test_config 案例2。 |
| GENCFG-11 | allowedOrigins 永遠含 localhost:8080 與 127.0.0.1:8080 | unit | P1 | ✅ | 陣列長度=3，含 "http://localhost:8080" 與 "http://127.0.0.1:8080"。新增缺口：未覆蓋。 |
| GENCFG-12 | googlechat audience = publicUrl + /googlechat | unit | P0 | ✅ | = <publicUrl>/googlechat。已覆蓋 test_config 案例2。 |
| GENCFG-13 | GOOGLE_CHAT_AUDIENCE 覆寫 audience（與 publicUrl 不同） | unit | P1 | ✅ | audience="https://b.example/googlechat"；allowedOrigins[0] 仍=https://a.run.app（兩者獨立）。新增缺口：未覆蓋。 |
| GENCFG-14 | GOOGLE_CHAT_AUDIENCE 為空字串 → 回退 publicUrl | unit | P2 | ✅ | = https://a.run.app/googlechat。新增缺口：未覆蓋。 |
| GENCFG-15 | GOOGLECHAT_ENABLED 預設啟用 | unit | P0 | ✅ | 含 channels.googlechat 區塊，enabled=true，webhookPath=/googlechat，audienceType=app-url，dm.policy=open，allowFrom=["*"]，groupP |
| GENCFG-16 | GOOGLECHAT_ENABLED=false → 無 googlechat | unit | P0 | ✅ | channels 不含 googlechat。已覆蓋 test_config 案例3。 |
| GENCFG-17 | GOOGLECHAT_ENABLED 各 truthy 值（1/true/yes/on/大小寫） | unit | P1 | ✅ | 每種皆含 googlechat 區塊（bool 正規表達式不分大小寫）。新增缺口：bool() 分支未測。 |
| GENCFG-18 | GOOGLECHAT_ENABLED 各 falsy/非法值（0/no/off/random） | unit | P1 | ✅ | 每種皆不含 googlechat（非匹配字串視為 false）。新增缺口：bool() 否定分支未測，尤其 'xyz' 任意字串。 |
| GENCFG-19 | GOOGLECHAT_ENABLED 為空字串 → 回退預設 true | unit | P2 | ✅ | 含 googlechat（空字串走 dflt=true）。新增缺口：未覆蓋。 |
| GENCFG-20 | 明確 GOOGLE_CHAT_SERVICE_ACCOUNT_FILE → serviceAccountFile 帶入 | unit | P1 | ✅ | = /secrets/sa.json。已覆蓋 test_config 案例5。 |
| GENCFG-21 | 未設 SA 檔且預設掛載路徑不存在 → 無 serviceAccountFile 欄位 | unit | P1 | ✅ | googlechat 無 serviceAccountFile 鍵（saFile 為空字串時不加入）。新增缺口：未明確斷言缺欄位。 |
| GENCFG-22 | SA 自動偵測 Cloud Run 慣用路徑 | integration | P2 | ✅ | .channels.googlechat.serviceAccountFile = /secrets/google-chat-sa/key.json。新增缺口：existsSync 自動偵測分支未測（需可寫 /secrets，建議在容器整合 |
| GENCFG-23 | 明確 SA 檔優先於自動偵測 | integration | P2 | ✅ | serviceAccountFile = /custom/sa.json（env 優先，不被偵測覆寫）。新增缺口：未覆蓋。 |
| GENCFG-24 | GOOGLECHAT_ENABLED=false 時 SA 檔不影響輸出 | unit | P2 | ✅ | 無 googlechat 區塊，亦無 serviceAccountFile 殘留。新增缺口：未覆蓋交互。 |
| GENCFG-25 | LINE 雙金鑰皆有 → 啟用 LINE 頻道 | unit | P0 | ✅ | 含 channels.line：enabled=true, channelSecret=s, channelAccessToken=t, webhookPath=/line, dmPolicy=open, allowFrom=["*"],  |
| GENCFG-26 | 僅 LINE_CHANNEL_SECRET（缺 ACCESS_TOKEN）→ 不啟用 LINE | unit | P0 | ✅ | channels 不含 line。新增缺口：負面案例未覆蓋。 |
| GENCFG-27 | 僅 LINE_CHANNEL_ACCESS_TOKEN（缺 SECRET）→ 不啟用 LINE | unit | P0 | ✅ | channels 不含 line。新增缺口：負面案例未覆蓋。 |
| GENCFG-28 | LINE 金鑰其一為空字串 → 不啟用 | unit | P1 | ✅ | channels 不含 line（空字串為 falsy）。新增缺口：未覆蓋邊界。 |
| GENCFG-29 | LINE 與 googlechat 可同時啟用 | unit | P1 | ✅ | channels 同時含 googlechat 與 line 兩區塊。新增缺口：未覆蓋共存。 |
| GENCFG-30 | LINE 啟用且 googlechat 停用 | unit | P2 | ✅ | channels 僅含 line，無 googlechat。新增缺口：未覆蓋。 |
| GENCFG-31 | 無任何頻道（googlechat 關 + 無 LINE）→ channels 為空物件 | unit | P1 | ✅ | .channels === {}（合法空物件），輸出仍為合法 JSON。新增缺口：未覆蓋。 |
| GENCFG-32 | trustedProxies 固定值 | unit | P2 | ✅ | = ["169.254.169.126","127.0.0.1"]。新增缺口：未覆蓋（Cloud Run metadata proxy 行為相關）。 |
| GENCFG-33 | controlUi 危險旗標固定為 true | unit | P1 | ✅ | 兩者皆 true。部分覆蓋（案例1僅測 dangerouslyDisableDeviceAuth）。 |
| GENCFG-34 | 寫入檔案模式（OPENCLAW_CONFIG_PATH） | unit | P0 | ✅ | 檔案被建立、內容為合法 JSON、結尾有換行；stderr 印 "wrote <path>"；stdout 無 JSON。部分覆蓋（案例8測檔案存在與合法，未測 stderr 訊息與換行）。 |
| GENCFG-35 | 寫檔模式內容尾端換行 | unit | P2 | ✅ | 檔尾為單一 \n（writeFileSync json + "\n"）。新增缺口：未覆蓋換行斷言。 |
| GENCFG-36 | --stdout 強制覆寫寫檔（同時設 OPENCLAW_CONFIG_PATH） | unit | P1 | ✅ | JSON 印到 stdout；$tmp/x.json 未被建立（forceStdout 優先）。新增缺口：--stdout override 分支未覆蓋。 |
| GENCFG-37 | 預設無 CONFIG_PATH 且無 --stdout → 印到 stdout | unit | P1 | ✅ | 完整 JSON 印至 stdout，exit 0。已隱含覆蓋（多數案例以 --stdout，但純預設 stdout 路徑未獨立測）。 |
| GENCFG-38 | 寫檔路徑不可寫 → 拋錯非零退出 | unit | P2 | ✅ | writeFileSync 拋例外，exit !=0，stderr 含錯誤。新增缺口：負面寫檔未覆蓋。 |
| GENCFG-39 | token 含特殊字元正確跳脫（雙引號/反斜線） | unit | P0 | ✅ | 輸出為合法 JSON 且解析回原始字串 a"b\c（JSON.stringify 正確跳脫）。新增缺口：跳脫核心保證未測。 |
| GENCFG-40 | OPENCLAW_PUBLIC_URL 含查詢字串/特殊字元跳脫 | unit | P1 | ✅ | 合法 JSON；allowedOrigins[0] 與 audience 解析回原值（含 & 與引號正確保留/跳脫）。新增缺口：未覆蓋。 |
| GENCFG-41 | LINE 金鑰含換行/控制字元跳脫 | unit | P2 | ✅ | 合法 JSON；channelSecret 解析回含換行原值（\n 跳脫）。新增缺口：未覆蓋。 |
| GENCFG-42 | 含非 ASCII（中文/emoji）值仍輸出合法 JSON | unit | P2 | ✅ | 合法 JSON，model.primary 解析回原 UTF-8 值。新增缺口：未覆蓋。 |
| GENCFG-43 | 輸出永遠是合法 JSON（跨多組環境變數組合） | unit | P0 | ✅ | 所有成功退出的組合 stdout/檔案皆通過 JSON.parse。部分覆蓋（案例1與8各測一次，缺組合矩陣）。 |
| GENCFG-44 | 冪等性：相同輸入產生相同輸出 | unit | P1 | ✅ | 兩次 stdout 位元組完全相同（無隨機/時間戳成分）。新增缺口：冪等性未覆蓋。 |
| GENCFG-45 | 冪等性：重複寫同一檔路徑覆寫且內容一致 | unit | P2 | ✅ | 第二次覆寫，內容與第一次完全相同，無附加/重複。新增缺口：未覆蓋。 |
| GENCFG-46 | JSON 縮排格式為 2 空白 | static | P2 | ✅ | 輸出為 pretty-print，縮排=2 空白（人類可讀，符合 entrypoint sed 遮蔽 token 假設）。新增缺口：未明確斷言格式。 |
| GENCFG-47 | entrypoint 整合：產生後通過 JSON 驗證並遮蔽 token | integration | P0 | ✅ | 印 "Config written"、token 顯示為 "***"、"exiting without starting gateway"，exit 0。已覆蓋 test_integration.sh CONFIG_ONLY 段。 |
| GENCFG-48 | entrypoint 整合：容器內設定含正確 token 與 allowedOrigins | integration | P1 | ✅ | 含傳入 token 與 OPENCLAW_PUBLIC_URL。已覆蓋 test_integration.sh 容器內設定段。 |
| GENCFG-49 | node --check 語法檢查 | static | P1 | ✅ | exit 0 無語法錯誤。已覆蓋 test_static.sh JS 語法段。 |
| GENCFG-50 | 無 node 環境 → 測試優雅跳過（非失敗） | manual | P2 | 手動 | 印 skipped 並以 finish 結束，不報 fail。已覆蓋 test_config.sh 開頭 command -v node 檢查。 |

### Image-build (deploy/Dockerfile：build 成功、--build-arg OPENCLAW_VERSION 生效、openclaw CLI 存在且版本正確、tini 為 PID1、.dockerignore 排除 .env/機密/tests、映像不含機密)（33）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| IMGBUILD-01 | Dockerfile 預設參數 build 成功 | integration | P0 | ✅ | build 結束 exit code 0，出現 'Successfully built / writing image'；映像 clawdbot-test 存在於 docker images。 |
| IMGBUILD-02 | build context 必須是 repo 根目錄（COPY extensions/ 才不會失敗） | integration | P1 | ✅ | build 失敗，錯誤指出 COPY extensions /app/extensions 找不到來源（COPY failed: ... extensions: not found），證明 context 必須為根目錄。 |
| IMGBUILD-03 | --build-arg OPENCLAW_VERSION 生效（安裝指定版本） | integration | P0 | ✅ | build 中 RUN `openclaw --version` 步驟成功；容器內 openclaw --version 輸出符合所傳入的 2026.6.1（版本字串相符）。 |
| IMGBUILD-04 | OPENCLAW_VERSION 不存在時 build 失敗（fail fast） | integration | P1 | ✅ | build 在 `npm install -g openclaw@0.0.0-...` 步驟失敗（npm ERR! 404 No matching version），整體 build 非 0 退出，不產生可用映像。 |
| IMGBUILD-05 | build-arg 覆寫不同於預設版本時確實改變安裝版本 | integration | P2 | ✅ | 兩映像回報的版本各自對應傳入的 build-arg，證明非寫死 2026.6.1。 |
| IMGBUILD-06 | openclaw CLI 存在且在 PATH（command -v） | integration | P0 | ✅ | command -v 回傳 openclaw 的絕對路徑（/usr/local/bin/openclaw），openclaw --version 退出碼 0 且印出版本。 |
| IMGBUILD-07 | tini 已安裝且為 ENTRYPOINT 第一個元素 | static | P0 | ✅ | apt-get install 行含 tini；ENTRYPOINT 首元素為 /usr/bin/tini，第二為 --，第三為 entrypoint.sh。 |
| IMGBUILD-08 | tini 二進位存在於映像且路徑正確 | integration | P1 | ✅ | /usr/bin/tini 存在且可執行；tini --version 回傳版本字串、退出碼 0。 |
| IMGBUILD-09 | 執行時 PID 1 為 tini | integration | P0 | ✅ | PID 1 的指令名為 tini（非 entrypoint.sh、非 node），證明 tini 為 init 程序。 |
| IMGBUILD-10 | tini 正確傳遞 SIGTERM 使 gateway 優雅結束（Cloud Run 縮容情境） | integration | P1 | ✅ | 容器收到 SIGTERM 後迅速且乾淨結束（退出碼非 137 強殺），證明 tini 已把訊號轉發給子程序。 |
| IMGBUILD-11 | entrypoint.sh 已被 COPY 且具可執行權限 | integration | P1 | ✅ | /app/deploy/entrypoint.sh 存在且權限含可執行位（Dockerfile chmod +x 生效）。 |
| IMGBUILD-12 | gen-config.mjs 已被 COPY 到映像內 | integration | P1 | ✅ | /app/deploy/gen-config.mjs 存在且為合法 JS（node --check 退出碼 0）。 |
| IMGBUILD-13 | extensions/ 內容存在於映像（nano-banana 技能） | integration | P0 | ✅ | /app/extensions/nano-banana/nano-banana.skill.md 應存在於映像。注意：.dockerignore 的 `*.md`（僅 `!README.md` 例外）會把此 .skill.md 排除於 bu |
| IMGBUILD-14 | .dockerignore 排除 .env 與 .env.*（機密不進 context/映像） | integration | P0 | ✅ | 映像內任何路徑皆找不到 .env 或 .env.*；證明 .dockerignore 已將其排除於 build context。 |
| IMGBUILD-15 | .dockerignore 排除金鑰與 SA JSON（*.key、*-sa.json） | integration | P0 | ✅ | 映像內找不到放在 repo 的 *.key 或 *-sa.json；事後清理假檔。 |
| IMGBUILD-16 | .dockerignore 排除 tests/ docs/ demo/ examples/ | integration | P1 | ✅ | 映像 /app 下不存在 tests、docs、demo、examples 目錄（皆被 .dockerignore 排除，且 Dockerfile 本就未 COPY）。 |
| IMGBUILD-17 | .dockerignore 排除 .git 目錄 | integration | P1 | ✅ | 映像內無 .git 目錄（ABSENT），避免 git 歷史/機密外洩並縮小 context。 |
| IMGBUILD-18 | .dockerignore 規則靜態完整性檢查 | static | P1 | ✅ | .dockerignore 含上述所有機密與測試排除規則；額外標記 `*.md` 與 `!README.md` 並存會誤殺 extensions/*.skill.md（見 IMGBUILD-13）。 |
| IMGBUILD-19 | 映像不含 build-arg/ENV 形式的明文機密 | integration | P0 | ✅ | history 與 image Env 內無任何 Gemini 金鑰、gateway token 或 SA 內容（機密僅於執行期由 Cloud Run env/Secret 注入，不烘進映像）；ENV 僅 NODE_ENV/PORT/OPE |
| IMGBUILD-20 | 映像層檔案系統全域掃描無機密殘留 | integration | P1 | ✅ | 掃描結果為空：/app 與映像層內無 API 金鑰、私鑰、LINE access token 等機密樣式。 |
| IMGBUILD-21 | ENV 預設值正確（NODE_ENV/PORT/OPENCLAW_HOME） | integration | P2 | ✅ | ENV 含 NODE_ENV=production、PORT=8080、OPENCLAW_HOME=/root/.openclaw；無多餘機密類變數。 |
| IMGBUILD-22 | EXPOSE 8080 與 WORKDIR /app 設定正確 | static | P2 | ✅ | Dockerfile 宣告 EXPOSE 8080 且 WORKDIR /app；與 Cloud Run --port=8080 一致。 |
| IMGBUILD-23 | 執行期相依套件（git、ca-certificates）已安裝 | integration | P1 | ✅ | git 在 PATH 且可執行；ca-certificates 套件已裝（ca-certificates.crt 存在），確保 agent 與 HTTPS 功能可用。 |
| IMGBUILD-24 | apt 快取已清理（縮小映像、無 /var/lib/apt/lists 殘留） | integration | P2 | ✅ | /var/lib/apt/lists 為空（行數 0），證明 Dockerfile 的 rm -rf 生效，未把 apt index 帶進映像。 |
| IMGBUILD-25 | 基底映像為釘選的 node:22-bookworm-slim | static | P2 | ✅ | FROM 使用 node:${NODE_VERSION}，NODE_VERSION 預設 22-bookworm-slim（已釘 major 與 distro，未用 latest）。 |
| IMGBUILD-26 | build 冪等性：重複 build 結果一致且可重現 | integration | P2 | ✅ | 兩次 build 皆成功、安裝版本相同、/app 結構相同；第二次出現 'Using cache'，證明步驟具決定性與冪等。 |
| IMGBUILD-27 | build 後映像可被 Cloud Build 流程的 push/deploy 接手（tag 命名一致） | static | P1 | ✅ | cloudbuild build step 使用 deploy/Dockerfile、傳遞 OPENCLAW_VERSION build-arg、context 為根目錄，且 build/push/images tag 三者一致。 |
| IMGBUILD-28 | Makefile build-local 與 Dockerfile/Cloud Build 參數一致 | static | P2 | ✅ | build-local 使用同一 Dockerfile、同一 build-arg 名稱與根目錄 context；OPENCLAW_VERSION 預設與 .env.example/cloudbuild 一致（2026.6.1）。 |
| IMGBUILD-29 | no-cache 全新環境 build 成功（不依賴本機 layer cache） | integration | P1 | ✅ | 在無快取、重新 pull 基底映像下 build 仍成功，模擬 Cloud Build 乾淨環境；npm install 與 openclaw --version 步驟皆通過。 |
| IMGBUILD-30 | build context 大小合理（.dockerignore 有效縮小傳輸） | manual | P2 | 手動 | context 大小遠小於整個 repo（不含 .git/node_modules/tests/demo），證明 .dockerignore 有效，避免 Cloud Build 上傳過大或機密。 |
| IMGBUILD-31 | hadolint Dockerfile 最佳實務檢查（既有，選用） | static | P2 | ✅ | hadolint 無 error 級告警；pin apt 套件版本等 warning 可評估。已被 test_static.sh 覆蓋（條件式）。 |
| IMGBUILD-32 | Dockerfile 與所有 *.sh 語法靜態檢查（既有覆蓋） | static | P1 | ✅ | deploy/Dockerfile 存在性已被 test_static.sh 覆蓋；本維度的版本/PID1/dockerignore/機密項目尚未覆蓋，屬新增缺口。 |
| IMGBUILD-33 | 整合測試現況：僅覆蓋 build 成功（缺口盤點） | integration | P0 | ✅ | 確認既有測試僅覆蓋 IMGBUILD-01（build 成功）；IMGBUILD-03/06/07/09/13/14/15/19 等版本、tini PID1、dockerignore、機密項目均為新增缺口，建議補入 test_integra |

### Installation（53）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| INSTALL-01 | cp .env.example .env 產生可用設定檔 | manual | P0 | ✅ | .env 被建立；包含所有必要鍵（GCP_PROJECT_ID、GCP_REGION、AR_REPO_NAME、SERVICE_NAME、IMAGE_TAG、OPENCLAW_VERSION、GEMINI_API_KEY、OPENCLAW_ |
| INSTALL-02 | .env.example 所有行皆為合法 KEY=VALUE 或註解 | static | P1 | ✅ | 每行符合 ^[A-Z][A-Z0-9_]*= 或為註解/空行；無非法行，避免 source/include 失敗 |
| INSTALL-03 | Makefile 會自動 include 並 export .env | integration | P1 | ✅ | make 正確載入 .env，help 末行顯示 project 等於 .env 中的值（驗證 include/export 生效） |
| INSTALL-04 | 無 .env 時 check-env 應失敗並提示 cp | unit | P0 | ✅ | exit 非零；輸出『找不到 .env，請先：cp .env.example .env』 |
| INSTALL-05 | GCP_PROJECT_ID 未設時 check-env 應失敗 | unit | P0 | ✅ | exit 非零；輸出『GCP_PROJECT_ID 未設』 |
| INSTALL-06 | check-env 通過時印出 OK | unit | P1 | ✅ | exit 0；輸出『✓ .env OK（project=demo）』，無 token 警告 |
| INSTALL-07 | check-env：GCP_PROJECT_ID 有值但 token 未設只警告不失敗 | unit | P1 | ✅ | exit 0；輸出 ⚠ token 未設警告，但仍判定 OK（不阻擋部署） |
| INSTALL-08 | check-env 對 placeholder 值（your-project-id）的處理（負面/已知缺口） | unit | P2 | ✅ | 目前 -n 檢查會放行佔位字串 your-project-id（視為已知缺口）。建議新增：偵測未替換佔位值並警告/失敗。記錄為缺口 |
| INSTALL-09 | gen-token：.env 無 token 行時 append | unit | P0 | ✅ | 在 .env 末尾新增一行 OPENCLAW_GATEWAY_TOKEN=<64 hex>；輸出『✓ 已寫入』 |
| INSTALL-10 | gen-token：.env 已有空 token 行時就地替換 | unit | P0 | ✅ | 原 OPENCLAW_GATEWAY_TOKEN= 被替換為含 64 hex 值；不重複新增第二行；無殘留 .env.bak |
| INSTALL-11 | gen-token 產生值為 64 字元 hex | unit | P1 | ✅ | token 為 openssl rand -hex 32 → 恰 64 個小寫十六進位字元 |
| INSTALL-12 | gen-token 冪等性：連續執行兩次 | unit | P0 | ✅ | .env 中 token 行仍只有一行（不累加）；值每次重新隨機（A≠B 屬正常）；無 .env.bak 殘留 |
| INSTALL-13 | gen-token 不依賴 GCP_PROJECT_ID（無 check-env 前置） | unit | P2 | ✅ | 成功寫入 token（gen-token 無 check-env 依賴，可在填 project 前先產生） |
| INSTALL-14 | gen-token：無 .env 時的行為（負面/邊界） | unit | P2 | ✅ | 因 grep ...2>/dev/null 失敗走 else 分支，echo >> .env 會建立只含 token 的 .env。需確認此行為可接受（缺其他鍵，後續 check-env 仍會擋 project）。記錄為邊界行為 |
| INSTALL-15 | gen-token 的 sed -i.bak 在 macOS(BSD) 與 Linux(GNU) 皆可用 | integration | P1 | ✅ | 使用 sed -i.bak 寫法在 BSD/GNU sed 皆相容；替換成功且清除 .bak |
| INSTALL-16 | bootstrap 依序執行 enable-apis 與 create-repo | manual | P0 | 手動 | 先啟用 run/cloudbuild/artifactregistry/secretmanager 四個 API，再建立 Artifact Registry repo；兩步皆成功 |
| INSTALL-17 | bootstrap 前置：未填 GCP_PROJECT_ID 時被 check-env 擋下 | unit | P1 | ✅ | 在 check-env 階段即 exit 非零，不呼叫 gcloud |
| INSTALL-18 | enable-apis 啟用四個必要 API | live | P0 | ✅ | run.googleapis.com、cloudbuild.googleapis.com、artifactregistry.googleapis.com、secretmanager.googleapis.com 皆為 enabled |
| INSTALL-19 | create-repo 冪等性（repo 已存在不報錯） | live | P1 | ✅ | 因結尾 // true，重複建立時 exit 0、不中斷流程（冪等） |
| INSTALL-20 | create-repo 在指定 region 建立 docker 格式庫 | live | P1 | ✅ | 建立名為 clawdbot-repo、format=docker、location=asia-east1 的庫 |
| INSTALL-21 | bootstrap 冪等性：整體重跑 | live | P1 | ✅ | enable-apis 對已啟用 API 為 no-op、create-repo 走 // true；整體 exit 0 無副作用 |
| INSTALL-22 | secret-set-gemini 缺 KEY 參數應失敗 | unit | P0 | ✅ | exit 非零；輸出『✗ 請提供 KEY，例如：make secret-set-gemini KEY=AIza...』 |
| INSTALL-23 | secret-set-gemini 首次建立 secret | live | P0 | ✅ | 建立 secret 名為 gemini-api-key 並寫入版本；值等於提供的 KEY（printf '%s' 無尾端換行）；輸出『✓ gemini-api-key 已更新』 |
| INSTALL-24 | secret-set-gemini 冪等性：secret 已存在時新增版本 | live | P0 | ✅ | create 失敗（2>/dev/null）後走 versions add 分支，新增新版本而非報錯；latest 版本值為 AIzaNEW |
| INSTALL-25 | secret-set-gemini 寫入值不含尾端換行 | live | P1 | ✅ | 值與 KEY 完全相同、無附加 \n（使用 printf '%s'），避免 API 金鑰帶換行導致驗證失敗 |
| INSTALL-26 | secret-set-gemini 前置 check-env 擋未填 project | unit | P2 | ✅ | check-env 先擋下，exit 非零，不呼叫 gcloud secrets |
| INSTALL-27 | deploy：Gemini 金鑰解析優先用 .env 值 | manual | P1 | 手動 | resolve_gemini 取 .env 的 GEMINI_API_KEY；不去 Secret Manager 查 |
| INSTALL-28 | deploy：.env 無 GEMINI_API_KEY 時回退 Secret Manager | manual | P0 | 手動 | resolve_gemini 執行 gcloud secrets versions access latest 取值並帶入 _GEMINI_API_KEY |
| INSTALL-29 | deploy：.env 與 Secret Manager 皆無 Gemini 金鑰（負面/邊界） | manual | P1 | 手動 | _GEMINI_API_KEY 解析為空字串，仍會提交 build（不中斷）；部署後容器無金鑰會在執行期失敗。記錄為缺口：deploy 未對缺金鑰預警 |
| INSTALL-30 | deploy：透過 cloudbuild 完成 build→push→deploy | live | P0 | 手動 | docker-auth→build→push→deploy 四步成功；映像推上 Artifact Registry；Cloud Run 服務 clawdbot 建立並就緒（約 3 分鐘，非 30 分鐘卡死） |
| INSTALL-31 | deploy 後自動執行 allow-public | live | P0 | 手動 | deploy recipe 末尾 $(MAKE) allow-public 被執行，補上 allUsers→run.invoker |
| INSTALL-32 | deploy substitutions 正確傳遞所有參數 | static | P1 | ✅ | Makefile 傳遞的每個 substitution 在 cloudbuild.yaml 都有對應宣告，名稱一致、無遺漏（避免 unknown substitution 錯誤） |
| INSTALL-33 | cloudbuild.yaml 設定值正確（port/timeout/env-vars/min-instances） | static | P1 | ✅ | deploy 參數與 Dockerfile EXPOSE 8080、entrypoint PORT 一致；env-vars 完整 |
| INSTALL-34 | 首次部署時 OPENCLAW_PUBLIC_URL 為空的雞生蛋問題 | manual | P1 | 手動 | gen-config 對空 URL 使用預設值 https://clawdbot.asia-east1.run.app；服務可起，但 allowedOrigins/audience 尚不正確 → 需後續 refresh-url + 再 de |
| INSTALL-35 | refresh-url 取得實際 URL 並寫回 .env | live | P0 | 手動 | 以 run services describe 取得 status.url，sed 就地替換 .env 的 OPENCLAW_PUBLIC_URL；無 .env.bak 殘留；輸出含實際 URL |
| INSTALL-36 | refresh-url 同步更新 Cloud Run 服務環境變數 | live | P0 | 手動 | 執行 run services update --update-env-vars=OPENCLAW_PUBLIC_URL=<url>，服務環境變數被更新為實際 URL |
| INSTALL-37 | refresh-url 取不到 URL 時失敗 | manual | P1 | 手動 | u 為空 → exit 非零、輸出『✗ 取不到 URL』，不執行 sed 與 update |
| INSTALL-38 | refresh-url 後再 deploy：URL 正確帶入設定 | manual | P0 | 手動 | allowedOrigins[0] 與 googlechat audience 皆為實際 Cloud Run URL；解決首次部署的 403/origin 問題 |
| INSTALL-39 | refresh-url 冪等性：URL 未變時重跑 | live | P2 | 手動 | OPENCLAW_PUBLIC_URL 行不重複、值不變；服務 update 為 no-op 或無害；無 .env.bak |
| INSTALL-40 | allow-public 加上 allUsers→run.invoker | live | P0 | 手動 | add-iam-policy-binding 成功，bindings 含 member=allUsers、role=roles/run.invoker；之後 / 回 200 而非 403(Google Frontend) |
| INSTALL-41 | allow-public 冪等性：重複綁定 | live | P1 | 手動 | 重複加同一 binding 不報錯（gcloud 視為已存在）；exit 0 |
| INSTALL-42 | allow-public 在缺 IAM 權限時的行為（負面） | manual | P2 | 手動 | gcloud 回 PERMISSION_DENIED、exit 非零並有清楚錯誤；提示需用擁有者帳號（呼應 README 說明 Cloud Build SA 無權） |
| INSTALL-43 | GCP_ACCOUNT 帶入 gcloud --account 旗標 | static | P2 | ✅ | GCP_ACCOUNT 非空時所有 gcloud 指令帶 --account=<值>；空時不帶該旗標（多帳號區分正確） |
| INSTALL-44 | 整合：容器啟動產生並驗證 openclaw.json（既有覆蓋） | integration | P0 | ✅ | 已由 test_integration.sh 覆蓋：CONFIG_ONLY 印出 config 路徑、token 遮蔽、正常結束；驗證安裝產物（設定檔）正確 |
| INSTALL-45 | 整合：映像可建置且 gateway 可啟動（既有覆蓋） | integration | P0 | ✅ | 已由 test_integration.sh 覆蓋：docker build 成功、gateway listening、/=200、token 401/200 行為、容器內設定含正確 token 與 publicUrl |
| INSTALL-46 | Dockerfile 安裝指定版本 OpenClaw 並驗版 | static | P1 | ✅ | 安裝預編譯套件（非原始碼 build），版本由 build-arg 控制，--version 作為安裝成功的 fail-fast 檢查 |
| INSTALL-47 | .gitignore/.dockerignore/.gcloudignore 確保機密不外洩（既有部分覆蓋） | static | P1 | ✅ | 安裝過程產生的機密（.env、SA JSON、token 檔）不進 git、不進映像、不進 build context；建議補測 .dockerignore/.gcloudignore（目前 test_static 僅查 .gitignor |
| INSTALL-48 | 靜態：必要安裝檔案結構齊全（既有覆蓋） | static | P1 | ✅ | 已覆蓋：README/LICENSE/Makefile/.env.example/三個 ignore/deploy 四檔/scripts/tests 皆存在；舊 Dockerfile.cloudrun 已移除 |
| INSTALL-49 | 全新安裝端到端（happy path） | manual | P0 | 手動 | 全流程無錯；服務就緒、/=200、token Bearer=200/無token=401；dashboard-url 可用無痕視窗開啟；端到端驗證一鍵安裝可用 |
| INSTALL-50 | 安裝順序顛倒的防呆（在 bootstrap 前 deploy） | manual | P2 | 手動 | Cloud Build 因 API 未啟用或 Artifact Registry 不存在而失敗，回傳清楚錯誤（push 階段找不到 repo）；記錄為使用者錯誤情境，建議 deploy 前可選擇性檢查 repo 是否存在（潛在改善） |
| INSTALL-51 | live 煙霧測試讀 .env URL+token（既有覆蓋） | live | P1 | ✅ | 已由 test_live.sh 覆蓋：URL/token 缺則 skip、不可連則 skip；/=200、Bearer=200、無 token=401。作為安裝後驗收 |
| INSTALL-52 | min-instances 設定（安裝後常駐確保） | live | P2 | 手動 | 服務 minScale=1；減少冷啟動與回覆中斷（呼應 .env MIN_INSTANCES 預設 1） |
| INSTALL-53 | OPENCLAW_GATEWAY_TOKEN 未在 .env 設時部署的隨機 token 行為 | manual | P1 | 手動 | cloudbuild 帶空 token → 容器 entrypoint 自動產生隨機 64hex；但 .env/dashboard-url 仍為空 token，Dashboard 無法用正確 token 連（token_mismatch）。 |

### Reinstall-Teardown-Idempotency（重新安裝、移除/teardown、重複執行冪等性、create-repo 已存在行為）（37）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| IDEMP-01 | create-repo 對已存在的 Artifact Registry 庫應冪等（不報錯） | unit | P0 | ✅ | 兩次 `make create-repo` 皆 exit 0（因 recipe 尾端 `// true`）；不因庫已存在而中斷部署流程。 |
| IDEMP-02 | create-repo 首次建立成功路徑 | unit | P1 | ✅ | exit 0，且實際呼叫了 `gcloud artifacts repositories create $(AR_REPO_NAME) --repository-format=docker --location=$(GCP_REGION)` |
| IDEMP-03 | bootstrap 重複執行冪等（enable-apis + create-repo 連跑兩次不壞） | unit | P0 | ✅ | 兩次皆 exit 0；enable-apis（gcloud services enable 本身冪等）與 create-repo（`// true`）皆不因重跑而失敗。 |
| IDEMP-04 | secret-set-gemini 首次建立 secret（create 路徑） | unit | P1 | ✅ | exit 0；走 `secrets create gemini-api-key --data-file=-` 分支；印出「✓ gemini-api-key 已更新」。 |
| IDEMP-05 | secret-set-gemini 對已存在 secret 應 fallback 為 add version（冪等可重跑 | unit | P0 | ✅ | create 失敗時自動 `// printf ... / gcloud secrets versions add gemini-api-key --data-file=-`；兩次皆 exit 0 並印「✓ gemini-api-key 已 |
| IDEMP-06 | secret-set-gemini 缺 KEY 參數應失敗（負面） | unit | P1 | ✅ | exit 非零，印出「✗ 請提供 KEY，例如：make secret-set-gemini KEY=AIza...」；不呼叫 gcloud。 |
| IDEMP-07 | gen-token 首次（.env 無此鍵）→ append 新行 | unit | P1 | ✅ | `.env` 結尾 append 一行 `OPENCLAW_GATEWAY_TOKEN=<64 hex>`；token 長度為 64 hex（openssl rand -hex 32）；exit 0。 |
| IDEMP-08 | gen-token 已存在鍵 → sed 就地替換（不重複新增行） | unit | P0 | ✅ | `.env` 中 `^OPENCLAW_GATEWAY_TOKEN=` 永遠只出現一次（sed 就地替換而非 append）；無殘留 `.env.bak`；每次都產生新值。 |
| IDEMP-09 | gen-token 重跑的破壞性風險：會覆蓋既有 token（語意冪等性負面案例） | unit | P1 | ✅ | 記錄事實：`gen-token` 每次都產生【不同】token，重跑屬破壞性（會使既有 Dashboard/已部署服務 token 失聯）。AC：確認重跑後 token 改變 → 文件需警告「已部署後勿重跑 gen-token，否則需重新  |
| IDEMP-10 | refresh-url 就地替換 OPENCLAW_PUBLIC_URL（冪等、單一鍵） | unit | P0 | ✅ | `^OPENCLAW_PUBLIC_URL=` 只出現一次並被替換為 describe 取得的 URL；無殘留 `.env.bak`；兩次皆 exit 0；第二次值不變（冪等）。 |
| IDEMP-11 | refresh-url 取不到 URL 時應 fail fast | unit | P1 | ✅ | exit 非零，印「✗ 取不到 URL」；不會把空值寫回 .env、不呼叫 update-env-vars。 |
| IDEMP-12 | allow-public 重複執行冪等（IAM binding 可重複套用） | unit | P1 | ✅ | 兩次皆 exit 0；add-iam-policy-binding 對 allUsers→roles/run.invoker 重複套用不報錯（GCP 本身冪等）；確認帶 --member=allUsers --role=roles/run. |
| IDEMP-13 | deploy 重跑（同 IMAGE_TAG）冪等：以相同 tag 覆蓋映像並重新部署 revision | unit | P0 | ✅ | 兩次皆成功；builds submit 帶相同 substitutions；deploy 結尾自動呼叫 allow-public；重跑不會因 tag 已存在而失敗（同 tag 覆蓋為設計行為）。 |
| IDEMP-14 | deploy 解析 Gemini 金鑰：.env 有值用 .env，否則自 Secret Manager 取（resol | unit | P2 | ✅ | 有值 → _GEMINI_API_KEY 用 .env 值；空值 → 走 `gcloud secrets versions access latest --secret=gemini-api-key`；兩種情境重跑結果一致。 |
| IDEMP-15 | entrypoint 重複產生設定冪等：重啟容器覆寫 openclaw.json，內容與初次一致 | integration | P0 | ✅ | 同輸入產生的 openclaw.json 內容【完全相同】（deterministic）；重跑覆寫不報錯；JSON 合法。 |
| IDEMP-16 | entrypoint 對既有 OPENCLAW_HOME（已有舊 openclaw.json）重跑：覆寫而非附加/損毀 | integration | P1 | ✅ | openclaw.json 被【整檔覆寫】為 TOKEN_B 的內容（writeFileSync 非 append）；無多份 config、無 JSON 解析錯誤；mkdir -p 對既有目錄冪等。 |
| IDEMP-17 | run-local 重複啟動冪等（先 docker rm -f 再 run） | integration | P1 | ✅ | 第二次因 recipe 內 `-docker rm -f $(LOCAL_NAME)` 先移除舊容器再啟動，不因『name already in use』失敗；容器最終為單一新實例並 listening。 |
| IDEMP-18 | stop-local 對不存在容器仍成功（冪等 teardown） | integration | P1 | ✅ | exit 0（recipe 用 `-docker rm -f` 前綴忽略錯誤）；對不存在容器不報致命錯誤。 |
| IDEMP-19 | clean 重複執行冪等（移除測試容器與 tests/.tmp） | integration | P1 | ✅ | 兩次皆 exit 0，印「✓ cleaned」；移除 clawdbot-local 與 clawdbot-test 容器、刪除 tests/.tmp；對不存在標的不報錯。 |
| IDEMP-20 | clean 不會誤刪 .env / 機密 / 原始檔（teardown 範圍邊界） | static | P0 | ✅ | clean 不含刪除 .env、secrets、deploy/、extensions/ 等；`rm -rf` 僅限 `tests/.tmp`（防止過度刪除）。 |
| IDEMP-21 | 整合測試自身 teardown 冪等（trap cleanup + 起頭 cleanup） | static | P1 | ✅ | 測試前先清掉殘留同名容器、結束時 trap 清理；重跑整合測試不因前次殘留容器而失敗（已覆蓋，標為現有覆蓋）。 |
| TEAR-01 | 缺口：無 Cloud Run 服務移除目標（make destroy/delete-service） | static | P0 | ✅ | 目前【不存在】teardown 目標。AC（缺口）：應新增 `delete-service`（`gcloud run services delete $(SERVICE_NAME) --region=$(GCP_REGION) --quie |
| TEAR-02 | 缺口：無 Artifact Registry 庫移除目標（teardown 殘留映像） | static | P1 | ✅ | 目前無。AC（缺口）：應提供刪除映像庫目標，且對不存在庫冪等；文件需提醒刪庫前先刪服務以免破壞回滾。標為【新增缺口】。 |
| TEAR-03 | 缺口：無 Secret Manager secret 移除目標（gemini-api-key 殘留） | static | P2 | ✅ | 目前無。AC（缺口）：應提供刪除 secret（或其版本）目標，對不存在 secret 冪等。標為【新增缺口】。 |
| TEAR-04 | 缺口：無移除 allUsers IAM binding 的回收目標 | static | P2 | ✅ | 目前需手動跑 `gcloud run services update --no-allow-unauthenticated`（README 維運表）；無對稱 Makefile 目標。AC（缺口）：宜新增 `remove-public`（re |
| TEAR-05 | 完整 teardown 後可乾淨重裝（reinstall round-trip） | live | P0 | 手動 | teardown 後資源確實消失（describe 回 NOT_FOUND）；重新安裝全程成功；test-live 全綠；新服務 URL/token 正常。屬手動 live 驗收。 |
| REINST-01 | reinstall：未先 teardown 直接重跑 bootstrap+deploy（覆蓋式重裝冪等） | live | P0 | 手動 | bootstrap 因 create-repo `// true` + enable-apis 冪等而成功；deploy 以同 tag 覆蓋映像、滾出新 revision、自動 allow-public；服務持續可用無中斷（min-inst |
| REINST-02 | reinstall：變更 IMAGE_TAG 後重部署（新 tag 並存，舊 revision 仍可回滾） | live | P1 | 手動 | AR 中 v1 與 v2 映像並存；Cloud Run 指向 v2 新 revision；可回滾到舊 revision；重裝不破壞既有 tag。 |
| REINST-03 | reinstall：升級 OPENCLAW_VERSION 後重 build/部署 | live | P2 | 手動 | 映像以新版 npm openclaw 重建並部署成功；版本變更生效；舊設定（openclaw.json 由 entrypoint 重新產生）相容。 |
| REINST-04 | reinstall：refresh-url 後第二次 deploy 帶入正確 PUBLIC_URL（首裝兩段式流程冪等） | integration | P1 | ✅ | 第二次 deploy 的 _OPENCLAW_PUBLIC_URL 等於 refresh-url 取得值；allowedOrigins/audience 因此正確；此「deploy→refresh-url→deploy」流程可重跑而結果穩定 |
| REINST-05 | reinstall：本機 build-local 重複建置以相同 LOCAL_NAME 覆蓋映像 | integration | P2 | ✅ | 兩次皆成功；以同 tag 覆蓋本機映像 clawdbot-local；重建冪等不報錯。 |
| EDGE-01 | 邊界：check-env 缺 .env 時所有部署/teardown 前置一致 fail | unit | P1 | ✅ | 皆 exit 非零，印「✗ 找不到 .env，請先：cp .env.example .env」；保證冪等流程的前置防呆一致。 |
| EDGE-02 | 邊界：check-env 有 .env 但缺 GCP_PROJECT_ID 應失敗 | unit | P2 | ✅ | exit 非零，印「✗ GCP_PROJECT_ID 未設」。 |
| EDGE-03 | 邊界：未設 OPENCLAW_GATEWAY_TOKEN 時 deploy 與 entrypoint 行為一致（自動產生 | integration | P2 | ✅ | entrypoint 印「Generated random OPENCLAW_GATEWAY_TOKEN」並產生 64 hex token；config 合法。注意：此情境下每次重啟 token 變動（非冪等），Dashboard 無法預知 |
| EDGE-04 | 邊界：sed 就地編輯在 macOS/Linux 的相容性（gen-token/refresh-url 使用 -i.ba | static | P1 | ✅ | 使用 `-i.bak` 形式（BSD/macOS 與 GNU sed 皆相容）並於成功後刪除 .bak；重跑不留 .env.bak 殘留（冪等清理）。 |
| EDGE-05 | 負面：deploy 中途 builds submit 失敗不應呼叫 allow-public | unit | P1 | ✅ | deploy 因 builds submit 非零而中止（recipe 兩條指令，第一條失敗即停）；不誤呼叫 allow-public；重跑失敗的 deploy 不會留下半套不一致狀態。 |
| EDGE-06 | 負面：refresh-url 寫回時若 .env 無 OPENCLAW_PUBLIC_URL 行的 sed 行為 | unit | P1 | ✅ | 記錄事實：refresh-url 用 sed 替換 `^OPENCLAW_PUBLIC_URL=.*`，若該行不存在則【不會新增】（與 gen-token 的 append fallback 不同）→ 後續 deploy 取不到 PUBLI |

### Deployment-CloudRun（58）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| CR-SUBST-01 | cloudbuild.yaml 宣告全部 13 個 substitutions 預設值 | static | P0 | ✅ | 恰好包含 _GCP_PROJECT_ID,_GCP_REGION,_AR_REPO_NAME,_SERVICE_NAME,_TAG,_OPENCLAW_VERSION,_GEMINI_API_KEY,_OPENCLAW_GATEWAY_TO |
| CR-SUBST-02 | Makefile deploy 帶入的 substitutions 與 cloudbuild.yaml 宣告完全對應 | static | P0 | ✅ | Makefile 帶入的 12 個 _KEY（除 build-arg 外）全部存在於 cloudbuild.yaml；無多餘也無遺漏的 key（避免 'key in substitution map not matched in templ |
| CR-SUBST-03 | 每個 substitution 在 steps/images 區塊都實際被引用 | static | P0 | ✅ | _GCP_PROJECT_ID/_GCP_REGION/_AR_REPO_NAME/_SERVICE_NAME/_TAG 用於 image 名與 deploy；_OPENCLAW_VERSION 用於 build-arg；_GEMINI_A |
| CR-SUBST-04 | 映像名稱在 build/push/deploy/images 四處完全一致 | static | P0 | ✅ | 四處皆為 ${_GCP_REGION}-docker.pkg.dev/${_GCP_PROJECT_ID}/${_AR_REPO_NAME}/${_SERVICE_NAME}:${_TAG}，字串完全相同（確保 push 與 deploy  |
| CR-SUBST-05 | Makefile IMAGE 變數與 cloudbuild 映像格式一致 | static | P1 | ✅ | 兩者欄位順序與分隔符一致，本機 build-local 與雲端 build 推到相同 AR 路徑格式。 |
| CR-FLAG-01 | deploy step 含 --platform=managed | static | P0 | ✅ | 存在 --platform=managed（避免 gcloud 互動式詢問 platform 導致 build 失敗）。 |
| CR-FLAG-02 | deploy step --port=8080 與 Dockerfile EXPOSE/ENV PORT 一致 | static | P0 | ✅ | 三者皆為 8080（容器監聽埠與 Cloud Run 路由埠一致，否則 revision 健康檢查失敗）。 |
| CR-FLAG-03 | deploy step --memory 由 _MEMORY 帶入且預設 2Gi | static | P0 | ✅ | --memory=${_MEMORY} 存在；預設 2Gi 與 .env.example 一致。 |
| CR-FLAG-04 | deploy step --cpu 由 _CPU 帶入且預設 1 | static | P0 | ✅ | --cpu=${_CPU} 存在；預設 1。 |
| CR-FLAG-05 | deploy step --min-instances 由 _MIN_INSTANCES 帶入且預設 1 | static | P0 | ✅ | --min-instances=${_MIN_INSTANCES} 存在；預設 1（避免冷啟動造成回覆中斷）。 |
| CR-FLAG-06 | deploy step 含 --timeout=300 | static | P1 | ✅ | --timeout=300 存在（長對話/串流回覆需要較長請求逾時）。 |
| CR-FLAG-07 | deploy step 含 --project=${_GCP_PROJECT_ID} | static | P1 | ✅ | 存在；確保部署落在指定專案而非 gcloud 預設專案。 |
| CR-FLAG-08 | deploy step 含 --region=${_GCP_REGION} | static | P0 | ✅ | 存在；與 AR repo location、Makefile GCP_REGION 一致（asia-east1）。 |
| CR-FLAG-09 | 硬編碼旗標（port/timeout）不可被 substitution 化導致漂移 | static | P2 | 手動 | port=8080 與 timeout=300 為刻意硬編碼，文件已說明；無與其他檔案不一致之處。 |
| CR-ENV-01 | --set-env-vars 恰含 4 個執行期環境變數 | static | P0 | ✅ | 恰為 GEMINI_API_KEY,OPENCLAW_GATEWAY_TOKEN,OPENCLAW_PUBLIC_URL,OPENCLAW_MODEL 四個，且各自對應 ${_GEMINI_API_KEY} 等 substitution。 |
| CR-ENV-02 | --set-env-vars 用逗號分隔且無多餘空白/換行 | static | P0 | ✅ | 格式為 KEY=val,KEY=val,... 單行；不含空白導致 gcloud 解析錯誤。 |
| CR-ENV-03 | GOOGLECHAT_ENABLED / LINE_* 未被帶入 Cloud Run env-vars（已知缺口） | static | P0 | ✅ | 記錄為設計缺口：這些變數 gen-config.mjs 會讀取，但 cloudbuild/Makefile 並未把它們注入 Cloud Run 容器，導致雲端部署時 LINE/Google Chat 開關無法經由 .env 生效。測試應斷言 |
| CR-ENV-04 | OPENCLAW_MODEL 自訂值正確傳遞到容器 env | live | P1 | ✅ | 容器 env OPENCLAW_MODEL 等於 .env 設定值；revision 內 openclaw.json 的 agents.defaults.model.primary 一致。 |
| CR-ENV-05 | 部署後 revision env vars 與 substitutions 完全一致 | live | P0 | ✅ | 含且僅含 GEMINI_API_KEY、OPENCLAW_GATEWAY_TOKEN、OPENCLAW_PUBLIC_URL、OPENCLAW_MODEL；值與部署輸入相符；PORT 由 Cloud Run 自動注入。 |
| CR-ENV-06 | OPENCLAW_PUBLIC_URL 空值部署不破壞容器啟動 | integration | P1 | ✅ | 容器仍啟動；openclaw.json allowedOrigins[0] 為預設 https://clawdbot.asia-east1.run.app（gen-config fallback），不致語法錯誤。模擬首次部署尚未 refre |
| CR-ENV-07 | GEMINI_API_KEY 經 Secret Manager 解析後帶入（resolve_gemini） | manual | P1 | 手動 | 建置日誌/部署後 env 顯示 GEMINI_API_KEY 為 Secret 內容（非空、非 'local-test'）；.env 有值時則優先用 .env 值。 |
| CR-ENV-08 | 含特殊字元的 token/URL 不破壞 --set-env-vars 解析 | manual | P2 | 手動 | 記錄限制：--set-env-vars 以逗號分隔，token 若含逗號會破壞解析；gen-token 產生純 hex 故安全。文件應提醒勿手填含逗號的值。 |
| CR-IAM-01 | allow-public 以 add-iam-policy-binding 綁定 allUsers→roles/run. | static | P0 | ✅ | 執行 gcloud run services add-iam-policy-binding $SERVICE --region=$REGION --member=allUsers --role=roles/run.invoker，且帶正確  |
| CR-IAM-02 | deploy 目標部署後自動串接 allow-public | static | P0 | ✅ | deploy 在 builds submit 後執行 allow-public，因為 cloudbuild 的 --allow-unauthenticated 在 Cloud Build SA 無 IAM 權限時會靜默失效。 |
| CR-IAM-03 | cloudbuild deploy step 仍帶 --allow-unauthenticated（盡力而為） | static | P1 | ✅ | 存在；若 Cloud Build SA 恰有 IAM 權限則此處即生效，否則由 make allow-public 補上（雙保險）。 |
| CR-IAM-04 | 未授權服務回 403（Google Frontend），allow-public 後回 200 | live | P0 | ✅ | 無 invoker 綁定時 Google 前端回 403（非 app 回應）；綁定 allUsers 後匿名 GET / 回 200。對應 README 排錯表。 |
| CR-IAM-05 | allow-public 冪等：重複執行不報錯 | live | P1 | ✅ | 第二次仍成功（add-iam-policy-binding 對既存綁定為幂等，不會重複新增或報錯）。 |
| CR-IAM-06 | 重新對外/關閉對外操作正確（README 維運表） | manual | P2 | 手動 | 兩個指令皆作用於正確 service+region，狀態切換符合預期。 |
| CR-REV-01 | 部署後最新 revision 進入 Ready=True | live | P0 | ✅ | latestReadyRevisionName 非空且等於 latestCreatedRevisionName；Ready 條件 status=True（容器成功啟動並通過健康檢查）。 |
| CR-REV-02 | make status 正確顯示 URL / latestReadyRevision / MIN | live | P1 | ✅ | 輸出表格含 status.url、status.latestReadyRevisionName、minScale annotation；MIN 欄等於部署的 MIN_INSTANCES。 |
| CR-REV-03 | revision 註解 minScale 等於 MIN_INSTANCES | live | P1 | ✅ | 等於部署時 _MIN_INSTANCES（預設 1）；設 0 時為 0。 |
| CR-REV-04 | revision 資源配置 memory/cpu/port 正確套用 | live | P0 | ✅ | memory=2Gi、cpu=1（或 .env 值）、containerPort=8080。 |
| CR-REV-05 | min-instances 目標可即時更新常駐數 | live | P1 | ✅ | minScale annotation 隨 N 即時變更；不需重建映像即可調整（services update）。 |
| CR-REV-06 | min-instances 未帶 N 時回退 MIN_INSTANCES 預設 | live | P2 | 手動 | $(or $(N),$(MIN_INSTANCES)) 取 MIN_INSTANCES（預設 1）作為 --min-instances。 |
| CR-REV-07 | 重新部署相同 tag 產生新 revision 且流量自動切換 | live | P1 | 手動 | 產生新 revision（名稱遞增），traffic 100% 指向 latest；舊 revision 不再收流量。tag 重用不影響部署正確性。 |
| CR-URL-01 | refresh-url 取得實際 URL、寫回 .env 並更新服務 env | live | P0 | 手動 | OPENCLAW_PUBLIC_URL 被替換為 describe 取得的 status.url；同時 services update --update-env-vars=OPENCLAW_PUBLIC_URL=<url> 更新容器 env |
| CR-URL-02 | 取不到 URL 時 refresh-url 以非零退出 | manual | P2 | 手動 | 輸出『✗ 取不到 URL』並 exit 1，不會寫入空值到 .env。 |
| CR-URL-03 | url 目標輸出純 URL，dashboard-url 輸出帶 token fragment 網址 | live | P2 | ✅ | url 輸出 status.url；dashboard-url 輸出 <url>/chat?session=main#token=<TOKEN> 並含無痕視窗提醒。 |
| CR-PRE-01 | deploy 前置 check-env：缺 GCP_PROJECT_ID 即失敗 | unit | P0 | ✅ | 輸出『✗ GCP_PROJECT_ID 未設』並 exit 1，阻止後續 deploy。 |
| CR-PRE-02 | check-env：缺 .env 檔即失敗並提示複製範本 | unit | P1 | ✅ | 輸出提示『cp .env.example .env』並 exit 1。 |
| CR-PRE-03 | check-env：缺 OPENCLAW_GATEWAY_TOKEN 僅警告不阻擋 | unit | P1 | ✅ | 印出 token 未設警告但 exit 0（部署時容器會自動產生隨機 token）。 |
| CR-PRE-04 | deploy 依賴 check-env（前置失敗不進行 builds submit） | static | P0 | ✅ | deploy: check-env；check-env 失敗時不會呼叫 gcloud builds submit。 |
| CR-PRE-05 | cloudbuild options.logging=CLOUD_LOGGING_ONLY | static | P0 | ✅ | 為 CLOUD_LOGGING_ONLY（無 logsBucket 時 Cloud Build 預設行為要求明確指定 logging，否則 builds submit 失敗）。 |
| CR-PRE-06 | build context 與 Dockerfile 路徑正確（context='.'、-f deploy/Docker | static | P0 | ✅ | context 為 repo 根目錄（需 COPY extensions/），Dockerfile 指向 deploy/Dockerfile；.gcloudignore 不排除 extensions/deploy。 |
| CR-STEP-01 | step 相依順序 docker-auth→build→push→deploy 正確 | static | P0 | ✅ | build waitFor docker-auth；push waitFor build；deploy waitFor push（確保推映像完成後才部署，避免拉不到映像）。 |
| CR-STEP-02 | docker-auth 對正確 AR host 設定 configure-docker | static | P1 | ✅ | host 與映像 registry host 一致，--quiet 避免互動。 |
| CR-STEP-03 | build step 帶 --build-arg OPENCLAW_VERSION=${_OPENCLAW_VERSIO | static | P1 | ✅ | 含 --build-arg OPENCLAW_VERSION=${_OPENCLAW_VERSION}，與 Dockerfile ARG OPENCLAW_VERSION 對應，npm install -g openclaw@版本。 |
| CR-STEP-04 | cloudbuild step 使用之 builder 映像名稱皆合法 | static | P2 | ✅ | docker-auth/deploy 用 cloud-sdk/gcloud builder；build/push 用 cloud-builders/docker；皆為有效公開 builder。 |
| CR-NEG-01 | 無效 region 部署應失敗（負面） | manual | P2 | 手動 | builds submit 或 deploy 報區域無效錯誤並非零退出；不產生半成品服務。 |
| CR-NEG-02 | AR repo 不存在時 push 失敗，bootstrap 後成功 | manual | P1 | 手動 | 首次 push step 因 repo 不存在失敗；make create-repo/bootstrap 後重試成功（create-repo 對既存 repo 為冪等，// true）。 |
| CR-NEG-03 | 無效 memory/cpu 組合部署被 Cloud Run 拒絕 | manual | P2 | 手動 | deploy step 回非零，錯誤訊息指出 memory/cpu 比例不合法；revision 不建立。 |
| CR-NEG-04 | 空 _GEMINI_API_KEY 仍可部署但圖片/模型呼叫受限 | manual | P2 | 手動 | 部署成功、revision Ready（gen-config 不要求 GEMINI_API_KEY）；但實際模型呼叫會 401/配額錯誤，屬執行期非部署期問題。記錄為已知行為。 |
| CR-IDEM-01 | bootstrap/create-repo/enable-apis 冪等 | manual | P1 | 手動 | enable-apis 重複啟用無副作用；create-repo 對既存 repo 因 // true 不報錯退出；整體 exit 0。 |
| CR-IDEM-02 | 重複 make deploy 冪等（同設定產生等價服務狀態） | live | P1 | 手動 | 每次成功；最終服務 env/flags/IAM 與單次部署一致；除新 revision 名稱外狀態等價。 |
| CR-IDEM-03 | secret-set-gemini 首次 create、再次 versions add（冪等更新） | manual | P2 | 手動 | 首次 create gemini-api-key；既存時改用 versions add 新增版本，不報 already exists 錯；latest 指向新值，供 resolve_gemini 取用。 |
| CR-COV-01 | 既有 test_live.sh 覆蓋：根頁 200 與 token 401/200（部分覆蓋） | live | P0 | ✅ | 已覆蓋：GET / =200、control-ui-config 帶正確 Bearer=200、無 token=401。未覆蓋：revision Ready、env-vars 正確、IAM allUsers、min-instances/me |
| CR-COV-02 | 既有 test_integration.sh 覆蓋：映像 build+啟動+token 行為（不含 Cloud Run  | integration | P0 | ✅ | 已覆蓋：Dockerfile 可 build、容器啟動 listening、根頁 200、Bearer 200/401、容器內 openclaw.json token/origin 正確。未覆蓋：cloudbuild substitutio |
| CR-COV-03 | 既有 test_static.sh 覆蓋：cloudbuild.yaml 可解析、bash/JS 語法（不含 subst | static | P0 | ✅ | 已覆蓋：cloudbuild.yaml YAML 合法/無 tab、檔案結構、make help 可解析。未覆蓋：13 個 substitutions 完整性、Makefile↔cloudbuild substitution 對齊、flag |

### Env-Makefile-parsing（33）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| ENVMK-01 | .env 不存在時 Makefile 仍可解析（include 為條件式） | integration | P0 | ✅ | make 不因缺 .env 而失敗（Makefile 第8行 ifneq+wildcard 條件式 include），help 正常輸出；『目前設定』行的 project= 為空但無 Make 錯誤。exit 0。 |
| ENVMK-02 | .env 存在時被正確 include 並 export 給 recipe | integration | P0 | ✅ | help 結尾顯示 project=openclow-498602 region=asia-east1 service=clawdbot tag=v1；make -n url 的 gcloud 指令含 --project=openclow- |
| ENVMK-03 | .env.example 與 .env 鍵集合一致（無遺漏、無多餘） | static | P0 | ✅ | 兩集合完全相同（目前各 18 鍵：AR_REPO_NAME, CPU, GCP_ACCOUNT, GCP_PROJECT_ID, GCP_REGION, GEMINI_API_KEY, GOOGLECHAT_ENABLED, GOOGLE_ |
| ENVMK-04 | .env.example 全行為 KEY=VALUE 或註解格式（已存在於 test_static） | static | P1 | ✅ | 無不合格行。已由 tests/test_static.sh『.env.example 鍵值格式』section 覆蓋（第35-37行）。【既有覆蓋】 |
| ENVMK-05 | .env.example 內含的鍵 = Makefile 實際引用的變數（無孤兒鍵/無未文件化變數） | static | P1 | ✅ | GCP_PROJECT_ID/GCP_REGION/GCP_ACCOUNT/AR_REPO_NAME/SERVICE_NAME/IMAGE_TAG/OPENCLAW_VERSION/MIN_INSTANCES/MEMORY/CPU/GEMI |
| ENVMK-06 | Makefile 衍生變數預設值正確（?= 在缺 .env 時生效） | integration | P0 | ✅ | 依 Makefile 14-27 行預設：GCP_REGION=asia-east1, AR_REPO_NAME=clawdbot-repo, SERVICE_NAME=clawdbot, IMAGE_TAG=v1, OPENCLAW_VE |
| ENVMK-07 | 預設值與 .env.example 範本值一致 | static | P1 | ✅ | 兩處同名變數的預設/範本值相同（皆 asia-east1 / clawdbot-repo / clawdbot / v1 / 2026.6.1 / 1 / 2Gi / 1 / google/gemini-3-flash-preview），避 |
| ENVMK-08 | make help 列出所有有 ## 說明的 target | static | P0 | ✅ | help 列出全部 24 個有 ## 說明的 target（allow-public, bootstrap, build-local, check-env, clean, create-repo, dashboard-url, deploy |
| ENVMK-09 | 每個 .PHONY target 都有 ## 說明（無遺漏文件） | static | P1 | ✅ | 兩集合完全相同；每個 .PHONY target 皆有 ## 說明，故都會出現在 make help。目前 24=24 一致，無孤兒 target。【新增缺口】 |
| ENVMK-10 | make help 為 .DEFAULT_GOAL（無參數 make 顯示 help） | static | P1 | ✅ | 輸出與 `make help` 相同（首行『openclaw-Taiwan 維運指令：』），證實 .DEFAULT_GOAL := help（第5行）生效，不會誤觸發任何具副作用的 target。【新增缺口】 |
| ENVMK-11 | 每個 target 可被 make -n 解析（dry-run 無語法/變數展開錯誤） | static | P0 | ✅ | 全部 24 target 的 make -n 皆 exit 0、無『*** ... Stop.』解析錯誤、無未定義函式/變數展開崩潰。特別涵蓋使用 define resolve_gemini、$(strip)、$(or N,...)、$(i |
| ENVMK-12 | make -n 不實際執行副作用（docker/gcloud/build 不被觸發） | static | P1 | ✅ | dry-run 只印命令字串，無容器被建立、無 gcloud API 呼叫。recipe 內 @ 前綴與 $(MAKE) 子呼叫在 -n 下亦只印不執行。【新增缺口】 |
| ENVMK-13 | check-env：缺 .env 時報錯並給出修復指引、exit 非零 | integration | P0 | ✅ | 輸出『✗ 找不到 .env，請先：cp .env.example .env』，exit code 非零（make 回 2）。對應 Makefile 第45行。【新增缺口】 |
| ENVMK-14 | check-env：有 .env 但缺 GCP_PROJECT_ID 時失敗 | integration | P0 | ✅ | 輸出『✗ GCP_PROJECT_ID 未設』並 exit 非零（第46行 test -n）。【新增缺口】 |
| ENVMK-15 | check-env：缺 OPENCLAW_GATEWAY_TOKEN 僅警告、不失敗（exit 0） | integration | P1 | ✅ | 印出『⚠ OPENCLAW_GATEWAY_TOKEN 未設…』警告與『✓ .env OK』，exit 0（第47-48行，token 缺失為非致命）。【新增缺口】 |
| ENVMK-16 | check-env：完整 .env 通過並回顯 project | integration | P1 | ✅ | 輸出『✓ .env OK（project=openclow-498602）』，exit 0。【新增缺口】 |
| ENVMK-17 | 邊界：.env.example 直接 cp 為 .env 時，行內註解污染變數值（footgun） | integration | P0 | ✅ | 暴露已知陷阱：Make include 對 `GCP_PROJECT_ID=your-project-id          # 例：...` 只去掉 # 後段，保留前段含尾端空白 → GCP_PROJECT_ID=『your-projec |
| ENVMK-18 | 邊界：.env 中變數值帶尾端空白污染 IMAGE 衍生變數 | integration | P1 | ✅ | 驗證 IMAGE = $(GCP_REGION)-docker.pkg.dev/$(GCP_PROJECT_ID)/... 是否含非法空白；理想上 deploy 的 substitutions 與 IMAGE 應對 project 做 $( |
| ENVMK-19 | 邊界：.env 中以空值定義變數會壓過 ?= 預設（footgun） | integration | P1 | ✅ | 暴露 GNU Make 行為：?= 只在『變數完全未定義』時套用；.env 明確空字串會被視為已定義 → 預設 asia-east1/2Gi 不生效，region= 變空。AC：測試應偵測『.env 不應出現 KEY= 空值且該鍵期望走 M |
| ENVMK-20 | 邊界：.env 重複鍵 — 後者覆蓋前者（last-wins） | integration | P2 | ✅ | project=second（GNU Make include 後定義覆蓋）。記錄此為已知行為，並建議 lint .env 不應有重複鍵。【新增缺口】 |
| ENVMK-21 | 負面：未知 target 時 make 報錯且 exit 非零 | static | P2 | ✅ | 輸出『No rule to make target `nonexistent-target'.  Stop.』且 exit 非零。【新增缺口】 |
| ENVMK-22 | Makefile 整體可被 GNU Make 解析（無語法錯誤）— 已存在 | static | P1 | ✅ | make help exit 0，無解析錯誤。已由 tests/test_static.sh 第43-44行覆蓋。【既有覆蓋】 |
| ENVMK-23 | 冪等性：重複執行 make help / check-env 結果穩定、不改檔案 | integration | P1 | ✅ | 兩次輸出一致；.env 內容/雜湊不變（help、check-env 為唯讀，不應寫檔）。【新增缺口】 |
| ENVMK-24 | 冪等性：gen-token 重複執行只更新同一行、不新增重複鍵、保持 64 hex | integration | P1 | ✅ | OPENCLAW_GATEWAY_TOKEN 行恰好 1 條（grep 存在則 sed 取代，否則 append；第52-56行），值為 64 hex，無 .env.bak 殘留。第二次執行覆蓋而非追加 → 冪等於『行數』。【新增缺口】 |
| ENVMK-25 | gen-token：在不存在 OPENCLAW_GATEWAY_TOKEN 行的 .env 上 append | integration | P2 | ✅ | 於檔尾新增 `OPENCLAW_GATEWAY_TOKEN=<64hex>`，原有其他鍵不受影響。【新增缺口】 |
| ENVMK-26 | make -n 對使用 $(or N,...) 參數覆寫的 target 正確解析（min-instances / lo | static | P2 | ✅ | min-instances 無 N 時 --min-instances=$(MIN_INSTANCES)=1；給 N=3 時為 3；logs N=10 時 --limit=10；無參數時 --limit=50。$(or $(N),...)  |
| ENVMK-27 | GCLOUD 變數依 GCP_ACCOUNT 條件帶入 --account | static | P2 | ✅ | 有值時指令含 `--account=<值>`；無值時不含 --account（第25行 $(if GCP_ACCOUNT,...) 條件）。【新增缺口】 |
| ENVMK-28 | deploy substitutions 由 .env 完整帶入且鍵名對齊 cloudbuild.yaml | static | P0 | ✅ | make 傳入的 _GCP_PROJECT_ID/_GCP_REGION/_AR_REPO_NAME/_SERVICE_NAME/_TAG/_OPENCLAW_VERSION/_GEMINI_API_KEY/_OPENCLAW_GATEWA |
| ENVMK-29 | resolve_gemini：GEMINI_API_KEY 有值時直接用、空值時退回 Secret Manager（dr | static | P1 | ✅ | 有值：substitutions 直接帶入該值；空值：展開為 `$(gcloud ... secrets ... gemini-api-key)` 取值表達式（第30-32行 define + 第82行 strip）。dry-run 不實際 |
| ENVMK-30 | make help 結尾『目前設定』行反映實際 .env 值（不洩漏機密） | integration | P2 | ✅ | 顯示 project/region/service/tag 四項，且不包含 OPENCLAW_GATEWAY_TOKEN/GEMINI_API_KEY 等機密（第40行只回顯非機密 4 項）。【新增缺口】 |
| ENVMK-31 | .gitignore 確實忽略 .env 與 token 檔（已存在） | static | P1 | ✅ | 兩者皆被忽略。已由 tests/test_static.sh 第39-41行覆蓋。【既有覆蓋】 |
| ENVMK-32 | 邊界：.env 含 CRLF / BOM 時 include 解析行為 | integration | P2 | ✅ | 偵測 CRLF 會使值帶入尾端 \r（污染 IMAGE/URL）；BOM 會破壞首個鍵名。AC：測試應警示需 LF、無 BOM；理想為 .env 載入前做正規化。【新增缺口】 |
| ENVMK-33 | 邊界：.env 值含特殊字元（空白、=、#、$）的解析正確性 | integration | P2 | ✅ | 暴露 Make 對 include 值中 $ 的二次展開風險（$ 會被解讀）。token 為 hex（無 $）故實務安全，但需記錄此限制；含 = 的值（如 URL query）以第一個 = 切分後保留其餘。AC：對目前實際值（hex tok |

### Runtime-Gateway-Auth（38）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| RGA-TOKEN-01 | 未設 OPENCLAW_GATEWAY_TOKEN 時 entrypoint 自動產生 64 字元 hex token | integration | P0 | ✅ | stderr 出現 '[entrypoint] Generated random OPENCLAW_GATEWAY_TOKEN'；產生的 config 中 gateway.auth.token 為 64 字元 [0-9a-f] 字串；流程不 |
| RGA-TOKEN-02 | 已設 OPENCLAW_GATEWAY_TOKEN 時 entrypoint 沿用不覆寫且不印產生訊息 | integration | P0 | ✅ | config 的 gateway.auth.token == $TOK；stderr 不出現 'Generated random OPENCLAW_GATEWAY_TOKEN' |
| RGA-TOKEN-03 | 自動產生 token 每次容器啟動皆為不同隨機值 | integration | P2 | ✅ | 兩次 token 不相等（隨機性），且皆為 64 字元 hex |
| RGA-TOKEN-04 | Makefile gen-token 產生 64 字元 hex 並寫回 .env（含覆寫既有值之冪等） | unit | P1 | ✅ | 第一次新增 OPENCLAW_GATEWAY_TOKEN=<64hex>；第二次以 sed 就地覆寫同一行（不重複新增）；無遺留 .env.bak |
| RGA-CONFIGONLY-01 | CLAWDBOT_CONFIG_ONLY=1 乾跑：產生並驗證設定後 exit 0，不啟動 gateway | integration | P0 | ✅ | 輸出含 'Config written to ...'、'CLAWDBOT_CONFIG_ONLY=1 → config generated, exiting without starting gateway'；exit code 0；無  |
| RGA-CONFIGONLY-02 | CONFIG_ONLY 輸出將 token 遮蔽為 *** | integration | P0 | ✅ | 印出的設定內容含 '"token": "***"'，且不出現明文 $TOK |
| RGA-CONFIGONLY-03 | CLAWDBOT_CONFIG_ONLY 未設或非 '1' 時不進入乾跑（會繼續啟動） | integration | P2 | ✅ | 兩種情況皆不印乾跑退出訊息，會繼續往 gateway 啟動流程（值需嚴格等於 '1' 才乾跑） |
| RGA-JSON-01 | 產生的 openclaw.json 為合法 JSON（entrypoint JSON.parse 驗證通過） | integration | P0 | ✅ | 檔案存在且 JSON.parse 成功；entrypoint 不印 'generated config is not valid JSON' |
| RGA-JSON-02 | 特殊字元 token/URL 經 gen-config 正確跳脫仍產生合法 JSON | unit | P1 | ✅ | 輸出仍為合法 JSON，token/URL 內容正確還原（驗證以程式組裝而非字串拼接，無引號破壞） |
| RGA-JSON-03 | entrypoint 對非法 JSON 之 fail-fast 行為 | manual | P1 | 手動 | 印出 '[entrypoint] ERROR: generated config is not valid JSON' 並以 exit 1 結束（set -e + fail fast） |
| RGA-GW-START-01 | gateway 正常啟動並 listening（http server listening） | integration | P0 | ✅ | 60s 內 logs 出現 'http server listening'；容器持續 Running |
| RGA-GW-START-02 | entrypoint 以正確參數 exec gateway（--allow-unconfigured --port -- | integration | P1 | ✅ | 印出 port=8080（或 PORT 注入值）、bind=lan（或 OPENCLAW_BIND）、public=$OPENCLAW_PUBLIC_URL；gateway 監聽於該 port |
| RGA-GW-START-03 | PORT 環境變數可覆寫監聽埠 | integration | P2 | ✅ | gateway 監聽於 9090，logs 顯示 port=9090，根頁回 200 |
| RGA-GW-START-04 | OPENCLAW_BIND 環境變數可覆寫綁定模式 | integration | P2 | ✅ | logs 'Starting gateway: ... bind=<指定值>'；gateway 依該 bind 啟動 |
| RGA-GW-START-05 | openclaw CLI 不在 PATH 時 fail-fast | manual | P2 | 手動 | 印出 '[entrypoint] ERROR: openclaw CLI not found on PATH' 並 exit 1，不嘗試 exec |
| RGA-SIGTERM-01 | SIGTERM 經 tini 傳遞給 gateway 達成優雅結束 | integration | P0 | ✅ | 容器在預設 10s 寬限期內結束、不需 SIGKILL 強殺；exit code 為 0 或 143(128+15)；tini 為 PID 1 確保訊號轉發 |
| RGA-SIGTERM-02 | tini 作為 PID 1 回收殭屍程序 | manual | P2 | 手動 | PID 1 = /usr/bin/tini；無 defunct 子程序累積 |
| RGA-AUTH-200-01 | 正確 token 經 Authorization: Bearer 取受保護端點回 200 | integration | P0 | ✅ | HTTP 200（已覆蓋於 test_integration.sh / test_live.sh） |
| RGA-AUTH-401-01 | 錯誤 token 取受保護端點回 401 | integration | P0 | ✅ | HTTP 401（已覆蓋於 test_integration.sh） |
| RGA-AUTH-401-02 | 完全無 token 取受保護端點回 401 | integration | P0 | ✅ | HTTP 401（已覆蓋於 test_integration.sh / test_live.sh） |
| RGA-AUTH-401-03 | 空 Bearer token（Authorization: Bearer 後無值）回 401 | integration | P1 | ✅ | HTTP 401（空字串不得視為有效）；新增缺口，現有測試未涵蓋 |
| RGA-AUTH-401-04 | 格式錯誤的 Authorization header（缺 Bearer 前綴 / 大小寫錯誤 / Basic）回 401 | integration | P1 | ✅ | 各情況皆回 401（僅標準 'Bearer <token>' 接受）；新增缺口 |
| RGA-AUTH-401-05 | token 大小寫/前後空白變異視為錯誤回 401 | integration | P2 | ✅ | 皆回 401（精確比對，無寬鬆匹配）；新增缺口 |
| RGA-AUTH-IDEM-01 | 重複多次帶正確 token 請求結果一致（冪等） | integration | P2 | ✅ | 每次皆回 200 且回應一致，無因 rate-limit/狀態而變動；新增缺口 |
| RGA-ROOT-200-01 | 根頁 / 回 200（無需 token） | integration | P0 | ✅ | HTTP 200（已覆蓋於 test_integration.sh / test_live.sh） |
| RGA-ORIGIN-403-01 | allowedOrigins 缺公開 URL 時 control UI 跨來源請求回 403 | integration | P0 | ✅ | HTTP 403（非允許來源遭拒，token 正確亦然）；新增缺口，現有測試未涵蓋 403 情境 |
| RGA-ORIGIN-200-01 | allowedOrigins 含公開 URL 時相符 Origin 請求通過 | integration | P1 | ✅ | HTTP 200（相符來源 + 正確 token 放行）；新增缺口 |
| RGA-ORIGIN-02 | localhost / 127.0.0.1:8080 預設在 allowedOrigins 內可放行 | unit | P2 | ✅ | allowedOrigins 含 'http://localhost:8080' 與 'http://127.0.0.1:8080'；部分由 test_config 覆蓋公開URL，本地兩項為新增 |
| RGA-ORIGIN-03 | 無 Origin header 的請求經 dangerouslyAllowHostHeaderOriginFallbac | integration | P2 | ✅ | 在 fallback 啟用下，依 Host 判定為合法來源 → 不因缺 Origin 直接 403（200 或正常授權流程）；新增缺口 |
| RGA-ORIGIN-04 | gen-config allowedOrigins[0] 為 OPENCLAW_PUBLIC_URL（缺值用預設 run | unit | P1 | ✅ | 有設時為該 URL（test_config 已覆蓋）；不設時為預設 'https://clawdbot.asia-east1.run.app'；預設值情境為新增缺口 |
| RGA-CFG-DEVAUTH-01 | dangerouslyDisableDeviceAuth=true 使純 token 瀏覽器 control UI 免裝 | unit | P1 | ✅ | 值為 true（已由 test_config 案例1 覆蓋） |
| RGA-CFG-TRUSTPROXY-01 | trustedProxies 含 Cloud Run 內部代理與 loopback | unit | P2 | ✅ | 陣列含 '169.254.169.126' 與 '127.0.0.1'（影響 X-Forwarded 來源判定）；新增缺口 |
| RGA-CFG-AUTHMODE-01 | gateway.auth.mode 固定為 token | unit | P0 | ✅ | 值為 'token'（已由 test_config 案例1 覆蓋） |
| RGA-HOME-01 | OPENCLAW_HOME 可覆寫設定目錄並正確建立 | integration | P2 | ✅ | 目錄被 mkdir -p 建立，config 寫入 /tmp/customhome/openclaw.json；新增缺口 |
| RGA-STATIC-01 | entrypoint.sh / gen-config.mjs 語法正確（bash -n / node --check） | static | P1 | ✅ | 皆退出 0（已由 test_static.sh 覆蓋） |
| RGA-STATIC-02 | entrypoint.sh 設 set -euo pipefail（嚴格模式 fail-fast） | static | P2 | ✅ | 存在該行，確保任一步失敗即中止；新增缺口（靜態確認） |
| RGA-STATIC-03 | Dockerfile ENTRYPOINT 使用 tini 以正確處理 SIGTERM | static | P1 | ✅ | ENTRYPOINT 為 ['/usr/bin/tini','--','/app/deploy/entrypoint.sh']；新增缺口（靜態確認，支撐 SIGTERM 行為） |
| RGA-LIVE-AUTH-01 | 線上 Cloud Run 服務 token 200/401 與根頁 200 煙霧驗證 | live | P0 | ✅ | 根頁 200、正確 Bearer 200、無 token 401（已由 test_live.sh 覆蓋；建議補錯誤 token 401 與 403 origin） |

### Channels（47）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| CH-GC-01 | 預設啟用 Google Chat 頻道（GOOGLECHAT_ENABLED 未設） | unit | P0 | ✅ | 輸出含 channels.googlechat 區塊且 .channels.googlechat.enabled=true（bool() 預設為 true） |
| CH-GC-02 | Google Chat webhookPath = /googlechat | unit | P0 | ✅ | 值精確為 "/googlechat" |
| CH-GC-03 | Google Chat audience 預設 = OPENCLAW_PUBLIC_URL + /googlechat | unit | P0 | ✅ | 值為 https://svc.a.run.app/googlechat（已由 test_config 案例2覆蓋） |
| CH-GC-04 | audienceType 為 app-url | unit | P1 | ✅ | 值為 "app-url"（既有測試未覆蓋，新增缺口） |
| CH-GC-05 | OPENCLAW_PUBLIC_URL 未設時 audience 用內建預設 URL | unit | P1 | ✅ | 值為 https://clawdbot.asia-east1.run.app/googlechat（預設 publicUrl 回退；新增缺口） |
| CH-GC-06 | GOOGLE_CHAT_AUDIENCE 覆寫 audience 來源 | unit | P1 | ✅ | audience=https://B/googlechat（以 GOOGLE_CHAT_AUDIENCE 優先；新增缺口） |
| CH-GC-07 | GOOGLECHAT_ENABLED=false 時不產生 googlechat 區塊 | unit | P0 | ✅ | 輸出不含 "googlechat"，channels.googlechat 不存在（已由 test_config 案例3覆蓋） |
| CH-GC-08 | GOOGLECHAT_ENABLED 各種真值寫法皆啟用 | unit | P2 | ✅ | 每種皆產生 googlechat 區塊（bool() regex /^(1/true/yes/on)$/i；新增缺口） |
| CH-GC-09 | GOOGLECHAT_ENABLED 各種假值/無效值皆停用 | unit | P2 | ✅ | 0/false/no/off 及任意非真值字串皆不產生 googlechat 區塊（注意 random 也視為 false；新增缺口） |
| CH-GC-10 | GOOGLECHAT_ENABLED 空字串走預設 true | unit | P2 | ✅ | 視為未設 → 預設啟用 googlechat（bool 對 "" 回 dflt；新增缺口） |
| CH-GC-11 | SA 檔：明確指定 GOOGLE_CHAT_SERVICE_ACCOUNT_FILE 帶入 serviceAccount | unit | P0 | ✅ | 值為 /secrets/sa.json（已由 test_config 案例5覆蓋） |
| CH-GC-12 | SA 偵測：存在 /secrets/google-chat-sa/key.json 時自動帶入 | unit | P1 | ✅ | serviceAccountFile 自動=/secrets/google-chat-sa/key.json（existsSync 偵測；新增缺口，需可寫該路徑或 mock） |
| CH-GC-13 | SA 偵測優先序：明確指定優先於自動偵測 | unit | P2 | ✅ | serviceAccountFile=/custom/sa.json（明確值優先；新增缺口） |
| CH-GC-14 | 無 SA 檔且無掛載時不輸出 serviceAccountFile 欄位 | unit | P1 | ✅ | googlechat 啟用但無 serviceAccountFile 欄位（僅 saFile 非空才寫入；新增缺口） |
| CH-GC-15 | Google Chat DM / group 政策預設值 | unit | P2 | ✅ | dm.policy="open"、dm.allowFrom=["*"]、groupPolicy="open"（新增缺口） |
| CH-LINE-01 | LINE 兩金鑰皆有才啟用 | unit | P0 | ✅ | 輸出含 channels.line 且 enabled=true（已由 test_config 案例4覆蓋啟用，但 enabled 欄位值為新增缺口） |
| CH-LINE-02 | LINE 只有 SECRET 不啟用 | unit | P0 | ✅ | 輸出不含 "line" 區塊（&& 短路；新增缺口，負面案例） |
| CH-LINE-03 | LINE 只有 ACCESS_TOKEN 不啟用 | unit | P0 | ✅ | 輸出不含 "line" 區塊（新增缺口，負面案例） |
| CH-LINE-04 | LINE 兩金鑰皆空不啟用（預設） | unit | P1 | ✅ | channels 無 line 區塊（新增缺口） |
| CH-LINE-05 | LINE 任一金鑰為空字串視為未提供 | unit | P1 | ✅ | 不啟用 line（空字串為 falsy；新增缺口，邊界） |
| CH-LINE-06 | LINE webhookPath = /line | unit | P0 | ✅ | 值精確為 "/line"（新增缺口，既有測試只驗 requireMention） |
| CH-LINE-07 | LINE requireMention 預設 true（群組需 @ 提及） | unit | P0 | ✅ | 值為 true（已由 test_config 案例4覆蓋） |
| CH-LINE-08 | LINE channelSecret / channelAccessToken 正確寫入 | unit | P0 | ✅ | channelSecret=mysecret、channelAccessToken=mytoken（金鑰原樣帶入；新增缺口） |
| CH-LINE-09 | LINE DM / group 政策預設值 | unit | P2 | ✅ | dmPolicy="open"、allowFrom=["*"]、groupPolicy="open"（新增缺口） |
| CH-LINE-10 | LINE 金鑰含特殊字元/引號仍產生合法 JSON | unit | P2 | ✅ | 輸出仍為合法 JSON 且值正確跳脫（JSON.stringify 保證；新增缺口，邊界） |
| CH-BOTH-01 | 同時啟用 Google Chat 與 LINE | unit | P1 | ✅ | channels 同時含 googlechat 與 line 兩區塊（新增缺口，組合案例） |
| CH-BOTH-02 | 停用 Google Chat、僅啟用 LINE | unit | P1 | ✅ | channels 僅含 line、無 googlechat（新增缺口） |
| CH-BOTH-03 | 兩頻道皆停用時 channels 為空物件 | unit | P1 | ✅ | channels={} 空物件且輸出仍合法 JSON、gateway 仍可啟動（新增缺口，負面/邊界） |
| CH-IDEM-01 | 頻道設定產生具冪等性（多次產生輸出一致） | unit | P2 | ✅ | 兩次輸出完全一致（無隨機性／時間戳；新增缺口，冪等性） |
| CH-IDEM-02 | 重複部署/重啟容器後 openclaw.json 頻道區塊不變 | integration | P2 | ✅ | channels 區塊（googlechat/line）內容一致，entrypoint 每次重產不漂移（新增缺口，冪等性） |
| CH-CFG-01 | 頻道設定反映在最終 openclaw.json（容器內，預設） | integration | P0 | ✅ | 檔案存在且 channels.googlechat.webhookPath=/googlechat、audience=<URL>/googlechat（既有 test_integration 僅驗 token/allowedOrigins， |
| CH-CFG-02 | LINE 經容器環境變數啟用並反映在 openclaw.json | integration | P0 | ✅ | openclaw.json 含 channels.line、webhookPath=/line、requireMention=true（新增缺口） |
| CH-CFG-03 | CONFIG_ONLY 模式輸出含頻道設定 | integration | P1 | ✅ | 印出 Config written 且設定含對應頻道區塊；token 顯示遮蔽為 ***（既有測試驗 token 遮蔽，channels 內容為新增缺口） |
| CH-WH-GC-01 | Google Chat webhook 端點可達性（容器本機） | integration | P1 | ✅ | 端點存在且回應非 404（路由已掛載；可能為 200/400/401，依驗證而定）。需確認與 webhookPath 一致（新增缺口，端點可達性） |
| CH-WH-LINE-01 | LINE webhook 端點可達性（容器本機） | integration | P1 | ✅ | 端點存在回應非 404；未帶/帶錯 X-Line-Signature 時應拒簽（4xx），路由僅在 LINE 啟用時掛載（新增缺口，端點可達性 + 負面） |
| CH-WH-LINE-02 | LINE 未啟用時 /line 端點不存在 | integration | P2 | ✅ | 回 404（LINE 未啟用則無此路由）（新增缺口，負面案例） |
| CH-WH-GC-LIVE-01 | 線上 Google Chat webhook 端點可達性 | live | P1 | ✅ | 非 404（端點存在）；驗證 audience 與此 URL 對齊（test_live 目前只驗根頁與 token，為新增缺口） |
| CH-WH-LINE-LIVE-01 | 線上 LINE webhook 端點可達性（僅當 LINE 已部署） | live | P2 | ✅ | 非 404；若服務未注入 LINE 金鑰則為 404（並據此判定部署管線缺漏，見 CH-DEPLOY-02）（新增缺口） |
| CH-DEPLOY-01 | 部署管線未傳遞 GOOGLECHAT_ENABLED（缺陷驗證） | static | P1 | ✅ | 目前皆未包含 → 部署後無法以 .env 停用 Google Chat（記錄為缺陷）。修正後應能傳遞並由 live 驗證（新增缺口） |
| CH-DEPLOY-02 | 部署管線未傳遞 LINE 金鑰（缺陷驗證） | static | P0 | ✅ | 目前未包含 → 即使 .env 填了 LINE 兩金鑰，Cloud Run 服務也收不到，LINE 永遠不會啟用（記錄為高風險缺陷）。修正後 live 端點應可達（新增缺口） |
| CH-DEPLOY-03 | 部署管線未掛載 Google Chat SA Secret（缺陷驗證） | static | P1 | ✅ | 目前未掛載 → entrypoint 的 SA 自動偵測在自動部署中永不命中；.env 的 GOOGLE_CHAT_SA_SECRET 未被任何腳本使用（記錄為缺陷／文件與實作落差）（新增缺口） |
| CH-DEPLOY-04 | webhookPath 與 README/設定步驟一致性 | static | P2 | ✅ | README 的 /googlechat 與 /line 與設定產生器完全一致（一致性檢查；新增缺口） |
| CH-DEPLOY-05 | GOOGLE_CHAT_AUDIENCE 未經部署管線傳遞（缺陷驗證） | static | P2 | ✅ | 未傳遞 → 線上 audience 只能等於 OPENCLAW_PUBLIC_URL，無法獨立覆寫（記錄為已知限制）（新增缺口） |
| CH-LIVE-AUD-01 | 線上 Google Chat audience 與實際服務 URL 對齊 | manual | P0 | 手動 | 訊息送達 gateway、回覆正常、無 audience mismatch（app-url 模式以 OPENCLAW_PUBLIC_URL/googlechat 驗證 JWT）；驗證 refresh-url 已寫對 URL（需真實 Chat |
| CH-LIVE-GC-SA-01 | 線上 Google Chat SA 偵測生效（掛載 SA 後） | manual | P1 | 手動 | serviceAccountFile 指向掛載路徑且功能正常（手動，依賴真實 SA 與權限） |
| CH-LIVE-LINE-01 | 線上 LINE 群組 @ 提及行為（requireMention） | manual | P1 | 手動 | (a) 機器人不回應；(b) 機器人回應（requireMention=true 生效）；私訊則直接回應（手動，依賴真實 LINE 群組） |
| CH-LIVE-LINE-02 | 線上 LINE 簽章驗證（Channel Secret 正確性） | manual | P1 | 手動 | Verify 成功（簽章用 channelSecret 驗證通過）、私訊有回覆（手動） |

### Operations（觀測與本機維運：make status/logs/url/dashboard-url/min-instances/refresh-url/secret-set-gemini + run-local/stop-local/clean/build-local）（55）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| OPS-URL-01 | make url 印出服務 status.url | live | P0 | ✅ | stdout 為單行 https://....run.app（status.url），exit 0，無多餘文字 |
| OPS-URL-02 | make url 在服務未部署時回空 | live | P1 | ✅ | describe 取不到 url 時 gcloud 回非零或空字串；不應誤印錯誤 URL（記錄實際行為作為基準） |
| OPS-URL-03 | make url 缺 .env 時被 check-env 擋下 | unit | P0 | ✅ | check-env 失敗：印『找不到 .env，請先：cp .env.example .env』且 exit 1，不呼叫 gcloud |
| OPS-URL-04 | make url 缺 GCP_PROJECT_ID 被擋 | unit | P0 | ✅ | check-env 印『GCP_PROJECT_ID 未設』exit 1 |
| OPS-STATUS-01 | make status 以 table 顯示 url/revision/MIN | live | P0 | ✅ | 輸出 table，含 status.url、latestReadyRevisionName 與 MIN（autoscaling minScale label=MIN）三欄，exit 0 |
| OPS-STATUS-02 | make status 服務未部署時的行為 | live | P2 | 手動 | gcloud describe 回錯誤（NOT_FOUND）；make 因 recipe 失敗回非零（記錄訊息是否友善，作為改善缺口） |
| OPS-STATUS-03 | make status 缺 .env/PROJECT_ID 被 check-env 擋 | unit | P1 | ✅ | check-env exit 1，不呼叫 gcloud |
| OPS-LOGS-01 | make logs 預設讀 50 行 | live | P0 | ✅ | 呼叫 gcloud logs read --limit=50；輸出最近最多 50 筆日誌，exit 0 |
| OPS-LOGS-02 | make logs N=行數 覆寫 limit | live | P1 | ✅ | 傳入 --limit=5（$(or $(N),50) 取 N），最多回 5 筆 |
| OPS-LOGS-03 | make logs N=0 邊界 | manual | P2 | 手動 | $(or $(N),50) 中 0 為非空字串故採用 N=0；--limit=0 行為依 gcloud（記錄是否回 0 筆或報錯） |
| OPS-LOGS-04 | make logs N 非數字 邊界 | manual | P2 | 手動 | --limit=abc 由 gcloud 驗證並報參數錯誤，make 回非零（負面案例） |
| OPS-LOGS-05 | make logs 缺 check-env 被擋 | unit | P1 | ✅ | check-env exit 1，不讀日誌 |
| OPS-DASH-01 | make dashboard-url 產生 fragment token 網址 | live | P0 | ✅ | 第一行為『<url>/chat?session=main#token=<TOKEN>』，TOKEN 等於 .env 之 OPENCLAW_GATEWAY_TOKEN；第二行印無痕視窗建議；exit 0 |
| OPS-DASH-02 | dashboard-url 使用即時 describe 的 URL 而非 .env | live | P1 | ✅ | URL 取自 gcloud run services describe status.url（非 .env OPENCLAW_PUBLIC_URL），確保與實際服務一致 |
| OPS-DASH-03 | dashboard-url 在 token 為空時輸出殘缺 fragment（負面） | unit | P1 | ✅ | 輸出尾端為『#token=』（空 token），會導致 Dashboard 無法登入——應驗證並標記為需提示使用者先 gen-token/refresh 的缺口 |
| OPS-DASH-04 | dashboard-url 在服務未部署時輸出以 /chat 開頭（負面/邊界） | live | P2 | 手動 | $u 為空 → 輸出『/chat?session=main#token=...』缺少 host，屬無效網址；記錄為缺口（未對空 URL fail-fast） |
| OPS-DASH-05 | dashboard-url 路徑與參數格式正確 | static | P1 | ✅ | 格式精確為 /chat?session=main#token=$(OPENCLAW_GATEWAY_TOKEN)，session=main 與 # fragment 不可遺漏 |
| OPS-DASH-06 | dashboard-url 缺 check-env 被擋 | unit | P1 | ✅ | check-env exit 1，不產生網址 |
| OPS-MIN-01 | make min-instances N=1 設常駐 | live | P0 | ✅ | gcloud run services update --min-instances=1 成功；status MIN 欄變 1 |
| OPS-MIN-02 | make min-instances N=0 縮到零 | live | P0 | ✅ | --min-instances=0（$(or $(N),...) 中 0 為非空被採用）；MIN 變 0 |
| OPS-MIN-03 | make min-instances 不帶 N 時回退 .env MIN_INSTANCES | unit | P1 | ✅ | 展開為 --min-instances=3（N 空 → 取 MIN_INSTANCES） |
| OPS-MIN-04 | min-instances 兩者皆空時用預設 1 | unit | P1 | ✅ | Makefile 預設 MIN_INSTANCES?=1，展開 --min-instances=1 |
| OPS-MIN-05 | min-instances N 為負數/非數字（負面） | live | P2 | 手動 | gcloud 驗證並報錯，make 回非零；不可靜默通過 |
| OPS-MIN-06 | min-instances 冪等性 | live | P2 | ✅ | 兩次皆成功 exit 0，狀態維持 1，無副作用（gcloud update 冪等） |
| OPS-MIN-07 | min-instances 缺 check-env 被擋 | unit | P1 | ✅ | check-env exit 1，不呼叫 update |
| OPS-REFRESH-01 | make refresh-url 取得 URL 寫回 .env 並更新服務 | live | P0 | ✅ | .env 之 OPENCLAW_PUBLIC_URL 被替換為實際 status.url；服務 env 也以 --update-env-vars 更新；印『OPENCLAW_PUBLIC_URL=<url>（已寫回...）』exit 0 |
| OPS-REFRESH-02 | refresh-url 取不到 URL 時 fail-fast | live | P0 | 手動 | $u 空 → 印『取不到 URL』exit 1，且不修改 .env、不呼叫 update |
| OPS-REFRESH-03 | refresh-url 清理 sed 暫存檔 | integration | P1 | ✅ | sed -i.bak 後 .env.bak 已被 rm 移除，不殘留備份檔 |
| OPS-REFRESH-04 | refresh-url 在 .env 無 OPENCLAW_PUBLIC_URL 行時不寫入（缺口） | integration | P1 | ✅ | sed 替換無匹配 → 不會 append，URL 未寫回 .env（與 gen-token 的 grep-then-append 不一致）；應驗證並標記為缺口 |
| OPS-REFRESH-05 | refresh-url 冪等性 | live | P2 | ✅ | 兩次結果一致，.env 內 URL 不重複、無多行，服務 env 不變 |
| OPS-REFRESH-06 | refresh-url 缺 check-env 被擋 | unit | P1 | ✅ | check-env exit 1 |
| OPS-SEC-01 | make secret-set-gemini 首次建立 secret | live | P0 | 手動 | secrets create 成功建立 gemini-api-key（data 為 KEY，無尾換行因 printf '%s'）；印『gemini-api-key 已更新』exit 0 |
| OPS-SEC-02 | secret-set-gemini 既存時新增版本（idempotent upsert） | live | P0 | 手動 | create 失敗 → fallback 到 versions add 新增一版；最新版為 AIzaNEW，舊版保留 |
| OPS-SEC-03 | secret-set-gemini 缺 KEY 報錯 | unit | P0 | ✅ | 印『請提供 KEY，例如：make secret-set-gemini KEY=AIza...』exit 1，不呼叫 gcloud |
| OPS-SEC-04 | secret-set-gemini KEY 寫入無尾換行 | live | P1 | 手動 | 取出內容精確等於 KEY，末尾無 \n（printf '%s' 不加換行），避免 API key 帶換行失效 |
| OPS-SEC-05 | secret-set-gemini KEY 含特殊字元 | manual | P2 | 手動 | printf '%s' "$(KEY)" 完整保留內容，不被 shell 拆分（負面/邊界） |
| OPS-SEC-06 | secret-set-gemini 缺 check-env 被擋 | unit | P1 | ✅ | check-env exit 1（依賴順序 check-env 先於 KEY 檢查） |
| OPS-RUNLOCAL-01 | make run-local 啟動本機容器並印 dashboard 連結 | integration | P0 | ✅ | 先 build-local（依賴），docker run -d 命名 clawdbot-local，映 LOCAL_PORT:8080，注入 OPENCLAW_GATEWAY_TOKEN/OPENCLAW_PUBLIC_URL=http:/ |
| OPS-RUNLOCAL-02 | run-local 自訂 LOCAL_PORT | integration | P1 | ✅ | 容器映 29090:8080；輸出連結 host 為 localhost:29090 |
| OPS-RUNLOCAL-03 | run-local 冪等：重跑先移除舊容器 | integration | P0 | ✅ | recipe 先 docker rm -f clawdbot-local（忽略錯誤）再啟新容器；不因『name already in use』失敗，最終僅一個容器 |
| OPS-RUNLOCAL-04 | run-local 健康：容器啟動後 gateway listening | integration | P1 | ✅ | 日誌出現『http server listening』，根頁回 200 |
| OPS-RUNLOCAL-05 | run-local 在 docker 不可用時失敗 | manual | P2 | 手動 | build-local 的 docker build 失敗 → make 回非零並停止（負面案例） |
| OPS-RUNLOCAL-06 | run-local token 為空時的本機行為 | integration | P2 | ✅ | 容器 entrypoint 自動產生隨機 token（印『Generated random...』），但 Makefile 印出的連結 #token= 為空，需驗證並標記為缺口 |
| OPS-BUILDLOCAL-01 | make build-local 以 deploy/Dockerfile 建置 | integration | P1 | ✅ | docker build -f deploy/Dockerfile --build-arg OPENCLAW_VERSION=<ver> -t clawdbot-local . 成功，產生映像 |
| OPS-BUILDLOCAL-02 | build-local 帶入 OPENCLAW_VERSION | integration | P2 | ✅ | build-arg 傳入指定版本；容器內 openclaw --version 相符 |
| OPS-STOPLOCAL-01 | make stop-local 停止並移除容器 | integration | P0 | ✅ | docker rm -f clawdbot-local 成功，容器消失 |
| OPS-STOPLOCAL-02 | stop-local 冪等：無容器時不報錯 | integration | P0 | ✅ | recipe 前綴 - 忽略 docker 錯誤，make exit 0（冪等） |
| OPS-CLEAN-01 | make clean 移除本機與測試容器及暫存 | integration | P0 | ✅ | docker rm -f clawdbot-local clawdbot-test、rm -rf tests/.tmp，印『cleaned』exit 0 |
| OPS-CLEAN-02 | clean 冪等：無容器/無暫存時仍成功 | integration | P0 | ✅ | - 前綴忽略錯誤，rm -rf 對不存在路徑安全，印『cleaned』exit 0 |
| OPS-CLEAN-03 | clean 不需要 .env（無 check-env 依賴） | static | P2 | ✅ | clean 不依賴 check-env，可在無 .env 環境執行（與 run-local/stop-local/build-local 一致） |
| OPS-HELP-01 | make help 列出所有 Operations 指令與目前設定 | static | P1 | ✅ | 列出 status/logs/url/dashboard-url/min-instances/refresh-url/secret-set-gemini/run-local/stop-local/clean 等含 ## 說明；尾行印 pro |
| OPS-STATIC-01 | 全部 Operations recipe 之 bash 片段語法正確 | static | P1 | ✅ | 變數展開正確、引號完整、無 unbound；refresh-url 的 sed/rm 與 dashboard-url 的字串組裝可解析（既有 test_static 僅檢查 *.sh，Makefile recipe 內嵌 shell 為新增 |
| OPS-STATIC-02 | GCLOUD 變數含 project/account 旗標組裝 | static | P2 | ✅ | 展開為 gcloud --project=<id> [--account=<acct>] ...；GCP_ACCOUNT 空時不帶 --account（既有測試未覆蓋，新增） |
| OPS-COV-01 | 既有 test_live 涵蓋根頁與 token 驗證（觀測健康面） | live | P1 | ✅ | 已覆蓋：根頁=200、Bearer→200、無 token→401。註：未覆蓋 url/status/logs/dashboard-url 之輸出正確性（屬本維度新增缺口） |
| OPS-COV-02 | 既有 doctor 涵蓋服務 Ready/根頁/token 驗證 | live | P2 | ✅ | 已覆蓋服務健康面（Ready、200、Bearer/無 token）；但未驗證 make status/logs/url 命令本身輸出格式（新增缺口） |

### Security-Negative（52）
| ID | 案例 | 類型 | 優先 | 自動化 | 驗收標準 |
|----|------|------|------|--------|----------|
| SECNEG-01 | .gitignore 忽略 .env | static | P0 | ✅ | 回傳 .env（exit 0），代表 .env 被忽略；不會被提交 |
| SECNEG-02 | .gitignore 忽略所有 .env.* 變體（.env.local/.env.prod/.env.bak） | static | P0 | ✅ | 三者皆被忽略（exit 0） |
| SECNEG-03 | .gitignore 例外：.env.example 必須可被追蹤 | static | P0 | ✅ | exit 非 0（未被忽略），確保範本可提交；對應 .gitignore 的 !.env.example |
| SECNEG-04 | .gitignore 忽略 *-sa.json（Service Account 金鑰） | static | P0 | ✅ | 皆被忽略（exit 0） |
| SECNEG-05 | .gitignore 忽略 service-account*.json | static | P0 | ✅ | 皆被忽略（exit 0） |
| SECNEG-06 | .gitignore 忽略 *.key | static | P0 | ✅ | 皆被忽略（exit 0） |
| SECNEG-07 | .gitignore 忽略 .gateway-token.env | static | P0 | ✅ | 被忽略（exit 0）；對應既有 test_static.sh『.gitignore 含 token 檔』(已覆蓋) |
| SECNEG-08 | git 實際未追蹤 .env（僅追蹤 .env.example） | static | P0 | ✅ | 輸出為空；git ls-files 中只有 .env.example，無 .env / 其他機密。新增缺口（既有測試只檢查 .gitignore 文字，未驗證實際追蹤狀態） |
| SECNEG-09 | git 索引中無任何機密檔（掃描已追蹤檔） | static | P0 | ✅ | 輸出為空（.env.example 除外）；確保歷史/索引未誤加機密。新增缺口 |
| SECNEG-10 | .dockerignore 忽略 .env / .env.* / token | static | P0 | ✅ | 三條目存在，避免機密進入映像 build context |
| SECNEG-11 | .dockerignore 忽略 *-sa.json 與 *.key | static | P0 | ✅ | 兩條目存在 |
| SECNEG-12 | 缺口：.dockerignore 未涵蓋 service-account*.json | static | P0 | ✅ | 目前無此條目 → 名為 service-account-prod.json 的金鑰會被 git 忽略卻可能進入 Docimage。AC：補上 service-account*.json，或測試應斷言其存在。已知缺口（需修補 + 新增測試） |
| SECNEG-13 | .gcloudignore 忽略 .env / .env.* / token | static | P0 | ✅ | 三條目存在，避免機密進入 gcloud builds submit 上傳的 source tarball |
| SECNEG-14 | .gcloudignore 忽略 *-sa.json 與 *.key | static | P0 | ✅ | 兩條目存在 |
| SECNEG-15 | 缺口：.gcloudignore 未涵蓋 service-account*.json | static | P0 | ✅ | 目前無此條目 → service-account*.json 金鑰可能上傳到 Cloud Build。AC：補上條目。已知缺口 |
| SECNEG-16 | 三份 ignore 機密條目一致性 | static | P1 | ✅ | 三者對機密的覆蓋一致；目前 service-account*.json 僅 .gitignore 有 → 不一致需修。新增缺口 |
| SECNEG-17 | Docker build context 不含機密（建置後驗證） | integration | P1 | ✅ | 映像內不存在 .env / *-sa.json / *.key（被 .dockerignore 排除）。新增缺口（既有 test_integration 未驗證機密未進映像） |
| SECNEG-18 | gcloud builds source tarball 不含機密（dry-run/模擬） | manual | P1 | 手動 | 上傳清單不含任何機密檔。手動/半自動 |
| SECNEG-19 | 負面：缺 GCP_PROJECT_ID → check-env 失敗 | unit | P0 | ✅ | 印出『✗ GCP_PROJECT_ID 未設』且 exit 非 0；不繼續部署 |
| SECNEG-20 | 負面：缺 .env 檔 → check-env 失敗並給提示 | unit | P0 | ✅ | 印出『找不到 .env，請先：cp .env.example .env』且 exit 非 0 |
| SECNEG-21 | 負面：缺 OPENCLAW_GATEWAY_TOKEN → check-env 僅警告不中止 | unit | P1 | ✅ | 印出 token 未設的⚠警告但 exit 0（部署時自動產生）；驗證行為與文件一致 |
| SECNEG-22 | 負面：缺 token → entrypoint 自動產生 64 hex | integration | P1 | ✅ | stderr 出現『Generated random OPENCLAW_GATEWAY_TOKEN』；config 仍合法、token 為 64 hex；不因缺 token 啟動失敗 |
| SECNEG-23 | 負面：缺 token → gen-config.mjs 直接失敗退出 | unit | P0 | ✅ | 印『ERROR: OPENCLAW_GATEWAY_TOKEN is required』且 exit 1；對應既有 test_config 案例6(已覆蓋) |
| SECNEG-24 | 負面：缺 Gemini secret 且 .env 無 GEMINI_API_KEY → install 中止 | unit | P0 | ✅ | 印『✗ 找不到 Gemini 金鑰：請 make install KEY=AIza... 或在 .env 設 GEMINI_API_KEY』且 exit 1。新增缺口 |
| SECNEG-25 | 負面：secret-set-gemini 未提供 KEY → 失敗 | unit | P1 | ✅ | 印『✗ 請提供 KEY，例如：make secret-set-gemini KEY=AIza...』且 exit 非 0；不會誤建空 secret。新增缺口 |
| SECNEG-26 | 負面：doctor 找不到 Gemini 金鑰時標記失敗 | unit | P1 | ✅ | 輸出『找不到 Gemini 金鑰』並計入 FAIL。新增缺口 |
| SECNEG-27 | 負面：錯誤 token（Bearer 不符）→ 401 | integration | P0 | ✅ | HTTP 401；對應既有 test_integration『錯誤 Bearer=401』(已覆蓋) |
| SECNEG-28 | 負面：無 token → 受保護端點 401 | integration | P0 | ✅ | HTTP 401；對應既有 test_integration / test_live / doctor(已覆蓋) |
| SECNEG-29 | 負面：空字串 token 的 Bearer header → 401 | integration | P1 | ✅ | HTTP 401（空 token 不得通過）。新增缺口 |
| SECNEG-30 | 負面：大小寫/前綴錯誤的 Authorization（如 token=xxx 或缺 Bearer）→ 401 | integration | P2 | ✅ | 皆非 200（預期 401），驗證僅接受正確格式。新增缺口 |
| SECNEG-31 | 正面對照：正確 Bearer → 200（確保負面測試不是恆假） | integration | P0 | ✅ | HTTP 200；對應既有 test_integration(已覆蓋)，作為 401 案例的對照 |
| SECNEG-32 | token 強度：gen-token 產生 64 字元 hex | unit | P0 | ✅ | 長度=64 且符合 ^[0-9a-f]{64}$（openssl rand -hex 32）。新增缺口（既有僅 doctor 對人工檢查長度） |
| SECNEG-33 | token 強度：entrypoint 自動產生為 64 hex | integration | P1 | ✅ | 自動產生 token 長度=64、hex（crypto.randomBytes(32).toString('hex')）。新增缺口 |
| SECNEG-34 | token 強度：doctor 對非 64 長度 token 發出警告 | unit | P1 | ✅ | 印『OPENCLAW_GATEWAY_TOKEN 長度非 64（建議 make gen-token）』警告。新增缺口 |
| SECNEG-35 | 缺口：弱 token 被 gen-config 接受（無長度/hex 驗證） | unit | P2 | ✅ | 目前會接受任意非空字串並寫入 config（不驗證強度）。AC：記錄為已知風險；若加固，短/非 hex token 應警告或拒絕。已知缺口 |
| SECNEG-36 | 缺口：無效模型字串被 gen-config 接受（無白名單驗證） | unit | P2 | ✅ | 目前 model.primary 原樣寫入『not-a-real-model』，無驗證 → 部署後執行期才失敗。AC：記錄為已知缺口；若加固應對模型前綴/格式做基本檢查。已知缺口 |
| SECNEG-37 | 負面：空模型字串 → 落回預設模型 | unit | P1 | ✅ | model.primary = google/gemini-3-flash-preview（空值落回預設，非空字串）。新增缺口 |
| SECNEG-38 | 機密遮蔽：entrypoint 輸出將 config 中 token 顯示為 *** | integration | P0 | ✅ | 輸出含 "token": "***" 且不含真實 token 明文；對應既有 test_integration『token 已遮蔽顯示』(已覆蓋) |
| SECNEG-39 | 機密外洩：容器日誌不得印出明文 token | integration | P1 | ✅ | grep 無命中；啟動日誌不洩漏明文 token（entrypoint 僅印遮蔽版）。新增缺口 |
| SECNEG-40 | 機密外洩：dashboard-url 會輸出含 token 的網址（預期行為，需告警/限縮） | manual | P2 | 手動 | 輸出 .../chat?session=main#token=<TOK>（token 在 fragment）。AC：確認為刻意設計、提示用無痕視窗；列為人工安全審視項，避免貼到聊天/紀錄 |
| SECNEG-41 | 冪等性：gen-token 重複執行只更新單一鍵、不殘留 .env.bak | unit | P1 | ✅ | OPENCLAW_GATEWAY_TOKEN 行始終僅 1 行（不重複附加）；無 .env.bak 殘留（sed -i.bak 後已 rm）。新增缺口 |
| SECNEG-42 | 冪等性/外洩：refresh-url 的 .env.bak 暫存被清除 | unit | P2 | ✅ | 操作後不留 .env.bak（避免含舊機密的備份檔殘留於工作目錄）。新增缺口 |
| SECNEG-43 | 若 .env.bak 殘留仍被忽略（防呆） | static | P1 | ✅ | 被 .gitignore 的 .env.* 規則忽略（exit 0），即使殘留也不會提交。新增缺口 |
| SECNEG-44 | 負面：未啟用計費 → doctor 標記失敗 | unit | P2 | ✅ | 印『計費未啟用』並計入 FAIL；防止在無計費專案誤部署。新增缺口 |
| SECNEG-45 | 負面：無法存取 GCP 專案（錯誤 project id）→ doctor 失敗 | unit | P2 | ✅ | 印『無法存取專案 <id>』並計入 FAIL。新增缺口 |
| SECNEG-46 | .env.example 不含任何真實機密值 | static | P0 | ✅ | 無命中；範本內 GEMINI_API_KEY/token 等皆為佔位字串（your-... / 空值），不洩漏真實金鑰。新增缺口 |
| SECNEG-47 | .env.example 的 token/secret 欄位預設為空或佔位 | static | P1 | ✅ | 敏感欄位無真實值；自動處理欄位留空。新增缺口 |
| SECNEG-48 | 負面：LINE 僅單邊金鑰（secret 或 token 其一）→ 不啟用 LINE 頻道 | unit | P1 | ✅ | config.channels 不含 line（避免半配置造成驗簽失效/誤啟）。新增缺口（既有案例4只測雙金鑰啟用） |
| SECNEG-49 | SA 檔不存在時不誤設 serviceAccountFile（避免指向不存在金鑰） | unit | P2 | ✅ | googlechat 區塊不含 serviceAccountFile 欄位（saFile 為空時不加入）。新增缺口 |
| SECNEG-50 | 產生的 config 一律為合法 JSON（含特殊字元 token 注入防護） | unit | P1 | ✅ | 輸出仍為合法 JSON（JSON.stringify 正確跳脫），不因 token 含引號/反斜線/$() 造成注入或破壞檔案。新增缺口（驗證 gen-config 設計目的） |
| SECNEG-51 | entrypoint 對非法 config 會 fail fast | integration | P2 | ✅ | 產生的 config 非合法 JSON 時印『generated config is not valid JSON』並 exit 1，不啟動 gateway。新增缺口 |
| SECNEG-52 | 負面：openclaw CLI 不在 PATH → entrypoint 失敗退出 | integration | P2 | 手動 | 印『openclaw CLI not found on PATH』且 exit 1，不靜默啟動。手動/特製映像 |

## 完整性審查（QA 主管）
> 已實地比對 repo 與測試矩陣，結論：矩陣對「一鍵安裝/重裝/doctor」的多數假設已過時——install/reinstall/uninstall/teardown-all/doctor 與 test_docs.sh 皆已實作，因此 TEAR-01/02/03/04 標記為「缺口待新增」屬於矛盾，應改寫為「驗證既有目標」。同時發現實作層級真正未覆蓋的高風險缺口：(1) cloudbuild.yaml 的 --set-env-vars 漏傳 GOOGLECHAT_ENABLED / LINE_CHANNEL_SECRET / LINE_CHANNEL_ACCESS_TOKEN / GOOGLE_CHAT_AUDIENCE，導致 .env 設定的 LINE 頻道與關閉 Google Chat 在雲端完全失效（設定漂移，矩陣 INSTALL-32/33 只驗「有傳的一致」未驗「該傳卻漏傳」）；(2) GOOGLE_CHAT_SA_SECRET 是 .env.example 第18鍵但無人消費（孤兒鍵），且 cloudbuild 未掛載任何 SA secret，README 記載的 Google Chat SA 流程端到端斷裂；(3) install/reinstall/doctor 的編排、相依、容錯與冪等完全無測試；(4) 缺整個維度：上線/回滾(revision rollback)、冷啟動(min-instances=0)、並發、Dockerfile/EXPOSE 與 cloudbuild --port 一致性、devices-remote.sh、nano-banana 擴充、tini 訊號處理。矩陣亦有重複案例（gen-token/secret/refresh-url 在 INSTALL 與 IDEMP 段重覆）。優先序：先補 P0「漏傳 env-vars」與「install/doctor 編排」測試，再補回滾/冷啟動維度。

### 待辦/手動維度（未自動化）
- **ROLLBACK-01** [P1]：缺維度：Cloud Run revision 回滾 — deploy v2 後可用 gcloud run services update-traffic --to-revisions=<v1>=100 回滾到舊 revision；舊映像 tag 仍在 Ar
- **COLDSTART-01** [P2]：缺維度：min-instances=0 冷啟動與 SIGTERM 截斷行為 — make min-instances N=0 後，閒置縮到零；首次請求冷啟動延遲可接受、不回 5xx；縮容時 tini 轉送 SIGTERM 使 gateway 優雅結束（呼應 README『回覆中斷

## 手動驗證清單（無法自動化／需外部設定）
- [ ] Google Chat App 綁定後，私訊與群組 @ 提及可收到回覆
- [ ] LINE OA webhook 設定後，私訊與群組可收到回覆
- [ ] Google Chat Service Account 驗證流程（掛載 /secrets/google-chat-sa/key.json）
- [ ] Cloud Run revision 回滾（rollback）後服務正常
- [ ] 冷啟動（min-instances=0）後首次請求可正常喚醒
- [ ] 圖片生成（Nano Banana）：標準金鑰有圖片配額時可出圖
- [ ] Dashboard 無痕視窗 + fragment token 可連線
