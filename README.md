<p align="center">
  <img src="docs/assets/moodball-logo.png" width="140" alt="MoodBall">
</p>

<h1 align="center">MoodBall（心情球）</h1>

<p align="center">
  macOS 桌面悬浮呼吸灯 —— 让 Agent 状态飞出 Web UI，悬浮在你桌面的任意位置<br>
  菜单栏常驻 + 置顶发光小球，随 DeepSeek Harness 的 Agent 状态实时呼吸变色
</p>

<p align="center">
  macOS 14+ · SwiftUI 原生应用 · 需要 DeepSeek Harness（DSH）运行
</p>

<p align="center">
  <a href="https://github.com/sundusk/dsh-moodball/releases/latest">⬇️ 下载最新 Release</a>
</p>

## 🎈 这是什么？

**心情球**把 Agent 的状态带到你的**整个桌面**上。它是一颗真正「活在桌面上」的悬浮球：
按住即可拖到屏幕**任意位置**（位置会被记住），完全不局限于 DeepSeek Harness 的 Web UI 页面内——
即使浏览器已最小化、甚至从头到尾都不打开 Web UI，也能随时看到任务状态。
小球颜色随 Agent 运行状态实时呼吸变化（正在思考中/工具调用/等待你的授权/做出你的抉择/搞定啦/出错了…），
非空闲时头顶还会弹出**漫画风说话气泡**，空闲时自动隐藏。瞄一眼桌面，就知道任务进度。

### 项目组成

- **MoodBall.app**：桌面呼吸球本体
- **dsh-moodball-status**：状态插件（订阅 agent 会话事件，提供状态接口；无界面、无设置项）

一切配置都在 app 的设置面板里完成。

### 📸 效果展示

<p align="center">
  <img src="docs/assets/moodball-desktop.jpg" width="720" alt="MoodBall 桌面悬浮球效果">
</p>

<p align="center">
  悬浮在桌面上的心情球 —— 可拖到屏幕任意位置，随时查看 Agent 状态
</p>

## 🚀 安装

### 安装依赖

1. **macOS 14+**
2. **DeepSeek Harness**：安装方法见 [官方文档](https://github.com/deepseek-ai/deepseek-harness)，装好后终端能运行 `dsh web`
3. **Node.js + pnpm**（一键安装脚本自动装插件时需要）：https://nodejs.org

### 方式一：一键安装（推荐）

```bash
curl -fsSL https://github.com/sundusk/dsh-moodball/raw/refs/heads/main/install.sh | bash
```

脚本会自动：

1. 检测状态接口 `/api/moodball/status`，未装插件则自动执行 `dsh plugin --profile web add github:sundusk/dsh-moodball`
2. 从 GitHub Release 下载 `MoodBall.app`（有本地构建产物时优先用本地）
3. 把 `MoodBall.app` 复制到 `~/Applications` 并启动

> 若脚本提示刚安装了插件，请先重启 `dsh web`（终端 Ctrl+C 后重新运行），
> 再重新执行一次脚本完成 app 安装。

### 方式二：仓库安装

```bash
git clone --depth 1 https://github.com/sundusk/dsh-moodball.git
cd dsh-moodball
bash install.sh
```

与方式一完全等价（方式一其实就是直接运行仓库里的 install.sh），适合想顺带查看源码/自行构建的用户。

### 方式三：下载 Release

从 [最新 Release](https://github.com/sundusk/dsh-moodball/releases/latest)
下载 `MoodBall.app.zip`，解压后放入 `~/Applications`（或「应用程序」），双击「MoodBall」启动。

> 提示：Release 安装不会自动装插件。若尚未安装，请先在终端执行
> `dsh plugin --profile web add github:sundusk/dsh-moodball`，然后重启 `dsh web`。

## ✨ 使用

安装并启动后，**桌面上没有任何窗口**——它是个纯菜单栏应用（不占 Dock、不抢焦点）：
菜单栏右侧出现一个**彩色小水球图标**（圆球 + 两只镂空小圆点眼睛，颜色随状态实时变化），桌面右下角出现发光呼吸球。

### 以后怎么打开？

- **访达 → 应用程序（或 ~/Applications）**：找到「MoodBall」，双击
- **终端**：`open -a MoodBall`

### 菜单栏图标功能

| 菜单项 | 功能 |
|---|---|
| 状态文字 | 当前连接状态与状态名（如「已连接 · 工具调用」） |
| 隐藏 / 显示悬浮球 | 开关悬浮球显示 |
| 设置… | 打开设置面板 |
| 退出 | 退出 app（不影响 DSH 本体） |

### 小球交互

- **拖动**：按住小球任意位置拖动，可把它移到任何地方（位置会记住）
- **双击**：小球左右摇动约 2 秒，表示兴奋
- **锁定位置**（设置面板 → 行为）开启后不可拖拽，仍可双击

### 状态展示

菜单栏 →「状态展示…」（⌘D）：查看每个状态下心情球的实时外观，可切换气泡文字的显示与隐藏，
并可将当前状态保存为 PNG 图片。

### 颜色含义

| 状态 | 心情球 | 颜色 |
|---|---|---|
| 空闲 | ![空闲](docs/assets/moodball-idle.png?v=2) | 蓝色 |
| 正在思考中 | ![正在思考中](docs/assets/moodball-waiting.png?v=2) | 绿色 |
| 工具调用 | ![工具调用](docs/assets/moodball-jumping.png?v=2) | 紫色 |
| 等待你的授权 | ![等待你的授权](docs/assets/moodball-authorizing.png?v=2) | 黄色 |
| 做出你的抉择 | ![做出你的抉择](docs/assets/moodball-questioning.png?v=2) | 粉色 |
| 搞定啦 | ![搞定啦](docs/assets/moodball-done.png?v=2) | 青色 |
| 出错了 | ![出错了](docs/assets/moodball-failed.png?v=2) | 红色 |
| 停止 / 中断 | ![停止 / 中断](docs/assets/moodball-stopped.png?v=2) | 黑色 |
| 未连接 / 插件未装 | ![未连接](docs/assets/moodball-disconnected.png?v=2) | 灰色 |

**所有颜色都可以在设置面板自定义。**

### 设置面板

菜单栏 →「设置…」可调整：球大小、呼吸速度、8 种状态颜色、眼睛开关与颜色、
**气泡文字开关**、**发光开关**、**锁定位置**、API 地址、轮询间隔、点击穿透模式等，修改立即生效。

「行为」Tab 底部还有**版本与更新**：显示当前版本，自动/手动检查 GitHub Releases
是否有新版本，有则给出「前往下载」链接。

### 卸载

```bash
git clone --depth 1 https://github.com/sundusk/dsh-moodball.git
cd dsh-moodball
bash uninstall.sh
```

脚本会退出并删除 `~/Applications/MoodBall.app`（含 `/Applications` 残留），
并询问是否同时移除 `dsh-moodball-status` 插件（移除后重启 dsh web 生效）。

### 常见问题

- **球是灰色的？** 说明 DSH 未运行（显示「DSH 未运行」）或状态插件未装（显示「插件已关闭」）。
  先确认终端里 `dsh web` 在跑，再确认插件已安装并启用。
- **「设置 → 插件」里怎么没有心情球插件卡片？** 这是正常的——心情球插件没有任何设置项
  （所有配置都在 app 的设置面板里），所以不显示配置卡片。可在「设置 → 插件 → **插件列表**」
  中查看它（状态为「已挂载」）。

## 🔧 开发

```bash
# 插件（dsh-moodball-status）：构建到 lib/
pnpm install
pnpm build

# app：构建 dist/MoodBall.app 并启动
bash make-app.sh
```

## 📄 License

本项目采用 [MIT License](LICENSE) 发布。
