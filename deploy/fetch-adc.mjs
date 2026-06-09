#!/usr/bin/env node
// 從 Secret Manager 取出 Vertex AI 用的 ADC 憑證（authorized_user）寫到指定路徑。
// 供 entrypoint 在 google-vertex/* 模型下啟動時呼叫，讓 Cloud Run / VM 皆免手動佈署金鑰檔。
//
// 認證：用 GCE/Cloud Run metadata server 取 runtime service account 的 access token
//       （該 SA 需有 roles/secretmanager.secretAccessor）。無外部相依，只用 node 內建。
//
// 用法：node fetch-adc.mjs <輸出路徑> <GCP專案ID> [secret名稱=vertex-adc]
import { writeFileSync } from "node:fs";
import https from "node:https";
import http from "node:http";

const outPath = process.argv[2];
const project = process.argv[3];
const secret = process.argv[4] || "vertex-adc";
if (!outPath || !project) {
  console.error("[fetch-adc] usage: node fetch-adc.mjs <outPath> <project> [secret]");
  process.exit(2);
}

function get(url, headers, isHttps = true) {
  const lib = isHttps ? https : http;
  return new Promise((resolve, reject) => {
    const req = lib.get(url, { headers }, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => resolve({ status: res.statusCode, body }));
    });
    req.on("error", reject);
    req.setTimeout(15000, () => req.destroy(new Error("timeout")));
  });
}

try {
  // 1) metadata server 取 access token
  const tok = await get(
    "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
    { "Metadata-Flavor": "Google" },
    false,
  );
  if (tok.status !== 200) throw new Error(`metadata token HTTP ${tok.status}`);
  const accessToken = JSON.parse(tok.body).access_token;
  if (!accessToken) throw new Error("no access_token from metadata");

  // 2) Secret Manager 取 secret 最新版本
  const sm = await get(
    `https://secretmanager.googleapis.com/v1/projects/${project}/secrets/${secret}/versions/latest:access`,
    { Authorization: `Bearer ${accessToken}` },
  );
  if (sm.status !== 200) throw new Error(`secret access HTTP ${sm.status}: ${sm.body.slice(0, 200)}`);
  const data = JSON.parse(sm.body)?.payload?.data;
  if (!data) throw new Error("secret payload empty");

  // 3) base64 解碼寫檔
  const json = Buffer.from(data, "base64").toString("utf8");
  JSON.parse(json); // 驗證是合法 JSON
  writeFileSync(outPath, json, { mode: 0o600 });
  console.error(`[fetch-adc] wrote ADC to ${outPath} (secret=${secret})`);
} catch (e) {
  console.error(`[fetch-adc] ERROR: ${e.message}`);
  process.exit(1);
}
