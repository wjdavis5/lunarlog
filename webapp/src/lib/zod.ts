// eslint-disable-next-line @typescript-eslint/no-restricted-imports -- this is the one module that may.
import { z } from 'zod';

/**
 * The one place the app takes zod's runtime from.
 *
 * zod 4 compiles object parsers with `new Function` when it can, and finds
 * out whether it can by trying. The app's CSP has no `unsafe-eval` and
 * requires Trusted Types for scripts, so the browser refuses that attempt.
 * zod catches the refusal and falls back, so parsing always worked — but the
 * browser logged "This document requires 'TrustedScript' assignment" on
 * every page load, in a client whose whole posture is a clean, strict CSP.
 *
 * `jitless` tells zod not to try. It is read when a schema is built, not
 * when it parses, so it must be set before the first `z.object(...)` runs.
 * That is why every schema module imports `z` from here: evaluating this
 * module first is then guaranteed by the import graph, not by the order of
 * imports in `main.tsx`. A lint rule bans importing zod's runtime anywhere
 * else in `src/` (`import type` is fine).
 */
z.config({ jitless: true });

export { z };
