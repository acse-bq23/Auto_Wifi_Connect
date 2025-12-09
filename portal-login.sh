#!/bin/bash
# auto_wifi/portal-login.sh —— 关键日志  + DEBUG 开关（DEBUG=1 时仍可追踪每行）
set -euo pipefail
PROJ="$(cd "$(dirname "$0")" && pwd)"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
export PLAYWRIGHT_BROWSERS_PATH="$PROJ/ms-playwright"

NODE_SCRIPT="$PROJ/portal-login.mjs"
LOG="$PROJ/portal-login.log"

# ── 轻量日志函数 ──────────────────────────────
log(){ printf "%s %s\n" "$(date '+%F %T')" "$*" >>"$LOG"; }

# DEBUG 环境变量可打开 bash -x 追踪
if [[ ${DEBUG:-0} == 1 ]]; then
  # 所有输出到同一个文件
  exec >>"$LOG" 2>&1
  set -x
fi

# ── 在线探针：任一成功即视为已联网 ───────────
is_online(){
  local probes=(
    "http://neverssl.com/"
    "http://www.msftconnecttest.com/connecttest.txt"
    "http://captive.apple.com/hotspot-detect.html"
    "https://www.qq.com"
    "https://www.baidu.com"
  )
  for u in "${probes[@]}"; do
    if curl -I -s --max-time 5 "$u" | head -1 | grep -qE ' 200| 30[12]'; then
      return 0
    fi
  done
  return 1
}

# ── 门户探测（5 秒）───────────────────────────
portal_detect(){
  curl -I -s --max-time 5 "http://114.114.114.114:90/" |
  awk 'NR==1{exit ($2 ~ /^(200|30[1237])$/ ? 0 : 1)}'
}

# ── 主流程 ────────────────────────────────────
if is_online; then
  exit 0                           # 已联网静默退出
fi

if portal_detect; then
  log "start login"
  node "$NODE_SCRIPT" >>"$LOG" 2>&1 || true
  sleep 2
  if is_online; then
    log "login ok"
    exit 0
  else
    log "login fail"
    exit 2
  fi
fi

# 无门户（可能 Wi-Fi 未连）→ 静默退出
exit 0
