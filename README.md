# waterball-mac — macOS 悬浮呼吸灯（交接文档）

目标：做一个原生 macOS 悬浮窗，让「DeepSeek Harness」的运行状态能在网页之外
被看到。形态是菜单栏常驻 + 一颗置顶的发光小球，颜色随 agent 状态变化并呼吸。

## 数据来源（已就绪，无需再开发）

DSH 本机已有一个 HTTP 接口（由 `dsh-waterball` 插件提供，见下文），直接轮询它：

```
GET http://127.0.0.1:3080/api/waterball/status
→ {"ok":true,"mood":"waiting","enabled":true,"size":120,"right":16,"bottom":16}
```

- 本机 loopback，只有 DSH 开着时才可用；DSH 关闭时接口 404/连接失败 → 悬浮灯显示「未连接」。
- 建议每 **700ms** 轮询一次（和网页插件一致）。

## mood → 颜色映射（7 个状态，唯一要遵守的契约）

| mood | 含义 | 颜色 |
|------|------|------|
| `idle` | 空闲 | 蓝 `#60a5fa` |
| `waiting` | 思考/工作 | 绿 `#34d399` |
| `jumping` | 工具调用 | 紫 `#a855f7` |
| `done` | 完成 | 青 `#22d3ee` |
| `failed` | 出错 | 红 `#f87171` |
| `stopped` | 中断/停止（aborted/blocked/max-tokens/interrupted） | 黑 `#000000` |
| `waving` | 点击挥手（网页端交互态，悬浮窗可忽略） | 橙 `#fb923c` |

## 悬浮窗需求（SwiftUI 都能原生做到）

- **菜单栏常驻**：`MenuBarExtra`，点击图标呼出/隐藏悬浮窗、退出。
- **置顶**：`NSWindow.level = .floating`。
- **透明无边框**：只有发光球本体可见，背景全透明。
- **可拖拽**：`isMovableByWindowBackground = true`。
- **不挡操作**：空闲时可 `ignoresMouseEvents = true`（点击穿透）；悬停时恢复响应。
- **呼吸动画**：球体透明度/缩放做 ease-in-out 呼吸（idle 慢、忙碌态快）。
- **未连接**：接口不可达时显示灰色「未连接」。

## 技术选型（二选一）

1. **SwiftUI 原生（推荐）**：最轻量，常驻内存极小。发光球用
   `Circle + radialGradient + blur` 即可实现。
2. **Tauri（Rust + WebView）**：能直接复用网页版水球 HTML/CSS，但要 Rust 工具链。

## 网页插件（状态的生产者，已完成，无需改动）

- 路径：`dsh-web-ui/packages/dsh-waterball`（已构建 `lib/`，已安装进 `~/.dsh/profiles/web`）。
- 职责：Host 半区监听 agent 活动 → 产出 `mood` → 暴露 `/api/waterball/status`。
- 修改它：改源码后 `cd dsh-web-ui && pnpm --filter @linxin666/dsh-waterball build`，
  再重启 `dsh web`（或网页刷新）生效。

## 开工建议

新项目目录就放这里：`/Users/sundusk/Desktop/deepseekAnget/waterball-mac/`，
先做「纯发光小球」版本（菜单栏 + 置顶透明球 + 700ms 轮询 + 7 色呼吸），
验证通了再考虑水球本体、用量读数、点击交互等。

---

## ✅ 已实现（2026-08-14）—— 纯发光小球版

SwiftUI 原生（技术选型 1），SwiftPM 可执行目标，无第三方依赖。

### 运行方式

```bash
./make-app.sh   # swift build -c release → 组装 dist/Waterball.app → open 启动
./run.sh        # 开发模式：直接 swift run（同样不占 Dock）
```

- 产物：`dist/Waterball.app`（`LSUIElement` 纯菜单栏应用，不占 Dock）。
- 退出：菜单栏图标 →「退出」。

### 已实现功能

| 需求 | 实现 |
|------|------|
| 菜单栏常驻 | `MenuBarExtra`，圆点图标颜色随 mood 实时变化；菜单内显示当前状态、「显示 / 隐藏悬浮球」、「退出」 |
| 置顶 | `NSPanel.level = .floating`（窗口层 layer=3） |
| 透明无边框 | 无边框透明 panel，仅发光球可见（radialGradient + blur 外发光 + 高光） |
| 700ms 轮询 | `Timer` 每 0.7s GET `/api/waterball/status`（间隔/超时/API 地址可设置）；DSH 未运行 → 灰球「DSH 未运行」，插件关闭(404) → 灰球「插件已关闭」 |
| 7 色映射 | 严格按上方表格：idle 蓝 / waiting 绿 / jumping 紫 / done 青 / failed 红 / stopped 黑 / waving 橙；颜色可在设置面板自定义，断连灰也可调 |
| 呼吸动画 | `TimelineView` 正弦驱动透明度(0.55→1) + 缩放(0.90→1.04)，全局统一呼吸速度（设置面板可调） |
| 不挡操作 | 点击穿透三模式：悬停恢复（默认）/ 永远穿透 / 永不穿透（设置面板可选，100ms 全局鼠标位置轮询） |
| 随便拖 | 按住球体任意位置即可拖动到任意位置/任意屏幕（SwiftUI `DragGesture` 抓取点跟随，1:1 平滑）；抬手即记住位置，重启后自动恢复（可关闭「记住位置」）；显示/隐藏后再显示也回到原位 |
| 位置 | 启动时优先恢复上次拖拽位置（`UserDefaults`），否则放鼠标所在屏幕右下角（距边 16px）；显示器增删/分辨率变化自动收回可视区；面板可一键重置右下角 |
| 设置面板 | 菜单栏「设置…」：外观（大小/呼吸速度）/ 颜色（7 色自定义 + 断连灰）/ 行为（API 地址/轮询/超时/穿透/记住位置）三 Tab，顶部实时预览小球；修改即生效并持久化 |

### 目录结构

```
waterball-mac/
├── Package.swift                      # swift-tools 5.10, macOS 14+
├── make-app.sh / run.sh
└── Sources/Waterball/
    ├── WaterballApp.swift             # @main + MenuBarExtra（图标、菜单）
    ├── SettingsStore.swift            # 全局设置（UserDefaults 持久化）+ 7 色映射 + 穿透模式
    ├── SettingsPanelView.swift        # 设置面板（外观/颜色/行为三 Tab + 实时预览）
    ├── WaterballModel.swift           # 可配置轮询、解码、mood→颜色/呼吸速度、两种灰球区分
    ├── WaterballView.swift            # 发光球 + 呼吸动画 + 拖拽
    └── AppDelegate.swift              # 悬浮 panel、置顶、穿透/拖拽、显隐、设置面板、显示器变化
```

### 实现备注

- 悬浮球显隐通过 `WaterballModel.isBallVisible` 驱动（`NSApp.delegate` 在 SwiftUI 下是
  `SwiftUI.AppDelegate` 包装类型，不能 `as? AppDelegate`，故不依赖它）。
- 拖拽用 SwiftUI `DragGesture` + 全局鼠标坐标（`NSEvent.mouseLocation`）驱动窗口
  `setFrameOrigin`：抓取点相对窗口的偏移保持不变，窗口 1:1 跟随光标，不受窗口移动的
  坐标系反馈影响（`isMovableByWindowBackground` 在 NSHostingView 下实测无效）。
- 设置面板通过通知路由到 AppDelegate（`NSApp.delegate` 是 `SwiftUI.AppDelegate` 包装类型，
  不能直接 `as? AppDelegate`）；面板打开时临时 `NSApp.activate` 以便输入框可编辑。
- 球已与网页解耦：大小由本地设置决定（不再跟随接口 `size`）；接口 `hidden` 字段（网页球隐藏）
  不影响桌面球——只要 `enabled=true` 且接口可达，桌面球照常工作。
- `stopped` 是纯黑球，深色壁纸上加了一圈淡白描边便于辨认。
- 日志：`log show --predicate 'subsystem == "com.linxin666.waterball-mac"'`（info 级，
  含轮询位置与显隐切换，便于排查）。

