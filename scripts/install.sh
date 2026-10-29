#!/usr/bin/env bash
# ============================================================
# Umi-OCR Wayland 截屏补丁 —— 安装 / 卸载脚本
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_FILE="$SCRIPT_DIR/../patch/umi-ocr-wayland-screenshot.patch"
REL_FROM_DATA="py_src/image_controller/screenshot_controller.py"
TARGET_REL="UmiOCR-data/$REL_FROM_DATA"
BACKUP_SUFFIX=".orig.bak"

RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'; RESET='\033[0m'
info() { echo -e "${GREEN}[+]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
die()  { echo -e "${RED}[x]${RESET} $*" >&2; exit 1; }

usage() {
  cat <<EOF
用法: $(basename "$0") [--uninstall] <Umi-OCR 解压目录>

  <Umi-OCR 解压目录>  含 umi-ocr.sh 的那一层目录
  --uninstall         从备份恢复原始文件
  -h, --help          显示本帮助

示例:
  $(basename "$0") ~/下载/Umi-OCR_Linux_Paddle_2.1.5
  $(basename "$0") --uninstall ~/下载/Umi-OCR_Linux_Paddle_2.1.5
EOF
}

UNINSTALL=0
APP_DIR=""
for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
    -h|--help)   usage; exit 0 ;;
    -*)          die "未知选项: $arg" ;;
    *)           APP_DIR="$arg" ;;
  esac
done

[ -n "$APP_DIR" ] || { usage; die "缺少 Umi-OCR 解压目录"; }
APP_DIR="$(cd "$APP_DIR" && pwd)" || die "目录不存在: $APP_DIR"

TARGET="$APP_DIR/$TARGET_REL"
[ -f "$TARGET" ] || die "找不到目标文件: $TARGET
请确认参数是含 umi-ocr.sh 的 Umi-OCR 解压目录。"
BACKUP="$TARGET$BACKUP_SUFFIX"

# ---------------- 卸载 ----------------
if [ "$UNINSTALL" = "1" ]; then
  if [ ! -f "$BACKUP" ]; then
    die "找不到备份文件: $BACKUP （可能未安装过，或备份已被删除）"
  fi
  cp -f "$BACKUP" "$TARGET"
  info "已从备份恢复: $TARGET"
  warn "备份文件保留在: $BACKUP （可手动删除）"
  exit 0
fi

# ---------------- 安装 ----------------
[ -f "$PATCH_FILE" ] || die "找不到补丁文件: $PATCH_FILE"

# 已打过补丁则跳过
if grep -q "_grabDesktop" "$TARGET" 2>/dev/null; then
  warn "目标文件似乎已打过补丁，跳过。如需重装请先 --uninstall。"
  exit 0
fi

# 备份（不覆盖已有备份，保证备份始终是最原始的版本）
if [ ! -f "$BACKUP" ]; then
  cp -f "$TARGET" "$BACKUP"
  info "已备份原文件 -> $BACKUP"
else
  info "备份已存在，沿用: $BACKUP"
fi

# 应用补丁
cd "$APP_DIR/UmiOCR-data"
if command -v patch >/dev/null 2>&1; then
  if ! patch -p1 --forward "$REL_FROM_DATA" < "$PATCH_FILE"; then
    warn "patch 应用失败，尝试用 git apply ..."
    cp -f "$BACKUP" "$TARGET"
    git apply -p1 "$PATCH_FILE" || die "补丁应用失败，已回滚。请手动检查。"
  fi
else
  warn "系统无 patch 命令，尝试用 git apply ..."
  command -v git >/dev/null 2>&1 || die "既没有 patch 也没有 git，无法应用补丁。请安装 patch。"
  git apply -p1 "$PATCH_FILE" || { cp -f "$BACKUP" "$TARGET"; die "补丁应用失败，已回滚。"; }
fi

# 语法检查
PY=""
for cand in "$APP_DIR/UmiOCR-data/.embeddable/bin/python3" python3; do
  if command -v "$cand" >/dev/null 2>&1; then PY="$cand"; break; fi
done
if [ -n "$PY" ]; then
  if "$PY" -c "import ast,sys;ast.parse(open(sys.argv[1]).read())" "$TARGET" 2>/dev/null; then
    info "语法检查通过"
  else
    warn "语法检查失败，回滚！"
    cp -f "$BACKUP" "$TARGET"
    die "已回滚到原始文件。"
  fi
fi

info "补丁安装完成"
echo
echo "下一步："
echo "  1. 重启 Umi-OCR"
echo "  2. 确保装了任一截图工具（KDE 自带 spectacle，wlroots 用 grim，GNOME 用 gnome-screenshot）"
echo "  3. 验证：./umi-ocr.sh --screenshot rect=0,0,1200,600"