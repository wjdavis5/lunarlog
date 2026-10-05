import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the marketing site's navigation (`site/src/layouts/BaseLayout.astro`).
///
/// Until this landed the header was the logo alone and the footer one link,
/// so a visitor on any page but the home page had no way to reach the rest
/// of the site. The header now carries four links and the footer is the
/// whole map. These tests keep that true as pages are added:
///
/// - a page added to the sitemap must also be added to the footer, or it is
///   reachable only by whoever already has its URL;
/// - the header must stay small enough to fit one row of a phone screen,
///   because the site ships no JavaScript and so has no menu button to hide
///   an overflow behind;
/// - a skip link must precede the header, so keyboard and screen-reader
///   users are not made to step through it on every page.
void main() {
  final layout = File('site/src/layouts/BaseLayout.astro')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');
  final sitemap = File('site/src/pages/sitemap.xml.ts')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  /// `/guides/` and `/guides` are the same page.
  String trimSlash(String path) {
    final trimmed = path.replaceAll(RegExp(r'/+$'), '');
    return trimmed.isEmpty ? '/' : trimmed;
  }

  Set<String> hrefsBetween(String start, String end) {
    final from = layout.indexOf(start);
    final to = from < 0 ? -1 : layout.indexOf(end, from);
    // Not `expect`: this runs while the file loads, outside any test.
    if (from < 0 || to <= from) {
      throw StateError('BaseLayout.astro lost `$start` or `$end`');
    }
    return RegExp(r'href: "([^"]+)"')
        .allMatches(layout.substring(from, to))
        .map((match) => trimSlash(match.group(1)!))
        .toSet();
  }

  final headerLinks = hrefsBetween('const headerLinks', 'const footerGroups');
  final footerLinks = hrefsBetween('const footerGroups', 'const trimSlash');
  final sitemapPages = RegExp(r'^\s*"(/[^"]*)",', multiLine: true)
      .allMatches(sitemap)
      .map((match) => trimSlash(match.group(1)!))
      .toSet();

  test('the sitemap parses', () {
    expect(sitemapPages, containsAll(<String>['/', '/tracking', '/guides']));
  });

  test('the footer maps every page except home and the individual guides',
      () {
    final expected = sitemapPages
        .where((path) => path != '/' && !path.startsWith('/guides/'))
        .toSet();
    expect(
      footerLinks,
      equals(expected),
      reason: 'a page in site/src/pages/sitemap.xml.ts is missing from '
          "BaseLayout's footerGroups (or the footer links somewhere the "
          'sitemap does not list)',
    );
  });

  test('every header link is also in the footer', () {
    expect(footerLinks, containsAll(headerLinks));
  });

  test('the header fits one row of a phone screen', () {
    expect(headerLinks, isNotEmpty);
    expect(
      headerLinks.length,
      lessThanOrEqualTo(4),
      reason: 'four short links are what fit on one 360px-wide row; a '
          'fifth wraps, and the site has no JavaScript for a menu button. '
          'Add new pages to the footer instead',
    );
  });

  test('a skip link precedes the header and lands on the content', () {
    final skip = layout.indexOf('class="skip-link" href="#content"');
    final header = layout.indexOf('<header class="site-header">');
    expect(skip, greaterThanOrEqualTo(0),
        reason: 'the skip link is gone or no longer targets #content');
    expect(skip, lessThan(header),
        reason: 'the skip link must be the first thing in the page');
    expect(layout, contains('<main id="content">'));
  });

  test('the two navigation landmarks are told apart by name', () {
    expect(layout, contains('<nav class="site-nav" aria-label="Main">'));
    expect(layout, contains('<nav class="site-map" aria-label="All pages">'));
  });
}
