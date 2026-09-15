/// The About section (Issue #226): app version and build number (via
/// [PackageInfo], the same dependency the diagnostics collector already
/// reads) and the open-source licences entry (`showLicensePage` — the
/// platform licence page Flutter ships, which enumerates every package's
/// NOTICE automatically).
///
/// Route naming: `showLicensePage` offers no `RouteSettings`, so the
/// licence page stays unnamed — the same deliberate informational-dialog
/// posture `settings_screen.dart`'s library doc records for "Contact
/// support". The version tile is not navigable at all.
library;

import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// The application name shown on the licence page — a proper noun, not
/// translatable copy (the same posture as `kSupportEmailAddress`).
const String kAboutApplicationName = 'LunarLog';

/// Reads [PackageInfo]; a seam so widget tests never touch the platform
/// channel (which throws `MissingPluginException` under `flutter test`).
typedef AboutPackageInfoReader = Future<PackageInfo> Function();

Future<PackageInfo> _defaultPackageInfoReader() => PackageInfo.fromPlatform();

class AboutSection extends StatefulWidget {
  const AboutSection({super.key, this.packageInfoReader});

  /// Injectable for tests; null means the real platform read.
  final AboutPackageInfoReader? packageInfoReader;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // A failed or unimplemented platform read (a harness without the
    // plugin's method channel) degrades to the "unavailable" copy rather
    // than erroring the screen — version display is informational, never
    // a gate.
    try {
      final info = await (widget.packageInfoReader ?? _defaultPackageInfoReader)();
      if (mounted) setState(() => _info = info);
    } catch (_) {
      // Deliberately swallowed: see the method comment.
    }
  }

  String _versionLabel(AppLocalizations l10n) {
    final info = _info;
    if (info == null || info.version.isEmpty) {
      return l10n.settingsAboutVersionUnavailable;
    }
    return l10n.settingsAboutVersion(info.version, info.buildNumber);
  }

  void _openLicenses() {
    showLicensePage(
      context: context,
      applicationName: kAboutApplicationName,
      applicationVersion: _versionLabel(AppLocalizations.of(context)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          key: const ValueKey('about-version-tile'),
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.settingsAboutVersionTitle),
          subtitle: Text(_versionLabel(l10n)),
        ),
        ListTile(
          key: const ValueKey('about-licenses-tile'),
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(l10n.settingsAboutLicensesTitle),
          subtitle: Text(l10n.settingsAboutLicensesSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: _openLicenses,
        ),
      ],
    );
  }
}
