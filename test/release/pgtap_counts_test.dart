import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

void main() {
  test('AGENTS.md database tests sentence matches actual supabase/tests/*.sql plan counts', () {
    final agentsMd = readRepoFile('AGENTS.md');
    final match = RegExp(r'-\s+\*\*Database tests \(`supabase/tests/`\):\*\*\s+(\d+)\s+pgTAP tests across (\d+) files \((.*?)\)\.')
        .firstMatch(agentsMd);

    expect(match, isNotNull, reason: 'AGENTS.md must contain the database tests summary sentence');

    final statedTotal = int.parse(match!.group(1)!);
    final statedFileCount = int.parse(match.group(2)!);
    final fileEntries = match.group(3)!;

    final dir = Directory('supabase/tests');
    expect(dir.existsSync(), isTrue, reason: 'supabase/tests directory must exist');

    final sqlFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    expect(statedFileCount, equals(sqlFiles.length),
        reason: 'Stated file count in AGENTS.md should match actual number of .sql files in supabase/tests');

    var actualTotal = 0;
    for (final file in sqlFiles) {
      final baseName = file.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final content = file.readAsStringSync();
      final planMatch = RegExp(r'select\s+plan\((\d+)\);').firstMatch(content);
      expect(planMatch, isNotNull, reason: '$baseName must contain a select plan(N); statement');

      final planCount = int.parse(planMatch!.group(1)!);
      actualTotal += planCount;

      final expectedEntry = '`$baseName` $planCount';
      expect(fileEntries.contains(expectedEntry), isTrue,
          reason: 'AGENTS.md must list $expectedEntry');
    }

    expect(statedTotal, equals(actualTotal),
        reason: 'Stated pgTAP test total in AGENTS.md must match sum of all plan() counts ($actualTotal)');
  });
}
