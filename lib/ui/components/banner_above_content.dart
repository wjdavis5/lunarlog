/// A full-width strip stacked above the app content, in a shape a screen
/// reader can still see (issue #1426).
///
/// Three strips mount in `MaterialApp.builder`, above the Navigator: the web
/// guardrails banner, the QA-build marker, and the pending-invite banner.
/// Each is a `Column` with the strip first and the Navigator in an
/// `Expanded` beneath it. Built with nothing else, that shape hides the
/// strip from assistive technology: every route's modal barrier is a
/// `BlockSemantics`, which drops the semantics of everything painted before
/// it up to the nearest semantics boundary, and with no boundary between
/// the `Column` and the barrier that includes the strip. It stays visible
/// and tappable, and TalkBack or VoiceOver is never told it exists — the
/// pending-invite banner's "Sign In" and close controls included.
///
/// [BannerAboveContent] is that `Column` with the boundaries in place.
library;

import 'package:flutter/widgets.dart';

/// Lays [banner] out above [child], which takes the remaining height.
///
/// Both sides are their own semantics container:
///
/// * [child]'s keeps a `BlockSemantics` inside it (a route's modal barrier)
///   from reaching past the Navigator and dropping [banner].
/// * [banner]'s gives the strip a node with the strip's own bounds. Without
///   it the strip's text merges into the nearest enclosing node, which for
///   a widget in `MaterialApp.builder` is the one covering the whole app.
class BannerAboveContent extends StatelessWidget {
  const BannerAboveContent({
    super.key,
    required this.banner,
    required this.child,
  });

  /// The strip. Sized by its own content.
  final Widget banner;

  /// The app content — in the app, the Navigator.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(container: true, child: banner),
        Expanded(child: Semantics(container: true, child: child)),
      ],
    );
  }
}
