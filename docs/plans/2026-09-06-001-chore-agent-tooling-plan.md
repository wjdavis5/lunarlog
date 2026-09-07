# Plan: Clean Up Agent-Native Tooling, Shadow Configs, and Doc References (#51)

## Goal

Resolve dev-agent tooling gaps and configuration drift identified during the agent-native architecture review (#37) by documenting the CLI equivalent for the Supabase advisor gate (`supabase db advisors` in pinned CLI 2.116.0+), removing unreferenced shadow files (`.mcps.json`, `claud.md`, `agent.md`), documenting the App Store Connect CLI status script (`scripts/asc.rb`) and its required environment keys in `AGENTS.md` and `.env.example`, and providing execution instructions and test setup fixes for `integration_test/gate_test.dart` so automated agents and developers can reliably execute host tests.

---

## Exact Files to Touch and Why

1. `AGENTS.md`
   - **Why:** 
     - Correct Migration Flow step 5 to document `npx supabase@2.116.0 db advisors --linked` as the CLI equivalent for the advisor gate (available in CLI 2.116.0+) so agents without MCP OAuth can verify security and performance lints.
     - Document `scripts/asc.rb` (usage: `status`, `builds`, `version`) under Development & Build Workflow.
     - Add `ASC_KEY_ID` and `ASC_ISSUER_ID` to the documented `.env` keys in the Config & Credential Locations section.
     - Add execution instructions for `integration_test/gate_test.dart` (`flutter test integration_test/gate_test.dart -d flutter-tester`) under the Tests section.

2. `.github/workflows/supabase-migrate.yml`
   - **Why:**
     - Update lines 34-35 in the workflow comments where it claims there is no CLI equivalent for `get_advisors`, referencing `supabase db advisors --linked`.

3. `.env.example`
   - **Why:**
     - Add `ASC_KEY_ID` and `ASC_ISSUER_ID` placeholders with comments documenting their use by `scripts/asc.rb` and the required `AuthKey_<KEY_ID>.p8` private key file.

4. `.mcps.json`
   - **Why:**
     - Unreferenced shadow MCP configuration file with divergent (Windsurf-style) schema. The canonical config is `.mcp.json`. Delete this file.

5. `claud.md`
   - **Why:**
     - Unreferenced typo duplicate of `CLAUDE.md`. Delete this file.

6. `agent.md`
   - **Why:**
     - Unreferenced duplicate pointer to `AGENTS.md`. Delete this file.

7. `integration_test/gate_test.dart`
   - **Why:**
     - Fix latent initialization bug in the issue #65 test case (missing `..grantNext = false` on initial pump and `gate.grantNext = true;` prior to `unlockViaButton`) so the host integration test passes cleanly under `flutter test integration_test/gate_test.dart -d flutter-tester`.

8. `CLAUDE.md`
   - **Why:**
     - Update Quick Reference to include the CLI advisor command and `scripts/asc.rb` reference.

---

## Step-by-Step Implementation

### Unit 1: Remove Shadow and Duplicate Files (U1)
- Remove `.mcps.json` using `git rm .mcps.json`.
- Remove `claud.md` using `git rm claud.md`.
- Remove `agent.md` using `git rm agent.md`.
- Verify that `git status` reflects the deletion of all three files and no remaining in-tree references exist.

### Unit 2: Update Supabase Advisor Gate Documentation (U2)
- In `AGENTS.md` (Migration Flow, step 5):
  - Change the parenthetical `(security and performance lints; there is no CLI equivalent)` to document both CLI and MCP paths:
    ```markdown
    5. **Before approving the run:** check for security and performance lints using either the Supabase CLI (`npx supabase@2.116.0 db advisors --linked` or `supabase db advisors --linked`) or the Supabase MCP `get_advisors` tool against project `dleexnnevuuddcgcpztq` and confirm no security or RLS findings. (The CLI command is available in CLI 2.116.0+ and does not require MCP OAuth; the MCP server requires an interactive login in the session that calls it).
    ```
- In `.github/workflows/supabase-migrate.yml`:
  - Update comments at lines 34-35:
    ```yaml
    # Before approving a run, check the Supabase CLI advisors output
    # (`supabase db advisors --linked`) or Supabase MCP `get_advisors`
    # for security or RLS findings.
    ```

### Unit 3: Document `scripts/asc.rb` and Environment Variables (U3)
- In `.env.example`:
  - Append the App Store Connect variables:
    ```bash
    # App Store Connect API (for scripts/asc.rb release checks)
    # The AuthKey_<KEY_ID>.p8 private key file is searched in ~/Downloads,
    # ~/.appstoreconnect/private_keys, or the repo root.
    ASC_KEY_ID=<asc-key-id>
    ASC_ISSUER_ID=<asc-issuer-uuid>
    ```
- In `AGENTS.md` (Config & Credential Locations -> Server-side only):
  - Add `ASC_KEY_ID` and `ASC_ISSUER_ID` to the `.env` keys bullet list:
    ```markdown
    - `ASC_KEY_ID` - App Store Connect API key ID (for `scripts/asc.rb`).
    - `ASC_ISSUER_ID` - App Store Connect API issuer ID (for `scripts/asc.rb`).
    ```
- In `AGENTS.md` (Development & Build Workflow):
  - Add an **App Store Connect CLI Tool (`scripts/asc.rb`)** section:
    ```markdown
    - **App Store Connect Checks (`scripts/asc.rb`):**
      - Agent-runnable CLI script for inspecting App Store Connect status without Xcode or browser:
        - `ruby scripts/asc.rb status`: App record, latest 5 builds, version state, and submission state.
        - `ruby scripts/asc.rb builds`: Build list and processing state.
        - `ruby scripts/asc.rb version`: Current editable version, attached build, and review submission flag.
      - Auth requirements: `ASC_KEY_ID` and `ASC_ISSUER_ID` in `.env` at repo root, plus `AuthKey_<KEY_ID>.p8` located in `~/Downloads/`, `~/.appstoreconnect/private_keys/`, or the repo root. Uses only the Ruby standard library.
    ```

### Unit 4: Document and Fix `integration_test/gate_test.dart` (U4)
- In `integration_test/gate_test.dart`:
  - In `issue #65: the credential prompt reporting its own focus loss still unlocks into the data`:
    - Update `final gate = FakeGate();` to `final gate = FakeGate()..grantNext = false;` so initial pump asserts lock screen.
    - Set `gate.grantNext = true;` before `await unlockViaButton(tester);` so unlocking succeeds as expected.
- In `AGENTS.md` (Development & Build Workflow -> Tests):
  - Document execution command for integration tests:
    ```markdown
    - **Integration tests:** `integration_test/gate_test.dart` exercises the gate matrix (cold start, decline, retry, prompt focus loss / #65, backgrounding re-lock, inactivity timeout, launch payload) with a fake authenticator and in-memory database on host:
      ```bash
      flutter test integration_test/gate_test.dart -d flutter-tester
      ```
      (or against a connected device/simulator with `-d <deviceId>`). Note that `flutter test` alone only auto-discovers tests under `test/`; tests under `integration_test/` require an explicit file argument and target device parameter.
    ```
- In `CLAUDE.md`:
  - Add pointer to `flutter test integration_test/gate_test.dart -d flutter-tester` in the Quick Reference.

---

## Verification

Concrete commands and checks to prove implementation:

1. **Shadow and Duplicate Files Removal:**
   ```bash
   git status --short
   # Assert .mcps.json, claud.md, agent.md are deleted (D)
   # Assert no file in the repo references .mcps.json, claud.md, or agent.md
   ```

2. **Supabase Advisor Command Validation:**
   ```bash
   npx supabase@2.116.0 db advisors --help
   # Confirms command is available and flags (--linked, --local) exist
   ```

3. **Git and Doc Content Validation:**
   ```bash
   git diff AGENTS.md .github/workflows/supabase-migrate.yml .env.example CLAUDE.md
   # Review changes for accurate doc references and formatting
   ```

4. **Integration Test Host Execution:**
   ```bash
   flutter test integration_test/gate_test.dart -d flutter-tester
   # Asserts all tests in integration_test/gate_test.dart pass cleanly on host
   ```

5. **Existing Verification & Lints:**
   ```bash
   flutter analyze
   flutter test
   dart run tool/quality_gate.dart
   ```
