/// The shared Settings section header (Issue #226, from #176's component
/// inventory direction): every section of the restructured Settings screen
/// renders through this one widget so section identity is data (the
/// screen composes an ordered list of these), not layout. The header
/// matches the style `YourDataSection`/`AccountSection` already used
/// (`titleSmall` over a 16/16/16/4 padding), so pre-existing sections
/// could adopt it without a visual change.
///
/// Self-hiding sections (`YourDataSection`, `FamilySharingSection`) host
/// this widget *inside* their own build so the header disappears together
/// with the body — a screen-level header would survive the body's
/// `SizedBox.shrink()` fallback and render an empty section.
library;

import 'package:flutter/material.dart';

import 'list_section_header.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.id,
    required this.title,
    required this.children,
    this.trailingDivider = true,
  });

  /// Stable identifier for the section's `ValueKey`
  /// (`settings-section-<id>`) — widget tests assert section presence and
  /// ordering against it.
  final String id;

  /// The localized section header text.
  final String title;

  /// The section's tiles, in display order.
  final List<Widget> children;

  /// Whether a `Divider` closes the section; true for every section
  /// except where a caller manages its own separation.
  final bool trailingDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: ValueKey('settings-section-$id'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSectionHeader(title: title),
        ...children,
        if (trailingDivider) const Divider(),
      ],
    );
  }
}
