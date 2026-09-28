import { satteri } from "@astrojs/markdown-satteri";
import { defineConfig } from "astro/config";

// https://astro.build/config
//
// The marketing site (issue #1099). `output: 'static'` builds plain files to
// `site/dist`, which the apex Worker's static-assets layer serves.
//
// No integrations and no `client:*` directives anywhere: the site ships zero
// client-side JavaScript by default (acceptance criterion 4 — loading any page
// must make no request to an origin other than lunarlog.app).
export default defineConfig({
  site: "https://lunarlog.app",
  output: "static",
  build: {
    // The CSP in `site/public/_headers` is `style-src 'self'` with no
    // `'unsafe-inline'`, so Astro must never inline a stylesheet into the
    // HTML. The default ('auto') inlines anything under 4 kB; 'never' always
    // emits an external `<link rel="stylesheet">`.
    inlineStylesheets: "never",
    // `format` stays Astro's default ('directory'): #1102's /support/ and
    // /delete-account/ pages (and their Lighthouse budgets) are built on it,
    // and `/privacy` resolves to the same page through the Worker's
    // auto-trailing-slash, whose target `/privacy/` is what the canonical
    // tag then correctly names (issue #1101).
  },
  markdown: {
    // Explicit (rather than the implicit default) so the rewrites below can
    // hook the same processor Astro would otherwise configure itself. GFM,
    // smart punctuation, syntax highlighting, heading ids, and image
    // handling keep their defaults — the processor appends those built-ins
    // after the user plugins.
    processor: satteri({
      hastPlugins: [rewriteRepoRelativeLinks, stripLeftAlignedTableStyles],
    }),
  },
  vite: {
    server: {
      fs: {
        // `src/pages/privacy.astro` (issue #1101) imports `PRIVACY.md` from
        // the repository root, one level above this Astro root. The build
        // resolves it regardless; this allowance keeps `astro dev` working
        // for the same import.
        allow: [".."],
      },
    },
  },
});

// Issue #1101: the canonical privacy policy (`PRIVACY.md`, repo root) is
// rendered at `/privacy` straight from the file — never a retyped copy. The
// document carries repo-relative links (e.g. `[SECURITY.md](SECURITY.md)`,
// the repo's security-policy convention), which on the site would resolve
// against lunarlog.app and 404 — and fail `npm run check:links`. Rewrite any
// markdown link without a scheme, a leading `/`, or a leading `#` to its
// absolute GitHub source URL. PRIVACY.md is the only imported markdown today,
// and the rewrite is a no-op for every absolute or in-page link, so this
// cannot surprise a future page's external links.
const REPO_BLOB_BASE = "https://github.com/wjdavis5/lunarlog/blob/main/";

function rewriteRepoRelativeLinks() {
  return {
    name: "rewrite-repo-relative-links",
    element: {
      filter: ["a"],
      visit(node, ctx) {
        const href = node.properties?.href;
        if (
          typeof href === "string" &&
          href !== "" &&
          !/^[a-z][a-z0-9+.-]*:/i.test(href) &&
          !href.startsWith("/") &&
          !href.startsWith("#")
        ) {
          ctx.setProperty(node, "href", REPO_BLOB_BASE + href);
        }
      },
    },
  };
}

// GFM table alignment (`| :--- |`) renders as an inline
// `style="text-align: left"` on every cell. The site CSP is `style-src
// 'self'` with no `'unsafe-inline'`, and `.htmlvalidate.json` errors on
// `no-inline-style`, so an inline style cannot ship; `text-align: left` is
// already the default in `src/pages/privacy.astro`'s table CSS, so drop
// exactly that declaration. Any other inline alignment (center/right) is
// left in place — it fails the html-validate step, which is the signal to
// give it a class-based home instead of weakening the CSP.
function stripLeftAlignedTableStyles() {
  return {
    name: "strip-left-aligned-table-styles",
    element: {
      filter: ["th", "td"],
      visit(node, ctx) {
        const style = node.properties?.style;
        if (typeof style === "string" && style.trim() === "text-align: left") {
          ctx.setProperty(node, "style", null);
        }
      },
    },
  };
}
