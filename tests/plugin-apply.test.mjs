import assert from 'node:assert/strict'
import { mkdtemp, rm } from 'node:fs/promises'
import { connect } from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'

function waitForServer(path) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 2_000
    const attempt = () => {
      const socket = connect(path)
      const onError = () => {
        socket.destroy()
        if (Date.now() >= deadline) reject(new Error('plugin command socket did not start'))
        else setTimeout(attempt, 10)
      }
      socket.once('error', onError)
      socket.once('connect', () => {
        socket.off('error', onError)
        resolve(socket)
      })
    }
    attempt()
  })
}

function nextJsonLine(socket) {
  let buffer = ''
  const waiters = []
  socket.setEncoding('utf8')
  socket.on('data', chunk => {
    buffer += chunk
    while (true) {
      const newline = buffer.indexOf('\n')
      if (newline < 0) return
      const line = buffer.slice(0, newline)
      buffer = buffer.slice(newline + 1)
      if (line.trim() !== '') waiters.shift()?.(JSON.parse(line))
    }
  })
  return () => new Promise(resolve => waiters.push(resolve))
}

async function command(socket, nextLine, id, action, fields = {}) {
  socket.write(`${JSON.stringify({ id, action, ...fields })}\n`)
  return nextLine()
}

test('plugin adapter calls official-style workspace and session services', async () => {
  const root = await mkdtemp(join(tmpdir(), 'moodball-plugin-'))
  const statusPath = join(root, 'status.sock')
  const commandPath = join(root, 'command.sock')
  const previousStatusPath = process.env.MOODBALL_SOCKET_PATH
  const previousCommandPath = process.env.MOODBALL_COMMAND_SOCKET_PATH
  process.env.MOODBALL_SOCKET_PATH = statusPath
  process.env.MOODBALL_COMMAND_SOCKET_PATH = commandPath

  let eventHandler
  let statusRoute
  const cleanups = []
  const calls = []
  const workspace = {
    id: 'workspace-test',
    title: 'Test workspace',
    path: root,
    sessionIds: [],
    status: async () => 'ok',
  }
  const ctx = {
    workspaceRegistry: {
      list: () => [workspace],
      get: id => String(id) === workspace.id ? workspace : undefined,
    },
    sessionController: {
      create: async request => {
        workspace.sessionIds.push(request.sessionId)
        return { sessionId: request.sessionId }
      },
      prompt: async request => {
        calls.push(request)
        return { accepted: true }
      },
    },
    on: (event, handler) => {
      if (event === 'session/event') eventHandler = handler
    },
    effect: effect => {
      const cleanup = effect()
      if (typeof cleanup === 'function') cleanups.push(cleanup)
    },
    webServer: {
      register: route => { statusRoute = route },
    },
  }

  try {
    const plugin = await import('../lib/index.js')
    plugin.apply(ctx)
    const socket = await waitForServer(commandPath)
    const nextLine = nextJsonLine(socket)

    const listed = await command(socket, nextLine, 'list', 'workspaces')
    assert.equal(listed.workspaces[0].id, workspace.id)

    const created = await command(socket, nextLine, 'create', 'createSession', {
      workspaceId: workspace.id,
      sessionId: 'moodball-session-test',
    })
    assert.equal(created.sessionId, 'moodball-session-test')

    const subscribed = await command(socket, nextLine, 'subscribe', 'subscribe', {
      sessionId: 'moodball-session-test',
    })
    assert.equal(subscribed.snapshot.workspaceId, workspace.id)
    assert.equal(subscribed.snapshot.mood, 'idle')

    const prompted = await command(socket, nextLine, 'prompt', 'prompt', {
      workspaceId: workspace.id,
      sessionId: 'moodball-session-test',
      requestId: 'request-test',
      text: 'hello',
    })
    assert.equal(prompted.accepted, true)
    assert.equal(calls[0].mode, 'queue')
    assert.deepEqual(calls[0].content, [{ type: 'text', text: 'hello' }])

    eventHandler({ id: 'moodball-session-test' }, { type: 'turn/start' })
    const event = await nextLine()
    assert.equal(event.event, 'status')
    assert.equal(event.snapshot.mood, 'waiting')
    assert.equal(event.snapshot.taskRunning, true)

    let routeBody
    statusRoute.handler(
      { method: 'GET' },
      { writeHead: status => assert.equal(status, 200), end: body => { routeBody = JSON.parse(body) } },
    )
    assert.equal(routeBody.ok, true)
    assert.equal(routeBody.sessionId, 'moodball-session-test')
    socket.destroy()
  } finally {
    for (const cleanup of cleanups.reverse()) cleanup()
    if (previousStatusPath === undefined) delete process.env.MOODBALL_SOCKET_PATH
    else process.env.MOODBALL_SOCKET_PATH = previousStatusPath
    if (previousCommandPath === undefined) delete process.env.MOODBALL_COMMAND_SOCKET_PATH
    else process.env.MOODBALL_COMMAND_SOCKET_PATH = previousCommandPath
    await rm(root, { recursive: true, force: true })
  }
})
