import { assertEquals, assertNotMatch, assertStringIncludes } from "jsr:@std/assert";
import worker, { AASA_CONTENT, Fetcher } from "./index.ts";

Deno.test("AASA: serves /.well-known/apple-app-site-association with 200 and application/json", async () => {
  const req = new Request("https://lunarlog.app/.well-known/apple-app-site-association");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "application/json; charset=utf-8");
  assertEquals(res.headers.get("x-content-type-options"), "nosniff");
  const text = await res.text();
  assertEquals(text, AASA_CONTENT);

  const json = JSON.parse(text);
  assertEquals(json.applinks.details[0].appID, "5273C9R3V4.com.wjdavis5.lunarlog");
  assertEquals(json.applinks.details[0].paths, ["/invite*"]);
});

Deno.test("AASA: handles trailing slash and HEAD requests", async () => {
  const headReq = new Request("https://lunarlog.app/.well-known/apple-app-site-association", {
    method: "HEAD",
  });
  const headRes = await worker.fetch(headReq, {});
  assertEquals(headRes.status, 200);
  assertEquals(headRes.headers.get("content-type"), "application/json; charset=utf-8");
  const headBody = await headRes.text();
  assertEquals(headBody, "");

  const slashReq = new Request("https://lunarlog.app/.well-known/apple-app-site-association/");
  const slashRes = await worker.fetch(slashReq, {});
  assertEquals(slashRes.status, 200);
});

Deno.test("AASA: rejects POST with 405", async () => {
  const req = new Request("https://lunarlog.app/.well-known/apple-app-site-association", {
    method: "POST",
  });
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 405);
});

Deno.test("assetlinks: returns 404 while Android is deferred", async () => {
  const req = new Request("https://lunarlog.app/.well-known/assetlinks.json");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 404);
});

Deno.test("/fhir/*: reserved URIs are a plain 404, never a redirect", async () => {
  const req = new Request("https://lunarlog.app/fhir/CodeSystem/cycle-status");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 404);
  assertEquals(res.headers.get("location"), null);
  assertEquals(res.headers.get("x-content-type-options"), "nosniff");
});

Deno.test("/fhir/*: 404 wins over a matching asset lookup", async () => {
  const fakeAssets: Fetcher = {
    fetch: async () => new Response("should never be served", { status: 200 }),
  };
  const req = new Request("https://lunarlog.app/fhir/CodeSystem/cycle-status");
  const res = await worker.fetch(req, { ASSETS: fakeAssets });
  assertEquals(res.status, 404);
  assertEquals(res.headers.get("location"), null);
});

Deno.test("/invite: serves invite.html without redirect and preserves query string", async () => {
  const req = new Request("https://lunarlog.app/invite?code=secret123&profile=prof-abc&kind=guardian");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
  assertEquals(res.headers.get("referrer-policy"), "no-referrer");
  assertEquals(res.headers.get("x-content-type-options"), "nosniff");
  const body = await res.text();
  assertStringIncludes(body, "You have a lunarlog invitation");
  assertStringIncludes(body, "Open in lunarlog");
  // Issue #1279: the web-app redemption link (issue #1255) is withheld until
  // #1258 serves the React client at app.lunarlog.app — that origin is still
  // the Flutter web build, which rejects https invite links, so the button
  // silently dropped the code. Re-adding it means updating this pin,
  // site/scripts/invite-page.test.mjs, and
  // test/domain/sharing/link_artifacts_test.dart in the same change.
  assertNotMatch(body, /Open in the web app/);
  assertNotMatch(body, /app\.lunarlog\.app/);
});

Deno.test("/invite/*: serves invite.html for subpaths", async () => {
  const req = new Request("https://lunarlog.app/invite/claim?code=claim123");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 200);
  const body = await res.text();
  assertStringIncludes(body, "You have a lunarlog invitation");
});

Deno.test("/invite: rejects POST with 405", async () => {
  const req = new Request("https://lunarlog.app/invite?code=123", {
    method: "POST",
  });
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 405);
});

Deno.test("/invite: proxies to env.ASSETS when available", async () => {
  const fakeAssets: Fetcher = {
    fetch: async (r: Request | string) => {
      const url = typeof r === "string" ? r : r.url;
      if (url.includes("/invite.html")) {
        return new Response("<html><body>Custom Asset Invite</body></html>", {
          status: 200,
          headers: { "Content-Type": "text/html" },
        });
      }
      return new Response("Not found in assets", { status: 404 });
    },
  };

  const req = new Request("https://lunarlog.app/invite?code=testcode");
  const res = await worker.fetch(req, { ASSETS: fakeAssets });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
  assertEquals(res.headers.get("referrer-policy"), "no-referrer");
  const body = await res.text();
  assertEquals(body, "<html><body>Custom Asset Invite</body></html>");
});

// --- The invitation page's own security headers --------------------------
//
// `_headers` does not reach a response the Worker produces, so until this
// was added the invitation page -- the one page whose address carries a
// redeemable code -- was the one page on the site with no
// Content-Security-Policy, no frame protection and no HSTS. Cloudflare's
// proxy was injecting its Web Analytics script into it, and with nothing to
// refuse it, that third-party script ran there.

/** `'sha256-...'` of [text], the way a browser computes a CSP hash source. */
async function hashSource(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return `'sha256-${btoa(String.fromCharCode(...new Uint8Array(digest)))}'`;
}

/** The value of one directive of a Content-Security-Policy header. */
function directive(csp: string, name: string): string {
  for (const part of csp.split(";")) {
    const trimmed = part.trim();
    if (trimmed === name) return "";
    if (trimmed.startsWith(`${name} `)) return trimmed.slice(name.length + 1);
  }
  throw new Error(`no ${name} directive in: ${csp}`);
}

const assetInvite = "<!DOCTYPE html><html><head><style>\nbody { margin: 0; }\n</style></head>" +
  '<body><a id="open-in-app" href="lunarlog://invite">Open</a>' +
  "<script>\n(function () { var a = 1; })();\n</script></body></html>";

const inviteAssets: Fetcher = {
  fetch: async (r: Request | string) => {
    const url = typeof r === "string" ? r : r.url;
    if (url.includes("/invite.html")) {
      return new Response(assetInvite, { status: 200, headers: { "Content-Type": "text/html" } });
    }
    return new Response("Not found in assets", { status: 404 });
  },
};

for (
  const [name, env] of [
    ["the built page", { ASSETS: inviteAssets }],
    ["the fallback page", {}],
  ] as const
) {
  Deno.test(`/invite (${name}): only this page's own inline script and style may run`, async () => {
    const res = await worker.fetch(
      new Request("https://lunarlog.app/invite?code=secret123"),
      env,
    );
    assertEquals(res.status, 200);
    const csp = res.headers.get("content-security-policy") ?? "";
    const body = await res.text();

    // Nothing is allowed that the page does not carry itself.
    assertEquals(directive(csp, "default-src"), "'none'");
    assertEquals(directive(csp, "base-uri"), "'none'");
    assertEquals(directive(csp, "form-action"), "'none'");
    assertEquals(directive(csp, "frame-ancestors"), "'none'");

    // The page's one inline script and one inline style, by hash, and
    // nothing else: no host, no scheme, no 'unsafe-inline'. An injected
    // <script src="https://static.cloudflareinsights.com/..."> has no hash
    // here, so the browser refuses it.
    const script = /<script>([\s\S]*?)<\/script>/.exec(body)![1];
    const style = /<style>([\s\S]*?)<\/style>/.exec(body)![1];
    assertEquals(directive(csp, "script-src"), await hashSource(script));
    assertEquals(directive(csp, "style-src"), await hashSource(style));
    assertNotMatch(csp, /unsafe-inline|unsafe-eval|https?:|\*/);
  });

  Deno.test(`/invite (${name}): the headers the rest of the site carries, and no-transform`, async () => {
    for (const method of ["GET", "HEAD"]) {
      const res = await worker.fetch(
        new Request("https://lunarlog.app/invite?code=secret123", { method }),
        env,
      );
      assertEquals(res.status, 200);
      assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
      assertEquals(res.headers.get("referrer-policy"), "no-referrer");
      assertEquals(res.headers.get("x-content-type-options"), "nosniff");
      assertEquals(res.headers.get("x-frame-options"), "DENY");
      assertEquals(
        res.headers.get("strict-transport-security"),
        "max-age=63072000; includeSubDomains; preload",
      );
      assertStringIncludes(res.headers.get("permissions-policy") ?? "", "camera=()");
      // no-transform: Cloudflare's proxy may not rewrite the page, which is
      // how its analytics script got into it.
      assertEquals(res.headers.get("cache-control"), "public, max-age=300, no-transform");
      // HEAD carries the same policy as GET, hashes included, and no body.
      assertStringIncludes(res.headers.get("content-security-policy") ?? "", "script-src 'sha256-");
      if (method === "HEAD") assertEquals(await res.text(), "");
    }
  });
}

Deno.test("/invite: a HEAD for the built page still reads it, so its policy has the hashes", async () => {
  const methods: string[] = [];
  const recording: Fetcher = {
    fetch: async (r: Request | string) => {
      methods.push(typeof r === "string" ? "GET" : r.method);
      return new Response(assetInvite, { status: 200 });
    },
  };
  const head = await worker.fetch(
    new Request("https://lunarlog.app/invite?code=x", { method: "HEAD" }),
    { ASSETS: recording },
  );
  const get = await worker.fetch(
    new Request("https://lunarlog.app/invite?code=x"),
    { ASSETS: recording },
  );
  assertEquals(methods, ["GET", "GET"]);
  assertEquals(
    head.headers.get("content-security-policy"),
    get.headers.get("content-security-policy"),
  );
});

Deno.test("/invite: a page with no inline script or style gets 'none', not an empty directive", async () => {
  const bare: Fetcher = {
    fetch: async () => new Response("<html><body>Plain</body></html>", { status: 200 }),
  };
  const res = await worker.fetch(new Request("https://lunarlog.app/invite?code=x"), {
    ASSETS: bare,
  });
  const csp = res.headers.get("content-security-policy") ?? "";
  assertEquals(directive(csp, "script-src"), "'none'");
  assertEquals(directive(csp, "style-src"), "'none'");
});

Deno.test("/invite: a script tag with attributes is not one the policy admits", async () => {
  // What the proxy's injection looks like. The Worker never sees it (it is
  // added after the Worker answers), and if one were ever in the page the
  // Worker serves, it would get no hash: only the bare inline blocks do.
  const withInjected = assetInvite.replace(
    "</body>",
    '<script type="module" src="https://static.cloudflareinsights.com/beacon.min.js"></script></body>',
  );
  const assets: Fetcher = { fetch: async () => new Response(withInjected, { status: 200 }) };
  const res = await worker.fetch(new Request("https://lunarlog.app/invite?code=x"), {
    ASSETS: assets,
  });
  const csp = res.headers.get("content-security-policy") ?? "";
  const own = /<script>([\s\S]*?)<\/script>/.exec(assetInvite)![1];
  assertEquals(directive(csp, "script-src"), await hashSource(own));
  assertNotMatch(csp, /cloudflareinsights/);
});

Deno.test("unknown path returns 404 without ASSETS", async () => {
  const req = new Request("https://lunarlog.app/unknown");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 404);
});

Deno.test("unknown path proxies to env.ASSETS when available", async () => {
  const fakeAssets: Fetcher = {
    fetch: async (r: Request | string) => {
      const url = typeof r === "string" ? r : r.url;
      if (url.includes("/favicon.png")) {
        return new Response("fake-png-bytes", {
          status: 200,
          headers: { "Content-Type": "image/png" },
        });
      }
      return new Response("Not found", { status: 404 });
    },
  };

  const req = new Request("https://lunarlog.app/favicon.png");
  const res = await worker.fetch(req, { ASSETS: fakeAssets });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "image/png");
});
