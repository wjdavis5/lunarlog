# Security Policy — lunarlog

`lunarlog` is a privacy-first, open-source, fully auditable family menstrual-cycle and symptom tracking application. We treat the security and confidentiality of reproductive health, family cycle records, and minor profile data with the highest priority.

This policy outlines how to report security vulnerabilities responsibly and what to expect in return.

---

## Supported Versions

Security updates are actively provided for the latest development state on the `main` branch and the latest official release:

| Version | Supported |
| --- | --- |
| Latest release / `main` branch | :white_check_mark: |
| Older releases | :x: |

---

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues, discussions, or pull requests.** Public disclosure before a fix is available puts users and their sensitive health data at risk.

If you have discovered a potential security vulnerability, privacy leak, or authorization flaw, please report it through one of the following channels:

### Option 1: GitHub Private Vulnerability Reporting (Recommended)

Submit an advisory draft directly via GitHub:
- Go to [Security Advisories](https://github.com/wjdavis5/lunarlog/security/advisories/new) on GitHub.
- Fill in the details of the vulnerability. This creates a confidential advisory draft visible only to maintainers and you.

### Option 2: Direct Email

If you cannot or prefer not to use GitHub's advisory system, email the project maintainer directly:
- **Contact:** William Davis (LunarLog Maintainer)
- **Email:** [will@wjdavis5.net](mailto:will@wjdavis5.net)
- **Subject line:** `[SECURITY] lunarlog vulnerability report`

---

## What to Include in Your Report

To help us investigate, reproduce, and resolve the issue quickly, please provide:

1. **Summary:** A clear and concise description of the vulnerability.
2. **Affected Components:** The part of the system affected (e.g., Flutter client, iOS/Android platform channels, Supabase database schema/migrations, Row-Level Security policies, Edge Functions).
3. **Impact Assessment:** The potential impact if exploited (e.g., unauthorized data access across accounts, cycle data leakage, bypass of biometric/device-credential app lock, unscrubbed crash report transmission).
4. **Steps to Reproduce:** Step-by-step reproduction instructions, a minimal proof-of-concept (PoC) script, or example payloads.
5. **Mitigation Suggestions:** Any suggested code fixes or configuration changes, if known.

---

## Our Security Response Commitment

- **Acknowledgment:** We aim to acknowledge your report within **48 hours**.
- **Triage & Assessment:** We will investigate, confirm or refute the finding, and evaluate its severity within **5 business days**.
- **Remediation:** If confirmed, we will develop and verify a fix in a private branch, ensuring all regression tests, coverage requirements (≥90%), and quality gates pass.
- **Coordinated Disclosure:** We adhere to responsible, coordinated disclosure. Once the fix is released, we will publish a security advisory. We will credit you in the advisory and release notes unless you prefer to remain anonymous.

---

## Scope

### In-Scope
- Vulnerabilities that permit unauthorized access to, modification of, or deletion of cycle, symptom, profile, or account data.
- Row-Level Security (RLS) or database RPC policy bypasses in Supabase PostgreSQL functions.
- Information disclosure or authorization bypasses in Supabase Edge Functions (`delete-account`, `feedback-notify`, `feedback-reply`, `push-dispatch`).
- Privacy scrubber regressions that cause sensitive cycle data, custom notes, dates, or user identities to leak into telemetry (e.g., Sentry) or notifications.
- Flaws in the local device-credential gate, biometric lock, or in-app PIN protections.
- File-protection or backup-exclusion misconfigurations that expose local databases or cache sidecars to unauthorized processes or cloud backups.

### Out-of-Scope
- Physical attacks requiring root or jailbreak access to an already-unlocked physical device.
- Attacks relying on social engineering, phishing, or physical coercion of maintainers.
- Distributed Denial-of-Service (DDoS) against third-party cloud infrastructure (e.g., Supabase, Apple, Google, Resend).
- Issues present only in unsupported or unconfigured development builds (e.g., builds running without required configuration defines).
- Theoretical issues or automated scanner outputs without a working proof-of-concept demonstrating practical exploitability.
