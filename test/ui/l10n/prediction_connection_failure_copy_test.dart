/// Unit tests for [predictionConnectionFailureCopy] (Issue #545, moved out
/// of `lib/domain/sharing/prediction_connection_service.dart`'s
/// `userFacingMessage` getter). Exercises every [PredictionConnectionFailure]
/// subtype so both halves of the mapper's split switch (see that file's doc
/// comment) are covered, not just the ones incidentally hit by widget
/// tests elsewhere.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/prediction_connection_service.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/prediction_connection_failure_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
  const allFailures = <PredictionConnectionFailure>[
    PredictionConnectionFailure.network(),
    PredictionConnectionFailure.notFound(),
    PredictionConnectionFailure.expired(),
    PredictionConnectionFailure.alreadyAccepted(),
    PredictionConnectionFailure.alreadyGuardian(),
    PredictionConnectionFailure.unauthorized(),
    PredictionConnectionFailure.invalidToken(),
    PredictionConnectionFailure.pregnancyMode(),
    PredictionConnectionFailure.alreadyConnected(),
    PredictionConnectionFailure.oneDirectional(),
    PredictionConnectionFailure.minorProfile(),
    PredictionConnectionFailure.other(),
  ];

  test('every subclass has non-empty copy', () {
    for (final failure in allFailures) {
      expect(
        predictionConnectionFailureCopy(_l10n, failure),
        isNotEmpty,
        reason: '${failure.runtimeType} has empty copy',
      );
    }
  });

  test('every subclass has distinct copy', () {
    final messages = allFailures
        .map((f) => predictionConnectionFailureCopy(_l10n, f))
        .toSet();
    expect(
      messages.length,
      allFailures.length,
      reason: 'two PredictionConnectionFailure subclasses share copy',
    );
  });

  test('network and unauthorized copy is never a raw provider message', () {
    expect(
      predictionConnectionFailureCopy(
        _l10n,
        const PredictionConnectionFailure.network(),
      ),
      'Network error. Please check your connection.',
    );
    expect(
      predictionConnectionFailureCopy(
        _l10n,
        const PredictionConnectionFailure.unauthorized(),
      ),
      'You do not have permission for this action.',
    );
  });
}
