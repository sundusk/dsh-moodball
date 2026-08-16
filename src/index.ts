/**
 * dsh-moodball-status host half — a pure host plugin (no browser UI, no
 * settings namespace) that tracks agent activity and serves the current mood
 * over a same-origin JSON route for the MoodBall macOS desktop app. Install
 * via `dsh plugin --profile web add github:sundusk/dsh-moodball`.
 * @module @linxin666/dsh-moodball-status
 */

import { Context } from '@deepseek-ai/cordis'
import type {} from '@deepseek-ai/dsh-host-webserver'
import type { WebRoute } from '@deepseek-ai/dsh-host-webserver'
import type { Session } from '@deepseek-ai/dsh-session'
import type { IncomingMessage, ServerResponse } from 'node:http'

/** Stable cordis plugin name (matches cordis.patch.yml insert id). */
export const name = 'moodball'

/** Services required before the status surface can mount. */
export const inject = ['webServer']

/** The mood the desktop app renders (same vocabulary as the web water ball). */
export type MoodballMood =
  | 'idle'
  | 'waiting'
  | 'jumping'
  | 'done'
  | 'failed'
  | 'stopped'
  | 'waving'
  | 'authorizing'
  | 'questioning'

/** Write one JSON response. */
function json(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(body))
}

/**
 * Register the MoodBall status surface: fold the agent session stream into a
 * mood and serve it over GET /api/moodball/status. The route is always live
 * while the plugin is loaded — there is no settings namespace to toggle.
 * @param ctx - host root context.
 */
export function apply(ctx: Context): void {
  let mood: MoodballMood = 'idle'
  let holdUntil = 0
  // ask_user_question 挂起中：选项框弹出期间锁定 questioning，防止
  // activity 追踪器的 tool phase 把它覆盖回 jumping。
  let questionActive = false

  // A transient mood (done / failed / stopped) holds for `ms` before reverting
  // to idle, so the colored reaction is visible instead of being swallowed by
  // the immediately following `activity/status` idle phase.
  const setTransient = (next: MoodballMood, ms: number): void => {
    mood = next
    holdUntil = Date.now() + ms
    setTimeout(() => {
      if (mood === next) mood = 'idle'
    }, ms)
  }

  // Track the activity tracker's `activity/status` session events (phases:
  // idle / waiting / thinking / tool / done) and the turn lifecycle, folding
  // them into a mood. Transient moods (done / failed / stopped) hold briefly
  // so their reaction color is visible before the next idle phase.
  ctx.on('session/event', (_session: Session, event: { type: string; data?: unknown }) => {
    if (event.type === 'turn/start' || event.type === 'step/start' || event.type === 'assistant/chunk') {
      mood = 'waiting'
      holdUntil = 0
    } else if (event.type === 'tool/call') {
      // ask_user_question 是普通工具调用：选项框弹出 → 粉色 questioning，
      // 与普通工具（紫色 jumping）区分开。
      const call = (event.data ?? {}) as { name?: string }
      if (call.name === 'ask_user_question') {
        questionActive = true
        mood = 'questioning'
        holdUntil = 0
      } else {
        mood = 'jumping'
        holdUntil = 0
      }
    } else if (event.type === 'tool/result') {
      const result = (event.data ?? {}) as { error?: { code?: string } }
      if (questionActive) {
        // 选项框关闭：用户点了选项 → 回 waiting；用户取消/关闭弹窗 → 短暂 stopped
        questionActive = false
        if (result.error !== undefined) setTransient('stopped', 1500)
        else {
          mood = 'waiting'
          holdUntil = 0
        }
      } else {
        mood = 'waiting'
        holdUntil = 0
      }
    } else if (event.type === 'approval/asked') {
      // 授权等待：用户尚未批准工具调用 → 黄色（authorizing）
      mood = 'authorizing'
      holdUntil = 0
    } else if (event.type === 'approval/decided') {
      // 授权已决定：批准 → 等后续工具事件；拒绝/取消/不可用 → 视为失败
      const payload = (event.data ?? {}) as { result?: string }
      if (payload.result === 'allowed-once') {
        mood = 'waiting'
        holdUntil = 0
      } else if (payload.result === 'rejected' || payload.result === 'cancelled' || payload.result === 'unavailable') {
        setTransient('failed', 3000)
      }
    } else if (event.type === 'activity/status') {
      const payload = (event.data ?? {}) as { phase?: string }
      if (payload.phase === undefined) return
      switch (payload.phase) {
        case 'waiting':
        case 'thinking':
          mood = 'waiting'
          holdUntil = 0
          break
        case 'tool':
          // 提问挂起中：选项框未关闭，保持 questioning，不被 tool phase 覆盖
          if (questionActive) return
          mood = 'jumping'
          holdUntil = 0
          break
        case 'done':
          setTransient('done', 2500)
          break
        case 'idle':
          if (Date.now() < holdUntil) return
          mood = 'idle'
          break
        default:
          break
      }
    } else if (event.type === 'turn/end') {
      questionActive = false
      const payload = (event.data ?? {}) as { reason?: { kind?: string } }
      const kind = payload.reason?.kind
      if (kind === 'error') setTransient('failed', 3000)
      else if (kind === 'completed') setTransient('done', 2500)
      else if (kind !== undefined) setTransient('stopped', 3000)
    }
  })

  const statusRoute: WebRoute = {
    kind: 'exact',
    path: '/api/moodball/status',
    handler: (req: IncomingMessage, res: ServerResponse): void => {
      if (req.method !== 'GET') {
        json(res, 405, { ok: false, error: 'method-not-allowed' })
        return
      }
      json(res, 200, { ok: true, mood, enabled: true })
    },
  }

  // Route is always live: unlike the web water ball there is no settings
  // namespace, so nothing can take it down while the plugin is loaded.
  ctx.effect(() => ctx.webServer.register(statusRoute), 'moodball: status route')
}
