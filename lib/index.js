import { createServer } from "node:net";
import { chmodSync, existsSync, lstatSync, mkdirSync, unlinkSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
//#region src/CommandBridge.ts
var CommandError = class extends Error {
	code;
	constructor(code, message) {
		super(message);
		this.code = code;
		this.name = "CommandError";
	}
};
/**
* User-local command and session-status transport.
*
* This socket is intentionally separate from LocalStateBridge. Older MoodBall
* clients continue to receive the global read-only snapshot, while new
* clients can issue authenticated-by-file-permission commands and subscribe
* to one selected session without mixing command responses into that stream.
*/
var CommandBridge = class CommandBridge {
	static defaultPath = join(homedir(), "Library", "Application Support", "MoodBall", "moodball-command.sock");
	socketPath;
	handlers;
	server;
	ownsSocket = false;
	clients = /* @__PURE__ */ new Set();
	constructor(handlers, socketPath = process.env.MOODBALL_COMMAND_SOCKET_PATH ?? CommandBridge.defaultPath) {
		this.handlers = handlers;
		this.socketPath = socketPath;
	}
	start() {
		if (this.server) return;
		mkdirSync(dirname(this.socketPath), { recursive: true });
		if (existsSync(this.socketPath)) {
			if (!lstatSync(this.socketPath).isSocket()) {
				console.warn(`[moodball] command bridge path is not a socket: ${this.socketPath}`);
				return;
			}
			unlinkSync(this.socketPath);
		}
		const server = createServer((socket) => {
			const client = {
				socket,
				buffer: "",
				subscriptions: /* @__PURE__ */ new Set(),
				operationTail: Promise.resolve()
			};
			this.clients.add(client);
			socket.setNoDelay(true);
			socket.setEncoding("utf8");
			socket.on("data", (chunk) => {
				client.buffer += String(chunk);
				this.consume(client);
			});
			socket.on("close", () => this.clients.delete(client));
			socket.on("error", () => this.clients.delete(client));
		});
		server.on("error", (error) => {
			console.warn(`[moodball] command bridge unavailable: ${error.message}`);
		});
		server.listen(this.socketPath, () => {
			this.ownsSocket = true;
			try {
				chmodSync(this.socketPath, 384);
			} catch {}
		});
		this.server = server;
	}
	/** Push a replacement snapshot to clients subscribed to this session. */
	publish(sessionId, snapshot) {
		for (const client of this.clients) {
			if (!client.subscriptions.has(sessionId)) continue;
			this.write(client.socket, {
				event: "status",
				sessionId,
				snapshot
			});
		}
	}
	stop() {
		for (const client of this.clients) client.socket.destroy();
		this.clients.clear();
		const server = this.server;
		this.server = void 0;
		if (!server) return;
		server.close();
		if (this.ownsSocket) try {
			unlinkSync(this.socketPath);
		} catch {}
		this.ownsSocket = false;
	}
	consume(client) {
		while (true) {
			const newline = client.buffer.indexOf("\n");
			if (newline < 0) return;
			const line = client.buffer.slice(0, newline);
			client.buffer = client.buffer.slice(newline + 1);
			if (line.trim() === "") continue;
			if (line.length > 131072) {
				this.write(client.socket, {
					id: null,
					ok: false,
					error: {
						code: "request-too-large",
						message: "command request is too large"
					}
				});
				continue;
			}
			client.operationTail = client.operationTail.then(() => this.handle(client, line)).catch((error) => {
				this.write(client.socket, {
					id: null,
					ok: false,
					error: {
						code: "internal-error",
						message: errorMessage(error)
					}
				});
			});
		}
	}
	async handle(client, line) {
		let request;
		try {
			request = JSON.parse(line);
		} catch {
			this.write(client.socket, {
				id: null,
				ok: false,
				error: {
					code: "invalid-json",
					message: "request must be one JSON object per line"
				}
			});
			return;
		}
		const id = typeof request.id === "string" && request.id !== "" ? request.id : null;
		const action = request.action;
		try {
			if (action === "capabilities") {
				this.respond(client.socket, id, {
					protocolVersion: 1,
					commandSocket: true,
					statusSubscription: true,
					supports: [
						"workspaces",
						"createSession",
						"prompt",
						"subscribe",
						"unsubscribe"
					]
				});
				return;
			}
			if (action === "workspaces") {
				this.respond(client.socket, id, { workspaces: await this.handlers.listWorkspaces() });
				return;
			}
			if (action === "createSession") {
				const workspaceId = stringField(request.workspaceId, "workspaceId");
				const sessionId = stringField(request.sessionId, "sessionId");
				const result = await this.handlers.createSession({
					workspaceId,
					sessionId
				});
				this.respond(client.socket, id, result);
				return;
			}
			if (action === "prompt") {
				const workspaceId = stringField(request.workspaceId, "workspaceId");
				const sessionId = stringField(request.sessionId, "sessionId");
				const requestId = stringField(request.requestId, "requestId");
				const text = stringField(request.text, "text");
				if (text.trim() === "") throw new CommandError("empty-prompt", "prompt text must not be blank");
				const result = await this.handlers.prompt({
					workspaceId,
					sessionId,
					requestId,
					text
				});
				this.respond(client.socket, id, result);
				return;
			}
			if (action === "subscribe") {
				const sessionId = stringField(request.sessionId, "sessionId");
				client.subscriptions.add(sessionId);
				this.respond(client.socket, id, {
					sessionId,
					snapshot: this.handlers.snapshotFor(sessionId) ?? null
				});
				return;
			}
			if (action === "unsubscribe") {
				const sessionId = stringField(request.sessionId, "sessionId");
				client.subscriptions.delete(sessionId);
				this.respond(client.socket, id, { sessionId });
				return;
			}
			throw new CommandError("unknown-action", "unsupported MoodBall command");
		} catch (error) {
			this.write(client.socket, {
				id,
				ok: false,
				error: {
					code: error instanceof CommandError ? error.code : "command-failed",
					message: errorMessage(error)
				}
			});
		}
	}
	respond(socket, id, result) {
		this.write(socket, {
			id,
			ok: true,
			...asObject(result)
		});
	}
	write(socket, payload) {
		if (!socket.destroyed) socket.write(`${JSON.stringify(payload)}\n`);
	}
};
function stringField(value, name) {
	if (typeof value !== "string" || value.trim() === "") throw new CommandError("invalid-request", `${name} must be a non-empty string`);
	return value;
}
function asObject(value) {
	if (value !== null && typeof value === "object" && !Array.isArray(value)) return value;
	return { value };
}
function errorMessage(error) {
	return error instanceof Error ? error.message : String(error);
}
//#endregion
//#region src/LocalStateBridge.ts
/**
* Small, opt-in local transport for the host plugin.
*
* The socket is deliberately a server owned by the plugin: MoodBall only
* observes it and never starts or stops Harness. Each client receives the
* latest snapshot immediately, then one JSON object per line on change.
*/
var LocalStateBridge = class LocalStateBridge {
	static defaultPath = join(homedir(), "Library", "Application Support", "MoodBall", "moodball.sock");
	socketPath;
	readSnapshot;
	server;
	clients = /* @__PURE__ */ new Set();
	ownsSocket = false;
	constructor(readSnapshot, socketPath = process.env.MOODBALL_SOCKET_PATH ?? LocalStateBridge.defaultPath) {
		this.readSnapshot = readSnapshot;
		this.socketPath = socketPath;
	}
	start() {
		if (this.server) return;
		mkdirSync(dirname(this.socketPath), { recursive: true });
		if (existsSync(this.socketPath)) {
			if (!lstatSync(this.socketPath).isSocket()) {
				console.warn(`[moodball] local bridge path is not a socket: ${this.socketPath}`);
				return;
			}
			unlinkSync(this.socketPath);
		}
		const server = createServer((client) => {
			this.clients.add(client);
			client.setNoDelay(true);
			client.on("close", () => this.clients.delete(client));
			client.on("error", () => this.clients.delete(client));
			this.write(client);
		});
		server.on("error", (error) => {
			console.warn(`[moodball] local bridge unavailable: ${error.message}`);
		});
		server.listen(this.socketPath, () => {
			this.ownsSocket = true;
			try {
				chmodSync(this.socketPath, 384);
			} catch {}
		});
		this.server = server;
	}
	publish() {
		for (const client of this.clients) this.write(client);
	}
	stop() {
		for (const client of this.clients) client.destroy();
		this.clients.clear();
		const server = this.server;
		this.server = void 0;
		if (!server) return;
		server.close();
		if (this.ownsSocket) try {
			unlinkSync(this.socketPath);
		} catch {}
		this.ownsSocket = false;
	}
	write(client) {
		if (!client.destroyed) client.write(`${JSON.stringify(this.readSnapshot())}\n`);
	}
};
//#endregion
//#region src/index.ts
/** Stable cordis plugin name (matches cordis.patch.yml insert id). */
const name = "moodball";
/** Services required before the status surface can mount. */
const inject = [
	"webServer",
	"workspaceRegistry",
	"sessionController"
];
function stateForMood(mood) {
	switch (mood) {
		case "waiting": return "thinking";
		case "jumping": return "toolCalling";
		case "authorizing": return "waitingApproval";
		case "questioning": return "waitingUserAnswer";
		case "done": return "completed";
		case "failed": return "failed";
		case "stopped": return "stopped";
		case "idle": return "idle";
		default: return "disconnected";
	}
}
/** Write one JSON response. */
function json(res, status, body) {
	res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
	res.end(JSON.stringify(body));
}
/**
* Register the MoodBall status surface: fold the agent session stream into a
* stable snapshot, serve it over GET /api/moodball/status, and broadcast the
* same snapshot through LocalStateBridge. The route is always live while the
* plugin is loaded — there is no settings namespace to toggle.
* @param ctx - host root context.
*/
function apply(ctx) {
	const globalState = {
		mood: "idle",
		holdUntil: 0,
		questionActive: false
	};
	const sessionStates = /* @__PURE__ */ new Map();
	const sessionOperations = /* @__PURE__ */ new Map();
	let activeSessionId;
	let commandBridge;
	const stateFor = (sessionId, workspaceId) => {
		const existing = sessionStates.get(sessionId);
		if (existing) {
			if (workspaceId) existing.workspaceId = workspaceId;
			return existing;
		}
		const created = {
			sessionId,
			workspaceId,
			mood: "idle",
			holdUntil: 0,
			questionActive: false
		};
		sessionStates.set(sessionId, created);
		return created;
	};
	const workspaceForSession = (sessionId) => {
		const workspace = ctx.workspaceRegistry.list().find((candidate) => candidate.sessionIds.some((candidateSessionId) => String(candidateSessionId) === sessionId));
		return workspace ? String(workspace.id) : void 0;
	};
	const snapshotOf = (state) => ({
		state: stateForMood(state.mood),
		mood: state.mood,
		...state.sessionId ? { sessionId: state.sessionId } : {},
		...state.workspaceId ? { workspaceId: state.workspaceId } : {},
		taskRunning: [
			"waiting",
			"jumping",
			"authorizing",
			"questioning"
		].includes(state.mood),
		waitingForUser: state.mood === "authorizing" || state.mood === "questioning",
		failed: state.mood === "failed",
		completed: state.mood === "done",
		...state.tool ? { tool: state.tool } : {},
		...state.message ? { message: state.message } : {},
		updatedAt: Date.now()
	});
	const snapshotForSession = (sessionId) => snapshotOf(stateFor(sessionId, workspaceForSession(sessionId)));
	const snapshot = () => activeSessionId === void 0 ? snapshotOf(globalState) : snapshotForSession(activeSessionId);
	const localBridge = new LocalStateBridge(snapshot);
	const publish = (state) => {
		localBridge.publish();
		if (state.sessionId) commandBridge?.publish(state.sessionId, snapshotOf(state));
	};
	const setTransient = (state, next, ms) => {
		state.mood = next;
		state.holdUntil = Date.now() + ms;
		publish(state);
		setTimeout(() => {
			if (state.mood === next) {
				state.mood = "idle";
				publish(state);
			}
		}, ms);
	};
	ctx.on("session/event", (_session, event) => {
		const info = _session;
		const sessionId = info.id ?? info.sessionId;
		const state = sessionId === void 0 ? globalState : stateFor(sessionId, info.workspaceId ?? workspaceForSession(sessionId));
		if (sessionId) activeSessionId = sessionId;
		if (event.type === "turn/start" || event.type === "step/start" || event.type === "assistant/chunk") {
			state.mood = "waiting";
			state.holdUntil = 0;
			state.message = void 0;
		} else if (event.type === "tool/call") {
			const call = event.data ?? {};
			state.tool = call.name;
			if (call.name === "ask_user_question") {
				state.questionActive = true;
				state.mood = "questioning";
				state.holdUntil = 0;
			} else {
				state.mood = "jumping";
				state.holdUntil = 0;
			}
		} else if (event.type === "tool/result") {
			const result = event.data ?? {};
			if (state.questionActive) {
				state.questionActive = false;
				if (result.error !== void 0) setTransient(state, "stopped", 1500);
				else {
					state.mood = "waiting";
					state.holdUntil = 0;
				}
			} else {
				state.mood = "waiting";
				state.holdUntil = 0;
			}
		} else if (event.type === "approval/asked") {
			state.mood = "authorizing";
			state.holdUntil = 0;
		} else if (event.type === "approval/decided") {
			const payload = event.data ?? {};
			if (payload.result === "allowed-once") {
				state.mood = "waiting";
				state.holdUntil = 0;
			} else if (payload.result === "rejected" || payload.result === "cancelled" || payload.result === "unavailable") setTransient(state, "failed", 3e3);
		} else if (event.type === "activity/status") {
			const payload = event.data ?? {};
			if (payload.phase === void 0) return;
			switch (payload.phase) {
				case "waiting":
				case "thinking":
					state.mood = "waiting";
					state.holdUntil = 0;
					state.message = void 0;
					break;
				case "tool":
					if (state.questionActive) return;
					state.mood = "jumping";
					state.holdUntil = 0;
					break;
				case "done":
					setTransient(state, "done", 2500);
					break;
				case "idle":
					if (Date.now() < state.holdUntil) return;
					state.mood = "idle";
					state.tool = void 0;
					state.message = void 0;
			}
		} else if (event.type === "turn/end") {
			state.questionActive = false;
			const kind = (event.data ?? {}).reason?.kind;
			if (kind === "error") setTransient(state, "failed", 3e3);
			else if (kind === "completed") setTransient(state, "done", 2500);
			else if (kind !== void 0) setTransient(state, "stopped", 3e3);
		}
		publish(state);
	});
	const serializeSession = (sessionId, operation) => {
		const result = (sessionOperations.get(sessionId) ?? Promise.resolve()).then(operation);
		const settled = result.then(() => void 0, () => void 0);
		sessionOperations.set(sessionId, settled);
		settled.then(() => {
			if (sessionOperations.get(sessionId) === settled) sessionOperations.delete(sessionId);
		});
		return result;
	};
	commandBridge = new CommandBridge({
		listWorkspaces: async () => Promise.all(ctx.workspaceRegistry.list().map(async (workspace) => ({
			id: String(workspace.id),
			title: workspace.title,
			path: workspace.path,
			status: await workspace.status(),
			sessionIds: workspace.sessionIds.map(String)
		}))),
		createSession: (request) => serializeSession(request.sessionId, async () => {
			const workspace = ctx.workspaceRegistry.get(request.workspaceId);
			if (workspace === void 0) throw new Error(`workspace "${request.workspaceId}" not found`);
			const result = await ctx.sessionController.create({
				workspaceId: workspace.id,
				sessionId: request.sessionId
			});
			stateFor(String(result.sessionId), String(workspace.id)).workspaceId = String(workspace.id);
			return { sessionId: String(result.sessionId) };
		}),
		prompt: (request) => serializeSession(request.sessionId, async () => {
			const workspace = ctx.workspaceRegistry.get(request.workspaceId);
			if (workspace === void 0) throw new Error(`workspace "${request.workspaceId}" not found`);
			if (!workspace.sessionIds.some((candidate) => String(candidate) === request.sessionId)) throw new Error(`session "${request.sessionId}" is not attached to workspace "${request.workspaceId}"`);
			await ctx.sessionController.prompt({
				requestId: request.requestId,
				sessionId: request.sessionId,
				mode: "queue",
				content: [{
					type: "text",
					text: request.text
				}]
			}, AbortSignal.timeout(3e4));
			return {
				accepted: true,
				sessionId: request.sessionId
			};
		}),
		snapshotFor: snapshotForSession
	});
	ctx.effect(() => {
		localBridge.start();
		commandBridge?.start();
		return () => {
			commandBridge?.stop();
			localBridge.stop();
		};
	}, "moodball: local bridges");
	const statusRoute = {
		kind: "exact",
		path: "/api/moodball/status",
		handler: (req, res) => {
			if (req.method !== "GET") {
				json(res, 405, {
					ok: false,
					error: "method-not-allowed"
				});
				return;
			}
			json(res, 200, {
				ok: true,
				enabled: true,
				...snapshot()
			});
		}
	};
	ctx.effect(() => ctx.webServer.register(statusRoute), "moodball: status route");
}
//#endregion
export { CommandBridge, apply, inject, name };
