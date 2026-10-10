import { assertEquals, assertNotMatch, assertStringIncludes } from "jsr:@std/assert";
import worker, {
  AASA_CONTENT,
  Fetcher,
  INVITE_FALLBACK_HTML,
  INVITE_PERMISSIONS_POLICY,
} from "./index.ts";

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
  // Issue #1255: the web-app redemption link ships on the neutral page, now
  // that the React client at app.lunarlog.app serves /invite (the #1258
  // cutover; the twin pins live in site/scripts/invite-page.test.mjs and
  // test/domain/sharing/link_artifacts_test.dart).
  assertStringIncludes(body, "Open in the web app");
  assertStringIncludes(body, "app.lunarlog.app/invite");
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
// proxy was injecting its Web Analytics script tag into it, and nothing was
// there to refuse that third-party script.

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
    // Cut on the tags' positions, not with the Worker's own pattern, so
    // this is a second opinion on which text the hashes cover.
    const script = between(body, "<script>", "</script>");
    const style = between(body, "<style>", "</style>");
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
      assertEquals(res.headers.get("permissions-policy"), INVITE_PERMISSIONS_POLICY);
      assertStringIncludes(INVITE_PERMISSIONS_POLICY, "camera=()");
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
  const own = between(assetInvite, "<script>", "</script>");
  assertEquals(directive(csp, "script-src"), await hashSource(own));
  assertNotMatch(csp, /cloudflareinsights/);
});

/** The text between the first `open` and the next `close` in [html]. */
function between(html: string, open: string, close: string): string {
  const start = html.indexOf(open) + open.length;
  return html.slice(start, html.indexOf(close, start));
}

/** How many times [needle] occurs in [haystack]. */
function count(haystack: string, needle: string): number {
  return haystack.split(needle).length - 1;
}

Deno.test("/invite: the whole policy, directive for directive", async () => {
  // Pinned as one string, so an added directive (a `script-src-elem` that
  // loosens the one above it, say) cannot pass unnoticed. The two hashes
  // are worked out here by cutting the fallback page on its tags, not with
  // the Worker's own pattern.
  const res = await worker.fetch(new Request("https://lunarlog.app/invite?code=x"), {});
  const script = await hashSource(between(INVITE_FALLBACK_HTML, "<script>", "</script>"));
  const style = await hashSource(between(INVITE_FALLBACK_HTML, "<style>", "</style>"));
  assertEquals(
    res.headers.get("content-security-policy"),
    "default-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'; " +
      `script-src ${script}; style-src ${style}; upgrade-insecure-requests`,
  );
});

Deno.test("/invite: the fallback page has exactly one script and one style, counted on the raw text", () => {
  // The Worker finds the blocks with a pattern. A second mention of either
  // tag anywhere, a comment included, could make it hash the wrong span and
  // have the page's own block refused.
  // Counted without regard to case: `<SCRIPT>` is a script to a browser
  // and nothing to the Worker's pattern.
  for (const tag of ["<script", "</script", "<style", "</style"]) {
    assertEquals(count(INVITE_FALLBACK_HTML.toLowerCase(), tag), 1, tag);
  }
  assertStringIncludes(INVITE_FALLBACK_HTML, "<script>");
  assertStringIncludes(INVITE_FALLBACK_HTML, "<style>");
});

for (
  const [name, assets] of [
    ["answer with a redirect", {
      fetch: async () => new Response(null, { status: 307, headers: { Location: "/invite" } }),
    }],
    ["answer 404", { fetch: async () => new Response("Not found", { status: 404 }) }],
    ["throw", {
      fetch: async () => {
        throw new Error("assets unavailable");
      },
    }],
    ["fail while the page is being read", {
      fetch: async () =>
        new Response(
          new ReadableStream({
            start(controller) {
              controller.error(new Error("stream broke"));
            },
          }),
          { status: 200 },
        ),
    }],
  ] as [string, Fetcher][]
) {
  Deno.test(`/invite: when the assets ${name}, the fallback page is served with its own hashes`, async () => {
    const res = await worker.fetch(new Request("https://lunarlog.app/invite?code=x"), {
      ASSETS: assets,
    });
    assertEquals(res.status, 200);
    const csp = res.headers.get("content-security-policy") ?? "";
    assertEquals(await res.text(), INVITE_FALLBACK_HTML);
    assertEquals(
      directive(csp, "script-src"),
      await hashSource(between(INVITE_FALLBACK_HTML, "<script>", "</script>")),
    );
    assertEquals(
      directive(csp, "style-src"),
      await hashSource(between(INVITE_FALLBACK_HTML, "<style>", "</style>")),
    );
  });
}

Deno.test("/invite: the built page is asked for with redirects followed", async () => {
  // The asset layer answers `/invite.html` with a redirect to its own
  // address for the file. Left to `manual`, that redirect was all the
  // Worker saw, and the built page was never served.
  const modes: string[] = [];
  const recording: Fetcher = {
    fetch: async (r: Request | string) => {
      modes.push(typeof r === "string" ? "(string)" : r.redirect);
      return new Response(assetInvite, { status: 200 });
    },
  };
  await worker.fetch(new Request("https://lunarlog.app/invite?code=x", { redirect: "manual" }), {
    ASSETS: recording,
  });
  assertEquals(modes, ["follow"]);
});

Deno.test("/invite: a built page that arrives with CRLF is served, and hashed, with LF", async () => {
  // A browser turns CRLF into LF before it hashes an inline block. Hashing
  // the CRLF bytes would have the page's own script and style refused.
  const crlf: Fetcher = {
    fetch: async () => new Response(assetInvite.replaceAll("\n", "\r\n"), { status: 200 }),
  };
  const res = await worker.fetch(new Request("https://lunarlog.app/invite?code=x"), {
    ASSETS: crlf,
  });
  const csp = res.headers.get("content-security-policy") ?? "";
  const body = await res.text();
  assertEquals(body, assetInvite);
  assertEquals(
    directive(csp, "script-src"),
    await hashSource(between(assetInvite, "<script>", "</script>")),
  );
  assertEquals(
    directive(csp, "style-src"),
    await hashSource(between(assetInvite, "<style>", "</style>")),
  );
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
