import { assertEquals, assertStringIncludes } from "jsr:@std/assert";
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

Deno.test("/invite: serves invite.html without redirect and preserves query string", async () => {
  const req = new Request("https://lunarlog.app/invite?code=secret123&profile=prof-abc&kind=guardian");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/html; charset=utf-8");
  assertEquals(res.headers.get("referrer-policy"), "no-referrer");
  assertEquals(res.headers.get("x-content-type-options"), "nosniff");
  const body = await res.text();
  assertStringIncludes(body, "You have a Lunarlog invitation");
  assertStringIncludes(body, "Open in Lunarlog");
});

Deno.test("/invite/*: serves invite.html for subpaths", async () => {
  const req = new Request("https://lunarlog.app/invite/claim?code=claim123");
  const res = await worker.fetch(req, {});
  assertEquals(res.status, 200);
  const body = await res.text();
  assertStringIncludes(body, "You have a Lunarlog invitation");
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
