// Type surface of scripts/generate.mjs for the freshness tests (the runtime
// file stays plain ESM — it runs under plain `node`).
export function buildMessageCatalogue(arbJson?: unknown): Record<string, string>;
export function serializeMessageCatalogue(catalogue: Record<string, string>): string;
export function buildMessageIdsModule(catalogue: Record<string, string>): string;
export function buildTokensCss(tokens: unknown): string;
export function loadTokens(tokensJson?: unknown): Record<string, unknown>;
export const webappRoot: string;
export const repoRoot: string;
export const arbPath: string;
export const messagesOutPath: string;
export const messageIdsOutPath: string;
export const tokensJsonPath: string;
export const tokensCssOutPath: string;
