# CLAUDE.md — lunarlog

**Read [`AGENTS.md`](AGENTS.md) first — it is the single source of project context, Supabase backend configuration, credential locations, and build instructions for `lunarlog`.**

## Quick Reference

- **Backend:** Supabase Cloud (`dleexnnevuuddcgcpztq`)
- **MCP Server:** Configured in `.mcp.json`
- **Config & Secrets:** `.env` (local, gitignored) and GitHub Secrets on `wjdavis5/lunarlog`
- **Skills:** `supabase`, `supabase-postgres-best-practices`
- **Dev & Verification:**
  - `flutter pub get`
  - `flutter analyze`
  - `flutter test`
  - `dart run tool/quality_gate.dart` (90% coverage floor + per-method CRAP gate, CI-enforced) and `dart run tool/mutation_gate.dart` (local-only mutation testing) — see AGENTS.md's "Quality gates" section
- **iOS Device Build:** Target macOS build machine (Xcode 26+).
- **Docs:** Full details live in [`AGENTS.md`](AGENTS.md) and [`README.md`](README.md).
