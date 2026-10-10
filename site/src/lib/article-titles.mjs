// The page-title budget for generated article pages (issue #1811).
//
// html-validate's long-title rule counts the `<title>` text as written -
// entities included - and BaseLayout appends " - lunarlog" (10 characters).
// An article title containing quotes or an ampersand escapes to more
// characters than its source length, so the budget is applied to the
// escaped form: escaped title + suffix must stay at or under 70. A title
// that does not fit is cut at a word boundary and marked with an ellipsis,
// which the reader still recognises in a tab.

/** Escapes a title the way Astro writes it into `<title>`. */
export function escapeTitleText(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

/**
 * [title], unchanged when it fits the 60-character escaped budget, else cut
 * at the last word boundary that fits 59 and marked with an ellipsis.
 */
export function pageTitleForArticle(title) {
  const budget = 60;
  if (escapeTitleText(title).length <= budget) return title;
  let cut = title;
  while (cut.length > 0 && escapeTitleText(cut).length > budget - 1) {
    cut = cut.slice(0, -1);
  }
  const lastSpace = cut.lastIndexOf(" ");
  if (lastSpace > 0) cut = cut.slice(0, lastSpace);
  return `${cut.trimEnd()}\u2026`;
}
