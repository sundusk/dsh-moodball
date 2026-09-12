# MoodBall 第一版验收记录

日期：2026-09-12

## 已验证

- 官方 Harness checkout 为 `c291e7961a515f6d7af9304e7fd1d257929aef26`，版本 `0.1.5-rc.2`；官方源码保持只读。
- 插件 TypeScript `pnpm typecheck` 通过。
- 插件 `pnpm build` 通过，生成 `lib/index.js` 和 `lib/types/`。
- 命令协议测试通过：能力查询、工作区查询、固定会话响应、同一 Session 串行提交、状态订阅推送、`0600` 权限、畸形 JSON 后连接继续可用。
- Swift Debug 构建通过：`swift build -c debug --disable-sandbox`。
- `dist/MoodBall.app` Release 构建通过，Bundle ID `com.sundusk.moodball`，资源图集齐全，`codesign --verify --deep --strict` 通过。
- 交互面板已采用独立附属窗口，输入框使用原生 `NSTextView`，Enter/Shift+Enter 和中文 IME 选字分支有对应代码路径。
- 实际启动构建产物并通过菜单栏检查“输入消息 / 新建会话 / 选择工作区 / 打开 Harness”；输入框截图可见，空工作区时发送按钮禁用，草稿经 Esc 收起再打开后仍保留。

## 尚未验证

- 尚未在真实运行的 Harness `pnpm dsh web` 上加载本版本插件并执行真实文字提交、连续对话和两个会话隔离验收。
- 尚未完成完整真实桌面截图验收：悬停路径、屏幕边缘、多屏、点击穿透、焦点切换和拖动期间附属面板跟随仍需要逐项检查。
- 尚未替换已安装 MoodBall.app、重启官方 Harness、推送 GitHub 或发布 Release；这些操作不属于本次默认交付。

## 运行验收顺序

1. 在官方源码根目录执行 `pnpm dsh web`，确认 `workspaceRegistry` 和 `sessionController` 可用。
2. 构建并安装本仓库插件后，重新加载对应 Harness profile；不修改官方源码。
3. 构建 `dist/MoodBall.app` 并启动 App。
4. 选择工作区，发送第一条文字；确认 Harness 新建并执行 MoodBall 专用 Session。
5. 在执行中确认发送按钮禁用；完成后发送第二条文字，确认上下文仍在同一 Session。
6. 通过菜单“新建会话”后选择同一或另一工作区，确认得到不同 Session ID，旧任务不被取消。
