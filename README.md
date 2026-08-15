# dsh-macDesktop-pet — macOS 桌面悬浮呼吸灯

macOS 原生悬浮呼吸灯：菜单栏常驻 + 一颗置顶的发光小球，颜色随
「DeepSeek Harness」的 agent 状态变化并呼吸（正在思考中=绿、调工具=紫、做出你的抉择=粉、
搞定啦=青、出错=红…共 8 色，颜色可在设置面板自定义）。

> macOS 14+ · SwiftUI 原生应用 · 需要 DeepSeek Harness（DSH）运行
>
> [下载最新 Release](https://github.com/sundusk/dsh-macDesktop-pet/releases/latest) · [查看 v0.2.1](https://github.com/sundusk/dsh-macDesktop-pet/releases/tag/v0.2.1)

## 🎈 这是什么？

把网页里的水球带到你的**整个桌面**上。安装后，桌面右下角会出现一颗置顶的发光小球，
颜色随 DeepSeek Harness 的 Agent 运行状态实时呼吸变化——即使不看 Web UI，
瞄一眼桌面就知道任务进度。非空闲状态时，小球脑门上方还会弹出**漫画风说话气泡**
（正在思考中/工具调用/做出你的抉择/等待你的授权/搞定啦/出错…），空闲时气泡自动隐藏。

它需要 DeepSeek Harness（`dsh web`）正在运行，并依赖
[dsh-waterball-pet](https://github.com/sundusk/dsh-waterball-pet) 插件提供状态接口
（下方一键安装脚本会自动帮你装好插件）。

## 🚀 安装

### 安装依赖

1. **macOS 14+**
2. **DeepSeek Harness**：安装方法见 [官方文档](https://github.com/deepseek-ai/deepseek-harness)，装好后终端能运行 `dsh web`
3. **Node.js + pnpm**（一键安装脚本自动装插件时需要）：https://nodejs.org

### 方式一：一键安装脚本（推荐）

```bash
git clone --depth 1 https://github.com/sundusk/dsh-macDesktop-pet.git
cd dsh-macDesktop-pet
bash install.sh
```

脚本会自动：

1. 检测状态接口，未装插件则自动执行 `dsh plugin --profile web add github:sundusk/dsh-waterball-pet`
2. 从 GitHub Release 下载 `Waterball.app`（有本地构建产物时优先用本地）
3. 把 `Waterball.app` 复制到 `/Applications` 并启动

> 若脚本提示刚安装了插件，请先重启 `dsh web`（终端 Ctrl+C 后重新运行），
> 再重新执行一次脚本完成 app 安装。

### 方式二：下载 Release

从 [最新 Release](https://github.com/sundusk/dsh-macDesktop-pet/releases/latest)
下载 `Waterball.app.zip`，解压后拖入「应用程序」文件夹，双击「Waterball」启动。

> 提示：Release 安装不会自动装插件。若尚未安装，请先在终端执行
> `dsh plugin --profile web add github:sundusk/dsh-waterball-pet`，然后重启 `dsh web`。

## ✨ 使用

安装并启动后，**桌面上没有任何窗口**——它是个纯菜单栏应用（不占 Dock、不抢焦点）：
菜单栏右侧出现一个**彩色圆点图标**，桌面右下角出现发光呼吸球。

### 以后怎么打开？

- **访达 → 应用程序**：找到「Waterball」，双击
- **终端**：`open -a Waterball`

### 菜单栏图标功能

| 菜单项 | 功能 |
|---|---|
| 状态文字 | 当前连接状态与状态名（如「已连接 · 工具调用」） |
| 隐藏 / 显示悬浮球 | 开关悬浮球显示 |
| 设置… | 打开设置面板 |
| 退出 | 退出 app（不影响 DSH 本体） |

### 颜色含义

| 状态 | 颜色 |
|---|---|
| 空闲 | 蓝 |
| 正在思考中 | 绿 |
| 工具调用 | 紫 |
| 等待你的授权 | 黄 |
| 做出你的抉择 | 粉 |
| 搞定啦 | 青 |
| 出错 | 红 |
| 停止 / 中断 | 黑 |

断连时球显示为灰色。所有颜色都可在设置面板自定义。

### 设置面板

菜单栏 →「设置…」可调整：球大小、呼吸速度、8 种状态颜色、眼睛开关与颜色、
**状态气泡开关**、API 地址、轮询间隔、点击穿透模式等，修改立即生效。

### 常见问题

- **球是灰色的？** 说明 DSH 未运行（显示「DSH 未运行」）或插件被禁用（显示「插件已关闭」）。先确认终端里 `dsh web` 在跑。
- **想同时看到网页水球？** 插件默认隐藏网页球，Web UI → 设置 → 插件 → 水球宠物 → 关闭「隐藏网页水球」。

## 📄 License

本项目采用 [MIT License](LICENSE) 发布。
