# Umi-OCR Wayland 截屏修复补丁

让 [Umi-OCR](https://github.com/hiroi-sora/Umi-OCR) 在 **Wayland 会话（KDE Plasma / GNOME / wlroots）** 下恢复「截图 OCR」功能。

> 上游现状：Umi-OCR 官方明确声明**不支持 Wayland 截屏**（[Umi-OCR_runtime_linux README](https://github.com/hiroi-sora/Umi-OCR_runtime_linux)：*"截图OCR（不支持 Wayland，仅在 x 会话下可用）"*），并建议用户切换到 Xorg 会话。相关 issue：[#975](https://github.com/hiroi-sora/Umi-OCR/issues/975)、[#988](https://github.com/hiroi-sora/Umi-OCR/issues/988)、[#1073](https://github.com/hiroi-sora/Umi-OCR/issues/1073)。
>
> 本补丁不改动上游源码仓库，只对已解压的 Linux 发行包打一个 Python 补丁，让截图走桌面自带的截图工具。

## 问题现象

在 Wayland 会话中点击「截图 OCR」，会出现：

```
显示器： eDP-1
错误信息： [Error] width=0, height=0
```

或者截图窗口能弹出，但**画面全黑**，只能看到十字光标。

## 根因

Umi-OCR 的截图实现（`py_src/image_controller/screenshot_controller.py`）直接调用 Qt 的 `QScreen.grabWindow(0)`：

| 启动方式 | `grabWindow(0)` 结果 | 原因 |
| --- | --- | --- |
| `QT_QPA_PLATFORM=wayland` | `0 x 0` 空图 | Wayland 协议不提供全屏抓取接口，Qt 无权截屏 |
| `QT_QPA_PLATFORM=xcb`（XWayland） | 有尺寸但**全黑** | XWayland 只能看到 X11 窗口，看不到 Wayland 原生窗口 |

这是 Wayland 的安全模型决定的，不是 Umi-OCR 的 bug，但可以通过调用桌面环境提供的合法截图接口绕开。

## 解决方案

补丁在 `getScreenshot()` 里加了一层「外部截图后端」：

1. 检测到 Wayland 会话（`platformName().startswith("wayland")` 或存在 `WAYLAND_DISPLAY`）时，优先调用系统截图工具抓取**整个桌面**；
2. 按各显示器的 `geometry()` 与整图尺寸的比例，裁切出每块屏幕的图像；
3. 设置 `devicePixelRatio`，保证 QML 侧按逻辑像素显示，不模糊、不偏移；
4. 外部工具全部失败时，**自动回退**到原来的 `screen.grabWindow(0)`，X11 用户完全不受影响。

支持的截图后端（按优先级自动探测）：

| 后端 | 适用桌面 | 命令 |
| --- | --- | --- |
| `spectacle` | KDE Plasma | `spectacle -b -n -f -o <png>` |
| `grim` | wlroots 系（Sway / Hyprland / river） | `grim <png>` |
| `gnome-screenshot` | GNOME | `gnome-screenshot -f <png>` |

只要装了其中任意一个即可。**KDE 用户无需额外安装**，Spectacle 是 Plasma 自带组件。

## 安装

### 方式一：一键脚本（推荐）

```bash
git clone https://github.com/lilyco-42/umi-ocr-wayland-patch.git
cd umi-ocr-wayland-patch
./scripts/install.sh ~/下载/Umi-OCR_Linux_Paddle_2.1.5
```

参数是 Umi-OCR 的解压目录（含 `umi-ocr.sh` 的那一层）。

### 方式二：手动打补丁

```bash
cd /path/to/Umi-OCR_Linux_Paddle_2.1.5/UmiOCR-data
cp py_src/image_controller/screenshot_controller.py py_src/image_controller/screenshot_controller.py.orig.bak
patch -p1 py_src/image_controller/screenshot_controller.py < /path/to/umi-ocr-wayland-screenshot.patch
```

> 补丁以 `a/py_src/...` 形式记录路径，因此用 `-p1` 去掉第一层前缀，在 `UmiOCR-data/` 目录下应用。

### 启动方式

打完补丁后，用正常方式启动即可。但**推荐**用仓库里的启动脚本，它会补上 Linux 下必须的 Qt 插件环境变量：

```bash
./scripts/launch.sh /path/to/Umi-OCR_Linux_Paddle_2.1.5
```

## 验证

```bash
# 截取左上角 1200x600 区域并 OCR，结果直接打印到终端
./umi-ocr.sh --screenshot rect=0,0,1200,600
```

如果输出了屏幕上的真实文字，说明补丁生效。

也可以直接测试截图模块：

```bash
cd UmiOCR-data
source .embeddable/activate.sh
export DISPLAY=:0 WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000
export QT_QPA_PLATFORM=wayland
export QT_QPA_PLATFORM_PLUGIN_PATH=$PWD/.embeddable/lib/python3.10/site-packages/PySide2/Qt/plugins
export QML2_IMPORT_PATH=$PWD/.embeddable/lib/python3.10/site-packages/PySide2/Qt/qml
python3 -c "
from PySide2.QtGui import QGuiApplication
app = QGuiApplication([])
import sys; sys.path[:0] = ['..', '../py_src/imports']
from py_src.image_controller import screenshot_controller as sc
print(sc.ScreenshotController.getScreenshot(0))
"
```

## 已知限制

- **多屏缩放不一致**时（例如一块 100% 一块 200%），裁切依赖整图与虚拟桌面尺寸的线性比例，可能有个别像素偏差。单屏或缩放一致的场景完全正常。
- 依赖桌面截图工具。**纯 Wayland 且没装 spectacle / grim / gnome-screenshot 的环境**无法工作——这是 Wayland 的硬限制，Qt 无法自行抓屏。
- 补丁针对 **Umi-OCR 2.1.5 Linux Paddle 版**验证。其他版本若 `screenshot_controller.py` 结构相同则同样适用；上游若重构该文件，需重新适配。
- 弹窗截屏（`--screenshot` 无参数的手动框选）依赖主窗口隐藏 + 外部工具抓屏，实测延迟约 0.5 秒，可接受。

## 测试环境

- CachyOS Linux，kernel 6.18.55-2-cachyos-lts
- KDE Plasma 6.8.2，Wayland 会话（`XDG_SESSION_TYPE=wayland`）
- Umi-OCR 2.1.5 Linux Paddle 版（内置 Python 3.10.4 + PySide2 5.15.2）
- 单屏 eDP-1，2880×1800 物理 / 1440×900 逻辑（devicePixelRatio=2）

验证结果：`getScreenshot()` 返回 2880×1800 的图，采样 80 种不同颜色（非黑屏），耗时约 520ms；`--screenshot rect=0,0,1200,600` 成功识别出屏幕上的真实文字。

## 卸载 / 回滚

```bash
./scripts/install.sh --uninstall /path/to/Umi-OCR_Linux_Paddle_2.1.5
```

或者直接恢复备份：`cp <UmiOCR-data>/py_src/image_controller/screenshot_controller.py.orig.bak <...>/screenshot_controller.py`

## 许可

本补丁以 **MIT** 协议发布。Umi-OCR 本身亦为 MIT 协议，版权归 [hiroi-sora](https://github.com/hiroi-sora) 所有。本仓库仅包含补丁文件与脚本，不包含 Umi-OCR 的任何原始代码。

## 相关链接

- [Umi-OCR 主仓库](https://github.com/hiroi-sora/Umi-OCR)
- [Umi-OCR Linux 运行时](https://github.com/hiroi-sora/Umi-OCR_runtime_linux)
- [Wayland 截屏黑屏 issue #975](https://github.com/hiroi-sora/Umi-OCR/issues/975)