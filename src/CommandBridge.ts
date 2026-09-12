import { createServer, type Server, type Socket } from 'node:net'
import { chmodSync, existsSync, lstatSync, mkdirSync, unlinkSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'
import type { MoodBridgePayload } from './LocalStateBridge.js'

/** A detached workspace projection exposed to MoodBall.app. */
export interface MoodballWorkspace {
  id: string
  title: string
  path: string
  status: 'ok' | 'missing-dir'
  sessionIds: readonly string[]
}

export interface CreateSessionCommand {
  workspaceId: string
  sessionId: string
}

export interface PromptCommand {
  workspaceId: string
  sessionId: string
  requestId: string
  text: string
}

export interface CommandHandlers {
  listWorkspaces: () => Promise<readonly MoodballWorkspace[]>
  createSession: (request: CreateSessionCommand) => Promise<{ sessionId: string }>
  prompt: (request: PromptCommand) => Promise<{ accepted: true; sessionId: string }>
  snapshotFor: (sessionId: string) => MoodBridgePayload | undefined
}

interface ClientState {
  socket: Socket
  buffer: string
  subscriptions: Set<string>
  operationTail: Promise<void>
}

interface CommandRequest {
  id?: unknown
  action?: unknown
  workspaceId?: unknown
  sessionId?: unknown
  requestId?: unknown
  text?: unknown
}

class CommandError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message)
    this.name = 'CommandError'
  }
}

/**
 * User-local command and session-status transport.
 *
 * This socket is intentionally separate from LocalStateBridge. Older MoodBall
 * clients continue to receive the global read-only snapshot, while new
 * clients can issue authenticated-by-file-permission commands and subscribe
 * to one selected session without mixing command responses into that stream.
 */
export class CommandBridge {
  static defaultPath = join(homedir(), 'Library', 'Application Support', 'MoodBall', 'moodball-command.sock')

  private readonly socketPath: string
  private readonly handlers: CommandHandlers
  private server: Server | undefined
  private ownsSocket = false
  private clients = new Set<ClientState>()

  constructor(
    handlers: CommandHandlers,
    socketPath = process.env.MOODBALL_COMMAND_SOCKET_PATH ?? CommandBridge.defaultPath,
  ) {
    this.handlers = handlers
    this.socketPath = socketPath
  }

  start(): void {
    if (this.server) return
    mkdirSync(dirname(this.socketPath), { recursive: true })

    if (existsSync(this.socketPath)) {
      const stat = lstatSync(this.socketPath)
      if (!stat.isSocket()) {
        console.warn(`[moodball] command bridge path is not a socket: ${this.socketPath}`)
        return
      }
      unlinkSync(this.socketPath)
    }

    const server = createServer(socket => {
      const client: ClientState = {
        socket,
        buffer: '',
        subscriptions: new Set(),
        operationTail: Promise.resolve(),
      }
      this.clients.add(client)
      socket.setNoDelay(true)
      socket.setEncoding('utf8')
      socket.on('data', chunk => {
        client.buffer += String(chunk)
        this.consume(client)
      })
      socket.on('close', () => this.clients.delete(client))
      socket.on('error', () => this.clients.delete(client))
    })
    server.on('error', error => {
      console.warn(`[moodball] command bridge unavailable: ${error.message}`)
    })
    server.listen(this.socketPath, () => {
      this.ownsSocket = true
      try { chmodSync(this.socketPath, 0o600) } catch { /* best effort */ }
    })
    this.server = server
  }

  /** Push a replacement snapshot to clients subscribed to this session. */
  publish(sessionId: string, snapshot: MoodBridgePayload): void {
    for (const client of this.clients) {
      if (!client.subscriptions.has(sessionId)) continue
      this.write(client.socket, {
        event: 'status',
        sessionId,
        snapshot,
      })
    }
  }

  stop(): void {
    for (const client of this.clients) client.socket.destroy()
    this.clients.clear()
    const server = this.server
    this.server = undefined
    if (!server) return
    server.close()
    if (this.ownsSocket) {
      try { unlinkSync(this.socketPath) } catch { /* already removed */ }
    }
    this.ownsSocket = false
  }

  private consume(client: ClientState): void {
    while (true) {
      const newline = client.buffer.indexOf('\n')
      if (newline < 0) return
      const line = client.buffer.slice(0, newline)
      client.buffer = client.buffer.slice(newline + 1)
      if (line.trim() === '') continue
      if (line.length > 128 * 1024) {
        this.write(client.socket, {
          id: null,
          ok: false,
          error: { code: 'request-too-large', message: 'command request is too large' },
        })
        continue
      }
      client.operationTail = client.operationTail
        .then(() => this.handle(client, line))
        .catch(error => {
          this.write(client.socket, {
            id: null,
            ok: false,
            error: { code: 'internal-error', message: errorMessage(error) },
          })
        })
    }
  }

  private async handle(client: ClientState, line: string): Promise<void> {
    let request: CommandRequest
    try {
      request = JSON.parse(line) as CommandRequest
    } catch {
      this.write(client.socket, {
        id: null,
        ok: false,
        error: { code: 'invalid-json', message: 'request must be one JSON object per line' },
      })
      return
    }

    const id = typeof request.id === 'string' && request.id !== '' ? request.id : null
    const action = request.action
    try {
      if (action === 'capabilities') {
        this.respond(client.socket, id, {
          protocolVersion: 1,
          commandSocket: true,
          statusSubscription: true,
          supports: ['workspaces', 'createSession', 'prompt', 'subscribe', 'unsubscribe'],
        })
        return
      }
      if (action === 'workspaces') {
        this.respond(client.socket, id, { workspaces: await this.handlers.listWorkspaces() })
        return
      }
      if (action === 'createSession') {
        const workspaceId = stringField(request.workspaceId, 'workspaceId')
        const sessionId = stringField(request.sessionId, 'sessionId')
        const result = await this.handlers.createSession({ workspaceId, sessionId })
        this.respond(client.socket, id, result)
        return
      }
      if (action === 'prompt') {
        const workspaceId = stringField(request.workspaceId, 'workspaceId')
        const sessionId = stringField(request.sessionId, 'sessionId')
        const requestId = stringField(request.requestId, 'requestId')
        const text = stringField(request.text, 'text')
        if (text.trim() === '') throw new CommandError('empty-prompt', 'prompt text must not be blank')
        const result = await this.handlers.prompt({ workspaceId, sessionId, requestId, text })
        this.respond(client.socket, id, result)
        return
      }
      if (action === 'subscribe') {
        const sessionId = stringField(request.sessionId, 'sessionId')
        client.subscriptions.add(sessionId)
        this.respond(client.socket, id, {
          sessionId,
          snapshot: this.handlers.snapshotFor(sessionId) ?? null,
        })
        return
      }
      if (action === 'unsubscribe') {
        const sessionId = stringField(request.sessionId, 'sessionId')
        client.subscriptions.delete(sessionId)
        this.respond(client.socket, id, { sessionId })
        return
      }
      throw new CommandError('unknown-action', 'unsupported MoodBall command')
    } catch (error) {
      this.write(client.socket, {
        id,
        ok: false,
        error: {
          code: error instanceof CommandError ? error.code : 'command-failed',
          message: errorMessage(error),
        },
      })
    }
  }

  private respond(socket: Socket, id: string | null, result: unknown): void {
    this.write(socket, { id, ok: true, ...asObject(result) })
  }

  private write(socket: Socket, payload: unknown): void {
    if (!socket.destroyed) socket.write(`${JSON.stringify(payload)}\n`)
  }
}

function stringField(value: unknown, name: string): string {
  if (typeof value !== 'string' || value.trim() === '') {
    throw new CommandError('invalid-request', `${name} must be a non-empty string`)
  }
  return value
}

function asObject(value: unknown): Record<string, unknown> {
  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>
  }
  return { value }
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error)
}
