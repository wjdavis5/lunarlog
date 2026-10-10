import type { APIRoute } from "astro";

import articles from "../content/literacy/articles.json";

// A plain `sitemap.xml` at the apex (issue #1099). Deliberately hand-rolled
// rather than `@astrojs/sitemap`, which emits `sitemap-index.xml` +
// `sitemap-0.xml`; the site has a fixed, tiny page list and the issue names
// `sitemap.xml` specifically. Add new pages here as they land (#1101,
// #1102, #1105's home + six feature pages, #1106's how-to guides).
const PAGES = [
  "/",
  "/privacy",
  "/delete-account",
  "/support",
  // Issue #1105's home + six feature pages.
  "/tracking",
  "/family-sharing",
  "/life-stage-modes",
  "/import",
  "/export",
  "/privacy-security",
  // The how-to guides (issue #1106).
  "/guides/",
  "/guides/getting-started",
  "/guides/household-setup",
  "/guides/inviting-someone",
  "/guides/transferring-ownership",
  "/guides/logging-a-day",
  "/guides/reading-estimates",
  "/guides/moving-your-data",
  "/guides/browser-version",
  // The cycle-literacy library (issue #1811).
  "/learn/",
  ...articles.map((article) => `/learn/${article.id}`),
];

export const GET: APIRoute = ({ site }) => {
  const base = site ?? new URL("https://lunarlog.app");
  const urls = PAGES.map(
    (path) => `  <url><loc>${new URL(path, base).href}</loc></url>`,
  ).join("\n");

  const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls}
</urlset>
`;

  return new Response(body, {
    headers: { "Content-Type": "application/xml; charset=utf-8" },
  });
};
