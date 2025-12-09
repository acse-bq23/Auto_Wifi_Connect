#!/bin/bash
# 一键解除（macOS，launchd）
set -euo pipefail

PLIST="$HOME/Library/LaunchAgents/com.autowifi.portal-login.plist"

if [ -f "$PLIST" ]; then
  launchctl bootout gui/$UID "$PLIST" >/dev/null 2>&1 || true
  rm -f "$PLIST"
  echo "已移除 $PLIST"
else
  echo "未找到 $PLIST，可能已卸载"
fi

echo "如需保留日志，可手动删除项目目录下的 *.log"

