# Illustration set (`assets/icon_pack/`)

**Status: retained but deliberately not shipped (issue #164).**

These 28 PNGs (`01_lunar-log.png` … `28_period-flow.png`) are no longer declared
under `pubspec.yaml`'s `assets:` list, so no build bundles them — every byte
used to ship in the IPA/AAB while nothing in `lib/` or `test/` referenced them.
The files stay in the repository for the follow-up that wires them into the
tracking UI (issue #765).

## Provenance and licence

**Not established, and not recorded anywhere in the repo.** The two commits
that introduced the set — `3396f04f` ("replace default Flutter icons with
LunarLog icon pack") and `2cefbf8e` ("replace icon pack with high-res
user-split assets") — carry no source, author, or licence. Unlike
`assets/branding/README.md` (which documents the Google "G" mark's origin and
usage terms), there is no attribution here.

That is tolerable only because the set does not ship. **Do not re-add
`assets/icon_pack/` to `pubspec.yaml` until its provenance and licence are
confirmed**, or replace the set with artwork that is. Resolving this is the
first item in issue #765.
