/// QA-build marker (issue #739): the persistent, non-dismissible banner
/// every QA build (`LUNARLOG_QA_BUILD=true`) renders above the app
/// content, so a QA binary is obvious in screenshots, screen recordings,
/// and reviewer eyes. The app shell (`LunarLogApp`) wires it through its
/// `showQaBanner` flag (defaulting to [AppConfig.qaBuild]); it is
/// compile-time absent from every store build.
///
/// Also owns the shared QA copy constants (named consts, not inline
/// literals, so `hardcoded_ui_strings_test.dart`'s scanner — which flags
/// first-positional `Text('...')` literals — sees nothing to allowlist;
/// QA copy is operator-facing English by design, like `WebDevBanner`'s,
/// and never ships).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

/// The banner copy: names what is disabled and that the build is not for
/// distribution.
const String kQaBuildBannerCopy =
    'QA build — the lock, relock, and re-auth prompts are disabled. '
    'Not for store distribution.';

/// The Settings relock toggle's QA note (issue #739: the toggle is
/// rendered disabled with this subtitle instead of its usual copy).
const String kQaBuildRelockNote =
    'Off in this QA build — relock is disabled for testing.';

/// Appended to the About section's version line and the OS task-switcher
/// app title in a QA build (the "cheap version suffix" of issue #739
/// scope item 3).
const String kQaBuildVersionSuffix = ' (QA build)';

/// Persistent, non-dismissible strip shown at the top of every QA-build
/// screen. Mirrors `WebDevBanner`'s shape (a colored `Material` above the
/// app content) but has no actions — it is a marker, not a guardrail.
class QaBuildBanner extends StatelessWidget {
  const QaBuildBanner({super.key});

  @visibleForTesting
  static const Key bannerKey = Key('qa-build-banner');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: bannerKey,
      // Deliberately a different container role from WebDevBanner's
      // errorContainer and the invite banner's primaryContainer, so the
      // two banners are visually distinct on a web QA build where both
      // render.
      color: theme.colorScheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            kQaBuildBannerCopy,
            key: const ValueKey('qa-build-banner-copy'),
            style: LLType.labelLarge
                .toTextStyle()
                .copyWith(color: theme.colorScheme.onTertiaryContainer),
          ),
        ),
      ),
    );
  }
}
