/// Clock-seam guard (issue #304): a source scan asserting `lib/domain`
/// never reads the wall clock directly (`DateTime.now()`), the same
/// discipline `test/architecture/layering_test.dart` already enforces for
/// import layering. Found while auditing `CycleHistorySection` and
/// `MonthCalendar` (both accepted an injected `todayProvider` but a prior
/// version silently dropped it before #299 fixed the pass-through) —
/// this test gives that same "domain never reads the wall clock" property
/// its own regression lock instead of relying on each widget's own tests to
/// notice a dropped seam.
///
/// **Path handling:** deliberately normalises `File.path` (backslash ->
/// forward slash) before comparing, unlike `layering_test.dart`'s
/// composition-root allowlist check (issue #658 — that one always fails on
/// Windows because it compares raw `File.path` against forward-slash
/// literals). Kept in its own file rather than folded into
/// `layering_test.dart` so this scan runs clean on every platform
/// regardless of #658's outcome.
///
/// **Documented allowlist, not a blanket ban.** A small number of files
/// *are* the canonical "read the real wall clock" implementation an
/// injectable seam defaults to when nothing is supplied — e.g.
/// `LocalDate.today()`, the tear-off every `todayProvider = LocalDate.today`
/// default parameter across `lib/ui`/`lib/data` resolves to. Forcing those
/// out of `lib/domain` too would mean every one of those ~10 call sites
/// loses its default and gains a mandatory constructor argument sourced
/// from a new non-domain clock module — a real, larger refactor, not an
/// audit-and-forward fix (see the bundle PR's description for why it was
/// left for a follow-up rather than folded in here). This test's job is
/// narrower and still valuable on its own: catch a *business-logic* file
/// drifting into `DateTime.now()` the way `sharing_service.dart`'s
/// `PendingInvite.isExpired` getter had (fixed alongside this test, moved
/// to `isExpiredAt(DateTime now)`) — not relitigate where the root clock
/// reads live.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to contain a literal `DateTime.now()` call: each is the
/// documented root of an injectable clock seam (a `now`/`today` parameter
/// defaults to it when the caller supplies nothing), not a business-logic
/// shortcut. Every entry names the exact seam it backs so a reviewer can
/// tell "still just the root default" from "a new leak" at a glance.
const Map<String, String> _domainWallClockAllowlist = {
  'lib/domain/models/local_date.dart':
      'LocalDate.today() -- the canonical seam every todayProvider default '
          '(lib/ui, lib/data) and every domain today ?? LocalDate.today '
          'default resolves to.',
  'lib/domain/health/health_sync_binding.dart':
      '_systemNow() -- HealthSyncBinding\'s default when no now is injected '
          '(issue #296).',
  'lib/domain/health/health_sync_mechanics.dart':
      'the now ?? (() => DateTime.now().toUtc()) default constructor '
          'fallback.',
};

final RegExp _wallClockCall = RegExp(r'DateTime\.now\s*\(');

/// A `//` (including `///`) line comment, stripped before matching so a
/// doc comment merely *mentioning* `DateTime.now()` in prose -- as several
/// of these files' own doc comments do when explaining the seam -- never
/// trips the guard. Mirrors `layering_test.dart`'s "anchor at line start"
/// care against the same false-positive shape, for this file's own scan.
final RegExp _lineComment = RegExp(r'//.*$', multiLine: true);

/// Whether [contents] contains a real (non-comment) `DateTime.now()` call.
bool _callsWallClock(String contents) =>
    _wallClockCall.hasMatch(contents.replaceAll(_lineComment, ''));

String _posix(String path) => path.replaceAll(r'\', '/');

List<File> _dartFilesUnder(String path) => Directory(path)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
    .toList();

void main() {
  group('clock seam (issue #304)', () {
    test(
        'no lib/domain file reads DateTime.now() directly, except the '
        'documented seam-root allowlist', () {
      final files = _dartFilesUnder('lib/domain');
      expect(files, isNotEmpty, reason: 'scanned zero files — check the path');

      final offenders = <String>[];
      for (final file in files) {
        final relPath = _posix(file.path);
        if (_domainWallClockAllowlist.containsKey(relPath)) continue;
        if (_callsWallClock(file.readAsStringSync())) {
          offenders.add(relPath);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: 'lib/domain must not read the wall clock directly -- take '
            '"now"/"today" as an explicit parameter instead, but these '
            'files do:\n${offenders.join('\n')}',
      );
    });

    // Falsification coverage for `_callsWallClock`, the same discipline
    // `layering_test.dart` gives its own detector: without this, a
    // detector that silently stopped matching would leave the scan above
    // passing on a dirty tree and catch nothing.
    test('detects a real call and ignores a doc-comment mention', () {
      expect(
        _callsWallClock('DateTime _now() => DateTime.now();'),
        isTrue,
        reason: 'a real call should be flagged',
      );
      expect(
        _callsWallClock('DateTime _now() => DateTime.now().toUtc();'),
        isTrue,
        reason: 'a real call with a chained method should be flagged',
      );
      expect(
        _callsWallClock(
          "/// never `Uuid.v4()`/`DateTime.now()` internally, see below.",
        ),
        isFalse,
        reason: 'a doc comment merely mentioning it should not be flagged',
      );
      expect(
        _callsWallClock('// TODO: stop calling DateTime.now() here'),
        isFalse,
        reason: 'a line comment should not be flagged',
      );
      expect(
        _callsWallClock('final now = clock();'),
        isFalse,
        reason: 'an unrelated clock call should not be flagged',
      );
    });

    test('the allowlist itself has no stale or missing entries', () {
      final actual = _dartFilesUnder('lib/domain')
          .map((f) => _posix(f.path))
          .where((path) => _callsWallClock(File(path).readAsStringSync()))
          .toSet();
      final allowed = _domainWallClockAllowlist.keys.toSet();
      expect(
        allowed.difference(actual),
        isEmpty,
        reason: 'these allowlisted files no longer call DateTime.now() at '
            'all -- shrink the allowlist so it keeps meaning something',
      );
      expect(
        actual.difference(allowed),
        isEmpty,
        reason: 'a new DateTime.now() call appeared outside the allowlist '
            '-- either it is a genuine seam root (document it above) or a '
            'domain-purity regression (the test above should already have '
            'caught it)',
      );
    });
  });
}
