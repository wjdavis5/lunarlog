// Whether the browser version is reachable at its public address.
//
// The site sends people to the browser version at app.lunarlog.app: the
// home page's main button, and links on three other pages. For a stretch in
// October 2026 that address answered a Cloudflare error page while the rest
// of the site carried on linking to it, so the one thing the home page
// asked a visitor to do led nowhere.
//
// The site is static and ships no script, so it cannot look at build time
// what a visitor will find later. What it can do is be told, when it is
// built for deploy, what the address answered a moment ago. The deploy
// workflow runs `scripts/probe-web-app.mjs` and passes the answer in as
// LUNARLOG_WEB_APP_LIVE; `site-deploy.yml` also rebuilds the site after
// every successful deploy of the browser version, so the button comes back
// on its own once the address does.
//
// Anything but the literal "false" means live. A local build, a pull
// request build, and a deploy whose probe could not reach the network at
// all render the site as it is meant to be.
//
// Plain `.mjs` with JSDoc types, like `ui-strings.mjs`: unit-tested by
// `node --test scripts/` with no transpiler.

/** The browser version's public address. */
export const WEB_APP_URL = "https://app.lunarlog.app";

/** The same address as people read it. */
export const WEB_APP_HOST = "app.lunarlog.app";

/** The build-time switch the deploy workflow sets from its probe. */
export const WEB_APP_LIVE_ENV = "LUNARLOG_WEB_APP_LIVE";

/**
 * Whether to link to the browser version.
 *
 * @param {Record<string, string | undefined>} [env]
 * @returns {boolean}
 */
export function webAppIsLive(env = process.env) {
  return env[WEB_APP_LIVE_ENV] !== "false";
}

/**
 * Whether an HTTP answer from the address is the browser version itself.
 *
 * A 200 alone is not enough: an error page, a parked page or another
 * project can answer 200 too. The browser version sends a Content Security
 * Policy with `require-trusted-types-for`, which nothing else on the
 * address ever has (the same test `webapp-deploy.yml` uses to decide
 * whether its cutover has happened).
 *
 * @param {{ status: number, contentSecurityPolicy: string | null }} answer
 * @returns {boolean}
 */
export function answerIsTheWebApp(answer) {
  return (
    answer.status === 200 &&
    typeof answer.contentSecurityPolicy === "string" &&
    answer.contentSecurityPolicy.includes("require-trusted-types-for")
  );
}
