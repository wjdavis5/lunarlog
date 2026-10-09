/// Issue #1783: the store release gate's required-check list has drifted
/// from its documentation twice (#1723 fixed `webapp/README.md`, #1783
/// `AGENTS.md`), so this pins the authoritative list in
/// `.github/scripts/check-ci-gate.sh` against the operating guide that
/// restates it. A future check added to the gate fails here until AGENTS.md
/// names it.
library;

import 'package:flutter_test/flutter_test.dart';

import 'repo_text_helpers.dart';

void main() {
  test('every required check the release gate enforces is named in '
      'AGENTS.md', () {
    final script = readRepoFile('.github/scripts/check-ci-gate.sh');
    final match = RegExp(
      r'REQUIRED_CHECKS="\$\{REQUIRED_CHECKS:-([^}]+)\}"',
    ).firstMatch(script);
    expect(match, isNotNull,
        reason: 'check-ci-gate.sh must define REQUIRED_CHECKS');
    final required = match!.group(1)!.split('|');
    expect(required, isNotEmpty);

    final agents = readRepoFile('AGENTS.md');
    for (final check in required) {
      // The guide compresses the three shard checks into one row.
      final spelled = RegExp(r'^Test \(shard \d\)$').hasMatch(check)
          ? 'Test (shard 0|1|2)'
          : check;
      expect(agents, contains(spelled),
          reason: 'AGENTS.md\'s release-gate bullet must name the required '
              'check "$check"');
    }
  });
}
