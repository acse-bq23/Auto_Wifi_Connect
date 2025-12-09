#!/bin/bash
# 一键部署（macOS，launchd）
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.autowifi.portal-login.plist"
ENV_FILE="$BASE/.env"
export PLAYWRIGHT_BROWSERS_PATH="$BASE/ms-playwright"

log() { printf "%s %s\n" "$(date '+%F %T')" "$*"; }

# 1) 环境检查
if ! command -v node >/dev/null 2>&1; then
  echo "需要先安装 Node.js (>=18)。可执行：HOMEBREW_NO_AUTO_UPDATE=1 brew install node    （或使用 nvm 安装）"
  exit 1
fi
if ! command -v npm >/dev/null 2>&1; then
  echo "未找到 npm，通常随 Node.js 一起安装。可执行：HOMEBREW_NO_AUTO_UPDATE=1 brew install node"
  exit 1
fi

# 2) 确保依赖
if [ ! -d "$BASE/node_modules" ]; then
  log "安装依赖..."
  (cd "$BASE" && npm install)
fi

# 2.1) 确保 Playwright 浏览器内核
if [ ! -d "$BASE/ms-playwright" ]; then
  log "安装 Playwright 浏览器内核（chromium）..."
  (cd "$BASE" && PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_PATH" npx playwright install chromium)
fi

# 3) 确保 .env 存在
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$BASE/.env.example" ]; then
    cp "$BASE/.env.example" "$ENV_FILE"
    log "已生成 .env，请填写账号/密码/门户地址后再运行 deploy.sh"
    exit 1
  else
    echo ".env 不存在且缺少 .env.example，请手动创建"; exit 1
  fi
fi

# 4) 读取 .env，校验必填（注意密码含 $ 时请用单引号包裹，防止被 shell 展开）
set +u
set -a
source "$ENV_FILE"
set +a
set -u

if [ -z "${PORTAL_ACCOUNT:-}" ] || [ -z "${PORTAL_PASSWORD:-}" ]; then
  echo "请在 .env 中填写 PORTAL_ACCOUNT / PORTAL_PASSWORD"; exit 1
fi

# 5) 写入 plist
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>com.autowifi.portal-login</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/zsh</string>
      <string>-lc</string>
      <string>cd "$BASE" && ./portal-login.sh</string>
    </array>
    <key>StartInterval</key><integer>120</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>$BASE/launchd.out.log</string>
    <key>StandardErrorPath</key><string>$BASE/launchd.err.log</string>
  </dict>
</plist>
EOF

log "写入 plist -> $PLIST"

# 6) 启动 launchd
launchctl bootout gui/$UID "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap gui/$UID "$PLIST"
launchctl enable gui/$UID/com.autowifi.portal-login
launchctl kickstart -k gui/$UID/com.autowifi.portal-login

log "部署完成：已启用 launchd 周期巡检（300s）并开机自启"
log "查看日志：tail -f $BASE/portal-login.log"

