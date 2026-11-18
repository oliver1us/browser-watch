FROM node:24-trixie-slim

ARG PLAYWRIGHT_MCP_VERSION=0.0.85
ARG BROWSER_USE_VERSION=1.0.6

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates chromium chromium-sandbox curl fonts-liberation \
        novnc python3-venv websockify x11-utils x11vnc xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --global --no-audit --no-fund \
        "@playwright/mcp@${PLAYWRIGHT_MCP_VERSION}" \
    && npm cache clean --force \
    && python3 -m venv /opt/browser-use \
    && /opt/browser-use/bin/pip install --no-cache-dir "browser-use==${BROWSER_USE_VERSION}"

ENV HOME=/home/node \
    PATH=/opt/browser-use/bin:$PATH \
    BU_CDP_URL=http://127.0.0.1:9222 \
    BU_CDP_WS="" \
    BH_TAB_MARKER=0

RUN install -d -o node -g node -m 0700 /home/node/profile \
    && chown node:node /usr/share/novnc/mandatory.json
COPY --chmod=0755 entrypoint.sh /usr/local/bin/browser-watch

USER node
WORKDIR /home/node
EXPOSE 6080 8931

# An MCP GET without a session returns 400 once the transport is listening.
HEALTHCHECK --interval=20s --timeout=5s --start-period=30s \
    CMD curl -fsS -o /dev/null http://127.0.0.1:9222/json/version \
        && curl -fsS -o /dev/null http://127.0.0.1:6080/vnc.html \
        && test "$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:8931/mcp)" = 400

ENTRYPOINT ["/usr/local/bin/browser-watch"]
