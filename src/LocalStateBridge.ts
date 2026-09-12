import { createServer, type Server, type Socket } from 'node:net'
import { chmodSync, existsSync, lstatSync, mkdirSync, unlinkSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join } from 'node:path'

/** The newline-delimited local bridge payload shared with MoodBall.app. */
export interface MoodBridgePayload {
  state: string
  mood: string
  sessionId?: string
  workspaceId?: string
  taskRunning: boolean
  waitingForUser: boolean
  failed: boolean
  completed: boolean
  tool?: string
  message?: string
  updatedAt: number
}

/**
 * Small, opt-in local transport for the host plugin.
 *
 * The socket is deliberately a server owned by the plugin: MoodBall only
 * observes it and never starts or stops Harness. Each client receives the
 * latest snapshot immediately, then one JSON object per line on change.
 */
export class LocalStateBridge {
  static defaultPath = join(homedir(), 'Library', 'Application Support', 'MoodBall', 'moodball.sock')

  private readonly socketPath: string
  private readonly readSnapshot: () => MoodBridgePayload
  private server: Server | undefined
  private clients = new Set<Socket>()
  private ownsSocket = false

  constructor(readSnapshot: () => MoodBridgePayload, socketPath = process.env.MOODBALL_SOCKET_PATH ?? LocalStateBridge.defaultPath) {
    this.readSnapshot = readSnapshot
    this.socketPath = socketPath
  }

  start(): void {
    if (this.server) return
    mkdirSync(dirname(this.socketPath), { recursive: true })

    // Only remove an existing Unix socket. Never replace an unrelated file.
    if (existsSync(this.socketPath)) {
      const stat = lstatSync(this.socketPath)
      if (!stat.isSocket()) {
        console.warn(`[moodball] local bridge path is not a socket: ${this.socketPath}`)
        return
      }
      unlinkSync(this.socketPath)
    }

    const server = createServer((client) => {
      this.clients.add(client)
      client.setNoDelay(true)
      client.on('close', () => this.clients.delete(client))
      client.on('error', () => this.clients.delete(client))
      this.write(client)
    })
    server.on('error', (error) => {
      console.warn(`[moodball] local bridge unavailable: ${error.message}`)
    })
    server.listen(this.socketPath, () => {
      this.ownsSocket = true
      try { chmodSync(this.socketPath, 0o600) } catch { /* best effort */ }
    })
    this.server = server
  }

  publish(): void {
    for (const client of this.clients) this.write(client)
  }

  stop(): void {
    for (const client of this.clients) client.destroy()
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

  private write(client: Socket): void {
    if (!client.destroyed) client.write(`${JSON.stringify(this.readSnapshot())}\n`)
  }
}
