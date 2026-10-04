/**
 * Punctuation between two catalogue fragments (issue #1253). These are not
 * translatable copy — the no-typed-copy ESLint ban (and its intent) covers
 * words, not the joining punctuation between two `t()` outputs — but they
 * must still reach JSX as expressions, never JSXText, so they live here as
 * named constants and render through `{SEPARATOR}`.
 */

/** Separator between two peer fragments (Today · Guardians). */
export const DOT_SEPARATOR = ' · ';

/** Sentence dash between two catalogue fragments. */
export const DASH_SEPARATOR = ' — ';

/** En dash between two formatted dates (a range). */
export const RANGE_SEPARATOR = ' – ';

/** Label colon inside a composed value ("Length: 28"). */
export const LABEL_COLON = ': ';
