window.__ModuleLoader__.load({
	id: "@linxin666/dsh-moodball-status",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		let react = require("react");
		let react_jsx_runtime = require("react/jsx-runtime");
		let _deepseek_ai_dsh_client_runtime_client = require("@deepseek-ai/dsh-client-runtime/client");
		//#region \0dsh-css:settings-card.module.css.mjs
		const css = ".KhFzGG_card{border:1px solid var(--dsw-alias-border-l2);background:var(--dsw-alias-bg-layer-3);border-radius:8px;list-style:none;transition:border-color .16s,background .16s;overflow:hidden}.KhFzGG_cardOpen{background:var(--dsw-alias-bg-layer-2);border-color:var(--dsw-alias-label-dimmed)}.KhFzGG_header{cursor:pointer;text-align:left;width:100%;font:inherit;background:0 0;border:0;align-items:center;gap:8px;padding:10px 14px;transition:background .12s;display:flex}.KhFzGG_header:hover{background:var(--dsw-alias-interactive-bg-hover)}.KhFzGG_header:active{background:var(--dsw-alias-interactive-bg-hover-solid)}.KhFzGG_header:focus-visible{box-shadow:inset 0 0 0 2px var(--dsw-alias-button-info-fill);outline:none}.KhFzGG_headText{flex-direction:column;flex:1;gap:2px;min-width:0;display:flex}.KhFzGG_name{color:var(--dsw-alias-label-primary);font-weight:600}.KhFzGG_description{color:var(--dsw-alias-label-tertiary);font-size:12px}.KhFzGG_pending{color:var(--dsw-alias-state-warn-primary);font-size:12px}.KhFzGG_chevron{color:var(--dsw-alias-label-tertiary);transition:transform .12s}.KhFzGG_chevronOpen{transform:rotate(180deg)}.KhFzGG_body{flex-direction:column;gap:14px;padding:0 14px 14px;display:flex}.KhFzGG_readOnly{color:var(--dsw-alias-label-tertiary);margin:0;font-size:12px}.KhFzGG_footer{justify-content:flex-end;align-items:center;gap:8px;display:flex}.KhFzGG_failed{color:var(--dsw-alias-state-error-primary);margin:0 auto 0 0;font-size:12px}.KhFzGG_discard,.KhFzGG_save{font:inherit;cursor:pointer;border-radius:6px;padding:5px 12px;font-size:13px;transition:color .12s,border-color .12s,background .12s,box-shadow .12s}.KhFzGG_discard{border:1px solid var(--dsw-alias-border-l2);color:var(--dsw-alias-label-secondary);background:0 0}.KhFzGG_discard:hover:not(:disabled){color:var(--dsw-alias-label-primary);border-color:var(--dsw-alias-label-dimmed)}.KhFzGG_discard:active:not(:disabled){background:var(--dsw-alias-interactive-bg-hover)}.KhFzGG_save{border:1px solid var(--dsw-alias-button-info-fill);background:var(--dsw-alias-button-info-fill);color:var(--dsw-alias-label-primary-foreground)}.KhFzGG_save:hover:not(:disabled){border-color:var(--dsw-alias-button-info-hover);background:var(--dsw-alias-button-info-hover)}.KhFzGG_save:active:not(:disabled){filter:brightness(.94)}.KhFzGG_discard:focus-visible:not(:disabled),.KhFzGG_save:focus-visible:not(:disabled){box-shadow:0 0 0 2px var(--dsw-alias-button-info-fill);outline:none}.KhFzGG_discard:disabled,.KhFzGG_save:disabled{opacity:.5;cursor:default}.KhFzGG_field{flex-direction:column;gap:4px;display:flex}.KhFzGG_head{align-items:center;gap:8px;display:flex}.KhFzGG_label{color:var(--dsw-alias-label-primary);font-size:13px;font-weight:500}.KhFzGG_badges{align-items:center;gap:6px;display:flex}.KhFzGG_badge{background:var(--dsw-alias-interactive-bg-hover-accent);color:var(--dsw-alias-state-business-primary);border-radius:999px;padding:1px 6px;font-size:11px}.KhFzGG_reset{color:var(--dsw-alias-state-business-primary);cursor:pointer;background:0 0;border:0;border-radius:3px;padding:0;font-size:11px;transition:color .12s,box-shadow .12s}.KhFzGG_reset:hover:not(:disabled){color:var(--dsw-alias-label-primary-bluish);text-decoration:underline}.KhFzGG_reset:active:not(:disabled){color:var(--dsw-alias-state-business-primary)}.KhFzGG_reset:focus-visible:not(:disabled){box-shadow:0 0 0 2px var(--dsw-alias-button-info-fill);outline:none}.KhFzGG_reset:disabled{opacity:.5;cursor:default}.KhFzGG_input,.KhFzGG_select{border:1px solid var(--dsw-alias-border-l2);font:inherit;color:var(--dsw-alias-label-primary);background:var(--dsw-specific-input-major);border-radius:6px;padding:6px 8px;font-size:13px}.KhFzGG_switch{color:var(--dsw-alias-label-secondary);font:inherit;cursor:pointer;background:0 0;border:0;align-self:flex-start;align-items:center;gap:8px;padding:0;font-size:13px;display:inline-flex}.KhFzGG_switch:disabled{opacity:.6;cursor:default}.KhFzGG_switch:focus-visible{box-shadow:0 0 0 2px var(--dsw-alias-button-info-fill);border-radius:999px;outline:none}.KhFzGG_switchTrack,.KhFzGG_switchTrackOn{background:var(--dsw-alias-border-l2);border-radius:999px;align-items:center;width:34px;height:20px;padding:2px;transition:background .12s;display:inline-flex;position:relative}.KhFzGG_switchTrackOn{background:var(--dsw-alias-button-info-fill)}.KhFzGG_switchThumb,.KhFzGG_switchThumbOn{background:var(--dsw-alias-bg-base);border-radius:50%;width:16px;height:16px;transition:transform .12s;display:block;transform:translate(0);box-shadow:0 1px 2px #0003}.KhFzGG_switchThumbOn{transform:translate(14px)}.KhFzGG_switchState{text-align:left;min-width:20px}.KhFzGG_inputInvalid{border:1px solid var(--dsw-alias-state-error-primary);font:inherit;color:var(--dsw-alias-label-primary);border-radius:6px;padding:6px 8px;font-size:13px}.KhFzGG_input:disabled,.KhFzGG_select:disabled{opacity:.6}.KhFzGG_input:focus,.KhFzGG_select:focus{border-color:var(--dsw-alias-button-info-fill);box-shadow:0 0 0 2px var(--dsw-alias-button-info-fill);outline:none}.KhFzGG_inputInvalid:focus{box-shadow:0 0 0 2px var(--dsw-alias-state-error-primary);outline:none}.KhFzGG_hint{color:var(--dsw-alias-label-secondary);margin:0;font-size:12px}.KhFzGG_invalid{color:var(--dsw-alias-state-error-primary);margin:0;font-size:12px}@media (prefers-reduced-motion:reduce){.KhFzGG_card,.KhFzGG_header,.KhFzGG_chevron,.KhFzGG_chevronOpen,.KhFzGG_switchTrack,.KhFzGG_switchTrackOn,.KhFzGG_switchThumb,.KhFzGG_switchThumbOn,.KhFzGG_reset,.KhFzGG_discard,.KhFzGG_save{transition:none}}";
		const tagId = "@linxin666/dsh-moodball-status/settings-card.module.css";
		if (typeof document !== "undefined" && document.querySelector("style[data-plugin-css=" + JSON.stringify(tagId) + "]") === null) {
			const tag = document.createElement("style");
			tag.dataset.plugin = "@linxin666/dsh-moodball-status";
			tag.dataset.pluginCss = tagId;
			tag.textContent = css;
			document.head.appendChild(tag);
		}
		var _dsh_css_settings_card_module_css_default = {
			"badge": "KhFzGG_badge",
			"badges": "KhFzGG_badges",
			"body": "KhFzGG_body",
			"card": "KhFzGG_card",
			"cardOpen": "KhFzGG_cardOpen",
			"chevron": "KhFzGG_chevron",
			"chevronOpen": "KhFzGG_chevronOpen",
			"description": "KhFzGG_description",
			"discard": "KhFzGG_discard",
			"failed": "KhFzGG_failed",
			"field": "KhFzGG_field",
			"footer": "KhFzGG_footer",
			"head": "KhFzGG_head",
			"headText": "KhFzGG_headText",
			"header": "KhFzGG_header",
			"hint": "KhFzGG_hint",
			"input": "KhFzGG_input",
			"inputInvalid": "KhFzGG_inputInvalid",
			"invalid": "KhFzGG_invalid",
			"label": "KhFzGG_label",
			"name": "KhFzGG_name",
			"pending": "KhFzGG_pending",
			"readOnly": "KhFzGG_readOnly",
			"reset": "KhFzGG_reset",
			"save": "KhFzGG_save",
			"select": "KhFzGG_select",
			"switch": "KhFzGG_switch",
			"switchState": "KhFzGG_switchState",
			"switchThumb": "KhFzGG_switchThumb",
			"switchThumbOn": "KhFzGG_switchThumbOn",
			"switchTrack": "KhFzGG_switchTrack",
			"switchTrackOn": "KhFzGG_switchTrackOn"
		};
		//#endregion
		//#region src/client/PluginSettingsCard.tsx
		/**
		* Shared chrome for the plugin settings card: a disclosure header naming the
		* plugin and what its settings govern, the controls inside, and the save that
		* writes them. Renders nothing while the namespace is unavailable — a
		* deployment that does not compose the owning plugin should show no trace of
		* it. Mirrors the official ui-plugin-config PluginCard in a self-contained
		* slice (this package must not depend on a sibling UI package).
		*/
		/**
		* Render one plugin settings card.
		* @param props - the plugin's copy keys, its form state, and its controls.
		* @returns the card, or nothing when the namespace is unavailable.
		*/
		function PluginSettingsCard(props) {
			const [open, setOpen] = (0, react.useState)(false);
			const { state } = props;
			if (!state.available) return null;
			const title = props.t(props.titleKey);
			const blocked = !state.dirty || state.invalid || state.saving;
			return /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("li", {
				className: _dsh_css_settings_card_module_css_default.card,
				children: [/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("button", {
					type: "button",
					className: _dsh_css_settings_card_module_css_default.header,
					"aria-expanded": open,
					"aria-label": `${props.t(open ? "settings.collapse" : "settings.expand")}: ${title}`,
					onClick: () => {
						setOpen(!open);
					},
					children: [
						/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("span", {
							className: _dsh_css_settings_card_module_css_default.headText,
							children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
								className: _dsh_css_settings_card_module_css_default.name,
								children: title
							}), /* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
								className: _dsh_css_settings_card_module_css_default.description,
								children: props.t(props.descriptionKey)
							})]
						}),
						state.dirty ? /* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
							className: _dsh_css_settings_card_module_css_default.pending,
							children: props.t("settings.unsaved")
						}) : null,
						/* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
							className: open ? _dsh_css_settings_card_module_css_default.chevronOpen : _dsh_css_settings_card_module_css_default.chevron,
							children: "▾"
						})
					]
				}), open ? /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
					className: _dsh_css_settings_card_module_css_default.body,
					children: [
						!state.writable ? /* @__PURE__ */ (0, react_jsx_runtime.jsx)("p", {
							className: _dsh_css_settings_card_module_css_default.readOnly,
							role: "status",
							children: props.t("settings.readOnly")
						}) : null,
						props.children,
						/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
							className: _dsh_css_settings_card_module_css_default.footer,
							children: [
								state.failed ? /* @__PURE__ */ (0, react_jsx_runtime.jsx)("p", {
									className: _dsh_css_settings_card_module_css_default.failed,
									role: "status",
									children: props.t("settings.saveFailed")
								}) : null,
								/* @__PURE__ */ (0, react_jsx_runtime.jsx)("button", {
									type: "button",
									className: _dsh_css_settings_card_module_css_default.discard,
									disabled: !state.dirty || state.saving,
									onClick: props.onDiscard,
									children: props.t("settings.discard")
								}),
								/* @__PURE__ */ (0, react_jsx_runtime.jsx)("button", {
									type: "button",
									className: _dsh_css_settings_card_module_css_default.save,
									disabled: blocked,
									onClick: props.onSave,
									children: props.t(!state.saving ? "settings.save" : "settings.saving")
								})
							]
						})
					]
				}) : null]
			});
		}
		/** A staged boolean field rendered as an accessible on/off switch. */
		function BooleanField(props) {
			const checked = props.text === "true";
			return /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
				className: _dsh_css_settings_card_module_css_default.field,
				children: [
					/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("div", {
						className: _dsh_css_settings_card_module_css_default.head,
						children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)("label", {
							className: _dsh_css_settings_card_module_css_default.label,
							htmlFor: props.id,
							children: props.label
						}), props.overridden ? /* @__PURE__ */ (0, react_jsx_runtime.jsxs)("span", {
							className: _dsh_css_settings_card_module_css_default.badges,
							children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
								className: _dsh_css_settings_card_module_css_default.badge,
								children: props.overriddenLabel
							}), /* @__PURE__ */ (0, react_jsx_runtime.jsx)("button", {
								type: "button",
								className: _dsh_css_settings_card_module_css_default.reset,
								disabled: props.disabled,
								onClick: props.onReset,
								children: props.resetLabel
							})]
						}) : null]
					}),
					/* @__PURE__ */ (0, react_jsx_runtime.jsxs)("button", {
						id: props.id,
						type: "button",
						className: _dsh_css_settings_card_module_css_default.switch,
						role: "switch",
						"aria-checked": checked,
						"aria-label": `${props.label}: ${checked ? props.onLabel : props.offLabel}`,
						disabled: props.disabled,
						onClick: () => {
							props.onEdit(checked ? "false" : "true");
						},
						children: [/* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
							className: checked ? _dsh_css_settings_card_module_css_default.switchTrackOn : _dsh_css_settings_card_module_css_default.switchTrack,
							"aria-hidden": "true",
							children: /* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", { className: checked ? _dsh_css_settings_card_module_css_default.switchThumbOn : _dsh_css_settings_card_module_css_default.switchThumb })
						}), /* @__PURE__ */ (0, react_jsx_runtime.jsx)("span", {
							className: _dsh_css_settings_card_module_css_default.switchState,
							children: checked ? props.onLabel : props.offLabel
						})]
					}),
					/* @__PURE__ */ (0, react_jsx_runtime.jsx)("p", {
						className: _dsh_css_settings_card_module_css_default.hint,
						children: props.hint
					})
				]
			});
		}
		//#endregion
		//#region src/client/settings-form.ts
		/** A boolean field, edited through true/false draft text. */
		function booleanField(field) {
			return {
				field,
				format: (value) => typeof value === "boolean" ? String(value) : "",
				parse: (text) => {
					if (text === "true") return {
						kind: "set",
						value: true
					};
					if (text === "false") return {
						kind: "set",
						value: false
					};
				}
			};
		}
		/**
		* Stages one card's edits over one settings namespace and writes them on save.
		*
		* The Host is the only authority on whether a value was accepted — its
		* validators own the constraints no schema can express — so the outcome is
		* read back from the section rather than predicted here. A save that did not
		* land keeps its drafts, so the user can correct them instead of retyping.
		*/
		var CardForm = class {
			scope;
			specs;
			staged = /* @__PURE__ */ new Map();
			listeners = /* @__PURE__ */ new Set();
			saving = false;
			failed = false;
			/** @param scope - the bound settings scope for this card's namespace. */
			constructor(scope, specs) {
				this.scope = scope;
				this.specs = new Map(specs.map((spec) => [spec.field, spec]));
				scope.subscribe(() => {
					this.publish();
				});
			}
			/** Publish a projection of this form, rebuilt whenever the scope or a draft changes. */
			bind(project) {
				const store = (0, _deepseek_ai_dsh_client_runtime_client.createSnapshotStore)(project());
				this.listeners.add(() => {
					store.set(project());
				});
				return store;
			}
			/** Read the card-level state: what the Host serves, and what a save would do. */
			shell() {
				const snapshot = this.scope.getSnapshot();
				const plan = this.plan();
				return {
					available: snapshot.status === "ready",
					writable: snapshot.writable,
					dirty: plan.length > 0,
					invalid: plan.some((item) => item.run === void 0),
					saving: this.saving,
					failed: this.failed
				};
			}
			/** Read one field's state from the effective section and its staged draft. */
			field(field) {
				const spec = this.specOf(field);
				const staged = this.staged.get(field);
				if (staged === void 0) return {
					text: spec.format(this.sectionValue(field)),
					overridden: this.stored(field),
					invalid: false
				};
				const write = staged.clear ? { kind: "clear" } : spec.parse(staged.text);
				return {
					text: staged.text,
					overridden: write?.kind === "set",
					invalid: write === void 0
				};
			}
			/** The actions the card's slot registration injects. */
			actions() {
				return {
					edit: (field, text) => {
						this.stage(field, {
							text,
							clear: false
						});
					},
					resetField: (field) => {
						this.stage(field, {
							text: this.specOf(field).format(this.baseValue(field)),
							clear: true
						});
					},
					save: () => {
						this.save();
					},
					discard: () => {
						if (this.staged.size === 0 && !this.failed) return;
						this.staged.clear();
						this.failed = false;
						this.publish();
					}
				};
			}
			/**
			* Write every staged edit, then re-seed from what the Host accepted.
			* @returns settlement after every write and the read-back.
			*/
			async save() {
				const plan = this.plan();
				const writes = plan.flatMap((item) => item.run === void 0 ? [] : [item.run]);
				if (plan.length === 0 || this.saving || writes.length !== plan.length) return;
				this.saving = true;
				this.failed = false;
				this.publish();
				let landed = true;
				for (const write of writes) landed = await write() && landed;
				if (landed) this.staged.clear();
				this.saving = false;
				this.failed = !landed;
				this.publish();
			}
			/**
			* Every staged edit a save would write. An entry whose draft is not a value
			* its field accepts carries no write: the form is still dirty, and the save
			* refuses rather than dropping the edit. A staged edit that matches the
			* effective section is not a write at all.
			* @returns the planned writes, in the order the fields were staged.
			*/
			plan() {
				const plan = [];
				for (const [field, staged] of this.staged) {
					const spec = this.specOf(field);
					if (staged.clear) {
						if (this.stored(field)) plan.push({
							field,
							run: () => this.clear(field)
						});
						continue;
					}
					if (staged.text === spec.format(this.sectionValue(field))) continue;
					const write = spec.parse(staged.text);
					if (write === void 0) plan.push({
						field,
						run: void 0
					});
					else if (write.kind === "clear") plan.push({
						field,
						run: () => this.clear(field)
					});
					else plan.push({
						field,
						run: () => this.store(field, write.value)
					});
				}
				return plan;
			}
			async clear(field) {
				await this.scope.unset(field);
				return !this.stored(field);
			}
			async store(field, value) {
				await this.scope.set(field, value);
				return this.userLayer()?.[field] === value;
			}
			stage(field, edit) {
				this.staged.set(field, edit);
				this.failed = false;
				this.publish();
			}
			specOf(field) {
				const spec = this.specs.get(field);
				if (spec === void 0) throw new Error(`settings card has no field ${field}`);
				return spec;
			}
			snapshotOf() {
				return this.scope.getSnapshot();
			}
			sectionValue(field) {
				return this.snapshotOf().value?.[field];
			}
			baseValue(field) {
				return this.snapshotOf().base?.[field];
			}
			userLayer() {
				return this.snapshotOf().user;
			}
			stored(field) {
				const user = this.userLayer();
				return user !== void 0 && Object.hasOwn(user, field);
			}
			publish() {
				for (const listener of this.listeners) listener();
			}
		};
		//#endregion
		//#region src/client/MoodBallSettingsCard.tsx
		/** Bridges the `moodball` scope onto the card's staged form. */
		var MoodBallSettingsCardController = class {
			form;
			store;
			/** @param scope - the bound settings scope for the `moodball` namespace. */
			constructor(scope) {
				this.form = new CardForm(scope, [booleanField("enabled")]);
				this.store = this.form.bind(() => this.projection());
			}
			projection() {
				return {
					...this.form.shell(),
					enabled: this.form.field("enabled")
				};
			}
			/**
			* Build the face the card's slot registration injects.
			* @returns the card's snapshot and its form actions.
			*/
			inject() {
				return {
					hooks: { moodBallSettingsCard: this.store },
					...this.form.actions()
				};
			}
		};
		/**
		* Render the MoodBall settings card.
		* @param props - locale copy, the card snapshot, and its form actions.
		* @returns the card.
		*/
		function MoodBallSettingsCard(props) {
			const { t } = props;
			const state = props.useMoodBallSettingsCard((snapshot) => snapshot);
			const disabled = !state.writable;
			const fieldProps = {
				overriddenLabel: t("settings.overridden"),
				resetLabel: t("settings.reset"),
				invalidLabel: t("settings.invalidNumber"),
				disabled
			};
			return /* @__PURE__ */ (0, react_jsx_runtime.jsx)(PluginSettingsCard, {
				t,
				titleKey: "settings.title",
				descriptionKey: "settings.description",
				state,
				onSave: props.save,
				onDiscard: props.discard,
				children: /* @__PURE__ */ (0, react_jsx_runtime.jsx)(BooleanField, {
					id: "settings-moodball-enabled",
					label: t("settings.enabled"),
					hint: t("settings.enabledHint"),
					inheritLabel: t("settings.inherit"),
					onLabel: t("settings.on"),
					offLabel: t("settings.off"),
					...fieldProps,
					...state.enabled,
					onEdit: (text) => {
						props.edit("enabled", text);
					},
					onReset: () => {
						props.resetField("enabled");
					}
				})
			});
		}
		//#endregion
		//#region src/client/locales.ts
		/**
		* dsh-moodball-status locale dictionaries (zh/en).
		* @module @linxin666/dsh-moodball-status/client/locales
		*/
		/** Dictionary namespace this package registers. */
		const NS = "moodball";
		/** Chinese copy. */
		const zh = {
			"settings.title": "心情球",
			"settings.description": "为 MoodBall 桌面 app 提供 agent 状态接口（/api/moodball/status）。桌面右下角的发光呼吸球随 Agent 状态变色。",
			"settings.enabled": "启用心情球",
			"settings.enabledHint": "关闭后移除状态接口，桌面球变为灰色「插件已关闭」；可在此重新启用。",
			"settings.inherit": "继承",
			"settings.on": "开",
			"settings.off": "关",
			"settings.overridden": "已覆盖",
			"settings.reset": "恢复默认",
			"settings.readOnly": "当前部署的设置只读。",
			"settings.expand": "展开设置",
			"settings.collapse": "收起设置",
			"settings.save": "保存",
			"settings.saving": "保存中…",
			"settings.discard": "放弃",
			"settings.unsaved": "未保存",
			"settings.saveFailed": "部署未接受这些值，已保留供你修改。",
			"settings.invalidNumber": "请输入数字，留空则使用默认值。"
		};
		/** English copy. */
		const en = {
			"settings.title": "MoodBall",
			"settings.description": "Serves the agent status API (/api/moodball/status) for the MoodBall desktop app — a glowing breathing ball that changes color with agent activity.",
			"settings.enabled": "Enable MoodBall",
			"settings.enabledHint": "When off, the status API is removed and the desktop ball turns gray (plugin off); re-enable it here.",
			"settings.inherit": "Inherit",
			"settings.on": "On",
			"settings.off": "Off",
			"settings.overridden": "Overridden",
			"settings.reset": "Reset to default",
			"settings.readOnly": "This deployment stores settings read-only.",
			"settings.expand": "Show settings",
			"settings.collapse": "Hide settings",
			"settings.save": "Save",
			"settings.saving": "Saving…",
			"settings.discard": "Discard",
			"settings.unsaved": "Unsaved",
			"settings.saveFailed": "The deployment did not accept these values; they were left for you to correct.",
			"settings.invalidNumber": "Enter a number, or leave blank to use the default."
		};
		//#endregion
		//#region src/client/index.ts
		/** Settings namespace the settings card edits (the host plugin registers it). */
		const MOODBALL_SETTINGS_NS = "moodball";
		/** Required services. */
		const inject = [
			"slots",
			"locale",
			"settingsScope"
		];
		/**
		* Client plugin body: register dictionaries and seat the settings card in the
		* settings plugin section.
		* @param ctx - client root context.
		*/
		function apply(ctx) {
			ctx.effect(() => ctx.locale.register(NS, {
				zh,
				en
			}), "moodball: dictionaries");
			const card = new MoodBallSettingsCardController(ctx.settingsScope.bind({ namespace: MOODBALL_SETTINGS_NS }));
			ctx.slots.inject("settings.plugin.item", () => ctx.slots.register({
				name: "settings.plugin.item",
				id: "moodball-settings",
				order: 150,
				locale: NS,
				inject: () => card.inject()
			}, MoodBallSettingsCard));
		}
		//#endregion
		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	}
});

//# sourceMappingURL=client.js.map