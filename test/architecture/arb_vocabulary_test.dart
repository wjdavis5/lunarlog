/// Issue #999 guard: user-facing copy in `lib/l10n/app_en.arb` must use the
/// established product vocabulary "estimate" (e.g. "Estimated day",
/// "cycle estimates", "estimate reminders", "Estimates paused",
/// "Estimates off"), rather than "prediction" / "predicted".
///
/// The only exception is the prediction-only sharing feature (Issue #151),
/// which uses its domain-specific "prediction sharing" and
/// "prediction connection" terminology.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Keys permitted to use the "prediction" stem in their user-facing values.
/// Every permitted key belongs to the Issue #151 prediction-only sharing
/// feature.
const Set<String> _predictionSharingAllowlist = {
  'predictionConnectionFailurePregnancyMode',
  'predictionConnectionFailureAlreadyConnected',
  'predictionConnectionFailureOneDirectional',
  'predictionConnectionFailureMinorProfile',
  'manageGuardiansEndSharingTooltip',
  'sharingAcceptPredictionTitle',
  'sharingManageGuardiansEndPredictionTitle',
  'sharingManageGuardiansEndPredictionBody',
  'sharingManageGuardiansPredictionSharingEnded',
  'sharingManageGuardiansPredictionsSectionTitle',
  'sharingManageGuardiansPredictionsMinor',
  'sharingManageGuardiansSharePredictionsAction',
  'sharingManageGuardiansPredictionsPrimaryOnly',
  'sharingManageGuardiansSharingPredictions',
  'sharingPredictionConnectionsStopTitle',
  'sharingPredictionConnectionsStopped',
  'sharingPredictionConnectionsEmptyTitle',
  'sharingPredictionConnectionsEmptyBody',
  'sharingPredictionConnectionsCyclePredictions',
  'sharingPredictionCalendarLoadError',
  'sharingPredictionCalendarWaitingBody',
  'sharingPredictionCalendarEndedBody',
  'sharingSharePredictionsSendLink',
  'sharingSharePredictionsTitle',
};

void main() {
  group('ARB vocabulary lint (#999)', () {
    test(
      'user-facing values in app_en.arb do not use "predict*" outside prediction sharing',
      () {
        final arbFile = File('lib/l10n/app_en.arb');
        expect(arbFile.existsSync(), isTrue, reason: 'app_en.arb must exist');

        final content =
            json.decode(arbFile.readAsStringSync()) as Map<String, dynamic>;
        final violations = <String>[];

        for (final entry in content.entries) {
          if (entry.key.startsWith('@')) continue;
          final value = entry.value;
          if (value is! String) continue;

          if (value.toLowerCase().contains('predict') &&
              !_predictionSharingAllowlist.contains(entry.key)) {
            violations.add('${entry.key}: "$value"');
          }
        }

        expect(
          violations,
          isEmpty,
          reason:
              'User-facing strings must use the "estimate" vocabulary rather '
              'than "prediction" / "predicted" (Issue #999). Violations found:\n'
              '${violations.join('\n')}',
        );
      },
    );

    test('allowlist stays minimal and does not contain obsolete keys', () {
      final arbFile = File('lib/l10n/app_en.arb');
      final content =
          json.decode(arbFile.readAsStringSync()) as Map<String, dynamic>;

      for (final key in _predictionSharingAllowlist) {
        expect(
          content.containsKey(key),
          isTrue,
          reason: 'Allowlist key "$key" does not exist in app_en.arb',
        );
        final value = content[key] as String;
        expect(
          value.toLowerCase().contains('predict'),
          isTrue,
          reason:
              'Allowlist key "$key" no longer contains "predict" and should be removed',
        );
      }
    });
  });
}
