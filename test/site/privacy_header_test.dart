import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the privacy policy's "Last Updated" header line (issue #1177).
///
/// `PRIVACY.md` is the source of the store privacy URL and, since #1170,
/// the in-app "Read the full privacy policy" destination — its line 4 is
/// the first thing under the title. It once carried a 10,713-character
/// nested changelog: 15 `previously:` levels, each inside the previous
/// entry's parentheses, ending in a run of `)`. The header is now a date
/// plus at most one short plain-language clause; every real entry lives in
/// Section 10's Change History. These assertions keep the pattern from
/// growing back:
///
/// - the header line exists and leads with `**Last Updated:** <date>`;
/// - it stays under 200 characters (room for the date and one clause);
/// - it never grows a nested `previously:` entry;
/// - Section 10's Change History still exists as the place entries go.
void main() {
  test('the Last Updated header stays a short date line (issue #1177)', () {
    // Normalize line endings the way `site_claims_test.dart` does: the
    // working copy may carry CRLF on Windows while CI checks out LF.
    final lines = File('PRIVACY.md')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .split('\n');
    final header = lines.firstWhere(
      (line) => line.startsWith('**Last Updated:**'),
      orElse: () => fail('PRIVACY.md lost its **Last Updated:** header line'),
    );
    expect(
      RegExp(r'^\*\*Last Updated:\*\* [A-Z][a-z]+ \d{1,2}, \d{4}')
          .hasMatch(header),
      isTrue,
      reason: 'the Last Updated line must lead with a written date',
    );
    expect(
      header.length,
      lessThanOrEqualTo(200),
      reason: 'the Last Updated line is regrowing into a changelog '
          '(${header.length} characters) — the header carries the date and '
          "at most one short plain-language clause; everything else goes to "
          "Section 10's Change History",
    );
    expect(
      header.contains('previously:'),
      isFalse,
      reason: "nested previously: entries belong in Section 10's Change "
          'History, not the header',
    );
  });

  test("Section 10's Change History remains the header's overflow home", () {
    final source =
        File('PRIVACY.md').readAsStringSync().replaceAll('\r\n', '\n');
    expect(source, contains('## 10. Changes to this Privacy Policy'));
    expect(source, contains('### Change History'));
  });
}
