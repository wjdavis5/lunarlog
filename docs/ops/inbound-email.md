# Inbound Email Processing Worker — Runbook

This document covers the configuration, architecture, and query interfaces for the Cloudflare Inbound Email Worker (`web/email/`).

---

## 1. Overview & Purpose

Testing transactional emails (Supabase auth verification, magic links, confirm sign-up tokens, and 8-digit OTPs from `noreply@lunarlog.app`) and receiving inbound support/ticket responses historically required manual human interaction with third-party webmail accounts.

The `lunarlog-inbound-email` worker accepts incoming emails sent to `lunarlog.app` (such as `*@inbound.lunarlog.app` or `auth-test@lunarlog.app`) via Cloudflare Email Routing, parses the MIME payload, extracts authentication tokens, and stores them in Cloudflare KV with a 24-hour expiration TTL. An authenticated REST API enables CI pipelines, integration test suites, and agents to query received emails programmatically.

---

## 2. Cloudflare Dashboard Prerequisites (Operator)

### A. KV Namespace Creation
1. In the Cloudflare Dashboard, go to **Workers & Pages → KV → Create a namespace**.
2. Name the namespace `lunarlog-inbound-emails`.
3. Copy the generated `id` and replace the placeholder in `web/email/wrangler.jsonc`:
   ```jsonc
   "kv_namespaces": [
     {
       "binding": "INBOUND_EMAILS",
       "id": "<KV_NAMESPACE_ID>",
       "preview_id": "<PREVIEW_KV_NAMESPACE_ID>"
     }
   ]
   ```

### B. Environment Secrets
Set the following secrets in Cloudflare Workers (or via `wrangler secret put`):
* `EMAIL_API_KEY`: Shared secret key used to authenticate API queries from CI/tests (passed as `Authorization: Bearer <key>` or `X-API-Key: <key>`).
* *(Optional)* `INBOUND_WEBHOOK_URL`: HTTP endpoint to receive a POST webhook when an email arrives.
* *(Optional)* `INBOUND_WEBHOOK_SECRET`: Bearer secret passed in the webhook `Authorization` header.

### C. Cloudflare Email Routing Configuration
1. Open the `lunarlog.app` zone in Cloudflare.
2. Navigate to **Email Routing**.
3. Enable Email Routing (Cloudflare will automatically prompt to add the necessary MX and TXT verification records to DNS).
4. Under **Routing Rules**, create a rule:
   * **Rule type:** Catch-all or Custom Address (e.g. `*@inbound.lunarlog.app` or `auth-test@lunarlog.app`).
   * **Action:** `Send to a Worker`.
   * **Destination:** `lunarlog-inbound-email`.
5. Save the rule. Inbound emails to that address will now be routed directly to the worker's `email(message, env, ctx)` handler.

---

## 3. Query & Retrieval REST API

The worker exposes an authenticated REST API at `https://email.lunarlog.app` (or the deployed worker domain).

### `GET /health`
* **Auth:** Unauthenticated.
* **Response:** `200 OK`
  ```json
  {
    "status": "ok",
    "service": "lunarlog-inbound-email",
    "timestamp": "2026-09-26T12:00:00.000Z"
  }
  ```

### `GET /api/emails/latest?recipient=<email>`
Retrieves the most recent email for the given recipient.
* **Auth:** `Authorization: Bearer <EMAIL_API_KEY>` or `X-API-Key: <EMAIL_API_KEY>`
* **Response:** `200 OK`
  ```json
  {
    "email": {
      "id": "msg-guid-12345",
      "from": "noreply@lunarlog.app",
      "to": "test-user@inbound.lunarlog.app",
      "subject": "Confirm your signup",
      "receivedAt": "2026-09-26T12:00:00.000Z",
      "otpCode": "84920183",
      "authLinks": [
        "https://dleexnnevuuddcgcpztq.supabase.co/auth/v1/verify?token=pkce_abc&type=signup"
      ],
      "text": "Your confirmation code is 84920183. Never share this code.",
      "html": "<p>Your confirmation code is <b>84920183</b>.</p>"
    }
  }
  ```

### `GET /api/emails?recipient=<email>&limit=<n>`
Lists up to `limit` emails (default 10, max 50) for the given recipient, ordered newest first.
* **Auth:** `Authorization: Bearer <EMAIL_API_KEY>`
* **Response:** `200 OK`
  ```json
  {
    "emails": [ ... ]
  }
  ```

### `GET /api/emails/:id`
Retrieves a single email by its message ID.
* **Auth:** `Authorization: Bearer <EMAIL_API_KEY>`
* **Response:** `200 OK` or `404 Not Found`

### `DELETE /api/emails/:id`
Deletes an email and purges it from recipient indices ahead of the 24-hour TTL expiration.
* **Auth:** `Authorization: Bearer <EMAIL_API_KEY>`
* **Response:** `200 OK`

### `POST /api/emails/simulate`
Simulation endpoint for testing the parsing and storage pipeline without sending real SMTP traffic.
* **Auth:** `Authorization: Bearer <EMAIL_API_KEY>`
* **Request:** JSON payload:
  ```json
  {
    "from": "noreply@lunarlog.app",
    "to": "sim@inbound.lunarlog.app",
    "subject": "Sign in code",
    "text": "Your code is 12345678."
  }
  ```
* **Response:** `201 Created`

---

## 4. Usage in Automated Tests

Automated scripts and test runners can fetch verification codes without polling third-party email providers:

```bash
# Fetch the 8-digit OTP code sent to a test recipient
OTP_CODE=$(curl -s \
  -H "Authorization: Bearer $EMAIL_API_KEY" \
  "https://email.lunarlog.app/api/emails/latest?recipient=test-123@inbound.lunarlog.app" \
  | jq -r '.email.otpCode')

echo "Received OTP: $OTP_CODE"
```

---

## 5. Development & Testing

Run tests and type checks locally via Deno:

```bash
# Type check TypeScript sources
deno check web/email/src/**/*.ts

# Run unit tests
deno test web/email/src/index.test.ts
```
