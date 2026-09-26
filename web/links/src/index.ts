/**
 * lunarlog-links: Cloudflare Worker for hosting universal-link files on lunarlog.app.
 * Issue #450.
 *
 * Serves:
 * - `/.well-known/apple-app-site-association`: application/json, 200, no redirect
 * - `/invite*`: invite.html preserving query string without logging sensitive parameters
 * - Static assets from `env.ASSETS` for other routes (or 404)
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
<title>Lunarlog invitation</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; margin: 0; padding: 2rem 1.25rem; color: #222; background: #fff; }
  main { max-width: 32rem; margin: 0 auto; }
  h1 { font-size: 1.4rem; }
  p { line-height: 1.5; }
  ol { line-height: 1.7; padding-left: 1.25rem; }
  .open { display: inline-block; margin-top: 1rem; padding: 0.75rem 1.5rem; background: #4a6fa5; color: #fff; text-decoration: none; border-radius: 0.5rem; }
</style>
</head>
<body>
<main>
<h1>You have a Lunarlog invitation</h1>
<p>Someone invited you to connect on Lunarlog, a private family cycle-tracking app. This device does not have the app installed (or it could not open the link directly), so the invitation is waiting for you inside the app instead.</p>
<ol>
<li>Install Lunarlog on your device.</li>
<li>Open this same invitation link again on that device.</li>
<li>Sign in (or create an account) and follow the prompt to accept.</li>
</ol>
<p>If the app is already installed, tap below to open the invitation in it:</p>
<p><a id="open-in-app" class="open" href="lunarlog://invite" rel="noreferrer noopener">Open in Lunarlog</a></p>
<p>Invitation links expire. If yours no longer works, ask the sender for a fresh one.</p>
</main>
<script>
(function () {
  try {
    var params = new URLSearchParams(window.location.search);
    var code = params.get('code');
    if (!code) { return; }
    var target = 'lunarlog://invite?code=' + encodeURIComponent(code);
    var profile = params.get('profile');
    var kind = params.get('kind');
    if (profile) { target += '&profile=' + encodeURIComponent(profile); }
    if (kind) { target += '&kind=' + encodeURIComponent(kind); }
    var openLink = document.getElementById('open-in-app');
    if (openLink) { openLink.setAttribute('href', target); }
  } catch (e) {
  }
})();
</script>
</body>
</html>
`;

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

  // 3. /invite* -> invite.html preserving query string without logging sensitive parameters
  if (pathname === "/invite" || pathname.startsWith("/invite/")) {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    if (env.ASSETS) {
      const inviteAssetUrl = new URL("/invite.html", request.url);
      return env.ASSETS.fetch(new Request(inviteAssetUrl.toString(), request)).then(
        (assetRes) => {
          if (assetRes.status === 200) {
            const headers = new Headers(assetRes.headers);
            headers.set("Content-Type", "text/html; charset=utf-8");
            headers.set("Referrer-Policy", "no-referrer");
            headers.set("X-Content-Type-Options", "nosniff");
            headers.set("Cache-Control", "public, max-age=300");
            return new Response(request.method === "HEAD" ? null : assetRes.body, {
              status: 200,
              headers,
            });
          }
          // Fallback if asset fetch wasn't 200
          return new Response(request.method === "HEAD" ? null : INVITE_FALLBACK_HTML, {
            status: 200,
            headers: {
              "Content-Type": "text/html; charset=utf-8",
              "Referrer-Policy": "no-referrer",
              "X-Content-Type-Options": "nosniff",
              "Cache-Control": "public, max-age=300",
            },
          });
        },
      );
    }

    return new Response(request.method === "HEAD" ? null : INVITE_FALLBACK_HTML, {
      status: 200,
      headers: {
        "Content-Type": "text/html; charset=utf-8",
        "Referrer-Policy": "no-referrer",
        "X-Content-Type-Options": "nosniff",
        "Cache-Control": "public, max-age=300",
      },
    });
  }

  // 4. Default / fall-through to static assets or 404
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
