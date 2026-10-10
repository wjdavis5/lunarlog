// The generated article pages' title budget (issue #1811): the escaped
// title plus the layout's " - lunarlog" suffix must stay within
// html-validate's 70-character long-title rule, and a title that does not
// fit is cut at a word boundary with an ellipsis.
import assert from "node:assert/strict";
import test from "node:test";

import { escapeTitleText, pageTitleForArticle } from "../src/lib/article-titles.mjs";

test("a short title passes through unchanged", () => {
  assert.equal(pageTitleForArticle("Luteal phase and progesterone"), "Luteal phase and progesterone");
});

test("a title whose escaped form fits still passes through", () => {
  const title = "Understanding the follicular phase";
  assert.equal(pageTitleForArticle(title), title);
});

test("quotes and ampersands count against the budget", () => {
  // 51 source characters escape to 65 - past the 60-character budget - so
  // the title is cut even though its source length looked fine.
  const title = 'Cycle Length & Natural Variation: What Is "Normal"?';
  assert.equal(escapeTitleText(title).length, 65);
  const pageTitle = pageTitleForArticle(title);
  assert.ok(pageTitle.endsWith("\u2026"));
  assert.ok(escapeTitleText(pageTitle).length <= 60);
});

test("a title past the budget is cut at a word boundary with an ellipsis", () => {
  const title = "A very long article title that keeps going and going and going well past the budget";
  const pageTitle = pageTitleForArticle(title);
  assert.ok(pageTitle.endsWith("\u2026"));
  assert.ok(!pageTitle.includes("  "));
  assert.ok(escapeTitleText(pageTitle).length <= 60);
  assert.ok(title.startsWith(pageTitle.slice(0, -1).trimEnd()));
});

test("entities count against the budget", () => {
  const title = 'Quotes "everywhere" and & ampersands & more & more and more padding';
  assert.ok(escapeTitleText(pageTitleForArticle(title)).length <= 60);
});
