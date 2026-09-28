import type { APIRoute } from "astro";

// A plain `sitemap.xml` at the apex (issue #1099). Deliberately hand-rolled
// rather than `@astrojs/sitemap`, which emits `sitemap-index.xml` +
// `sitemap-0.xml`; the site has a fixed, tiny page list and the issue names
// `sitemap.xml` specifically. Add new pages here as they land (#1101,
// #1102, #1105's home + six feature pages, #1106).
const PAGES = [
  "/",
  "/privacy",
  "/delete-account",
  "/support",
  "/tracking",
  "/family-sharing",
  "/life-stage-modes",
  "/import",
  "/export",
  "/privacy-security",
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
