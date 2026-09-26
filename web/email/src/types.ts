/**
 * Types and interfaces for the lunarlog inbound email worker.
 */

export interface KVListKey {
  name: string;
  expiration?: number;
  metadata?: unknown;
}

export interface KVListResult {
  keys: KVListKey[];
  list_complete: boolean;
  cursor?: string;
}

export interface KVNamespace {
  get(key: string, options?: { type?: "text" }): Promise<string | null>;
  get<T = unknown>(key: string, options: { type: "json" }): Promise<T | null>;
  get(key: string, options?: { type?: string }): Promise<unknown>;
  put(
    key: string,
    value: string | ArrayBuffer | ArrayBufferView | ReadableStream,
    options?: { expiration?: number; expirationTtl?: number; metadata?: unknown },
  ): Promise<void>;
  delete(key: string): Promise<void>;
  list(options?: { prefix?: string; limit?: number; cursor?: string }): Promise<KVListResult>;
}

export interface ForwardableEmailMessage {
  readonly from: string;
  readonly to: string;
  readonly headers: Headers;
  readonly raw: ReadableStream<Uint8Array>;
  readonly rawSize: number;
  setReject(reason: string): void;
  forward(rcptTo: string, headers?: Headers): Promise<void>;
  reply(message: unknown): Promise<void>;
}

export interface ExecutionContext {
  waitUntil(promise: Promise<unknown>): void;
  passThroughOnException(): void;
}

export interface Env {
  INBOUND_EMAILS?: KVNamespace;
  EMAIL_API_KEY?: string;
  INBOUND_WEBHOOK_URL?: string;
  INBOUND_WEBHOOK_SECRET?: string;
}

export interface ParsedEmailData {
  id: string;
  from: string;
  to: string;
  subject: string;
  receivedAt: string;
  text?: string;
  html?: string;
  otpCode?: string;
  authLinks: string[];
  headers?: Record<string, string>;
}
