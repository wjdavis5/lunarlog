import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards how the marketing site sizes app screenshots.
///
/// A phone capture is 1290x2796: more than twice as tall as it is wide. The
/// site's figures used to let one fill the text column, so on a desktop the
/// guardians and estimates screenshots on the home page drew 640px wide and
/// 1,385px tall, each taller than the window. The fix is in two places that
/// have to agree: the `Screenshot` component marks a capture's shape, and
/// the stylesheet caps the portrait shape at a phone's width. These tests
/// keep the two halves together, and keep every figure going through the
/// component so none can skip the cap.
void main() {
  final component = File('site/src/components/Screenshot.astro')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final css = File('site/src/styles/global.css')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  test('the component marks each capture portrait or landscape', () {
    expect(
      component,
      contains('height > width ? "shot--portrait" : "shot--landscape"'),
      reason: 'the shape comes from the manifest size, not from the caller',
    );
    expect(
      component,
      contains(r'class={`shot ${shape}`}'),
      reason: 'the shape has to reach the rendered <img>',
    );
  });

  test('the stylesheet caps a portrait capture at a phone width', () {
    final rule = RegExp(
      r'\.screenshot-figure \.shot--portrait \{\s*'
      r'max-width: min\(100%, (\d+(?:\.\d+)?)rem\);\s*\}',
    ).firstMatch(css);
    expect(
      rule,
      isNotNull,
      reason: 'a portrait screenshot needs a max-width that also never '
          'exceeds its column',
    );
    final rem = double.parse(rule!.group(1)!);
    // 24rem is 384px at the default size: about a large phone. Wider than
    // that and the capture is taller than a 900px window again.
    expect(rem, lessThanOrEqualTo(24));
    expect(rem, greaterThanOrEqualTo(16),
        reason: 'narrower than this and the app text in the capture is '
            'too small to read');
  });

  test('no other rule sets a width on figure images that would beat the cap',
      () {
    // `.screenshot-figure img` (the base rule) may say max-width: 100%;
    // the portrait cap is more specific and wins. A modifier that pinned
    // its own img width would silently fork the sizing again.
    final forks = RegExp(r'\.screenshot-figure--[a-z-]+ img \{[^}]*width')
        .allMatches(css)
        .map((match) => match.group(0))
        .toList();
    expect(forks, isEmpty);
  });

  test('every screenshot figure renders through the component', () {
    final pages = Directory('site/src/pages')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.astro'))
        .toList();
    expect(pages, isNotEmpty);

    var figures = 0;
    for (final page in pages) {
      final source = page.readAsStringSync().replaceAll('\r\n', '\n');
      final matches = RegExp(
        r'<figure class="screenshot-figure[^"]*">([\s\S]*?)</figure>',
      ).allMatches(source);
      for (final match in matches) {
        figures++;
        final body = match.group(1)!;
        expect(
          body,
          contains('<Screenshot'),
          reason: '${page.path}: a screenshot figure must use the '
              'Screenshot component, which is what marks the shape',
        );
        expect(
          body,
          isNot(contains('<img')),
          reason: '${page.path}: a raw <img> in a screenshot figure '
              'carries no shape class and skips the cap',
        );
      }
    }
    expect(figures, greaterThan(5),
        reason: 'the scan found too few figures to prove anything');
  });
}
