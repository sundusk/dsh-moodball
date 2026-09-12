# MoodBall 命令协议

本文档描述 `@sundusk/dsh-moodball-status` 与 MoodBall.app 之间的本地协议。它是用户当前 macOS 账户下的 Unix Socket，插件拥有服务端，App 只连接和观察；协议不启动、停止或重启 DeepSeek Harness，也不提供未鉴权的 HTTP 写接口。

## Socket

- 路径：`~/Library/Application Support/MoodBall/moodball-command.sock`
- 传输：Unix stream socket，UTF-8，NDJSON（一行一个 JSON 对象）
- 权限：服务端创建后设为 `0600`
- 旧状态兼容：`moodball.sock` 和 `GET /api/moodball/status` 保留不变

## 请求与响应

请求都携带客户端生成的 `id`。成功响应形状为 `{ "id": "...", "ok": true, ... }`；失败响应形状为 `{ "id": "...", "ok": false, "error": { "code": "...", "message": "..." } }`。

### `capabilities`

```json
{"id":"r1","action":"capabilities"}
```

返回协议版本、能力名和状态订阅支持情况。App 只有在命令 Socket 能力可用时显示发送能力；只有旧状态 Socket/HTTP 时继续显示宠物状态并禁用发送。

### `workspaces`

```json
{"id":"r2","action":"workspaces"}
```

返回已由 Harness 注册的工作区投影：`id`、`title`、规范路径、`status`（`ok` / `missing-dir`）和已归属的 Session ID。插件直接读取官方 `ctx.workspaceRegistry`，不会把任意本地目录伪装成工作区。

### `createSession`

```json
{
  "id":"r3",
  "action":"createSession",
  "workspaceId":"...",
  "sessionId":"moodball-session-..."
}
```

插件验证工作区后调用官方 `ctx.sessionController.create({ workspaceId, sessionId })`。App 会持久化这个固定 Session ID，因此同一次重试会被 Harness 幂等接纳，不会因为超时重复创建会话。

### `prompt`

```json
{
  "id":"r4",
  "action":"prompt",
  "workspaceId":"...",
  "sessionId":"...",
  "requestId":"moodball-...",
  "text":"请继续处理……"
}
```

插件验证 Session 属于目标工作区后，调用官方：

```ts
ctx.sessionController.prompt({
  requestId,
  sessionId,
  mode: 'queue',
  content: [{ type: 'text', text }],
}, signal)
```

同一 Session 的创建和提交按顺序串行化；Harness 自身也按 `requestId` 去重。收到 `accepted: true` 只代表消息进入 Agent inbox，不代表执行完成。超时由 App 显示“提交结果未确认”，保留草稿并沿用同一 `requestId` 重试。

### `subscribe` / `unsubscribe`

```json
{"id":"r5","action":"subscribe","sessionId":"..."}
```

订阅成功时返回当前 Session 快照；之后服务端向同一连接推送：

```json
{
  "event":"status",
  "sessionId":"...",
  "snapshot": {
    "state":"thinking",
    "mood":"waiting",
    "taskRunning":true,
    "waitingForUser":false,
    "failed":false,
    "completed":false,
    "updatedAt": 0
  }
}
```

状态按 Session 独立折叠。`waiting`、`jumping`、`authorizing`、`questioning` 表示任务仍在进行；`done`、`failed`、`stopped` 是结果/终止状态，不能与“已提交”混同。

## 降级边界

- 命令 Socket 不存在、旧插件或 Harness 未提供官方服务时：App 保留原有本地状态 Socket/HTTP 展示，输入框不可发送并给出原因。
- 工作区失效、Session 不存在或跨工作区发送被拒绝时：草稿保留，不切换到其他 Session。
- `新建会话` 只清除 MoodBall 的本地绑定；不删除、不取消旧 Harness Session。
- 打开 Harness 只打开设置中的 Harness 首页；会话 ID可复制，不依赖未经官方验证的深链接。
