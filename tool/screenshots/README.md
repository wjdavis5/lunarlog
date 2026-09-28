# tool/screenshots — scripted site screenshots (issue #1104)

Every app screenshot the site shows is rendered, not hand-captured: one
command walks a fixed (screen × device × theme) manifest, mounts the real
production widgets over a deterministic fabricated dataset, and writes PNGs
plus a `screenshots.json` index.

```
npm run screenshots        # from site/ — resolves the repo root and commit
```

or directly: `flutter test tool/screenshots/render_screens_test.dart`.

## The pieces

| File | Role |
|---|---|
| `manifest.dart` | The fixed manifest: devices (6.7"/6.1" iPhone, Pixel, iPad 11"), themes, screens. Pure data, unit-tested. |
| `fabricated_profile.dart` | The only data the screenshots may draw from: two fabricated profiles (the seeder's "Maya" and "Riley"), fixed clock, generator-sourced notes. **Fails the run** if a profile name is not on the seed generator's list (`tool/seed_test_accounts/payload_generator.dart`'s `kSeedProfileNames`) — edit that list first, never here. |
| `index.dart` | The JSON index builder: screen id, device, theme, file, pixel size, store size, app version, commit. Byte-stable for identical inputs. |
| `render_harness.dart` | The provider tree + per-screen scene plans — the same real widgets the widget-test harnesses mount, no app rewrite. |
| `render_screens_test.dart` | The `flutter test` runner: pumps, settles, captures via a `RepaintBoundary`, writes PNG + index. |

Unit tests: `test/tool/screenshots/` (run by CI's normal `flutter test`
shards). The runner itself is deliberately **not** part of the CI suite —
it writes files and renders dozens of frames; it runs in
`site-deploy.yml`'s deploy job and locally.

## Where the output goes

Default output is `site/public/screenshots/` (gitignored). The Astro build
copies `public/` verbatim into `dist/`, and `site-deploy.yml` regenerates
the PNGs on every deploy — **never commit them**; a UI change redeploying
the site is how they stay fresh (that path filter is in the workflow).

## Determinism

Fixed clock (`fabricated_profile.dart`'s `kScreenshotToday`), fixed
fabricated data, bundled fonts loaded into the test engine, stable manifest
walk order — two runs on the same commit on one platform are
byte-identical. Render a subset locally with
`LUNARLOG_SCREENSHOTS_FILTER=today,calendar`.

## Store sizes

The index records each device's store listing size (App Store 6.7"/6.1"/
iPad, Play 1080×2400) — recorded only; nothing here uploads anywhere. The
store-upload path is deliberately out of scope (issue #1104).
