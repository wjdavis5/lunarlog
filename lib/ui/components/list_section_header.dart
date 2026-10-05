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
      // A heading, and a node of its own. Without `container` the title
      // is folded into whatever it sits beside, and the heading flag lands
      // there with it. See [ListSectionGroup] for the other half.
      child: Semantics(
        header: true,
        container: true,
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A titled section that is one child of a list: its [ListSectionHeader]
/// and the rows beneath it, as a plain group to a screen reader.
///
/// A list child is a semantics node. Left to itself that node takes the
/// section's first control into itself: the whole section becomes that
/// control's button, with the title and every later row inside it, and a
/// screen reader reaches the title after the control it heads. Settings'
/// Health section was one button the size of the section, "Health, Health
/// Connect sync, ...". `explicitChildNodes` keeps the section a group:
/// the title first, then each row as a node of its own.
class ListSectionGroup extends StatelessWidget {
  const ListSectionGroup({super.key, required this.child});

  /// The section: a [ListSectionHeader] followed by its rows.
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, explicitChildNodes: true, child: child);
}
