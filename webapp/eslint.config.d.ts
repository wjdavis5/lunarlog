// Type surface of eslint.config.js, for the lint-ban tests that import the
// ban tables (the runtime file stays plain JS — it is ESLint's own config).
export const STORAGE_BANS: {
  name?: string;
  object?: string;
  property?: string;
  message: string;
}[];
export const COPY_BANS: { selector: string; message: string }[];
export const STORAGE_SYNTAX_BANS: { selector: string; message: string }[];
