import assert from 'node:assert/strict'
import { mkdtemp, rm, stat } from 'node:fs/promises'
import { connect } from 'node:net'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { test } from 'node:test'
import { CommandBridge } from '../lib/index.js'

const snapshot = {
  state: 'thinking',
  mood: 'waiting',
  sessionId: 'moodball-session-test',
  workspaceId: 'workspace-test',
  taskRunning: true,
  waitingForUser: false,
  failed: false,
  completed: false,
  updatedAt: 1,
}

function waitForServer(path) {
  return new Promise((resolve, reject) => {
    const deadline = Date.now() + 2_000
    const attempt = () => {
      const socket = connect(path)
      const onError = () => {
        socket.destroy()
        if (Date.now() >= deadline) reject(new Error('command socket did not start'))
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

function readLines(socket) {
  let buffer = ''
  const waiting = []
  socket.setEncoding('utf8')
  socket.on('data', chunk => {
    buffer += chunk
    while (true) {
      const newline = buffer.indexOf('\n')
      if (newline < 0) return
      const line = buffer.slice(0, newline)
      buffer = buffer.slice(newline + 1)
      if (line.trim() !== '') waiting.shift()?.(JSON.parse(line))
    }
  })
  return () => new Promise(resolve => waiting.push(resolve))
}

function send(socket, nextLine, id, action, fields = {}) {
  socket.write(`${JSON.stringify({ id, action, ...fields })}\n`)
  return nextLine()
}

test('command bridge serves capabilities, subscription snapshots, and serialized prompt commands', async () => {
  const root = await mkdtemp(join(tmpdir(), 'moodball-command-'))
  const socketPath = join(root, 'command.sock')
  let active = 0
  let maxActive = 0
  const prompts = []
  const bridge = new CommandBridge({
    listWorkspaces: async () => [{
      id: 'workspace-test', title: 'Test', path: root, status: 'ok', sessionIds: [],
    }],
    createSession: async request => ({ sessionId: request.sessionId }),
    prompt: async request => {
      active += 1
      maxActive = Math.max(maxActive, active)
      await new Promise(resolve => setTimeout(resolve, 20))
      active -= 1
      prompts.push(request)
      return { accepted: true, sessionId: request.sessionId }
    },
    snapshotFor: () => snapshot,
  }, socketPath)
  bridge.start()

  const socket = await waitForServer(socketPath)
  const nextLine = readLines(socket)
  const capabilities = await send(socket, nextLine, 'cap', 'capabilities')
  assert.equal(capabilities.ok, true)
  assert.deepEqual(capabilities.supports, ['workspaces', 'createSession', 'prompt', 'subscribe', 'unsubscribe'])

  const listed = await send(socket, nextLine, 'list', 'workspaces')
  assert.equal(listed.workspaces[0].title, 'Test')

  const subscribed = await send(socket, nextLine, 'sub', 'subscribe', { sessionId: snapshot.sessionId })
  assert.deepEqual(subscribed.snapshot, snapshot)

  const promptA = send(socket, nextLine, 'prompt-a', 'prompt', {
    workspaceId: snapshot.workspaceId, sessionId: snapshot.sessionId, requestId: 'request-a', text: 'A',
  })
  const promptB = send(socket, nextLine, 'prompt-b', 'prompt', {
    workspaceId: snapshot.workspaceId, sessionId: snapshot.sessionId, requestId: 'request-b', text: 'B',
  })
  assert.equal((await promptA).accepted, true)
  assert.equal((await promptB).accepted, true)
  assert.equal(maxActive, 1)
  assert.deepEqual(prompts.map(prompt => prompt.requestId), ['request-a', 'request-b'])

  bridge.publish(snapshot.sessionId, { ...snapshot, mood: 'done', state: 'completed', taskRunning: false })
  const event = await nextLine()
  assert.equal(event.event, 'status')
  assert.equal(event.snapshot.mood, 'done')

  const permissions = (await stat(socketPath)).mode & 0o777
  assert.equal(permissions, 0o600)

  socket.destroy()
  bridge.stop()
  await rm(root, { recursive: true, force: true })
})

test('command bridge rejects malformed JSON without taking down the socket', async () => {
  const root = await mkdtemp(join(tmpdir(), 'moodball-command-invalid-'))
  const socketPath = join(root, 'command.sock')
  const bridge = new CommandBridge({
    listWorkspaces: async () => [],
    createSession: async request => ({ sessionId: request.sessionId }),
    prompt: async request => ({ accepted: true, sessionId: request.sessionId }),
    snapshotFor: () => undefined,
  }, socketPath)
  bridge.start()
  const socket = await waitForServer(socketPath)
  const nextLine = readLines(socket)
  socket.write('not-json\n')
  const invalid = await nextLine()
  assert.equal(invalid.ok, false)
  assert.equal(invalid.error.code, 'invalid-json')
  const capabilities = await send(socket, nextLine, 'cap', 'capabilities')
  assert.equal(capabilities.ok, true)
  socket.destroy()
  bridge.stop()
  await rm(root, { recursive: true, force: true })
})
