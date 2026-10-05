import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The getting-started guide sends a reader either to a store or to the
/// browser version, then walks the phone app's first-run screens. The
/// browser version is the React web client: it has no first-run screen and
/// no account-free mode, so a browser reader has to sign in first and add
/// a profile afterwards. This pins the paragraph that says so, so the
/// guide cannot drift back to describing one flow for both.
void main() {
  final guide = File('site/src/pages/guides/getting-started.astro')
      .readAsStringSync()
      .replaceAll(RegExp(r'\s+'), ' ');

  final start = guide.indexOf('<p id="browser-first-steps">');
  final paragraph =
      start < 0 ? '' : guide.substring(start, guide.indexOf('</p>', start));

  test('the guide tells a browser reader to sign in before anything else',
      () {
    expect(start, greaterThanOrEqualTo(0),
        reason: 'the browser paragraph is missing from the install section');
    expect(paragraph, contains('create the account or sign in first'));
    expect(paragraph, contains('follows the phone apps'));
  });

  test('it names the web client\'s controls through UiLabel', () {
    // A renamed label then fails the site build, not a reader.
    expect(
      paragraph,
      contains('<UiLabel key="profilePickerEmptyAddAction" />'),
    );
    expect(paragraph, contains('<UiLabel key="profilePickerEmptyTitle" />'));
  });

  test('it cites the web client, not the phone app', () {
    expect(paragraph, contains('webapp/src/pages/SignedOutHome.tsx'));
    expect(paragraph, contains('webapp/src/pages/TodayPage.tsx'));
  });

  test('it sits in the install section, before the first-run walkthrough',
      () {
    final install = guide.indexOf('<h2>Install, or open the browser version</h2>');
    final firstRun = guide.indexOf('<h2>Set up the first profile</h2>');
    expect(install, greaterThanOrEqualTo(0));
    expect(firstRun, greaterThan(install));
    expect(start, greaterThan(install));
    expect(start, lessThan(firstRun));
  });
}
