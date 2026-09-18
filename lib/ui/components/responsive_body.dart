/// Shared responsive width constraint (issue #262).
///
/// Decision recorded here so it is not re-opened: lunarlog keeps all four
/// orientations and supports wide viewports properly rather than locking to
/// portrait. Reason: the App Store screenshot pass is taken on iPad-sized
/// simulators for some listing requirements, so a portrait lock would only
/// hide the layout problem instead of fixing it.
///
/// Contract: purely presentational. This widget centres its child and caps
/// its width — no behaviour change, no state change, no new dependency.
/// Form surfaces use [kResponsiveBodyMaxWidth]; the month calendar grid
/// (which must stay seven columns — it is a calendar) uses the wider
/// [kCalendarGridMaxWidth] so its cells stay a sane size at 900dp+ without
/// shrinking to a phone-form column.
library;

import 'package:flutter/widgets.dart';

/// Max content width for form surfaces (day sheet, profile dialogs,
/// onboarding/first-run, settings forms).
const double kResponsiveBodyMaxWidth = 560;

/// Max content width for the 7-column month calendar grid. Wider than the
/// form cap: at 560 a 7-column cell is ~79dp, at 720 it is ~102dp — both
/// sane sizes for the fixed 34dp day circle, while an uncapped 900dp
/// viewport would stretch each cell to ~128dp of mostly empty space.
const double kCalendarGridMaxWidth = 720;

/// Centres [child] and caps it at [maxWidth].
///
/// Uses [Align] (top-centre) rather than [Center] so a scrollable child
/// (e.g. a settings [ListView]) anchors to the top instead of centring
/// vertically, while still getting loose constraints it can fill.
///
/// `heightFactor: 1` is deliberate: without it [Align] would expand to the
/// incoming max height, forcing a shrink-wrapped child (a short profile
/// dialog, a day sheet whose content fits) to fill the viewport. With it,
/// width is still the full available width capped at [maxWidth] (the
/// [ConstrainedBox] fills, because nothing shrink-wraps width), but height
/// stays child-driven — the same layout each surface had before the wrap.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = kResponsiveBodyMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
