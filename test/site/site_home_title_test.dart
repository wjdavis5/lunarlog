import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The home page's `<title>` is what a search result, a browser tab and a
/// shared link show of the site. It used to be the bare name, "lunarlog",
/// which says nothing to someone who has not heard of it. This pins that it
/// names the product and says what it is, and that the other pages keep
/// their `<page> — lunarlog` form.
void main() {
  final layout = File('site/src/layouts/BaseLayout.astro').readAsStringSync();
  final home = File('site/src/pages/index.astro').readAsStringSync();

  final homeTitle = RegExp(r'const homeTitle = "([^"]+)";').firstMatch(layout);

  test('the home page has a title of its own', () {
    expect(homeTitle, isNotNull,
        reason: 'BaseLayout.astro no longer declares homeTitle');
    expect(
      layout,
      contains(r'title === "lunarlog" ? homeTitle : `${title} — lunarlog`'),
      reason: 'the home title is not what the layout renders for the home',
    );
    // The home page is the one page that asks for it.
    expect(home, contains('<BaseLayout title="lunarlog"'));
  });

  test('it leads with the name and then says what lunarlog is', () {
    final title = homeTitle?.group(1) ?? '';
    expect(title, startsWith('lunarlog — '));
    expect(title.length, greaterThan('lunarlog — '.length + 10));
    // Short enough that a search result shows all of it.
    expect(title.length, lessThanOrEqualTo(60));
  });

  test('it says the same thing the home page says under its heading', () {
    // The page's own description opens "A cycle tracker a family shares".
    // The title borrows those words, so the two cannot drift apart into
    // two different pitches.
    final title = (homeTitle?.group(1) ?? '').toLowerCase();
    final strapline = title.replaceFirst('lunarlog — ', '');
    final description = home.replaceAll(RegExp(r'"\s*\+\s*"'), '').toLowerCase();
    expect(strapline, isNotEmpty);
    expect(description, contains(strapline));
  });

  test('the title is also what a shared link shows', () {
    expect(layout, contains('<title>{fullTitle}</title>'));
    expect(
      layout,
      contains('<meta property="og:title" content={fullTitle} />'),
    );
  });
}
