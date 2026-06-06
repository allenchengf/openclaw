# syntax=docker/dockerfile:1
# openclaw-Taiwan Cloud Run 映像
#
# 採 npm 預編譯套件安裝 OpenClaw，而非從原始碼 build：
# 從原始碼 build 時 tsdown/rolldown 編譯整個 monorepo 會在 Cloud Build 內 OOM 卡死
# （實測 1vCPU / 8vCPU 皆然）。npm 套件 `openclaw`（bin: openclaw）已含
# gateway / channels / control UI，建置從 30 分鐘卡死降為約 3 分鐘。
#
# 建置（context 必須是 repo 根目錄，因為會 COPY extensions/）：
#   docker build -f deploy/Dockerfile --build-arg OPENCLAW_VERSION=2026.6.1 -t clawdbot .

ARG NODE_VERSION=22-bookworm-slim
FROM node:${NODE_VERSION}

# 執行期相依：git（部分 agent 功能需要）、ca-certificates（HTTPS）、tini（PID 1 正確處理訊號）
RUN apt-get update && apt-get install -y --no-install-recommends \
      git ca-certificates tini tzdata \
    && rm -rf /var/lib/apt/lists/*

# 時區：預設台灣（可由執行期 TZ 環境變數覆寫）
ENV TZ=Asia/Taipei

WORKDIR /app

# 安裝 OpenClaw CLI（預編譯，不在容器內編譯原始碼）
ARG OPENCLAW_VERSION=2026.6.1
RUN npm install -g "openclaw@${OPENCLAW_VERSION}" \
    && openclaw --version

# 本專案檔案：entrypoint + 設定產生器 + 擴充套件
COPY deploy/entrypoint.sh /app/deploy/entrypoint.sh
COPY deploy/gen-config.mjs /app/deploy/gen-config.mjs
COPY extensions /app/extensions
RUN chmod +x /app/deploy/entrypoint.sh

ENV NODE_ENV=production \
    PORT=8080
# 注意：不要設 OPENCLAW_HOME=/root/.openclaw。openclaw 把 OPENCLAW_HOME 當「家目錄基底」
# 會再接 .openclaw/，導致設定路徑變成 /root/.openclaw/.openclaw/ → CLI/記憶同步找不到設定、
# 模型掉回預設、記憶 embedding 誤用 OpenAI。改用 $HOME（/root）預設即可，設定在 /root/.openclaw/。

EXPOSE 8080

# 用 tini 當 PID 1，確保 SIGTERM 能正確傳給 gateway（Cloud Run 縮容時優雅結束）
ENTRYPOINT ["/usr/bin/tini", "--", "/app/deploy/entrypoint.sh"]
