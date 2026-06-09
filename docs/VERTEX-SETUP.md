# Vertex AI 模型設定（小龍蝦 / OpenClaw）

本文件說明小龍蝦如何用 **Google Vertex AI** 作為 Gemini 模型供應，以及**使用者必做的一次性身份驗證每一步**。

> TL;DR：模型用 `google-vertex/gemini-2.5-flash`，靠 **service account ADC** 認證（免 API 金鑰、吃 GCP 專案試用金）。
> 因組織政策禁止建立 SA 金鑰，改用**使用者 ADC**——需執行一次 `make vertex-auth`。

---

## 1. 為什麼用 Vertex AI（而非 AI Studio 金鑰）

| 方案 | 結果 |
|------|------|
| AI Studio `AQ.` 臨時憑證 / 連帳單專案的 `AIza` 金鑰 | `429 prepayment credits depleted`（預付額度耗盡） |
| 無帳單專案的免費 `AIza` 金鑰 | 被 Google **帳號層級軟封** `403 project denied access` |
| **Vertex AI（google-vertex/*）** | ✅ 走獨立的 `aiplatform.googleapis.com`，吃專案試用金，正常運作 |

**成本模式**：Vertex `trafficType=ON_DEMAND`，計入 GCP 專案。免費 GCP 帳號有三個月試用額度；
到期後**換一個新的免費 Google 帳號**重做下方 `make vertex-auth` 即可續用。

---

## 2. 運作原理（技術規格）

- **模型字串**：`OPENCLAW_MODEL=google-vertex/gemini-2.5-flash`（openclaw provider=`google-vertex`）。
- **必要環境變數**（部署時帶入容器）：
  - `GOOGLE_CLOUD_PROJECT`：GCP 專案 ID。
  - `GOOGLE_CLOUD_LOCATION=global`（endpoint `https://aiplatform.googleapis.com`；指定 region 則為 `{loc}-aiplatform.googleapis.com`）。
- **認證**：Google ADC（Application Default Credentials）。openclaw 的 vertex 同步預判**只認憑證「檔案」**
  （`authorized_user` / `external_account` / `service_account`），**刻意不認 GCE metadata-server ADC**。故必須提供一個 ADC 憑證檔。
- **憑證檔來源**：因組織禁 SA 金鑰，採 `gcloud auth application-default login` 產生的 **`authorized_user`** ADC（含可自動刷新的 refresh_token）。
- **佈署方式**：ADC 檔存入 **Secret Manager（`vertex-adc`）**；容器 `deploy/entrypoint.sh` 啟動時，若為 vertex 模型，
  自動以 runtime SA 從 Secret Manager 取出寫到 `GOOGLE_APPLICATION_CREDENTIALS` 指向的檔（`deploy/fetch-adc.mjs`）。Cloud Run（無狀態）與 VM 皆適用。
- **必要 IAM**：
  - runtime SA（`<projNum>-compute@developer.gserviceaccount.com`）需 `roles/aiplatform.user`（由 `make bootstrap` / `grant-build-roles` 授予）。
  - 同一 SA 需 `roles/secretmanager.secretAccessor` 於 `vertex-adc`（由 `make vertex-store-adc` 授予）。
  - **ADC 所屬的使用者帳號**需對專案有 Vertex 權限（owner 即可）。

---

## 3. 一次性身份驗證步驟（使用者必做）

執行 **`make vertex-auth`**，它會逐步完成下列 4 步（每步都會印出實際指令）：

```
make vertex-auth
```

| 步驟 | 指令 | 說明 / 你要做什麼 |
|------|------|------|
| **[1] 登入 ADC** | `gcloud auth application-default login --account=<GCP_ACCOUNT>` | **會開瀏覽器**。務必選用 `.env` 裡 `GCP_ACCOUNT` 那個帳號（即專案 owner）登入並同意授權。 |
| **[2] 設 quota 專案** | `gcloud auth application-default set-quota-project <GCP_PROJECT_ID>` | 設定 API 配額/計費歸屬。使用者 ADC 打 API 需要 quota project。 |
| **[3] 存入 Secret** | `gcloud secrets create/versions add vertex-adc --data-file=~/.config/gcloud/application_default_credentials.json` | 將 ADC 憑證存入 Secret Manager，供 Cloud Run/VM 取用（`make vertex-auth` 自動做）。 |
| **[4] 授權 SA** | `gcloud secrets add-iam-policy-binding vertex-adc --member=serviceAccount:<SA> --role=roles/secretmanager.secretAccessor` | 讓 runtime SA 能讀取該 secret（`make vertex-auth` 自動做）。 |

完成後執行 `make install`，其 `[3/8] 模型認證` 步驟會偵測到 `vertex-adc` 已存在並直接繼續。
若未做 vertex-auth 就 `make install`，install 會**印出完整步驟並擋下**，不會中途無故失敗。

> 已在本機登入過 ADC 者：`make install` 會自動偵測本機 ADC 並呼叫 `make vertex-store-adc` 存入 Secret，無需手動。

---

## 4. 換帳號續用（試用到期）

1. 用新的免費 Google 帳號建立 / 切換 GCP 專案（更新 `.env` 的 `GCP_PROJECT_ID`、`GCP_ACCOUNT`）。
2. 重跑 `make vertex-auth`（用新帳號登入 ADC）。
3. `make install`。

---

## 5. 排錯對照

| 症狀 | 成因 | 解法 |
|------|------|------|
| `Unknown model: google-vertex/...`（`model_not_found`） | config 缺 `models.providers["google-vertex"]` 憑證標記，或無 auth profile | `gen-config.mjs` 會在 vertex 模型自動寫入 `apiKey:"gcp-vertex-credentials"` 標記；確認 config 有此區塊 |
| `Provider google-vertex has auth issue` / `403 PERMISSION_DENIED on aiplatform.endpoints.predict` | ADC 憑證的**帳號不對**（非專案 owner 或無 aiplatform 權限） | 用 `gcloud auth application-default print-access-token` 取 token，打 `tokeninfo` 看 `email`；重做 `make vertex-auth` 選對帳號 |
| `403 project denied access`（打 generativelanguage） | 那是 **AI Studio** 路被封，與 Vertex 無關 | 確認模型是 `google-vertex/*` 而非 `google/*` |
| entrypoint `fetch vertex-adc 失敗` | secret 不存在或 SA 缺 `secretmanager.secretAccessor` | `make vertex-store-adc` |

**驗證 Vertex 可用**（用 ADC token 直打）：
```
TOK=$(gcloud auth application-default print-access-token)
curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $TOK" \
  "https://aiplatform.googleapis.com/v1/projects/<PROJ>/locations/global/publishers/google/models/gemini-2.5-flash:generateContent" \
  -H "Content-Type: application/json" -d '{"contents":[{"role":"user","parts":[{"text":"hi"}]}]}'
# 期望 200
```
