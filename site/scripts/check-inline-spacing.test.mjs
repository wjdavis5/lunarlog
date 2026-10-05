// Unit tests for the inline-spacing check. Plain `node --test` (`npm test`
// from site/): the finder is a pure function over a page's HTML.

import assert from "node:assert/strict";
import { test } from "node:test";

import {
  findGluedInlineElements,
  nonProseRanges,
} from "./check-inline-spacing.mjs";

test("a word directly before a link is found", () => {
  const found = findGluedInlineElements(
    '<p>each role, exactly — sees what<a href="/family-sharing">their role</a> allows.</p>',
  );
  assert.equal(found.length, 1);
  assert.match(found[0], /sees what<a href/);
});

test("clause punctuation directly before a link is found", () => {
  for (const before of ["Questions:", "the app.", "old enough,", "in? The)"]) {
    const found = findGluedInlineElements(
      `<p>${before}<a href="/support">Support</a>.</p>`,
    );
    assert.equal(found.length, 1, `expected a finding after "${before}"`);
  }
});

test("a word directly after a link is found", () => {
  const found = findGluedInlineElements(
    '<p>The <a href="/guides/inviting-someone/">inviting guide</a>picks the story up.</p>',
  );
  assert.equal(found.length, 1);
  assert.match(found[0], /<\/a>picks/);
});

test("the other inline text elements are covered too", () => {
  assert.equal(findGluedInlineElements("<p>very<strong>bold</strong> text</p>").length, 1);
  assert.equal(findGluedInlineElements("<p>an <em>aside</em>here</p>").length, 1);
  assert.equal(findGluedInlineElements("<p>run<code>npm ci</code> first</p>").length, 1);
});

test("correctly spaced prose passes", () => {
  const html = [
    '<p>sees what <a href="/family-sharing">their role</a> allows, and no more.</p>',
    // A line break and indentation are a space to the browser.
    '<p>sees what\n        <a href="/family-sharing">their role</a> allows.</p>',
    '<p>Read <a href="/privacy">the policy</a>. Then <strong>decide</strong>, <em>calmly</em>.</p>',
  ].join("\n");
  assert.deepEqual(findGluedInlineElements(html), []);
});

test("ordinary typography around a link is not a finding", () => {
  const html = [
    '<p>(<a href="/privacy">the policy</a>) and “<a href="/support">support</a>”.</p>',
    '<p>The policy — <a href="/privacy">in full</a> — says so; see <a href="/a">a</a>/<a href="/b">b</a>.</p>',
    '<li><a href="/tracking">Tracking</a></li><li><a href="/import">Import</a></li>',
    '<nav><a href="/">Home</a><span aria-hidden="true">·</span><a href="/support">Support</a></nav>',
  ].join("\n");
  assert.deepEqual(findGluedInlineElements(html), []);
});

test("tags that merely start with an inline tag's name are not matched", () => {
  // <article>, <aside>, <abbr>, <embed> and <address> begin with a/em.
  const html =
    "<p>text<abbr>x</abbr></p><div>text<article>y</article></div><p>word<embed></p>";
  assert.deepEqual(findGluedInlineElements(html), []);
});

test("comments, scripts, styles and code samples are not prose", () => {
  const html = [
    '<!-- cite: PRIVACY.md§6<a href="x">y</a> -->',
    '<script type="application/ld+json">{"x":"word<a href=\\"y\\">z</a>w"}</script>',
    "<style>.x::after{content:'w<a>'}</style>",
    '<pre><code>grep -o "what<a href" dist/index.html</code></pre>',
  ].join("\n");
  // One range per line, each covering its whole line.
  const lines = html.split("\n");
  const ranges = nonProseRanges(html);
  assert.equal(ranges.length, lines.length);
  let offset = 0;
  lines.forEach((line, i) => {
    assert.deepEqual(ranges[i], [offset, offset + line.length]);
    offset += line.length + 1;
  });
  assert.deepEqual(findGluedInlineElements(html), []);
});

test("prose right beside a skipped region is still checked", () => {
  const html =
    '<!-- note --><p>sees what<a href="/x">their role</a></p><pre>a<a>b</a>c</pre><p>and<em>this</em></p>';
  const found = findGluedInlineElements(html);
  assert.equal(found.length, 2);
  assert.match(found[0], /sees what<a href/);
  assert.match(found[1], /and<em>/);
});

test("findings come back in document order with context", () => {
  const found = findGluedInlineElements(
    '<p>first<a href="/a">a</a> and <a href="/b">b</a>second and third<a href="/c">c</a>.</p>',
  );
  assert.equal(found.length, 3);
  assert.match(found[0], /first<a/);
  assert.match(found[1], /<\/a>second/);
  assert.match(found[2], /third<a/);
});
