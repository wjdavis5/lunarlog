library;

import 'package:flutter/material.dart';

/// A filled button styled with the theme's error colors for irreversible,
/// destructive actions (issue #250).
///
/// Ensures destructive confirmations never style the irreversible action as
/// the brand-primary default button, keeping Cancel as the visually calm default.
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.icon,
  });

  /// Icon constructor variant for [DestructiveButton].
  const DestructiveButton.icon({
    super.key,
    required this.onPressed,
    required Widget this.icon,
    required Widget label,
  }) : child = label;

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = FilledButton.styleFrom(
      backgroundColor: theme.colorScheme.error,
      foregroundColor: theme.colorScheme.onError,
    );

    if (icon != null) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: style,
        icon: icon!,
        label: child,
      );
    }

    return FilledButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}
