#!/bin/bash
# =============================================================================
# MoodBall 一键安装脚本
#
# 功能：
#   1. 检查 DeepSeek Harness (dsh) 是否已安装
#   2. 检查/安装 dsh-moodball 插件（状态接口的生产者，纯 host 无网页 UI）
#   3. 把 MoodBall.app 复制到 ~/Applications 并启动
#
# 依赖：
#   - macOS 14+
#   - DeepSeek Harness（需已安装，未安装会提示）
#   - Node.js + pnpm（安装插件时用到）
#
# 用法：
#   curl -fsSL https://github.com/sundusk/dsh-moodball/raw/refs/heads/main/install.sh | bash
#   或下载后本地执行：./install.sh
#   注：raw.githubusercontent.com 的 CDN 对最近提交有缓存滞后（可能拿到旧版脚本），
#       故用 github.com/.../raw/refs/heads/main/... 路径（内部走 API 重定向，更及时）。
# =============================================================================
set -euo pipefail

PLUGIN_SPEC="github:sundusk/dsh-moodball"
STATUS_URL="http://127.0.0.1:3080/api/moodball/status"
APP_SRC="dist/MoodBall.app"
APP_DEST="$HOME/Applications/MoodBall.app"

# 带颜色输出
info()  { printf "\033[1;34m[info]\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m[ok]\033[0m   %s\n" "$1"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$1"; }
err()   { printf "\033[1;31m[error]\033[0m %s\n" "$1"; }

# 定位 dsh 命令：curl|bash 的非交互 shell PATH 可能不含 npx 缓存路径，做多路回退
find_dsh() {
    command -v dsh 2>/dev/null && return 0
    # npx 缓存里的 dsh（常见安装位置）
    local cand
    cand=$(ls -d "$HOME"/.npm/_npx/*/node_modules/.bin/dsh 2>/dev/null | head -1)
    [ -n "$cand" ] && { echo "$cand"; return 0; }
    return 1
}

# ---------------------------------------------------------------- 1. 检查插件（接口优先）
info "检查 MoodBall 状态插件是否已安装……"
if curl -fsS -m 2 "$STATUS_URL" >/dev/null 2>&1; then
    ok "插件已就绪（$STATUS_URL 可访问）"
    HAS_PLUGIN=1
else
    warn "状态接口不可达（DSH 未启动，或插件未安装）。"
    HAS_PLUGIN=0
fi

# ---------------------------------------------------------------- 2. 检查 dsh（仅装插件时需要）
DSH_BIN=""
if [ "$HAS_PLUGIN" = "1" ]; then
    # 插件已就绪：装 app 不需要 dsh 命令，跳过检测
    if DSH_BIN=$(find_dsh); then
        ok "DeepSeek Harness 已安装（$(basename "$DSH_BIN")）"
    else
        ok "插件已就绪，跳过 dsh 检测（安装 app 不需要 dsh 命令）"
    fi
else
    if DSH_BIN=$(find_dsh); then
        ok "DeepSeek Harness 已安装：$("$DSH_BIN" --version 2>/dev/null | head -1 || echo '?')"
    else
        err "未检测到 DeepSeek Harness（dsh 命令不存在，且未在常见位置找到）。"
        echo ""
        echo "请先安装并启动 DeepSeek Harness，然后再运行本脚本。"
        echo "安装方法见：https://github.com/sundusk/dsh-moodball#-安装依赖"
        echo "（提示：curl|bash 的子 shell 可能读不到你 shell 里配置的 PATH，"
        echo "  如 dsh 可运行，可先 source 你的 shell 配置或改用：bash install.sh）"
        exit 1
    fi

    # 插件不可用且 dsh 就绪 → 自动装插件
    if ! command -v pnpm >/dev/null 2>&1 && ! command -v node >/dev/null 2>&1; then
        err "未检测到 Node.js/pnpm，无法自动安装插件。"
        echo "请先安装 Node.js（https://nodejs.org），再运行本脚本。"
        exit 1
    fi
    if ! "$DSH_BIN" plugin --profile web add "$PLUGIN_SPEC" 2>&1; then
        err "插件安装失败。请手动执行："
        echo "  dsh plugin --profile web add $PLUGIN_SPEC"
        echo "然后重启 dsh web。"
        exit 1
    fi
    ok "插件已安装。"
    warn "需要重启 dsh web（终端里 Ctrl+C 后重新运行 dsh web）插件才会生效，"
    warn "重启后请重新运行本脚本以继续安装 app。"
    exit 0
fi

# ---------------------------------------------------------------- 3. 获取 app
RELEASE_VERSION="v0.4.0"
RELEASE_URL="https://github.com/sundusk/dsh-moodball/releases/download/$RELEASE_VERSION/MoodBall.app.zip"
APP_TMP=""

# 优先用本地构建产物（开发者场景）；否则从 GitHub Release 下载（普通用户场景）
if [ -d "$APP_SRC" ]; then
    ok "使用本地构建产物 $APP_SRC"
else
    info "未找到本地 ${APP_SRC}，从 GitHub Release 下载……"
    APP_TMP="$(mktemp -d)"
    if ! curl -fsSL -m 120 -o "$APP_TMP/MoodBall.app.zip" "$RELEASE_URL"; then
        err "下载 Release 失败：$RELEASE_URL"
        echo "请检查网络，或手动下载：$RELEASE_URL"
        exit 1
    fi
    if ! unzip -qo "$APP_TMP/MoodBall.app.zip" -d "$APP_TMP"; then
        err "解压失败（需要 unzip 命令）。"
        exit 1
    fi
    APP_SRC="$APP_TMP/MoodBall.app"
    ok "已下载并解压 Release 版 app"
fi

# ---------------------------------------------------------------- 4. 安装 app
if [ ! -d "$APP_SRC" ]; then
    err "未找到 $APP_SRC —— app 获取失败。"
    exit 1
fi

# 旧版 Waterball.app（/Applications）自动迁移：退出旧球并移除，避免菜单栏双球并存
if [ -d "/Applications/Waterball.app" ]; then
    info "检测到旧版 Waterball.app（/Applications），正在退出并移除（迁移到 MoodBall）……"
    osascript -e 'tell application "Waterball" to quit' 2>/dev/null || true
    sleep 1
    if pgrep -x Waterball >/dev/null 2>&1; then
        pkill -x Waterball 2>/dev/null || true
    fi
    rm -rf "/Applications/Waterball.app"
    ok "旧版 Waterball.app 已移除"
fi

if [ -d "$APP_DEST" ]; then
    info "已存在 ${APP_DEST}，先移除旧版本……"
    rm -rf "$APP_DEST"
fi

info "复制 app 到 $APP_DEST ……"
cp -R "$APP_SRC" "$APP_DEST"
xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
ok "app 已安装到 $APP_DEST"

if [ -n "$APP_TMP" ]; then
    rm -rf "$APP_TMP"
fi

info "启动 MoodBall……"
open "$APP_DEST"
ok "启动完成！"

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ 安装完成！桌面右下角会出现一颗发光呼吸球（心情球）。"
echo ""
echo "  说明："
echo "  - 状态由 dsh-moodball-status 插件提供（纯 host，无网页水球），"
echo "    接口常驻 /api/moodball/status，桌面球随 agent 状态变色。"
echo "  - 想在网页也看到水球？单独安装 dsh-waterball-pet"
echo "    （Web UI 水球宠物）即可，两者互不影响。"
echo "  - 菜单栏图标可：显示/隐藏悬浮球、打开设置、退出。"
echo "  - 设置面板可调大小/颜色/呼吸速度/API 地址等。"
echo "══════════════════════════════════════════════════════════════"
