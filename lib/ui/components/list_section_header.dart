/// Shared list section header (issue #813): one header style for every
/// sectioned list — Settings, the profile picker, and Care — so a section
/// title reads identically on every surface instead of being styled (or
/// weighted) per screen. [SettingsSection] wraps it so Settings keeps its
/// own trailing-divider behaviour without the header owning it.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ListSectionHeader extends StatelessWidget {
  const ListSectionHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(
      LLSpace.space4,
      LLSpace.space4,
      LLSpace.space4,
      LLSpace.space1,
    ),
  });

  /// The section header text.
  final String title;

  /// The header's outer padding. Defaults to the standard 16/16/16/4
  /// gutter; a surface whose parent already carries horizontal padding
  /// (the care screen's `ListView(padding: 16)`) overrides it so the title
  /// still aligns with its section's content.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
