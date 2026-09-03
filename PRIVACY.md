# LunarLog Privacy Policy

**Effective Date:** September 3, 2026  
**Last Updated:** September 3, 2026  

LunarLog ("we", "our", or "the app") is a privacy-first, local-first menstrual cycle and symptom tracker designed for individuals and families. We believe that reproductive and menstrual health data is deeply personal and sensitive. LunarLog is architected from the ground up to protect your privacy: your device is the primary source of truth, data is encrypted, and cloud synchronization is strictly optional.

This Privacy Policy explains what information LunarLog processes, how that information is protected, and the choices and rights you have.

---

## 1. Core Principles

- **Local-First & Offline:** LunarLog operates entirely offline without requiring an account. All cycle tracking, notes, symptoms, and profiles function without an internet connection.
- **Encrypted at Rest:** All data stored on your device is encrypted at rest using SQLCipher (AES-256) behind device-level biometric or passcode authentication.
- **No Advertising or Data Brokers:** We do not display advertisements, sell your data, monetize your health information, or share data with data brokers or tracking networks.
- **No Fertility Tracking or Algorithms:** By design, LunarLog does not contain ovulation prediction, fertility forecasting, conception algorithms, or pregnancy-related data sharing.
- **Minimal, Scrubbed Telemetry:** Crash and diagnostic reports are strictly scrubbed on your device before transmission to ensure no health data, personal notes, dates, or user identities ever leave your device.

---

## 2. Information We Collect and Process

### A. Health & Cycle Information (Local & Optional Cloud Sync)
When you log entries in LunarLog, you may record:
- Dates and timestamps of menstrual cycles.
- Flow intensity levels (spotting, light, medium, heavy).
- Personal tags and custom notes.
- Profile information (display name, sort order, archive status, minor status flag).

**Storage:** This information is stored directly on your device in an encrypted SQLite database. It is never uploaded to any remote server unless you explicitly create an optional account and choose to enable cloud sync.

### B. Account & Authentication Information (Optional)
Creating an account is entirely optional. If you choose to enable cross-device sync, we process:
- **Email Address:** Used for account verification, passwordless sign-in links, and password recovery.
- **Authentication Credentials:** Handled securely via Supabase Auth. We support email/password, passwordless magic links, Sign in with Apple, and Google Sign-In.
- **Provider Identifiers:** If you authenticate via Apple or Google, we store a cryptographic subject identifier (`sub`) provided by the identity provider to link your account. We do not access your contacts, external profile files, or social graphs.

**Upload Consent:** When you sign in on a device that already holds local data, LunarLog asks for your explicit consent before uploading existing records to your account.

### C. Technical & Crash Information (Diagnostics)
To maintain app stability and diagnose crashes, LunarLog includes optional telemetry powered by Sentry. 
- **Strict Privacy Floor:** Before any error or crash report leaves your device, an automated client-side scrubber (`lib/observability/scrub.dart`) removes all health information, dates, flow levels, notes, tags, profile names, user IDs, device names, auth tokens, and request payloads.
- Crash data is anonymous, not linked to your identity or health records, and used solely for bug fixes and app performance.

---

## 3. How We Use Your Information

We use the information we process strictly for the following purposes:
1. **Core App Functionality:** Enabling you to log, view, and organize cycle records across profiles.
2. **Cross-Device Synchronization (Optional):** Mirroring your encrypted records across your authorized devices using row-level-secured cloud storage.
3. **App Reliability & Security:** Diagnosing technical faults and preventing unauthorized access through biometric locks and automated inactivity relocking.

We **do not** use your information for targeted advertising, marketing communications, automated profiling, or behavioral tracking.

---

## 4. Third-Party Service Providers

LunarLog limits third-party integration to essential operational infrastructure:

| Service | Purpose | Data Received | Location / Security |
| :--- | :--- | :--- | :--- |
| **Supabase** | Cloud authentication and database sync (optional) | Account email, encrypted cycle entries, authentication tokens | Encrypted in transit (TLS 1.3) and at rest (AES-256); Row-Level Security enforced |
| **Sentry** | Crash reporting and error diagnostics | Anonymized stack traces, OS version, device architecture (all health/identity data stripped) | Client-side scrubbed; retained for a maximum of 90 days for debugging |
| **Apple (Sign in with Apple)** | Optional identity provider on iOS/macOS | Apple user identifier, relay email address (if selected) | Governed by Apple Privacy Policy |
| **Google (Google Sign-In)** | Optional identity provider | Google ID token (email and basic account identifier) | Governed by Google Privacy Policy |

No other third parties receive data from LunarLog.

---

## 5. Minors' Privacy & Family Profiles

LunarLog is intended to be operated by a parent, legal guardian, or adult individual. 
- **Custodian Model:** The app supports creating and managing profiles for family members, including minors (`is_minor` flag). An adult operator remains the sole custodian of the device, authentication credentials, and synchronization settings.
- **No Direct Marketing or Tracking:** We do not knowingly collect personal data directly from children under 13 (or under 16 in certain jurisdictions) without parental consent. Minor profiles receive the same end-to-end encryption and protections as adult profiles and are never shared or analyzed.

---

## 6. Security Protections

We implement rigorous technical safeguards to ensure the security and confidentiality of your data:
- **Device Encryption:** SQLite database encrypted using SQLCipher with AES-256 encryption.
- **Biometric Security:** Biometric authentication (Face ID / Touch ID / Android Biometrics) required to unlock the app.
- **Inactivity Timeout:** Configurable automatic relocking after inactivity, plus immediate locking upon backgrounding. The one exception is while a sign-in or unlock prompt the app itself opened is on screen: the system reports those the same way it reports you leaving, so locking is deferred for their duration. The app's contents stay masked throughout, the app relocks as soon as the prompt closes if you have left, and a prompt left open relocks the app after two minutes regardless of the inactivity setting.
- **Screen Obfuscation:** App switcher and lock screen previews are masked to prevent unauthorized viewing.
- **Transport Security:** All network transmissions use HTTPS with modern TLS (TLS 1.2/1.3) and strong cipher suites.
- **Database Row-Level Security:** Cloud database tables enforce PostgreSQL Row-Level Security (RLS) ensuring each user can only read and write their own rows.

---

## 7. Data Retention & Deletion Rights

You have complete control over your data:
- **Local Deletion:** You can delete individual cycle entries or entire profiles from the app at any time. Deleted records are tombstoned and permanently removed upon sync.
- **Sign Out & Local Wipe:** Signing out of your account gives you the option to discard all local database records from that device immediately.
- **Sign Out Everywhere:** You can invalidate sessions across all devices from the Account settings.
- **Account & Cloud Deletion:** You may request complete deletion of your Supabase account and all associated cloud data by emailing us at `will@wjdavis5.net` or using the in-app account deletion request. Upon request, all server records are permanently deleted within 30 days.

---

## 8. Your Legal Rights (GDPR, CCPA, and Worldwide)

Depending on your jurisdiction (such as the European Economic Area, United Kingdom, California, and other US states), you have the right to:
- **Access:** Know what personal data is processed and request a copy.
- **Rectification:** Correct inaccurate or incomplete information.
- **Erasure:** Request that your personal data be permanently erased ("Right to be Forgotten").
- **Restrict or Object to Processing:** Object to or limit specific processing activities.
- **Data Portability:** Receive your data in a structured, commonly used, and machine-readable format.
- **Withdraw Consent:** Withdraw consent for cloud synchronization or error reporting at any time.

To exercise any of these rights, please contact us at `will@wjdavis5.net`.

---

## 9. Apple App Store & Google Play Declarations

In compliance with Apple App Store Guidelines (including Guideline 5.1.1 and `PrivacyInfo.xcprivacy`) and Google Play Data Safety:
- **Data Used to Track You:** None (`NSPrivacyTracking: false`).
- **Data Linked to You:** Email Address (App Functionality), Health Information (App Functionality, only when cloud sync is active).
- **Data Not Linked to You:** Crash Data (App Functionality, fully anonymized).

---

## 10. Changes to this Privacy Policy

We may update this Privacy Policy from time to time to reflect improvements to the app, legal requirements, or architectural changes. The "Last Updated" date at the top of this document will always indicate when changes were made. Substantial changes will be highlighted in app release notes.

---

## 11. Contact Information

If you have any questions, concerns, or requests regarding this Privacy Policy or the handling of your data, please contact:

**William Davis (LunarLog Maintainer)**  
Email: [will@wjdavis5.net](mailto:will@wjdavis5.net)  
Repository: [https://github.com/wjdavis5/lunarlog](https://github.com/wjdavis5/lunarlog)  
Issues: [https://github.com/wjdavis5/lunarlog/issues](https://github.com/wjdavis5/lunarlog/issues)  
