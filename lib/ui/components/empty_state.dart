/// Shared empty-state presentation (issue #187; B-8): illustration slot,
/// title, body, and an optional primary action, for any screen/section
/// whose data has loaded but come back empty (as opposed to still loading,
/// which stays a spinner/skeleton, or failed, which is [InlineError]'s
/// job — see `lib/ui/README.md` for the full rule).
///
/// The illustration slot is deliberately unwired here: #164 (UX-11) owns
/// the bundled illustration set and its provenance decision. Until that
/// lands, callers either pass nothing (a text-only empty state) or their
/// own [Icon]/[Widget] — never a literal asset path invented in this file.
library;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    this.illustration,
    required this.title,
    required this.body,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.titleStyle,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  }) : assert(
         (primaryActionLabel == null) == (onPrimaryAction == null),
         'primaryActionLabel and onPrimaryAction must both be null or both '
         'be set',
       );

  /// Optional illustration/icon slot, rendered above [title]. Left `null`
  /// by every call site in this issue (#164/UX-11 supplies the real
  /// artwork later).
  final Widget? illustration;

  final String title;
  final String body;

  /// Both null (no action) or both set — enforced by the constructor
  /// assert so a caller can never end up with a label and no callback or
  /// vice versa.
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;

  /// Issue #308: overrides the title's default `titleMedium` weight — e.g.
  /// [OverviewPanel]'s not-enough card, which wants its old `headlineSmall`
  /// heading weight back now that it renders through this shared component.
  final TextStyle? titleStyle;

  /// Issue #308: [CrossAxisAlignment.start] left-aligns title/body/action
  /// (and the title/body text itself) instead of the default centred
  /// layout — for callers, like the overview not-enough card, that sit
  /// this component alongside other left-aligned content.
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final content = Center(child: _content(context));
        if (!constraints.hasBoundedHeight) return content;
        // Issue #308: a Scaffold-body use (profile_picker_screen.dart) gets
        // bounded, viewport-sized constraints here — at large text scale
        // the column can grow taller than that without this, overflowing
        // the way the old ListView-based screen never could. A card/panel
        // use (unbounded height from its parent Column) skips this branch
        // and keeps the plain centred layout it had before.
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: content,
          ),
        );
      },
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimaryAction = this.onPrimaryAction;
    final textAlign = crossAxisAlignment == CrossAxisAlignment.start
        ? TextAlign.start
        : TextAlign.center;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LLSpace.space5,
        vertical: LLSpace.space6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: crossAxisAlignment,
        children: [
          if (illustration != null) ...[
            illustration!,
            const SizedBox(height: LLSpace.space4),
          ],
          Semantics(
            header: true,
            child: Text(
              title,
              style: titleStyle ?? theme.textTheme.titleMedium,
              textAlign: textAlign,
            ),
          ),
          const SizedBox(height: LLSpace.space1),
          Text(
            body,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: textAlign,
          ),
          if (onPrimaryAction != null) ...[
            const SizedBox(height: LLSpace.space4),
            FilledButton(
              onPressed: onPrimaryAction,
              child: Text(primaryActionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}
