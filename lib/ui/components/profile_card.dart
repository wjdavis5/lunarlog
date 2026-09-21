/// `ProfileCard` (issue #241, B-15; issue #811): one profile row carrying
/// the facts a multi-profile guardian actually scans for — an avatar
/// showing the profile's initials, or a real image when one exists
/// (issue #811), the profile name, a one-line cycle status sourced from
/// [CyclePredictionService] ("Cycle day 14" / "Period, day 2" / "No
/// history yet"), and the #126 shared/pending badges — replacing the
/// picker's former created-date-only `ListTile` (the created date stays
/// as the secondary line under the status).
///
/// Issue #811 withdrew the earlier "no initial, no icon — colour is the
/// identifier, precisely so a minor's name never has to be" stance: this
/// is an app for a family to track cycles together, the name is already
/// rendered next to the avatar, and a bare hash-hue disc made several
/// profiles hard to tell apart. Initials and avatar images are both fine.
/// The deterministic hue remains as the disc's background, but it is no
/// longer the *only* thing distinguishing one profile from another.
///
/// Everything status-shaped is pure and testable with no widget tree:
/// [profileAvatarHue]/[profileAvatarColor] derive the avatar from the
/// profile id alone (djb2 — a stable, cross-platform hash; never
/// `String.hashCode`, which Dart does not guarantee across runs),
/// [profileAvatarInitials] derives the label shown on it, and
/// [profileCycleStatus] maps a [CyclePrediction] onto localized copy,
/// reusing the exact `cycleWheel*` strings the overview wheel renders so
/// the same state never reads two ways in one app. No business logic
/// lives here — the widget only renders what the prediction service
/// already computed.
///
/// Colours follow the repo's theme discipline (#727): no literal hex, the
/// avatar derives from a data hue the same way `LunarLogColors` derives
/// its flow ramp, with a brightness-aware tone pair so both themes keep
/// the avatar glanceable against their own surfaces. The initials' own
/// foreground comes from [profileAvatarOnColor], which picks black or
/// white by WCAG contrast so the label stays legible at every hue in both
/// themes.
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/models/local_date.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/prediction.dart';
import 'package:lunarlog/domain/prediction/prediction_service.dart';
import 'package:lunarlog/domain/sharing/sharing_overview.dart';
import 'package:lunarlog/domain/sharing/sharing_service.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/sharing/pending_invite_badge.dart';
import 'package:lunarlog/ui/theme/lunarlog_colors.dart' show contrastRatio;
import 'package:lunarlog/ui/theme/tokens.dart';

/// The avatar's hue for [profileId], in `[0, 360)` — deterministic and
/// stable across runs, devices, and the web VM (djb2 kept under 30 bits
/// so every intermediate stays exactly representable as a web `double`;
/// see the library doc on why `String.hashCode` is deliberately not used).
int profileAvatarHue(String profileId) {
  var hash = 5381;
  for (final codeUnit in profileId.codeUnits) {
    hash = ((hash << 5) + hash + codeUnit) & 0x3FFFFFFF;
  }
  return hash % 360;
}

/// The avatar's disc colour at [hue] under [brightness] (issue #811):
/// [profileAvatarColor]'s hue-driven core, exposed separately so contrast
/// can be verified across the whole generated palette rather than a few
/// sampled profile ids. Saturation/lightness are fixed per brightness so
/// the disc always separates from the list background; the label drawn on
/// it takes [profileAvatarOnColor].
Color profileAvatarColorForHue(double hue, Brightness brightness) {
  return brightness == Brightness.light
      ? HSLColor.fromAHSL(1, hue, 0.45, 0.44).toColor()
      : HSLColor.fromAHSL(1, hue, 0.30, 0.62).toColor();
}

/// The avatar's disc colour for [profileId] under [brightness]. The hue is
/// [profileAvatarHue]; saturation/lightness are fixed per brightness so
/// the disc always separates from the list background.
Color profileAvatarColor(String profileId, Brightness brightness) =>
    profileAvatarColorForHue(
      profileAvatarHue(profileId).toDouble(),
      brightness,
    );

/// The foreground for an avatar label drawn on [background] (issue #811):
/// whichever of black/white has the greater WCAG contrast. The two
/// extremes always reach at least ~4.58:1 against any colour, so an
/// initial can never be illegible regardless of the profile's hue. Mirrors
/// `_ToneOnTone` in `lunarlog_colors.dart`; `test/ui/components/
/// profile_card_test.dart` sweeps every generated colour to hold it.
Color profileAvatarOnColor(Color background) =>
    contrastRatio(background, Colors.black) >=
            contrastRatio(background, Colors.white)
        ? Colors.black
        : Colors.white;

/// The one-or-two initials [ProfileAvatar] draws for [displayName] (issue
/// #811), or null for a blank/whitespace name (the avatar then falls back
/// to a person glyph rather than a bare disc).
///
/// Takes the first code point of the first word plus the first code point
/// of the last word when there is more than one word ("Alice Mae Smith" ->
/// "AS"), else just the first word's ("Alice" -> "A"). Splitting is on
/// Unicode whitespace and extraction is by code point, not UTF-16 code
/// unit — an emoji or a character outside the BMP yields one whole
/// character instead of half a surrogate pair. Upper-casing is a no-op for
/// scripts and emoji that have no case.
String? profileAvatarInitials(String displayName) {
  final words = displayName
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) return null;
  final first = _firstCodePoint(words.first);
  if (words.length == 1) return first.toUpperCase();
  return (first + _firstCodePoint(words.last)).toUpperCase();
}

String _firstCodePoint(String word) => String.fromCharCode(word.runes.first);

/// The one-line cycle status for a picker/switcher row (issue #241),
/// from the prediction the [CyclePredictionService] already computed —
/// or null while the first emission has not landed (and for a null
/// prediction, which a not-yet-emitted stream produces; callers render
/// no status line rather than guessing).
///
/// Reuses the overview wheel's exact `cycleWheel*` copy so the same state
/// reads identically everywhere it appears; the three #241-specific
/// strings (no history / suppressed / turned off) live in the ARB
/// alongside them. Issue #982: a stale history ([ActivePrediction
/// .staleHistory], #859) renders the neutral "No recent period logged"
/// instead of the rolled day count.
String? profileCycleStatus({
  required CyclePrediction? prediction,
  required AppLocalizations l10n,
}) {
  switch (prediction) {
    case null:
      return null;
    case final ActivePrediction active:
      // Issue #982: a stale history's rolled "Cycle day N" is the count
      // #859's overview card deliberately hides — the row reads the same
      // neutral line instead, off the same flag (never re-derived).
      if (active.staleHistory) return l10n.profileStatusNoRecentPeriod;
      // During a logged bleed, `cycleDay` *is* the period day (it counts
      // from the episode start), so both lines come from the same field.
      return active.duringEpisode
          ? l10n.cycleWheelPhasePeriodDay(active.cycleDay)
          : l10n.cycleWheelCenterCycleDay(active.cycleDay);
    case NotEnoughHistory():
      return l10n.profileStatusNoHistory;
    case PredictionsSuppressed():
      return l10n.profileStatusPredictionsSuppressed;
    case PredictionsDisabled():
      return l10n.profileStatusPredictionsOff;
  }
}

/// The profile avatar (B-15; issue #811): [profileAvatarInitials] drawn on
/// the deterministic [profileAvatarColor] disc, or [imageProvider] when the
/// profile has a real avatar image. This replaces the original bare-hue
/// disc — see the library doc for the #811 decision that withdrew the
/// "no initial" stance.
///
/// The avatar is decorative: every call site renders the profile's name
/// beside it, so it is excluded from semantics wholesale rather than
/// announced as a second element repeating that name (the same merging
/// discipline `chip_semantics.dart` applies to chips). No profile carries
/// an image today; [imageProvider] is the presentation seam that lets one
/// render here when an image source exists.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profileId,
    required this.displayName,
    this.imageProvider,
    this.radius = 20,
  });

  final String profileId;

  /// The name [profileAvatarInitials] draws from.
  final String displayName;

  /// A real avatar image, when the profile has one; the initials render
  /// otherwise.
  final ImageProvider? imageProvider;

  /// Visual radius; the picker row uses the 40dp Material list avatar.
  final double radius;

  @override
  Widget build(BuildContext context) {
    final background = profileAvatarColor(
      profileId,
      Theme.of(context).colorScheme.brightness,
    );
    final foreground = profileAvatarOnColor(background);
    final initials = profileAvatarInitials(displayName);
    return ExcludeSemantics(
      child: CircleAvatar(
        key: ValueKey('profile-avatar-$profileId'),
        radius: radius,
        backgroundColor: background,
        backgroundImage: imageProvider,
        // The image carries the avatar when there is one; otherwise the
        // initials, or a person glyph for a blank name.
        child: imageProvider != null ? null : _label(initials, foreground),
      ),
    );
  }

  Widget _label(String? initials, Color foreground) {
    if (initials == null) {
      return Icon(Icons.person, size: radius * 1.1, color: foreground);
    }
    return Text(
      initials,
      // The disc is a fixed size, so its label must not grow with the
      // user's text scale and spill out of the circle.
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        color: foreground,
        fontSize: radius * 0.9,
        fontWeight: FontWeight.w600,
        height: 1,
      ),
    );
  }
}

/// The status line for one profile, subscribed to that profile's
/// [CyclePredictionService.watch] stream. Stateful so the stream is
/// created once per (profile, service) pair rather than on every build —
/// `watch()` builds a fresh combine graph per call.
class ProfileCycleStatusText extends StatefulWidget {
  const ProfileCycleStatusText({
    super.key,
    required this.profileId,
    required this.predictionService,
    this.todayProvider = LocalDate.today,
    this.style,
  });

  final String profileId;
  final CyclePredictionService predictionService;
  final LocalDate Function() todayProvider;
  final TextStyle? style;

  @override
  State<ProfileCycleStatusText> createState() => _ProfileCycleStatusTextState();
}

class _ProfileCycleStatusTextState extends State<ProfileCycleStatusText> {
  late Stream<CyclePrediction> _predictions;

  @override
  void initState() {
    super.initState();
    _predictions = widget.predictionService.watch(
      widget.profileId,
      today: widget.todayProvider,
    );
  }

  @override
  void didUpdateWidget(ProfileCycleStatusText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId ||
        oldWidget.predictionService != widget.predictionService) {
      _predictions = widget.predictionService.watch(
        widget.profileId,
        today: widget.todayProvider,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CyclePrediction>(
      stream: _predictions,
      builder: (context, snapshot) {
        final status = profileCycleStatus(
          prediction: snapshot.data,
          l10n: AppLocalizations.of(context),
        );
        if (status == null) return const SizedBox.shrink();
        return Text(
          status,
          key: ValueKey('profile-cycle-status-${widget.profileId}'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: widget.style,
        );
      },
    );
  }
}

/// The profile row (issue #241): [ProfileAvatar] + name + the
/// [ProfileCycleStatusText] status line + the #126 shared/pending badges
/// + the caller's own trailing control (the picker's overflow menu).
///
/// The badge assembly mirrors `ProfileSharingTile`'s (this issue's card
/// is that tile plus avatar/status; the settings section keeps the bare
/// tile), keys included, so #126's tests and semantics carry over
/// unchanged.
class ProfileCard extends StatelessWidget {
  const ProfileCard({
    super.key,
    required this.profile,
    required this.info,
    this.predictionService,
    this.todayProvider = LocalDate.today,
    this.subtitle,
    this.subtitleExtra,
    this.sharingService,
    this.refreshToken = 0,
    this.onTap,
    this.trailing,
  });

  final Profile profile;
  final SharingProfileInfo info;

  /// Null in an unconfigured tree (or a bare test harness): no status
  /// line renders — never a guessed "No history yet" for a profile whose
  /// entries were simply never asked about.
  final CyclePredictionService? predictionService;

  final LocalDate Function() todayProvider;

  /// Secondary line under the status (issue #126's role subtitle, or the
  /// picker's created-date fallback) — rendered in the theme's small
  /// variant style so the status reads as the primary fact.
  final String? subtitle;

  /// Issue #803: an optional widget rendered under [subtitle] in the
  /// subtitle column (the household view's per-profile signal lines —
  /// timing / silence / changes). The caller owns its subscriptions; the
  /// card only places it, so a plain picker row (null) renders exactly as
  /// before.
  final Widget? subtitleExtra;

  /// Null when the build has no sharing service: the row still renders
  /// its local shared state, but no badge is fetched.
  final SharingService? sharingService;

  /// From the owning screen's `SharingOverviewController.badgeEpoch`.
  final int refreshToken;

  final VoidCallback? onTap;

  /// The caller's own trailing control, rendered after the indicator and
  /// badge (the picker's row menu) — the overflow menu this issue
  /// preserves.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = predictionService;
    final subtitleText = subtitle;
    final trailingRow = _trailingRow();
    return ListTile(
      leading: ProfileAvatar(
        profileId: profile.id,
        displayName: profile.displayName,
      ),
      title: Text(profile.displayName),
      subtitle: _subtitle(theme, service, subtitleText, subtitleExtra),
      isThreeLine: service != null && subtitleText != null,
      onTap: onTap,
      trailing: trailingRow,
    );
  }

  /// The #126 badge assembly (mirroring `ProfileSharingTile`) plus the
  /// caller's own trailing control, or null when nothing renders.
  Widget? _trailingRow() {
    final showBadge = sharingService != null &&
        SharingProfileInfo.canShowPendingBadge(info.myRole);
    final showIndicator = info.isCoManaged;
    final extraTrailing = trailing;
    if (!showBadge && !showIndicator && extraTrailing == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showIndicator) _sharedIndicator(),
        if (showBadge) ...[
          const SizedBox(width: 8),
          PendingInviteBadge(
            key: ValueKey('pending-invite-badge-${profile.id}'),
            profileId: profile.id,
            sharingService: sharingService!,
            refreshToken: refreshToken,
          ),
        ],
        if (extraTrailing != null) ...[
          const SizedBox(width: 4),
          extraTrailing,
        ],
      ],
    );
  }

  Widget _sharedIndicator() => Tooltip(
        message: 'Shared · ${info.acceptedCount} guardians',
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              key: ValueKey('shared-indicator-${profile.id}'),
            ),
            const SizedBox(width: 2),
            Text('${info.acceptedCount}'),
          ],
        ),
      );

  /// The status line (when a prediction service exists) plus the caller's
  /// secondary line, stacked small-under-primary, plus the caller's own
  /// extra widget (issue #803's signal lines) under both.
  Widget? _subtitle(
    ThemeData theme,
    CyclePredictionService? service,
    String? subtitleText,
    Widget? subtitleExtra,
  ) {
    if (service == null) {
      if (subtitleText == null && subtitleExtra == null) return null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (subtitleText != null) Text(subtitleText),
          ?subtitleExtra,
        ],
      );
    }
    final secondary = subtitleText == null
        ? null
        : Text(
            subtitleText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ProfileCycleStatusText(
          profileId: profile.id,
          predictionService: service,
          todayProvider: todayProvider,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (secondary != null) ...[
          const SizedBox(height: LLSpace.space1),
          secondary,
        ],
        if (subtitleExtra != null) ...[
          const SizedBox(height: LLSpace.space1),
          subtitleExtra,
        ],
      ],
    );
  }
}
