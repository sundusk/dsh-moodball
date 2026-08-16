import { installSettingsSection, settingsNamespace } from "@deepseek-ai/dsh-settings";
import z from "schemastery";
//#region src/index.ts
/** Stable cordis plugin name (matches cordis.patch.yml insert id). */
const name = "moodball";
/** Services required before the status surface can mount. */
const inject = ["webServer"];
/** Settings namespace of the moodball capability (the browser card edits it). */
const MOODBALL_SETTINGS_NAMESPACE = "moodball";
/** Settings section schema. */
const MOODBALL_SETTINGS_SCHEMA = z.object({ enabled: z.boolean().default(true) });
/** Write one JSON response. */
function json(res, status, body) {
	res.writeHead(status, { "content-type": "application/json; charset=utf-8" });
	res.end(JSON.stringify(body));
}
/**
* Register the MoodBall status surface: fold the agent session stream into a
* mood and serve it over GET /api/moodball/status. The route is live while the
* `moodball` settings namespace is enabled; toggling it off removes the route
* until re-enabled.
* @param ctx - host root context.
*/
function apply(ctx) {
	let mood = "idle";
	let holdUntil = 0;
	let questionActive = false;
	let current = () => ({ enabled: true });
	const enabled = () => current().enabled ?? true;
	const setTransient = (next, ms) => {
		mood = next;
		holdUntil = Date.now() + ms;
		setTimeout(() => {
			if (mood === next) mood = "idle";
		}, ms);
	};
	ctx.on("session/event", (_session, event) => {
		if (!enabled()) return;
		if (event.type === "turn/start" || event.type === "step/start" || event.type === "assistant/chunk") {
			mood = "waiting";
			holdUntil = 0;
		} else if (event.type === "tool/call") {
			if ((event.data ?? {}).name === "ask_user_question") {
				questionActive = true;
				mood = "questioning";
				holdUntil = 0;
			} else {
				mood = "jumping";
				holdUntil = 0;
			}
		} else if (event.type === "tool/result") {
			const result = event.data ?? {};
			if (questionActive) {
				questionActive = false;
				if (result.error !== void 0) setTransient("stopped", 1500);
				else {
					mood = "waiting";
					holdUntil = 0;
				}
			} else {
				mood = "waiting";
				holdUntil = 0;
			}
		} else if (event.type === "approval/asked") {
			mood = "authorizing";
			holdUntil = 0;
		} else if (event.type === "approval/decided") {
			const payload = event.data ?? {};
			if (payload.result === "allowed-once") {
				mood = "waiting";
				holdUntil = 0;
			} else if (payload.result === "rejected" || payload.result === "cancelled" || payload.result === "unavailable") setTransient("failed", 3e3);
		} else if (event.type === "activity/status") {
			const payload = event.data ?? {};
			if (payload.phase === void 0) return;
			switch (payload.phase) {
				case "waiting":
				case "thinking":
					mood = "waiting";
					holdUntil = 0;
					break;
				case "tool":
					if (questionActive) return;
					mood = "jumping";
					holdUntil = 0;
					break;
				case "done":
					setTransient("done", 2500);
					break;
				case "idle":
					if (Date.now() < holdUntil) return;
					mood = "idle";
			}
		} else if (event.type === "turn/end") {
			questionActive = false;
			const kind = (event.data ?? {}).reason?.kind;
			if (kind === "error") setTransient("failed", 3e3);
			else if (kind === "completed") setTransient("done", 2500);
			else if (kind !== void 0) setTransient("stopped", 3e3);
		}
	});
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
				mood,
				enabled: enabled()
			});
		}
	};
	let disposeRoute;
	const syncRoutes = () => {
		if (disposeRoute === void 0 && enabled()) disposeRoute = ctx.effect(() => ctx.webServer.register(statusRoute), "moodball: status route");
		else if (disposeRoute !== void 0 && !enabled()) {
			disposeRoute();
			disposeRoute = void 0;
		}
	};
	installSettingsSection(ctx, settingsNamespace(MOODBALL_SETTINGS_NAMESPACE), MOODBALL_SETTINGS_SCHEMA, { enabled: true }, {
		setSource: (source) => {
			current = source;
		},
		onChange: () => {
			if (!enabled()) mood = "idle";
			syncRoutes();
		}
	});
	syncRoutes();
}
//#endregion
export { MOODBALL_SETTINGS_NAMESPACE, MOODBALL_SETTINGS_SCHEMA, apply, inject, name };
