#!/usr/bin/env node
// 產生 OpenClaw gateway 設定檔（~/.openclaw/openclaw.json）。
//
// 設計理由：以程式組裝 JSON 物件後再 JSON.stringify，可正確處理跳脫與型別，
// 避免用 shell heredoc 字串拼接造成的引號/插值錯誤（先前 token / allowedOrigins
// 的 bug 即源於此）。本檔同時被 entrypoint.sh（執行期）與 tests/（單元測試）使用。
//
// 讀取的環境變數：
//   OPENCLAW_GATEWAY_TOKEN   gateway 認證 token（必填）
//   OPENCLAW_PUBLIC_URL      對外公開 URL（control UI allowedOrigins + Google Chat audience）
//   GOOGLE_CHAT_AUDIENCE     覆寫 Google Chat audience（預設 = OPENCLAW_PUBLIC_URL）
//   OPENCLAW_MODEL           主要模型（預設 google/gemini-2.5-flash）
//   GOOGLECHAT_ENABLED       是否啟用 Google Chat 頻道（預設 true）
//   GOOGLE_CHAT_SERVICE_ACCOUNT_FILE  Service Account JSON 路徑（有則加入 googlechat）
//   LINE_CHANNEL_SECRET / LINE_CHANNEL_ACCESS_TOKEN  兩者皆有則啟用 LINE 頻道
//   OPENCLAW_CONFIG_PATH     輸出路徑；未設則印到 stdout
//
// 用法：
//   node gen-config.mjs            # 印到 stdout
//   OPENCLAW_CONFIG_PATH=... node gen-config.mjs   # 寫入檔案
//   node gen-config.mjs --stdout   # 強制印到 stdout（即使有 OPENCLAW_CONFIG_PATH）

import { writeFileSync, existsSync } from "node:fs";

const env = process.env;
const bool = (v, dflt) => (v == null || v === "" ? dflt : /^(1|true|yes|on)$/i.test(v));

const token = env.OPENCLAW_GATEWAY_TOKEN;
if (!token) {
  console.error("[gen-config] ERROR: OPENCLAW_GATEWAY_TOKEN is required");
  process.exit(1);
}

const publicUrl = env.OPENCLAW_PUBLIC_URL || "https://clawdbot.asia-east1.run.app";
const audience = env.GOOGLE_CHAT_AUDIENCE || publicUrl;
// 預設用 Vertex AI（google-vertex/*）：免 API 金鑰、靠 SA ADC，吃專案試用金。
// 需容器具 GOOGLE_CLOUD_PROJECT/GOOGLE_CLOUD_LOCATION 與 runtime SA 具 roles/aiplatform.user。
const model = env.OPENCLAW_MODEL || "google-vertex/gemini-2.5-flash";

// Service account：明確指定，或偵測 Cloud Run 慣用掛載路徑
let saFile = env.GOOGLE_CHAT_SERVICE_ACCOUNT_FILE || "";
if (!saFile && existsSync("/secrets/google-chat-sa/key.json")) {
  saFile = "/secrets/google-chat-sa/key.json";
}

// 記憶搜尋的 embedding provider。OpenClaw 內建記憶引擎預設用 OpenAI embedding，
// 未設 OPENAI_API_KEY 時會出現 "sync failed: No API key found for provider openai"。
// 預設 "none"：停用 embedding 向量搜尋（僅關鍵字 + MEMORY.md，完全免金鑰、最穩定，
//   記憶仍跨重啟保留）。slim 映像的 gemini 向量索引需 chunks_vec 表，易出錯，故不預設。
// 進階：設 OPENCLAW_MEMORY_PROVIDER=gemini 用 Gemini 金鑰做語意記憶（需向量表可用）。
const memoryProvider = env.OPENCLAW_MEMORY_PROVIDER || "none";

// 時區：影響 AI 提示中的「現在時間」。預設台灣。
const userTimezone = env.OPENCLAW_TIMEZONE || "Asia/Taipei";

// 依 provider 組出記憶搜尋設定：
//  none   → 停用 embedding（僅關鍵字，完全免金鑰）
//  gemini → 用 gemini-embedding-001 + 既有 GEMINI_API_KEY（推薦；免 OpenAI、保留語意）
//  其他   → 僅設 provider（openai/local/ollama…，需自備對應金鑰）
function buildMemorySearch(provider, e) {
  if (provider === "none") return { enabled: false };
  if (provider === "gemini") {
    const ms = { provider: "gemini", model: "gemini-embedding-001" };
    if (e.GEMINI_API_KEY) ms.remote = { apiKey: e.GEMINI_API_KEY };
    return ms;
  }
  return { provider };
}

const config = {
  gateway: {
    auth: { mode: "token", token },
    // control UI 自 v2026.2.26 起，非 loopback 部署必須設 allowedOrigins，否則回 403。
    // dangerouslyAllowHostHeaderOriginFallback：允許無 Origin header 的請求用 Host 判定。
    // dangerouslyDisableDeviceAuth：Cloud Run 純遠端，僅持 token 的瀏覽器 control UI 跳過裝置配對。
    controlUi: {
      allowedOrigins: [publicUrl, "http://localhost:8080", "http://127.0.0.1:8080"],
      dangerouslyAllowHostHeaderOriginFallback: true,
      dangerouslyDisableDeviceAuth: true,
    },
    trustedProxies: ["169.254.169.126", "127.0.0.1"],
  },
  channels: {},
  // 提醒/排程功能（未啟用時 bot 設定提醒會出現 Cron tool error）
  cron: { enabled: true, maxConcurrentRuns: 8, sessionRetention: "24h" },
  agents: {
    defaults: {
      model: { primary: model },
      memorySearch: buildMemorySearch(memoryProvider, env),
      userTimezone,
      timeFormat: "24",
    },
  },
};

// Vertex AI（google-vertex/*）：agent 解析需在 models.providers 放「憑證標記」apiKey，
// 否則會 model_not_found。實際憑證走 GOOGLE_APPLICATION_CREDENTIALS 指向的 ADC 檔（authorized_user）。
if (model.startsWith("google-vertex/")) {
  config.models = { providers: { "google-vertex": { apiKey: "gcp-vertex-credentials" } } };
}

if (bool(env.GOOGLECHAT_ENABLED, true)) {
  const gc = {
    enabled: true,
    audienceType: "app-url",
    audience: `${audience}/googlechat`,
    webhookPath: "/googlechat",
    dm: { policy: "open", allowFrom: ["*"] },
    groupPolicy: "open",
  };
  if (saFile) gc.serviceAccountFile = saFile;
  config.channels.googlechat = gc;
}

if (env.LINE_CHANNEL_SECRET && env.LINE_CHANNEL_ACCESS_TOKEN) {
  config.channels.line = {
    enabled: true,
    channelSecret: env.LINE_CHANNEL_SECRET,
    channelAccessToken: env.LINE_CHANNEL_ACCESS_TOKEN,
    webhookPath: "/line",
    dmPolicy: "open",
    allowFrom: ["*"],
    groupPolicy: "open",
    groups: { "*": { requireMention: true } },
  };
}

const json = JSON.stringify(config, null, 2);
const outPath = env.OPENCLAW_CONFIG_PATH;
const forceStdout = process.argv.includes("--stdout");

if (outPath && !forceStdout) {
  writeFileSync(outPath, json + "\n");
  console.error(`[gen-config] wrote ${outPath}`);
} else {
  process.stdout.write(json + "\n");
}
