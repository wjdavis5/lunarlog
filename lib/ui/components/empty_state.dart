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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onPrimaryAction = this.onPrimaryAction;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: LLSpace.space5,
          vertical: LLSpace.space6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (illustration != null) ...[
              illustration!,
              const SizedBox(height: LLSpace.space4),
            ],
            Text(
              title,
              style: LLType.titleMedium.toTextStyle(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: LLSpace.space1),
            Text(
              body,
              style: LLType.bodyMedium
                  .toTextStyle()
                  .copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
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
      ),
    );
  }
}
