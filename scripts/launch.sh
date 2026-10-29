#!/usr/bin/env bash
# ============================================================
# Umi-OCR Linux 启动脚本（Wayland 友好）
#
# 解决两个常见启动问题：
#   1. 不 source activate.sh -> 报 libpython3.10.so.1.0: cannot open shared object file
#   2. 不设 QT_QPA_PLATFORM_PLUGIN_PATH / QML2_IMPORT_PATH
#      -> 报 no Qt platform plugin can be initialized
#      -> 或 QML 报 module "QtQuick.Controls" is not installed
# ============================================================
set -euo pipefail

APP_DIR="${1:-}"
if [ -z "$APP_DIR" ]; then
  APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
if [ ! -f "$APP_DIR/umi-ocr.sh" ]; then
  echo "[x] 找不到 $APP_DIR/umi-ocr.sh" >&2
  echo "用法: $(basename "$0") <Umi-OCR 解压目录>" >&2
  exit 1
fi
APP_DIR="$(cd "$APP_DIR" && pwd)"
DATA_DIR="$APP_DIR/UmiOCR-data"
SITE="$DATA_DIR/.embeddable/lib/python3.10/site-packages"

# Qt 插件 / QML 模块路径（必须，否则找不到平台插件与 QML 模块）
export QT_QPA_PLATFORM_PLUGIN_PATH="$SITE/PySide2/Qt/plugins"
export QML2_IMPORT_PATH="$SITE/PySide2/Qt/qml"

# Wayland 会话下的建议设置：
#   用 wayland 平台插件（配合补丁里的外部截图后端）；
#   如果遇到输入法/窗口异常，可改成 xcb 并配合 QT_WAYLAND_RECONNECT=1
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
  export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
fi

# XDG_RUNTIME_DIR 缺失时补上（从 cron/服务启动时常见）
if [ -z "${XDG_RUNTIME_DIR:-}" ] && [ -d "/run/user/$(id -u)" ]; then
  export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

exec "$APP_DIR/umi-ocr.sh" "${@:2}"
