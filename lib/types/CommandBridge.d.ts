import type { MoodBridgePayload } from './LocalStateBridge.js';
/** A detached workspace projection exposed to MoodBall.app. */
export interface MoodballWorkspace {
    id: string;
    title: string;
    path: string;
    status: 'ok' | 'missing-dir';
    sessionIds: readonly string[];
}
export interface CreateSessionCommand {
    workspaceId: string;
    sessionId: string;
}
export interface PromptCommand {
    workspaceId: string;
    sessionId: string;
    requestId: string;
    text: string;
}
export interface CommandHandlers {
    listWorkspaces: () => Promise<readonly MoodballWorkspace[]>;
    createSession: (request: CreateSessionCommand) => Promise<{
        sessionId: string;
    }>;
    prompt: (request: PromptCommand) => Promise<{
        accepted: true;
        sessionId: string;
    }>;
    snapshotFor: (sessionId: string) => MoodBridgePayload | undefined;
}
/**
 * User-local command and session-status transport.
 *
 * This socket is intentionally separate from LocalStateBridge. Older MoodBall
 * clients continue to receive the global read-only snapshot, while new
 * clients can issue authenticated-by-file-permission commands and subscribe
 * to one selected session without mixing command responses into that stream.
 */
export declare class CommandBridge {
    static defaultPath: string;
    private readonly socketPath;
    private readonly handlers;
    private server;
    private ownsSocket;
    private clients;
    constructor(handlers: CommandHandlers, socketPath?: string);
    start(): void;
    /** Push a replacement snapshot to clients subscribed to this session. */
    publish(sessionId: string, snapshot: MoodBridgePayload): void;
    stop(): void;
    private consume;
    private handle;
    private respond;
    private write;
}
