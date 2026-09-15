/// The per-type custom notification text editor (Issue #184): a title and
/// a body field for one reminder type, plus a live OS-notification-styled
/// preview that re-renders on every keystroke showing exactly what the OS
/// will present — nothing more.
///
/// Discretion posture (the issue's hard constraint): the text is manual
/// user-authored copy. There is no templating, no placeholder syntax, and
/// no interpolation of a profile name or date anywhere on this screen —
/// the preview renders the two fields' effective values (typed text, else
/// the generic defaults) verbatim, and the saved values round-trip into
/// `ReminderTypeConfig.customTitle`/`customBody` exactly as typed (blank
/// clears back to the default). Pushed from a reminder type's
/// "Notification text" row in the reminder settings; names its route
/// through [kRouteReminderTextEditorScreen] via [buildNamedRoute] (it
/// needs per-type data, so it lives at its push site, not in `kAppRoutes`
/// — the `ManageGuardiansScreen` shape).
library;

import 'package:flutter/material.dart';
import 'package:lunarlog/domain/notifications/reminder_config.dart';
import 'package:lunarlog/domain/notifications/scheduling.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/observability/route_names.dart';
import 'package:lunarlog/ui/routes.dart';
import 'package:lunarlog/ui/theme/tokens.dart';

/// The editor's saved result (Issue #184): the trimmed custom title/body,
/// each null when left blank (blank = fall back to the generic default,
/// so no reminder type is ever left without valid text).
typedef ReminderTextEditorResult = ({String? title, String? body});

/// Pushes the editor for [kind] and awaits its result; null means the
/// user dismissed without saving.
Future<ReminderTextEditorResult?> pushReminderTextEditor(
  BuildContext context, {
  required ReminderTypeConfig typeConfig,
}) =>
    Navigator.of(context).push<ReminderTextEditorResult>(
      buildNamedRoute(
        name: kRouteReminderTextEditorScreen,
        builder: (_) => ReminderTextEditorScreen(typeConfig: typeConfig),
      ),
    );

class ReminderTextEditorScreen extends StatefulWidget {
  const ReminderTextEditorScreen({
    super.key,
    required this.typeConfig,
  });

  final ReminderTypeConfig typeConfig;

  @override
  State<ReminderTextEditorScreen> createState() =>
      _ReminderTextEditorScreenState();
}

class _ReminderTextEditorScreenState extends State<ReminderTextEditorScreen> {
  late final TextEditingController _title =
      TextEditingController(text: widget.typeConfig.customTitle ?? '');
  late final TextEditingController _body =
      TextEditingController(text: widget.typeConfig.customBody ?? '');

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  /// The in-progress text as the preview shows it: typed custom copy,
  /// else the generic defaults — exactly what the OS will present, computed
  /// through the very same [resolveReminderText] the planner uses, so the
  /// preview can never drift from the delivered notification.
  ReminderText get _effective => resolveReminderText(
        ReminderTypeConfig(
          enabled: true,
          timeOfDayMinutes: 0,
          customTitle: _title.text,
          customBody: _body.text,
        ),
      );

  /// The save result: trimmed custom text, each null when blank (blank =
  /// fall back to the generic default, so no type is ever left without
  /// valid text).
  ReminderTextEditorResult get _trimmed => (
        title: _title.text.trim().isEmpty ? null : _title.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
      );

  void _save() => Navigator.of(context).pop<ReminderTextEditorResult>(_trimmed);

  void _resetToDefault() {
    // Clears the fields rather than popping: the preview immediately
    // shows the generic defaults, and Save is what commits the fallback.
    _title.clear();
    _body.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.reminderTextEditorAppBarTitle),
        actions: [
          TextButton(
            key: const ValueKey('reminder-text-save'),
            onPressed: _save,
            child: Text(l10n.reminderTextSaveButton),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(LLSpace.space4),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: LLSpace.space2),
              child: Text(
                l10n.reminderTextPreviewSection,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            // Live preview: rebuilds on every keystroke through
            // Listenable.merge over both controllers.
            AnimatedBuilder(
              animation: Listenable.merge([_title, _body]),
              builder: (context, _) =>
                  ReminderNotificationPreview(text: _effective),
            ),
            const SizedBox(height: LLSpace.space5),
            TextField(
              key: const ValueKey('reminder-text-title-field'),
              controller: _title,
              maxLength: kMaxReminderCustomTextLength,
              decoration: InputDecoration(
                labelText: l10n.reminderTextTitleLabel,
                // The generic default is what an empty field falls back
                // to — showing it as the hint says so without extra copy.
                hintText: kReminderTitle,
                counterText: '',
              ),
            ),
            const SizedBox(height: LLSpace.space3),
            TextField(
              key: const ValueKey('reminder-text-body-field'),
              controller: _body,
              maxLength: kMaxReminderCustomTextLength,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.reminderTextBodyLabel,
                hintText: kReminderBody,
                counterText: '',
              ),
            ),
            const SizedBox(height: LLSpace.space3),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                key: const ValueKey('reminder-text-reset'),
                onPressed: _resetToDefault,
                child: Text(l10n.reminderTextResetButton),
              ),
            ),
            const SizedBox(height: LLSpace.space2),
            Text(
              l10n.reminderTextDiscretionNote,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// An OS-notification-styled preview (Issue #184): the banner shape a
/// delivered notification takes — header row (app identity and a "now"
/// timestamp), bold title, body — rendering [text] verbatim and nothing
/// else. Theme tokens only: every color comes from the ambient
/// [ColorScheme], so the preview follows light/dark like the rest of the
/// app rather than pinning one OS's chrome colors.
class ReminderNotificationPreview extends StatelessWidget {
  const ReminderNotificationPreview({super.key, required this.text});

  final ReminderText text;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey('reminder-text-preview'),
      padding: const EdgeInsets.all(LLSpace.space3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(LLRadius.rLg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: LLSpace.space3,
            backgroundColor: scheme.primaryContainer,
            child: Icon(
              Icons.notifications_none_outlined,
              size: LLSpace.space4,
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: LLSpace.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.reminderTextPreviewAppName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.apply(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Text(
                      l10n.reminderTextPreviewNow,
                      style: textTheme.labelSmall?.apply(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: LLSpace.space1),
                Text(
                  text.title,
                  key: const ValueKey('reminder-text-preview-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: LLSpace.space1),
                Text(
                  text.body,
                  key: const ValueKey('reminder-text-preview-body'),
                  style: textTheme.bodyMedium?.apply(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
