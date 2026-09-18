/// Drag-dismiss header wrapper for modal bottom sheets (issue #763).
///
/// A downward drag started over a sheet's scrollable content is claimed by
/// the scroll view, so only the ~24px drag handle dismisses the sheet.
/// Wrapping the sheet's non-interactive header chrome in this widget gives
/// that chrome its own explicit dismiss gesture: a downward fling (or a
/// sustained downward drag past the distance threshold) pops the sheet's
/// route, while taps, upward drags, and small jitter do nothing.
///
/// Deliberately scoped to header chrome only — callers must not wrap chips,
/// text fields, or scrollable content in this, or those controls would lose
/// their own gestures. The sheet's scroll behaviour is untouched (this sits
/// outside any scroll view at the call site), and the existing drag handle
/// keeps working (the sheet's own `showDragHandle` path is unchanged).
library;

import 'package:flutter/material.dart';

/// Downward velocity (logical px/s) that counts as a dismiss fling.
@visibleForTesting
const double kSheetDragDismissVelocity = 300;

/// Downward drag distance (logical px) that counts as a deliberate dismiss
/// even without fling velocity.
@visibleForTesting
const double kSheetDragDismissDistance = 60;

class SheetDragHeader extends StatefulWidget {
  const SheetDragHeader({super.key, required this.child});

  final Widget child;

  @override
  State<SheetDragHeader> createState() => _SheetDragHeaderState();
}

class _SheetDragHeaderState extends State<SheetDragHeader> {
  double _dragDy = 0;

  void _onDragUpdate(DragUpdateDetails details) {
    // Only accumulate downward movement; an upward correction cancels the
    // pending dismiss distance rather than banking it.
    _dragDy = (_dragDy + details.delta.dy).clamp(0, double.infinity);
    if (_dragDy >= kSheetDragDismissDistance) {
      _dragDy = 0;
      _dismiss();
    }
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    _dragDy = 0;
    if (velocity >= kSheetDragDismissVelocity) _dismiss();
  }

  void _onDragCancel() {
    _dragDy = 0;
  }

  void _dismiss() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      onVerticalDragCancel: _onDragCancel,
      child: widget.child,
    );
  }
}
