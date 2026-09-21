/// Branding & product-identity guard (issues #164, #258).
///
/// Pins, as text/filesystem assertions, the invariants that neither compiles
/// nor renders under `flutter test`:
///
/// * exactly one product-name spelling — `lunarlog` (lowercase, one word) —
///   across the manifests and every user-visible string;
/// * real launch/adaptive-icon assets derived from the brand mark, not the
///   Flutter template stubs;
/// * the deliberate unbundling of `assets/icon_pack/` from `pubspec.yaml`;
/// * the collective noun is "guardian" in the localized copy, with
///   "caregiver" reserved for the specific role.
///
/// Mirrors `fcm_presentation_manifest_test.dart`'s shape (read repo files as
/// text, pin against the Dart constants the app actually uses).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/ui/profiles/first_run_screen.dart';
import 'package:lunarlog/ui/settings/about_section.dart';

import 'repo_text_helpers.dart';

/// PascalCase identifiers that legitimately contain `LunarLog`/`Lunarlog`.
///
/// Class names are Dart identifiers, and issue #258 froze every identifier —
/// only *copy* converges on the lowercase spelling. Stripping these before
/// scanning lets the guard reject a stray `LunarLog` in a comment or string
/// without renaming `LunarLogRoot` or `kSystemLunarlogLocal`. Sorted longest
/// first so a prefix identifier cannot leave a stray fragment behind.
const _identifierAllowlist = <String>[
  'LunarLogStorageRemoteApply',
  'LunarLogStorageLocalWrites',
  'LunarLogDatabaseManager',
  'LunarLogStorageQueries',
  'LunarLogWidgetBuilder',
  // Issue #141: the widget kind (the Swift struct and the WidgetCenter
  // kind string) and the Android provider class are frozen cross-platform
  // identifiers; the Dart constants that name them carry the same words.
  'kLunarLogWidgetAndroidName',
  'LunarLogWidgetProvider',
  'kLunarLogWidgetName',
  'LunarLogWidget',
  'LunarlogLocalIntensity',
  'LunarLogAppState',
  'LunarLogRootState',
  'LunarLogDatabase',
  'LunarLogDbFactory',
  'LunarLogStorage',
  'LunarLogColors',
  'LunarLogRoot',
  'LunarLogApp',
  'LunarlogLocalFlow',
  'LunarlogLocal',
  '_runLunarlog',
];

/// Matches a second spelling of the product name, case-sensitively: the
/// lowercase `lunarlog` (the one true spelling) is deliberately not matched.
final _wrongSpelling = RegExp('LunarLog|Lunarlog');

/// [text] with the frozen Dart identifiers removed, so the remaining text can
/// be scanned for a product-name spelling that should not exist.
String _stripFrozenIdentifiers(String text) {
  var result = text;
  for (final identifier in _identifierAllowlist) {
    result = result.replaceAll(identifier, '');
  }
  return result;
}

/// Every `lib/**/*.dart` file's path and contents.
Map<String, String> _libSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      sources[entity.path] = entity.readAsStringSync();
    }
  }
  return sources;
}

/// The width/height encoded in a PNG's IHDR chunk, read without an image
/// dependency so the guard proves the launch images are real rasters rather
/// than 68-byte transparent stubs.
({int width, int height}) _pngSize(File file) {
  final bytes = file.readAsBytesSync();
  expect(bytes.length, greaterThan(1000),
      reason: '${file.path} looks like a template stub, not a real raster');
  final data = ByteData.sublistView(Uint8List.fromList(bytes));
  // 8-byte signature, then IHDR's length (4) and type (4) before the data.
  return (width: data.getUint32(16), height: data.getUint32(20));
}

void main() {
  group('product name is lunarlog, lowercase (issues #164, #258)', () {
    test('pubspec.yaml names the package lunarlog', () {
      final pubspec = stripHashComments(readRepoFile('pubspec.yaml'));
      expect(pubspec, contains('name: lunarlog'));
      expect(pubspec, isNot(matches(RegExp(r'name:\s*LunarLog|name:\s*Lunarlog'))));
    });

    test('the iOS display name is lunarlog', () {
      final plist = readRepoFile('ios/Runner/Info.plist');
      expect(
        plist,
        matches(RegExp(
          r'<key>CFBundleDisplayName</key>\s*<string>lunarlog</string>',
        )),
        reason: 'CFBundleDisplayName is the springboard label',
      );
    });

    test('the Android application label is lunarlog', () {
      final manifest = readRepoFile('android/app/src/main/AndroidManifest.xml');
      expect(manifest, contains('android:label="lunarlog"'));
    });

    test('the localization template carries no second spelling', () {
      final arb = readRepoFile('lib/l10n/app_en.arb');
      expect(_wrongSpelling.hasMatch(arb), isFalse,
          reason: 'every user-visible string must read "lunarlog"');
    });

    test('no lib/ source carries a stray second spelling', () {
      final offenders = <String>[];
      _libSources().forEach((path, contents) {
        final stripped = _stripFrozenIdentifiers(contents);
        if (_wrongSpelling.hasMatch(stripped)) {
          offenders.add(path);
        }
      });
      expect(offenders, isEmpty,
          reason: 'these files still spell the product name wrong outside a '
              'frozen Dart identifier: $offenders');
    });

    test('the product-name constants the UI renders are lowercase', () {
      expect(kFirstRunBrandName, 'lunarlog');
      expect(kAboutApplicationName, 'lunarlog');
      expect(kReminderTitle, 'A reminder from lunarlog');
      expect(kReminderBody, 'Open lunarlog to see what it is about.');
    });

    test('the Android permissions rationale and Deno push copy are lowercase',
        () {
      expect(
        readRepoFile('android/app/src/main/kotlin/com/wjdavis5/lunarlog/'
            'PermissionsRationaleActivity.kt'),
        isNot(matches(_wrongSpelling)),
      );
      expect(
        _wrongSpelling
            .hasMatch(readRepoFile('supabase/functions/_shared/'
                'notification_copy.ts')),
        isFalse,
      );
    });
  });

  group('launch screens and adaptive icon are real brand assets (issue #164)',
      () {
    test('the iOS launch images are the brand mark at all three densities',
        () {
      const expected = {
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/LaunchImage.png':
            (width: 168, height: 185),
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/'
                'LaunchImage@2x.png':
            (width: 336, height: 370),
        'ios/Runner/Assets.xcassets/LaunchImage.imageset/'
                'LaunchImage@3x.png':
            (width: 504, height: 555),
      };
      expected.forEach((path, size) {
        final actual = _pngSize(File(path));
        expect(actual.width, size.width, reason: '$path width');
        expect(actual.height, size.height, reason: '$path height');
      });
    });

    test('the default Flutter LaunchImage README stub is gone', () {
      expect(
        File('ios/Runner/Assets.xcassets/LaunchImage.imageset/README.md')
            .existsSync(),
        isFalse,
      );
    });

    test('the iOS launch storyboard is branded, not stock white', () {
      final storyboard = readRepoFile('ios/Runner/Base.lproj/'
          'LaunchScreen.storyboard');
      expect(storyboard, contains('red="0.21568627"'));
      expect(storyboard, contains('green="0.08235294"'));
      expect(storyboard, contains('blue="0.42352941"'));
    });

    test('both Android launch backgrounds show the mark, not bare white', () {
      for (final path in [
        'android/app/src/main/res/drawable/launch_background.xml',
        'android/app/src/main/res/drawable-v21/launch_background.xml',
      ]) {
        final xml = readRepoFile(path);
        expect(xml, contains('@drawable/launch_mark'), reason: path);
        expect(xml, contains('@color/ic_launcher_background'), reason: path);
        expect(xml, isNot(contains('android:drawable="@android:color/white"')),
            reason: path);
      }
    });

    test('an Android adaptive icon exists with all three layers', () {
      final adaptive = readRepoFile(
          'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml');
      expect(adaptive, contains('<adaptive-icon'));
      expect(adaptive, contains('<background'));
      expect(adaptive, contains('<foreground'));
      expect(adaptive, contains('<monochrome'));
      expect(readRepoFile('android/app/src/main/res/values/colors.xml'),
          contains('ic_launcher_background'));
    });

    test('the adaptive foreground/monochrome layers exist at every density',
        () {
      for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        for (final name in [
          'ic_launcher_foreground.png',
          'ic_launcher_monochrome.png',
          'launch_mark.png',
        ]) {
          final file =
              File('android/app/src/main/res/drawable-$density/$name');
          expect(file.existsSync(), isTrue, reason: file.path);
          expect(file.lengthSync(), greaterThan(1000), reason: file.path);
        }
      }
    });

    test('the generation is reproducible from a committed script', () {
      expect(
        File('tool/branding/generate_brand_assets.py').existsSync(),
        isTrue,
        reason: 'the rasters must be regenerable, not hand-placed',
      );
    });
  });

  group('the bundled illustration set no longer ships (issue #164)', () {
    test('pubspec.yaml does not declare assets/icon_pack/', () {
      final pubspec = stripHashComments(readRepoFile('pubspec.yaml'));
      expect(pubspec, isNot(contains('assets/icon_pack/')));
    });

    test('the illustration files stay in the repo for the follow-up', () {
      final files = Directory('assets/icon_pack')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.png'));
      expect(files.length, 28,
          reason: 'the follow-up that wires these up must still find them');
    });
  });

  group('guardian is the collective noun, caregiver the role (issue #258)', () {
    test('the localization template uses "guardians" as the umbrella', () {
      final arb = readRepoFile('lib/l10n/app_en.arb');
      expect(arb, contains('"settingsCaregiverAlertsTitle": "Guardian alerts"'));
      expect(arb, contains('"manageGuardiansRemoveCaregiverTooltip": '
          '"Remove guardian"'));
      // The role's own label is untouched — "caregiver" still names the seat.
      expect(arb, contains('"guardianRoleLabelCaregiver": "Caregiver"'));
    });

    test('no frozen wire value was renamed', () {
      final arb = readRepoFile('lib/l10n/app_en.arb');
      expect(arb, contains('"guardianRoleLabelCaregiver"'));
      expect(
        readRepoFile('lib/domain/models/profile_guardian.dart'),
        contains("caregiver => 'caregiver'"),
        reason: 'the role enum\'s wire value is frozen',
      );
    });

    test('the voice-and-copy guide exists and records the naming rules', () {
      final guide = readRepoFile('docs/product/voice-and-copy.md');
      expect(guide, contains('lunarlog'));
      expect(guide, contains('guardian'));
      expect(guide, contains('caregiver'));
    });
  });
}
