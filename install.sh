#!/bin/bash
# =============================================================================
# MoodBall 一键安装脚本
#
# 安装层会绑定到用户实际使用的 Harness：
#   - Source：在 sourceRoot 内执行 pnpm dsh
#   - NPM/NPX：执行 dsh 或 npx @deepseek-ai/dsh
#   - Desktop：第一阶段只检测，不把插件误装到 web profile
#
# 运行架构不变：DeepSeek Harness → dsh-moodball-status → HTTP / Unix Socket → MoodBall.app
# =============================================================================
set -euo pipefail

PLUGIN_SPEC="github:sundusk/dsh-moodball"
PLUGIN_NAME="@sundusk/dsh-moodball-status"
PLUGIN_PROFILE="web"
STATUS_URL="${MOODBALL_STATUS_URL:-http://127.0.0.1:3080/api/moodball/status}"
SOCKET_PATH="${MOODBALL_SOCKET_PATH:-$HOME/Library/Application Support/MoodBall/moodball.sock}"
APP_SRC="dist/MoodBall.app"
RELEASE_URL="https://github.com/sundusk/dsh-moodball/releases/latest/download/MoodBall.app.zip"
CONFIG_PATH="$HOME/Library/Application Support/MoodBall/config.json"

APP_TMP=""
APP_STAGE=""
APP_DEST=""
PNPM_BIN=""
NPX_BIN=""
HARNESS_DSH_BIN=""
HARNESS_TYPE="none"
HARNESS_CLI_KIND=""
HARNESS_SOURCE_ROOT=""
HARNESS_DSH_HOME="${DSH_HOME:-}"
HARNESS_PID=""
HARNESS_RUNNING=0
HARNESS_DISPLAY=""
PLUGIN_STATE="unknown"
PLUGIN_INSTALL_FAILED=0
SAVED_TYPE=""
SAVED_SOURCE_ROOT=""
SAVED_DSH_HOME=""

SOURCE_CANDIDATES=()

# 带颜色输出
info()  { printf "\033[1;34m[info]\033[0m %s\n" "$1"; }
ok()    { printf "\033[1;32m[ok]\033[0m   %s\n" "$1"; }
warn()  { printf "\033[1;33m[warn]\033[0m %s\n" "$1"; }
err()   { printf "\033[1;31m[error]\033[0m %s\n" "$1"; }

cleanup() {
    if [ -n "$APP_TMP" ] && [ -d "$APP_TMP" ]; then
        rm -rf "$APP_TMP"
    fi
    if [ -n "$APP_STAGE" ] && [ -d "$APP_STAGE" ]; then
        rm -rf "$APP_STAGE"
    fi
}
trap cleanup EXIT

normalize_path() {
    local path="$1"
    if [ -d "$path" ]; then
        (cd "$path" 2>/dev/null && pwd -P)
    fi
}

find_pnpm() {
    local candidate
    candidate=$(command -v pnpm 2>/dev/null || true)
    if [ -n "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    for candidate in \
        "$HOME"/.local/bin/pnpm \
        "$HOME"/.npm-global/bin/pnpm \
        "$HOME"/Library/pnpm/pnpm; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_npx() {
    local candidate
    candidate=$(command -v npx 2>/dev/null || true)
    if [ -n "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
    fi
    for candidate in \
        "$HOME"/.npm-global/bin/npx \
        "$HOME"/Library/pnpm/npx; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

find_dsh_bin() {
    local candidate

    candidate=$(command -v dsh 2>/dev/null || true)
    if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" --version >/dev/null 2>&1; then
        printf '%s\n' "$candidate"
        return 0
    fi

    for candidate in \
        "$HOME"/.npm/_npx/*/node_modules/.bin/dsh \
        "$HOME"/.local/bin/dsh \
        "$HOME"/.npm-global/bin/dsh \
        "$HOME"/Library/pnpm/dsh; do
        if [ -x "$candidate" ] && "$candidate" --version >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

source_is_valid() {
    local root
    root=$(normalize_path "$1" || true)
    [ -n "$root" ] || return 1
    [ -f "$root/package.json" ] || return 1
    [ -d "$root/apps/cli" ] || return 1
    [ -f "$root/pnpm-lock.yaml" ] || return 1
    grep -Eq '"dsh"[[:space:]]*:' "$root/package.json"
}

source_root_for_path() {
    local current
    current=$(normalize_path "$1" || true)
    [ -n "$current" ] || return 1

    while [ "$current" != "/" ]; do
        if source_is_valid "$current"; then
            printf '%s\n' "$(normalize_path "$current")"
            return 0
        fi
        current=$(dirname "$current")
    done
    if source_is_valid "/"; then
        printf '%s\n' "/"
        return 0
    fi
    return 1
}

add_source_candidate() {
    local root existing
    root=$(normalize_path "$1" || true)
    source_is_valid "$root" || return 0
    for existing in "${SOURCE_CANDIDATES[@]-}"; do
        [ "$existing" = "$root" ] && return 0
    done
    SOURCE_CANDIDATES[${#SOURCE_CANDIDATES[@]}]="$root"
}

# 只在用户允许的常见目录内、有限深度扫描；跳过依赖和构建目录。
scan_source_dir() {
    local dir="$1"
    local depth="$2"
    local child name

    [ "$depth" -le 3 ] || return 0
    add_source_candidate "$dir"
    [ "$depth" -lt 3 ] || return 0

    for child in "$dir"/*; do
        [ -d "$child" ] || continue
        name=$(basename "$child")
        case "$name" in
            .git|node_modules|.build|build|dist|.cache|Library|Caches)
                continue
                ;;
        esac
        scan_source_dir "$child" $((depth + 1))
    done
}

config_field() {
    local field="$1"
    [ -f "$CONFIG_PATH" ] || return 1

    if command -v node >/dev/null 2>&1; then
        node -e '
          const fs = require("fs")
          try {
            const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"))[process.argv[2]]
            if (typeof value === "string") process.stdout.write(value)
          } catch (_) {}
        ' "$CONFIG_PATH" "$field" 2>/dev/null || true
    else
        sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$CONFIG_PATH" | head -1
    fi
}

process_cwd() {
    local pid="$1"
    command -v lsof >/dev/null 2>&1 || return 1
    lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
}

# 仅取 DSH_HOME，不输出完整的进程环境，避免把其它环境变量写入日志。
process_dsh_home() {
    local pid="$1"
    ps eww -p "$pid" -o command= 2>/dev/null | awk '
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^DSH_HOME=/) {
            sub(/^DSH_HOME=/, "", $i)
            print $i
            exit
          }
        }
      }
    '
}

running_command_is_web() {
    case "$1" in
        *" apps/cli/src/bin.ts web"*|*" apps/cli/src/bin.ts --profile web"*|\
        *"pnpm dsh web"*|*"pnpm dsh --profile web"*|\
        *"@deepseek-ai/dsh web"*|*"@deepseek-ai/dsh --profile web"*|\
        *"/dsh web"*|*"/dsh --profile web"*)
            return 0
            ;;
    esac
    return 1
}

running_command_is_source() {
    case "$1" in
        *"apps/cli/src/bin.ts"*|*"pnpm dsh web"*|*"pnpm dsh --profile web"*)
            return 0
            ;;
    esac
    return 1
}

running_command_is_npm() {
    case "$1" in
        *"@deepseek-ai/dsh"*|*"/.npm/_npx/"*|*"/node_modules/.bin/dsh"*|\
        *"/dsh web"*|*"/dsh --profile web"*)
            return 0
            ;;
    esac
    return 1
}

# 运行中 Source 优先于运行中 NPM；只读扫描，不触碰进程。
detect_running_harness() {
    local pid command cwd root dsh_home
    local source_pid="" source_root="" npm_pid=""

    while read -r pid command; do
        [ -n "$pid" ] || continue
        running_command_is_web "$command" || continue

        if running_command_is_source "$command"; then
            cwd=$(process_cwd "$pid" || true)
            root=$(source_root_for_path "$cwd" || true)
            if [ -n "$root" ] && [ -z "$source_root" ]; then
                source_root="$root"
                source_pid="$pid"
            fi
        elif running_command_is_npm "$command" && [ -z "$npm_pid" ]; then
            npm_pid="$pid"
        fi
    done < <(ps -axo pid=,command= 2>/dev/null || true)

    if [ -n "$source_root" ]; then
        HARNESS_TYPE="source"
        HARNESS_SOURCE_ROOT="$source_root"
        HARNESS_PID="$source_pid"
        HARNESS_RUNNING=1
        dsh_home=$(process_dsh_home "$source_pid" || true)
        [ -n "$dsh_home" ] && HARNESS_DSH_HOME="$dsh_home"
        return 0
    fi

    if [ -n "$npm_pid" ]; then
        HARNESS_TYPE="npm"
        HARNESS_PID="$npm_pid"
        HARNESS_RUNNING=1
        dsh_home=$(process_dsh_home "$npm_pid" || true)
        [ -n "$dsh_home" ] && HARNESS_DSH_HOME="$dsh_home"
        return 0
    fi
    return 1
}

detect_desktop() {
    [ -d "/Applications/DeepSeek Harness.app" ] && return 0
    [ -d "$HOME/Applications/DeepSeek Harness.app" ] && return 0
    [ -d "/Applications/DeepSeek Harness Desktop.app" ] && return 0
    [ -d "$HOME/Applications/DeepSeek Harness Desktop.app" ] && return 0
    return 1
}

find_npm_harness() {
    HARNESS_DSH_BIN=$(find_dsh_bin || true)
    if [ -n "$HARNESS_DSH_BIN" ]; then
        HARNESS_TYPE="npm"
        HARNESS_CLI_KIND="dsh"
        HARNESS_DISPLAY="NPM/NPX Harness（${HARNESS_DSH_BIN}）"
        return 0
    fi

    NPX_BIN=$(find_npx || true)
    if [ -n "$NPX_BIN" ] && "$NPX_BIN" --yes @deepseek-ai/dsh --version >/dev/null 2>&1; then
        HARNESS_TYPE="npm"
        HARNESS_CLI_KIND="npx"
        HARNESS_DISPLAY="NPM/NPX Harness（${NPX_BIN} @deepseek-ai/dsh）"
        return 0
    fi
    return 1
}

choose_source_candidate() {
    local count=${#SOURCE_CANDIDATES[@]}
    local choice

    [ "$count" -gt 0 ] || return 1
    if [ "$count" -eq 1 ]; then
        HARNESS_SOURCE_ROOT="${SOURCE_CANDIDATES[0]}"
        return 0
    fi

    if [ ! -r /dev/tty ]; then
        warn "检测到多个有效 DeepSeek Harness 源码目录，但当前环境不可交互选择。"
        return 1
    fi

    echo "检测到多个 DeepSeek Harness 源码目录，请选择实际使用的版本：" >&2
    local index=1
    for choice in "${SOURCE_CANDIDATES[@]}"; do
        printf '  %s) %s\n' "$index" "$choice" >&2
        index=$((index + 1))
    done
    printf '选择编号（直接回车跳过）： ' >&2
    read -r choice < /dev/tty || true
    case "$choice" in
        ''|*[!0-9]*) return 1 ;;
    esac
    [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ] || return 1
    HARNESS_SOURCE_ROOT="${SOURCE_CANDIDATES[$((choice - 1))]}"
}

select_harness() {
    local env_source saved_source saved_type saved_home

    # 1. 当前正在运行的 Harness。
    if detect_running_harness; then
        if [ "$HARNESS_TYPE" = "source" ]; then
            HARNESS_CLI_KIND="source"
            HARNESS_DISPLAY="DeepSeek Harness 源码版（${HARNESS_SOURCE_ROOT}）"
        else
            if [ -z "$HARNESS_DSH_BIN" ] && [ -z "$NPX_BIN" ]; then
                find_npm_harness || true
            fi
            HARNESS_DISPLAY="DeepSeek Harness NPM/NPX 版"
        fi
        return 0
    fi

    # 2. 环境变量指定的源码根目录。
    env_source="${DSH_SOURCE_ROOT:-}"
    if [ -n "$env_source" ] && source_is_valid "$env_source"; then
        HARNESS_TYPE="source"
        HARNESS_CLI_KIND="source"
        HARNESS_SOURCE_ROOT="$(normalize_path "$env_source")"
        HARNESS_DISPLAY="DeepSeek Harness 源码版（${HARNESS_SOURCE_ROOT}）"
        return 0
    fi

    SAVED_TYPE=$(config_field type || true)
    SAVED_SOURCE_ROOT=$(config_field sourceRoot || true)
    SAVED_DSH_HOME=$(config_field dshHome || true)

    # 3. 最近明确配置的 Harness。
    if [ "$SAVED_TYPE" = "source" ] && source_is_valid "$SAVED_SOURCE_ROOT"; then
        HARNESS_TYPE="source"
        HARNESS_CLI_KIND="source"
        HARNESS_SOURCE_ROOT="$(normalize_path "$SAVED_SOURCE_ROOT")"
        [ -n "$SAVED_DSH_HOME" ] && HARNESS_DSH_HOME="$SAVED_DSH_HOME"
        HARNESS_DISPLAY="DeepSeek Harness 源码版（${HARNESS_SOURCE_ROOT}）"
        return 0
    fi
    if [ "$SAVED_TYPE" = "npm" ] && find_npm_harness; then
        [ -n "$SAVED_DSH_HOME" ] && HARNESS_DSH_HOME="$SAVED_DSH_HOME"
        HARNESS_DISPLAY="${HARNESS_DISPLAY}（最近使用）"
        return 0
    fi

    # 4. 有限搜索 Source；Source 优先于 NPM，但多个仓库必须选择。
    for env_source in "$HOME/Projects" "$HOME/Developer" "$HOME/Documents" "$HOME/Desktop"; do
        [ -d "$env_source" ] && scan_source_dir "$env_source" 0
    done
    if choose_source_candidate; then
        HARNESS_TYPE="source"
        HARNESS_CLI_KIND="source"
        HARNESS_DISPLAY="DeepSeek Harness 源码版（${HARNESS_SOURCE_ROOT}）"
        return 0
    fi

    # 5. 没有 Source 目标时才选择 NPM/NPX。
    if find_npm_harness; then
        return 0
    fi

    # 6. Desktop 只检测，不把插件装到 web profile 冒充支持。
    if detect_desktop; then
        HARNESS_TYPE="desktop"
        HARNESS_DISPLAY="DeepSeek Harness Desktop"
        return 0
    fi

    HARNESS_TYPE="none"
    HARNESS_DISPLAY="未检测到 DeepSeek Harness"
    return 1
}

# 统一 HarnessCLI 边界；调用方不直接拼接 dsh/pnpm dsh 命令。
harness_cli() {
    case "$HARNESS_TYPE" in
        source)
            [ -n "$PNPM_BIN" ] || return 127
            if [ -n "$HARNESS_DSH_HOME" ]; then
                (cd "$HARNESS_SOURCE_ROOT" && DSH_HOME="$HARNESS_DSH_HOME" "$PNPM_BIN" dsh "$@")
            else
                (cd "$HARNESS_SOURCE_ROOT" && "$PNPM_BIN" dsh "$@")
            fi
            ;;
        npm)
            if [ "$HARNESS_CLI_KIND" = "npx" ]; then
                [ -n "$NPX_BIN" ] || return 127
                if [ -n "$HARNESS_DSH_HOME" ]; then
                    DSH_HOME="$HARNESS_DSH_HOME" "$NPX_BIN" --yes @deepseek-ai/dsh "$@"
                else
                    "$NPX_BIN" --yes @deepseek-ai/dsh "$@"
                fi
            else
                [ -n "$HARNESS_DSH_BIN" ] || return 127
                if [ -n "$HARNESS_DSH_HOME" ]; then
                    DSH_HOME="$HARNESS_DSH_HOME" "$HARNESS_DSH_BIN" "$@"
                else
                    "$HARNESS_DSH_BIN" "$@"
                fi
            fi
            ;;
        *)
            return 127
            ;;
    esac
}

harness_cli_version() {
    harness_cli --version 2>/dev/null | head -1 || true
}

plugin_is_installed() {
    local inventory
    if ! inventory=$(harness_cli plugin --profile "$PLUGIN_PROFILE" list --depth 0 --json 2>/dev/null); then
        return 2
    fi
    if [[ "$inventory" == *"$PLUGIN_NAME"* ]]; then
        return 0
    fi
    return 1
}

socket_is_active() {
    [ -S "$SOCKET_PATH" ] || return 1
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 1 -U "$SOCKET_PATH" >/dev/null 2>&1 && return 0
        return 1
    fi
    # macOS 的标准工具集可能没有 nc -U；套接字存在仍是有用的 active 信号。
    return 0
}

status_is_active() {
    curl -fsS -m 2 "$STATUS_URL" >/dev/null 2>&1
}

save_harness_config() {
    [ "$HARNESS_TYPE" = "source" ] || [ "$HARNESS_TYPE" = "npm" ] || return 0
    command -v node >/dev/null 2>&1 || return 0

    mkdir -p "$(dirname "$CONFIG_PATH")"
    MOODBALL_CONFIG_PATH="$CONFIG_PATH" \
    MOODBALL_HARNESS_TYPE="$HARNESS_TYPE" \
    MOODBALL_SOURCE_ROOT="$HARNESS_SOURCE_ROOT" \
    MOODBALL_DSH_HOME="$HARNESS_DSH_HOME" \
    MOODBALL_PROFILE="$PLUGIN_PROFILE" \
    MOODBALL_TRANSPORT="$PLUGIN_STATE" \
    node <<'NODE'
const fs = require('fs')
const path = process.env.MOODBALL_CONFIG_PATH
let previous = {}
try { previous = JSON.parse(fs.readFileSync(path, 'utf8')) } catch (_) {}
const next = {
  ...previous,
  type: process.env.MOODBALL_HARNESS_TYPE,
  sourceRoot: process.env.MOODBALL_SOURCE_ROOT || undefined,
  dshHome: process.env.MOODBALL_DSH_HOME || undefined,
  profile: process.env.MOODBALL_PROFILE,
  lastSuccessfulTransport: process.env.MOODBALL_TRANSPORT,
}
for (const key of Object.keys(next)) if (next[key] === undefined) delete next[key]
fs.writeFileSync(path, `${JSON.stringify(next, null, 2)}\n`, { mode: 0o600 })
NODE
}

choose_app_destination() {
    if [ -d "/Applications" ] && [ -w "/Applications" ]; then
        APP_DEST="/Applications/MoodBall.app"
    else
        APP_DEST="$HOME/Applications/MoodBall.app"
    fi
}

install_app() {
    choose_app_destination
    mkdir -p "$(dirname "$APP_DEST")"
    info "安装 MoodBall.app 到 $APP_DEST ……"

    # 同目录 staging：复制失败时保留旧版本，不留下半个 App。
    APP_STAGE="$(mktemp -d "$(dirname "$APP_DEST")/.MoodBall.install.XXXXXX")"
    cp -R "$APP_SRC" "$APP_STAGE/MoodBall.app"
    if [ -d "$APP_DEST" ]; then
        rm -rf "$APP_DEST"
    fi
    mv "$APP_STAGE/MoodBall.app" "$APP_DEST"
    rm -rf "$APP_STAGE"
    APP_STAGE=""
    xattr -dr com.apple.quarantine "$APP_DEST" 2>/dev/null || true
    ok "MoodBall.app 已安装到 $APP_DEST"
}

# ---------------------------------------------------------------- 1. 检查 macOS
if [ "$(uname -s 2>/dev/null || true)" != "Darwin" ]; then
    err "MoodBall 目前只支持 macOS。"
    exit 1
fi
MACOS_VERSION=$(sw_vers -productVersion 2>/dev/null || true)
MACOS_MAJOR=${MACOS_VERSION%%.*}
if [ -n "$MACOS_MAJOR" ] && [[ "$MACOS_MAJOR" =~ ^[0-9]+$ ]] && [ "$MACOS_MAJOR" -lt 14 ]; then
    err "需要 macOS 14 或更高版本（当前：$MACOS_VERSION）。"
    exit 1
fi
ok "macOS ${MACOS_VERSION:-已检测}"

PNPM_BIN=$(find_pnpm || true)

# ---------------------------------------------------------------- 2. 选择目标 Harness
if select_harness; then
    ok "检测到 $HARNESS_DISPLAY"
    if [ "$HARNESS_TYPE" = "source" ]; then
        if [ -n "$PNPM_BIN" ]; then
            ok "使用源码 CLI：$PNPM_BIN dsh（cwd=${HARNESS_SOURCE_ROOT}）"
        else
            warn "未找到 pnpm，不能操作源码版 Harness；不会回退到 NPM Harness。"
        fi
    elif [ "$HARNESS_TYPE" = "npm" ]; then
        VERSION=$(harness_cli_version)
        [ -n "$VERSION" ] && ok "Harness 版本：$VERSION"
    elif [ "$HARNESS_TYPE" = "desktop" ]; then
        warn "检测到官方 Desktop；第一阶段不支持自动安装 Desktop 插件。"
    fi
else
    warn "未检测到可绑定的 DeepSeek Harness；仍会安装 MoodBall.app。"
    warn "之后可设置 DSH_SOURCE_ROOT，或重新运行安装器来安装状态插件。"
fi

# ---------------------------------------------------------------- 3. 分离 PluginInstalled 与 PluginActive
# 先通过目标 Harness CLI 查询 profile 依赖；传输层只负责判断 ACTIVE，
# 不用 HTTP 200 反推插件已经安装到哪个 profile。
if [ "$HARNESS_TYPE" = "source" ] || [ "$HARNESS_TYPE" = "npm" ]; then
    plugin_query_status=0
    if [ "$PLUGIN_INSTALL_FAILED" -eq 1 ]; then
        PLUGIN_STATE="unknown"
    elif plugin_is_installed; then
        PLUGIN_STATE="installedInactive"
        ok "状态插件已安装，但当前未 ACTIVE"
    else
        plugin_query_status=$?
        case "$plugin_query_status" in
            1)
                PLUGIN_STATE="notInstalled"
                warn "状态插件尚未安装，将安装到：$HARNESS_DISPLAY"
                ;;
            *)
                PLUGIN_STATE="unknown"
                warn "无法通过目标 Harness CLI 确认插件是否已安装。"
                ;;
        esac
    fi
else
    PLUGIN_STATE="unknown"
fi

# Unix Socket 优先，HTTP 作为兼容回退。若 CLI 已明确说目标 profile 没有插件，
# 但传输层却来自某个正在工作的 Harness，不把它静默归属到错误 profile。
if socket_is_active; then
    if [ "$PLUGIN_STATE" = "notInstalled" ]; then
        warn "检测到活动状态桥接，但目标 profile 未列出插件；不会改装其它 Harness。"
        PLUGIN_STATE="unknown"
    else
        PLUGIN_STATE="active"
        ok "状态插件已连接（Unix Socket）"
    fi
elif status_is_active; then
    if [ "$PLUGIN_STATE" = "notInstalled" ]; then
        warn "检测到活动 HTTP 状态，但目标 profile 未列出插件；不会改装其它 Harness。"
        PLUGIN_STATE="unknown"
    else
        PLUGIN_STATE="active"
        ok "状态插件已连接（HTTP）"
    fi
fi

# ---------------------------------------------------------------- 4. 通过 HarnessCLI 安装插件，不提前退出
if [ "$PLUGIN_STATE" = "notInstalled" ]; then
    info "安装 dsh-moodball-status……"
    if harness_cli plugin --profile "$PLUGIN_PROFILE" add "$PLUGIN_SPEC" 2>&1; then
        PLUGIN_STATE="installedInactive"
        ok "状态插件已安装。"
        if [ "$HARNESS_RUNNING" -eq 1 ]; then
            warn "当前运行中的 Harness 不会热加载新插件。"
        fi
    else
        PLUGIN_STATE="unknown"
        PLUGIN_INSTALL_FAILED=1
        err "状态插件安装失败；仍会继续安装 MoodBall.app。"
        if [ "$HARNESS_TYPE" = "source" ]; then
            echo "请在源码根目录手动执行："
            echo "  cd \"$HARNESS_SOURCE_ROOT\" && pnpm dsh plugin --profile $PLUGIN_PROFILE add $PLUGIN_SPEC"
        else
            echo "请稍后手动执行：dsh plugin --profile $PLUGIN_PROFILE add $PLUGIN_SPEC"
        fi
    fi
fi

# ---------------------------------------------------------------- 5. 获取 App
if [ -d "$APP_SRC" ]; then
    ok "使用本地构建产物 $APP_SRC"
else
    info "未找到本地 ${APP_SRC}，下载 GitHub latest release……"
    APP_TMP="$(mktemp -d)"
    if ! curl -fsSL -L -m 120 -o "$APP_TMP/MoodBall.app.zip" "$RELEASE_URL"; then
        err "下载 latest release 失败：$RELEASE_URL"
        echo "请检查网络，或手动下载：https://github.com/sundusk/dsh-moodball/releases/latest"
        exit 1
    fi
    if ! unzip -qo "$APP_TMP/MoodBall.app.zip" -d "$APP_TMP"; then
        err "解压失败（需要 unzip 命令）。"
        exit 1
    fi
    APP_SRC="$APP_TMP/MoodBall.app"
    ok "已下载并解压 latest release 版 App"
fi

if [ ! -d "$APP_SRC" ]; then
    err "未找到 $APP_SRC —— App 获取失败。"
    exit 1
fi

# 旧版 Waterball 迁移保持原有行为；不会触碰 Harness 进程。
if [ -d "/Applications/Waterball.app" ]; then
    info "检测到旧版 Waterball.app，正在迁移到 MoodBall……"
    osascript -e 'tell application "Waterball" to quit' 2>/dev/null || true
    sleep 1
    if pgrep -x Waterball >/dev/null 2>&1; then
        pkill -x Waterball 2>/dev/null || true
    fi
    rm -rf "/Applications/Waterball.app"
    ok "旧版 Waterball.app 已移除"
fi

install_app
APP_TMP=""

info "启动 MoodBall……"
if open "$APP_DEST" >/dev/null 2>&1; then
    ok "启动完成！"
else
    warn "App 已安装，但自动启动失败；请手动执行：open \"$APP_DEST\""
fi

# App 启动后再检查一次；刚安装的 Bundle 可能要等下次 Harness 启动。
if socket_is_active; then
    PLUGIN_STATE="active"
elif status_is_active; then
    PLUGIN_STATE="active"
fi

save_harness_config || true

echo ""
echo "══════════════════════════════════════════════════════════════"
echo "  ✅ MoodBall 安装完成！"
echo ""
case "$PLUGIN_STATE" in
    active)
        echo "  ✓ 状态插件已连接，MoodBall 会随 Agent 状态变化。"
        ;;
    installedInactive)
        echo "  ✓ 状态插件已安装。"
        if [ "$HARNESS_RUNNING" -eq 1 ]; then
            echo "  ⚠ 当前运行中的 Harness 尚未加载插件。"
            echo "    请在当前任务完成后重启一次 DeepSeek Harness。"
        else
            echo "  ℹ Harness 当前未运行；之后启动 Harness 后 MoodBall 会自动连接。"
        fi
        echo "    无需再次运行 MoodBall 安装脚本。"
        ;;
    notInstalled)
        echo "  ⚠ 状态插件尚未安装。"
        ;;
    unknown)
        echo "  ⚠ 暂时无法确认状态插件是否已连接。"
        if [ "$HARNESS_TYPE" = "desktop" ]; then
            echo "    Desktop 插件自动安装尚未支持，未向 web profile 写入插件。"
        else
            echo "    MoodBall 会先显示未连接状态；请检查目标 Harness 和插件安装结果。"
        fi
        ;;
esac
echo "  ✓ MoodBall.app 已安装并已尝试启动：$APP_DEST"
echo ""
echo "  说明：安装器只操作选定 Harness 的 web profile，不会停止、重启或修改 Harness Session。"
echo "══════════════════════════════════════════════════════════════"

if [ "$PLUGIN_INSTALL_FAILED" -eq 1 ]; then
    exit 1
fi
