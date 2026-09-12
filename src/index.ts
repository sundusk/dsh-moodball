/**
 * dsh-moodball-status host plugin — a pure Harness status bridge (no browser
 * UI, no settings namespace) that tracks agent activity and serves a stable
 * snapshot over HTTP and a local Unix socket for the MoodBall macOS desktop app.
 * Install
 * via `dsh plugin --profile web add github:sundusk/dsh-moodball`.
 * @module @sundusk/dsh-moodball-status
 */

import { Context } from '@deepseek-ai/cordis'
import type {} from '@deepseek-ai/dsh-host-webserver'
import type { WebRoute } from '@deepseek-ai/dsh-host-webserver'
import type {} from '@deepseek-ai/dsh-api-session-controller'
import type {} from '@deepseek-ai/dsh-workspace'
import type { Session } from '@deepseek-ai/dsh-session'
import type { IncomingMessage, ServerResponse } from 'node:http'
import { CommandBridge, type MoodballWorkspace } from './CommandBridge.js'
import { LocalStateBridge, type MoodBridgePayload } from './LocalStateBridge.js'

export { CommandBridge } from './CommandBridge.js'

/** Stable cordis plugin name (matches cordis.patch.yml insert id). */
export const name = 'moodball'

/** Services required before the status surface can mount. */
export const inject = ['webServer', 'workspaceRegistry', 'sessionController']

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

function stateForMood(mood: MoodballMood): string {
  switch (mood) {
    case 'waiting': return 'thinking'
    case 'jumping': return 'toolCalling'
    case 'authorizing': return 'waitingApproval'
    case 'questioning': return 'waitingUserAnswer'
    case 'done': return 'completed'
    case 'failed': return 'failed'
    case 'stopped': return 'stopped'
    case 'idle': return 'idle'
    default: return 'disconnected'
  }
}

/** Write one JSON response. */
function json(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { 'content-type': 'application/json; charset=utf-8' })
  res.end(JSON.stringify(body))
}

/**
 * Register the MoodBall status surface: fold the agent session stream into a
 * stable snapshot, serve it over GET /api/moodball/status, and broadcast the
 * same snapshot through LocalStateBridge. The route is always live while the
 * plugin is loaded — there is no settings namespace to toggle.
 * @param ctx - host root context.
 */
export function apply(ctx: Context): void {
  interface SessionMoodState {
    sessionId?: string
    workspaceId?: string
    mood: MoodballMood
    holdUntil: number
    questionActive: boolean
    tool?: string
    message?: string
  }

  const globalState: SessionMoodState = {
    mood: 'idle',
    holdUntil: 0,
    questionActive: false,
  }
  const sessionStates = new Map<string, SessionMoodState>()
  const sessionOperations = new Map<string, Promise<void>>()
  let activeSessionId: string | undefined
  let commandBridge: CommandBridge | undefined

  const stateFor = (sessionId: string, workspaceId?: string): SessionMoodState => {
    const existing = sessionStates.get(sessionId)
    if (existing) {
      if (workspaceId) existing.workspaceId = workspaceId
      return existing
    }
    const created: SessionMoodState = {
      sessionId,
      workspaceId,
      mood: 'idle',
      holdUntil: 0,
      questionActive: false,
    }
    sessionStates.set(sessionId, created)
    return created
  }

  const workspaceForSession = (sessionId: string): string | undefined => {
    const workspace = ctx.workspaceRegistry.list().find(candidate =>
      candidate.sessionIds.some(candidateSessionId => String(candidateSessionId) === sessionId),
    )
    return workspace ? String(workspace.id) : undefined
  }

  const snapshotOf = (state: SessionMoodState): MoodBridgePayload => ({
    state: stateForMood(state.mood),
    mood: state.mood,
    ...(state.sessionId ? { sessionId: state.sessionId } : {}),
    ...(state.workspaceId ? { workspaceId: state.workspaceId } : {}),
    taskRunning: ['waiting', 'jumping', 'authorizing', 'questioning'].includes(state.mood),
    waitingForUser: state.mood === 'authorizing' || state.mood === 'questioning',
    failed: state.mood === 'failed',
    completed: state.mood === 'done',
    ...(state.tool ? { tool: state.tool } : {}),
    ...(state.message ? { message: state.message } : {}),
    updatedAt: Date.now(),
  })

  const snapshotForSession = (sessionId: string): MoodBridgePayload =>
    snapshotOf(stateFor(sessionId, workspaceForSession(sessionId)))

  const snapshot = (): MoodBridgePayload =>
    activeSessionId === undefined
      ? snapshotOf(globalState)
      : snapshotForSession(activeSessionId)

  const localBridge = new LocalStateBridge(snapshot)

  const publish = (state: SessionMoodState): void => {
    localBridge.publish()
    if (state.sessionId) commandBridge?.publish(state.sessionId, snapshotOf(state))
  }

  // A transient mood (done / failed / stopped) holds for `ms` before reverting
  // to idle, so the colored reaction is visible instead of being swallowed by
  // the immediately following `activity/status` idle phase.
  const setTransient = (state: SessionMoodState, next: MoodballMood, ms: number): void => {
    state.mood = next
    state.holdUntil = Date.now() + ms
    publish(state)
    setTimeout(() => {
      if (state.mood === next) {
        state.mood = 'idle'
        publish(state)
      }
    }, ms)
  }

  // Track each session independently. The legacy HTTP/socket snapshot follows
  // the most recently active session, while command subscribers receive only
  // the session they explicitly selected.
  ctx.on('session/event', (_session: Session, event: { type: string; data?: unknown }) => {
    const info = _session as unknown as { id?: string; sessionId?: string; workspaceId?: string }
    const sessionId = info.id ?? info.sessionId
    const state = sessionId === undefined
      ? globalState
      : stateFor(sessionId, info.workspaceId ?? workspaceForSession(sessionId))
    if (sessionId) activeSessionId = sessionId

    if (event.type === 'turn/start' || event.type === 'step/start' || event.type === 'assistant/chunk') {
      state.mood = 'waiting'
      state.holdUntil = 0
      state.message = undefined
    } else if (event.type === 'tool/call') {
      const call = (event.data ?? {}) as { name?: string }
      state.tool = call.name
      if (call.name === 'ask_user_question') {
        state.questionActive = true
        state.mood = 'questioning'
        state.holdUntil = 0
      } else {
        state.mood = 'jumping'
        state.holdUntil = 0
      }
    } else if (event.type === 'tool/result') {
      const result = (event.data ?? {}) as { error?: { code?: string } }
      if (state.questionActive) {
        state.questionActive = false
        if (result.error !== undefined) setTransient(state, 'stopped', 1500)
        else {
          state.mood = 'waiting'
          state.holdUntil = 0
        }
      } else {
        state.mood = 'waiting'
        state.holdUntil = 0
      }
    } else if (event.type === 'approval/asked') {
      state.mood = 'authorizing'
      state.holdUntil = 0
    } else if (event.type === 'approval/decided') {
      const payload = (event.data ?? {}) as { result?: string }
      if (payload.result === 'allowed-once') {
        state.mood = 'waiting'
        state.holdUntil = 0
      } else if (payload.result === 'rejected' || payload.result === 'cancelled' || payload.result === 'unavailable') {
        setTransient(state, 'failed', 3000)
      }
    } else if (event.type === 'activity/status') {
      const payload = (event.data ?? {}) as { phase?: string }
      if (payload.phase === undefined) return
      switch (payload.phase) {
        case 'waiting':
        case 'thinking':
          state.mood = 'waiting'
          state.holdUntil = 0
          state.message = undefined
          break
        case 'tool':
          if (state.questionActive) return
          state.mood = 'jumping'
          state.holdUntil = 0
          break
        case 'done':
          setTransient(state, 'done', 2500)
          break
        case 'idle':
          if (Date.now() < state.holdUntil) return
          state.mood = 'idle'
          state.tool = undefined
          state.message = undefined
          break
        default:
          break
      }
    } else if (event.type === 'turn/end') {
      state.questionActive = false
      const payload = (event.data ?? {}) as { reason?: { kind?: string } }
      const kind = payload.reason?.kind
      if (kind === 'error') setTransient(state, 'failed', 3000)
      else if (kind === 'completed') setTransient(state, 'done', 2500)
      else if (kind !== undefined) setTransient(state, 'stopped', 3000)
    }
    publish(state)
  })

  const serializeSession = <T>(sessionId: string, operation: () => Promise<T>): Promise<T> => {
    const previous = sessionOperations.get(sessionId) ?? Promise.resolve()
    const result = previous.then(operation)
    const settled = result.then(() => undefined, () => undefined)
    sessionOperations.set(sessionId, settled)
    void settled.then(() => {
      if (sessionOperations.get(sessionId) === settled) sessionOperations.delete(sessionId)
    })
    return result
  }

  commandBridge = new CommandBridge({
    listWorkspaces: async (): Promise<readonly MoodballWorkspace[]> => Promise.all(
      ctx.workspaceRegistry.list().map(async workspace => ({
        id: String(workspace.id),
        title: workspace.title,
        path: workspace.path,
        status: await workspace.status(),
        sessionIds: workspace.sessionIds.map(String),
      })),
    ),
    createSession: request => serializeSession(request.sessionId, async () => {
      const workspace = ctx.workspaceRegistry.get(request.workspaceId as never)
      if (workspace === undefined) throw new Error(`workspace "${request.workspaceId}" not found`)
      const result = await ctx.sessionController.create({
        workspaceId: workspace.id,
        sessionId: request.sessionId as never,
      })
      stateFor(String(result.sessionId), String(workspace.id)).workspaceId = String(workspace.id)
      return { sessionId: String(result.sessionId) }
    }),
    prompt: request => serializeSession(request.sessionId, async () => {
      const workspace = ctx.workspaceRegistry.get(request.workspaceId as never)
      if (workspace === undefined) throw new Error(`workspace "${request.workspaceId}" not found`)
      if (!workspace.sessionIds.some(candidate => String(candidate) === request.sessionId)) {
        throw new Error(`session "${request.sessionId}" is not attached to workspace "${request.workspaceId}"`)
      }
      await ctx.sessionController.prompt({
        requestId: request.requestId as never,
        sessionId: request.sessionId as never,
        mode: 'queue',
        content: [{ type: 'text', text: request.text }],
      }, AbortSignal.timeout(30_000))
      return { accepted: true, sessionId: request.sessionId }
    }),
    snapshotFor: snapshotForSession,
  })

  ctx.effect(() => {
    localBridge.start()
    commandBridge?.start()
    return () => {
      commandBridge?.stop()
      localBridge.stop()
    }
  }, 'moodball: local bridges')

  const statusRoute: WebRoute = {
    kind: 'exact',
    path: '/api/moodball/status',
    handler: (req: IncomingMessage, res: ServerResponse): void => {
      if (req.method !== 'GET') {
        json(res, 405, { ok: false, error: 'method-not-allowed' })
        return
      }
      json(res, 200, { ok: true, enabled: true, ...snapshot() })
    },
  }

  // Route is always live: unlike the web water ball there is no settings
  // namespace, so nothing can take it down while the plugin is loaded.
  ctx.effect(() => ctx.webServer.register(statusRoute), 'moodball: status route')
}
