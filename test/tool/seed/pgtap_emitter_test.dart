import 'package:flutter_test/flutter_test.dart';

import '../../../tool/seed_test_accounts/pgtap_emitter.dart';

void main() {
  final sql = buildPgtapFixture();

  test('carries the generated-file header and regen command', () {
    expect(sql, contains('GENERATED FILE -- DO NOT EDIT'));
    expect(
      sql,
      contains('dart run tool/seed_test_accounts/main.dart --emit-pgtap'),
    );
  });

  test('plan(N) count matches the number of assertions', () {
    final planMatch = RegExp(r'select plan\((\d+)\);').firstMatch(sql);
    expect(planMatch, isNotNull);
    final declared = int.parse(planMatch!.group(1)!);
    final actual = RegExp(r'^select (?:is|ok)\(', multiLine: true)
        .allMatches(sql)
        .length;
    expect(actual, declared,
        reason: 'every assertion must be declared in plan()');
  });

  test('is self-contained: begin/finish/rollback and a fixture user', () {
    expect(sql, contains('begin;'));
    expect(sql, contains("select tests.create_supabase_user('seed_sample_user');"));
    expect(sql, contains("select tests.authenticate_as('seed_sample_user');"));
    expect(sql.trim().endsWith('rollback;'), isTrue);
    expect(sql, contains('select * from finish();'));
  });

  test('updated_at rides now() so the fixture never ages out', () {
    expect(sql, contains("now() - interval '2 days'"));
    // And no literal anchor timestamps leak into the day-entry rows.
    expect(sql, isNot(contains("'updated_at', '20")));
  });

  test('the embedded payload never writes the deprecated spotting flow', () {
    expect(sql, isNot(contains("'flow', 'spotting'")));
    expect(sql, contains("'flow', 'not_bleeding'"));
  });

  test('the fixture is small: a single profile, months of rows, few calls',
      () {
    expect(RegExp('jsonb_build_object\\(\'id\', \'[0-9A-HJKMNP-TV-Z]{26}\', '
            '\'display_name\'')
        .allMatches(sql)
        .length, 1);
    expect(sql, contains("display_name', 'Maya'"));
    // 2 months of daily entries fit into one day_entries call.
    final dayEntryCalls = RegExp('p_day_entries, \\d+ rows').firstMatch(sql);
    expect(dayEntryCalls, isNotNull);
    expect(int.parse(dayEntryCalls!.group(0)!.split(' ')[1]), lessThan(500));
  });
}
