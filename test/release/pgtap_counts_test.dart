import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

void main() {
  test(
      'every real supabase/tests/*.sql file declares a pgTAP plan of at '
      'least 1', () {
    // Issue #652: this test used to check a hand-maintained (later,
    // generated) per-file pgTAP count sentence in AGENTS.md against the
    // actual `select plan(N);` sums -- the sentence itself was the
    // merge-conflict generator the issue fixed. Per the repo owner, the
    // schema/test-count history doesn't belong in a committed doc at all:
    // the Supabase MCP server (`list_tables`/`list_migrations`) and CI's
    // `db-tests` job (which actually runs the suite) are the live sources
    // of truth, and maintaining a doc that mirrors them is wasted upkeep.
    // What's left worth guarding here is purely structural and has nothing
    // to do with AGENTS.md: a pgTAP file with a missing or zero plan count
    // fails confusingly (or not at all) rather than at this test's clear
    // failure message. `000-setup.sql`-style helper files that declare no
    // test plan at all (nothing to assert, just shared setup) are allowed
    // to have none; every other file must declare at least one.
    final testsDir = Directory('supabase/tests');
    expect(testsDir.existsSync(), isTrue,
        reason: 'supabase/tests directory must exist');

    final sqlFiles = testsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(sqlFiles, isNotEmpty,
        reason: 'scanned zero .sql files — check the path');

    final planPattern = RegExp(r'select\s+plan\((\d+)\);');
    for (final file in sqlFiles) {
      final baseName = file.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final content = file.readAsStringSync();
      final match = planPattern.firstMatch(content);

      if (match == null) {
        expect(baseName.toLowerCase().contains('setup'), isTrue,
            reason: '$baseName has no `select plan(N);` statement and is '
                "not a setup-style file — every real pgTAP test file must "
                'declare a plan');
        continue;
      }

      final planCount = int.parse(match.group(1)!);
      expect(planCount, greaterThanOrEqualTo(1),
          reason: "$baseName's plan count must be at least 1, was "
              '$planCount');
    }
  });

  test(
      'AGENTS.md does not re-embed per-file pgTAP counts or a running '
      'total', () {
    // Regression guard for the fix above: nothing should reintroduce the
    // hand-maintained "N pgTAP tests across M files (`file` count, ...)"
    // sentence issue #652 removed — that sentence, sitting right next to
    // the equally conflict-prone Schema bullet, was what made nearly every
    // migration PR touch the same lines in AGENTS.md.
    final agentsMd = readRepoFile('AGENTS.md');
    expect(agentsMd.contains('pgTAP tests across'), isFalse,
        reason: 'AGENTS.md must not re-embed a pgTAP count sentence — use '
            "the Supabase MCP server or CI's db-tests job instead of a "
            'doc that has to be kept in sync by hand');
  });
}
