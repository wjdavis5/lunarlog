/**
 * lunarlog-links: Cloudflare Worker for the lunarlog.app apex (issue #450).
 *
 * Serves:
 * - `/.well-known/apple-app-site-association`: application/json, 200, no redirect
 * - `/invite*`: invite.html preserving query string without logging sensitive parameters
 * - `/fhir/*`: a reserved-URI 404, never a redirect (issue #961)
 * - Static assets from `env.ASSETS` for other routes (or the Astro 404 page)
 *
 * Since issue #1099 the static assets are the Astro build output (`site/dist`,
 * set in `wrangler.jsonc`), so `env.ASSETS` also serves the marketing pages,
 * robots.txt, the sitemap, and the brand images.
 *
 * `wrangler.jsonc` sets `assets.run_worker_first` to
 * `["/.well-known/*", "/invite*"]` (issue #1090). Without it the
 * static-asset layer answers those paths before this handler runs, and the
 * AASA goes out as `application/octet-stream` with none of the headers below.
 */

export interface Fetcher {
  fetch(request: Request | string, init?: RequestInit): Promise<Response>;
}

export interface Env {
  ASSETS?: Fetcher;
}

export const AASA_CONTENT = JSON.stringify(
  {
    applinks: {
      apps: [],
      details: [
        {
          appID: "5273C9R3V4.com.wjdavis5.lunarlog",
          paths: ["/invite*"],
        },
      ],
    },
  },
  null,
  2,
);

export const INVITE_FALLBACK_HTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<meta name="robots" content="noindex">
<title>Your lunarlog invitation</title>
<style>
  html { background: #f6f4fa; }
  body { margin: 0; padding: 2.5rem 1.25rem; font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; font-size: 1rem; line-height: 1.6; color: #1c1b22; }
  main { max-width: 30rem; margin: 0 auto; padding: 2rem 1.5rem; background: #ffffff; border: 1px solid #e4dff1; border-radius: 1rem; }
  .brand { margin: 0 0 1.5rem; font-family: Georgia, "Times New Roman", serif; font-size: 1.25rem; font-weight: 600; color: #37156c; }
  h1 { margin: 0 0 0.75rem; font-family: Georgia, "Times New Roman", serif; font-size: 1.75rem; line-height: 1.2; font-weight: 600; color: #37156c; }
  p { margin: 0 0 1rem; }
  ol { margin: 0 0 1.5rem; padding-left: 1.25rem; }
  li { margin-bottom: 0.25rem; }
  a { color: #00696f; }
  a:focus-visible { outline: 3px solid #00696f; outline-offset: 3px; border-radius: 0.25rem; }
  .open { display: inline-block; padding: 0.875rem 1.5rem; border-radius: 0.75rem; background: #37156c; color: #ffffff; font-weight: 600; text-decoration: none; }
  .open:hover { background: #2a1052; }
  .note { margin: 1.5rem 0 0; padding-top: 1rem; border-top: 1px solid #e4dff1; color: #55525f; font-size: 0.9375rem; }
</style>
</head>
<body>
<main>
<p class="brand">lunarlog</p>
<h1>You have a lunarlog invitation</h1>
<p>Someone invited you to connect on lunarlog, a private family cycle-tracking app. This device does not have the app installed (or it could not open the link directly), so the invitation is waiting for you inside the app instead.</p>
<ol>
<li>Install lunarlog on your device.</li>
<li>Open this same invitation link again on that device.</li>
<li>Sign in (or create an account) and follow the prompt to accept.</li>
</ol>
<p>If the app is already installed, tap below to open the invitation in it:</p>
<p><a id="open-in-app" class="open" href="lunarlog://invite" rel="noreferrer noopener">Open in lunarlog</a></p>
<!-- Issue #1279: the #1255 web-app button is withheld until #1258 puts the
     React client on the app subdomain; until then the button silently
     dropped the code. Keep this fallback in sync with
     docs/links/invite.html, whose comment carries the cutover steps. -->
<p class="note">Invitation links expire. If yours no longer works, ask the sender for a fresh one. New to lunarlog? <a href="/" rel="noreferrer noopener">See what it is and how it works.</a></p>
</main>
<script>
(function () {
  try {
    var params = new URLSearchParams(window.location.search);
    var code = params.get('code');
    if (!code) { return; }
    var query = 'code=' + encodeURIComponent(code);
    var profile = params.get('profile');
    var kind = params.get('kind');
    if (profile) { query += '&profile=' + encodeURIComponent(profile); }
    if (kind) { query += '&kind=' + encodeURIComponent(kind); }
    var openLink = document.getElementById('open-in-app');
    if (openLink) { openLink.setAttribute('href', 'lunarlog://invite?' + query); }
  } catch (e) {
  }
})();
</script>
</body>
</html>
`;

/**
 * The deny-by-default Permissions-Policy the rest of the site sends
 * (`site/public/_headers`). Kept identical to it.
 */
export const INVITE_PERMISSIONS_POLICY =
  "accelerometer=(), autoplay=(), camera=(), display-capture=(), encrypted-media=(), " +
  "fullscreen=(), geolocation=(), gyroscope=(), magnetometer=(), microphone=(), midi=(), " +
  "payment=(), picture-in-picture=(), publickey-credentials-get=(), screen-wake-lock=(), " +
  "sync-xhr=(), usb=(), xr-spatial-tracking=()";

/** The bodies of the bare inline `<tag>` blocks in [html]. */
function inlineBlocks(html: string, tag: "script" | "style"): string[] {
  const blocks: string[] = [];
  const pattern = new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, "g");
  for (const match of html.matchAll(pattern)) blocks.push(match[1]);
  return blocks;
}

/** `'sha256-...'` of one inline block, as a Content-Security-Policy source. */
async function hashSource(block: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(block));
  return `'sha256-${btoa(String.fromCharCode(...new Uint8Array(digest)))}'`;
}

/**
 * The Content-Security-Policy for an invitation page whose markup is [html].
 *
 * The page loads nothing: it has one inline style and one inline script and
 * no other resource. So the policy allows nothing, then admits exactly those
 * inline blocks by their hashes, taken from the markup being served so they
 * cannot go stale. Anything added to the page after the Worker has answered
 * has no hash here and the browser refuses it.
 *
 * That matters because something does get added. Cloudflare's proxy injects
 * its Web Analytics script into HTML it serves for the zone. The site's
 * pages refuse it through `_headers`; this page is produced by the Worker,
 * which `_headers` does not reach, and until this policy existed the script
 * ran on the one page whose address carries a redeemable code.
 */
export async function inviteContentSecurityPolicy(html: string): Promise<string> {
  const scripts = await Promise.all(inlineBlocks(html, "script").map(hashSource));
  const styles = await Promise.all(inlineBlocks(html, "style").map(hashSource));
  return [
    "default-src 'none'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
    `script-src ${scripts.join(" ") || "'none'"}`,
    `style-src ${styles.join(" ") || "'none'"}`,
    "upgrade-insecure-requests",
  ].join("; ");
}

/**
 * The invitation page, with the headers `_headers` gives every other page
 * of the site and its own policy ([inviteContentSecurityPolicy]).
 *
 * `no-transform` tells the proxy not to rewrite the page at all, which is
 * how the analytics script reached it; the policy is what holds if that is
 * ever ignored. HEAD gets the same headers and no body.
 */
async function inviteResponse(html: string, method: string): Promise<Response> {
  return new Response(method === "HEAD" ? null : html, {
    status: 200,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300, no-transform",
      "Content-Security-Policy": await inviteContentSecurityPolicy(html),
      "Permissions-Policy": INVITE_PERMISSIONS_POLICY,
      "Referrer-Policy": "no-referrer",
      "Strict-Transport-Security": "max-age=63072000; includeSubDomains; preload",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    },
  });
}

/**
 * The built `invite.html`, or null when the assets cannot supply it. Always
 * read with GET, whatever the visitor's method: a HEAD needs the markup too,
 * for the hashes in its policy.
 */
async function builtInvitePage(assets: Fetcher, request: Request): Promise<string | null> {
  const url = new URL("/invite.html", request.url);
  const response = await assets.fetch(new Request(url.toString(), { method: "GET" }));
  return response.status === 200 ? await response.text() : null;
}

export function handleRequest(request: Request, env: Env): Promise<Response> | Response {
  const url = new URL(request.url);
  const pathname = url.pathname;

  // 1. Apple App Site Association
  // Must be served as application/json, 200, no redirect, no extension.
  if (
    pathname === "/.well-known/apple-app-site-association" ||
    pathname === "/.well-known/apple-app-site-association/"
  ) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405 });
    }
    return new Response(request.method === "HEAD" ? null : AASA_CONTENT, {
      status: 200,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Cache-Control": "public, max-age=3600",
        "X-Content-Type-Options": "nosniff",
      },
    });
  }

  // 2. Android Digital Asset Links
  // Android is deferred (issue #450) - do not publish assetlinks.json with placeholder fingerprints.
  if (pathname === "/.well-known/assetlinks.json") {
    return new Response("Not Found", {
      status: 404,
      headers: { "Content-Type": "text/plain; charset=utf-8" },
    });
  }

  // 3. Reserved FHIR URIs (issue #961): exported Bundles already carry
  //    `https://lunarlog.app/fhir/CodeSystem/...`, so those URIs are frozen.
  //    Serve a plain 404 and never a redirect.
  if (pathname === "/fhir" || pathname.startsWith("/fhir/")) {
    return new Response("Not Found", {
      status: 404,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "X-Content-Type-Options": "nosniff",
      },
    });
  }

  // 4. /invite* -> invite.html preserving query string without logging sensitive parameters
  if (pathname === "/invite" || pathname.startsWith("/invite/")) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    // The built page when the assets have it, the inline fallback otherwise.
    // Either way the Worker writes the headers: `_headers` does not reach a
    // response the Worker produces.
    const built = env.ASSETS ? builtInvitePage(env.ASSETS, request) : Promise.resolve(null);
    return built.then((html) => inviteResponse(html ?? INVITE_FALLBACK_HTML, request.method));
  }

  // 5. Default / fall-through to static assets or 404
  if (env.ASSETS) {
    return env.ASSETS.fetch(request);
  }

  return new Response("Not Found", {
    status: 404,
    headers: { "Content-Type": "text/plain; charset=utf-8" },
  });
}

export default {
  fetch(request: Request, env: Env): Promise<Response> | Response {
    return handleRequest(request, env);
  },
};
