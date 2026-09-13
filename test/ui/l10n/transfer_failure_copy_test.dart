/// Unit tests for [transferFailureCopy] (Issue #545, moved out of
/// `lib/domain/sharing/ownership_transfer_service.dart`'s
/// `userFacingMessage` getters).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/ownership_transfer_service.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/transfer_failure_copy.dart';

final _l10n = AppLocalizationsEn();

void main() {
  const allFailures = <TransferFailure>[
    TransferFailure.network(),
    TransferFailure.notFound(),
    TransferFailure.expired(),
    TransferFailure.cancelled(),
    TransferFailure.alreadyAccepted(),
    TransferFailure.selfTransfer(),
    TransferFailure.staleOwner(),
    TransferFailure.alreadyArmed(),
    TransferFailure.unauthorized(),
    TransferFailure.invalidToken(),
    TransferFailure.other(),
  ];

  test('every subclass has non-empty copy', () {
    for (final failure in allFailures) {
      expect(
        transferFailureCopy(_l10n, failure),
        isNotEmpty,
        reason: '${failure.runtimeType} has empty copy',
      );
    }
  });

  test('every subclass has distinct copy', () {
    final messages = allFailures
        .map((f) => transferFailureCopy(_l10n, f))
        .toSet();
    expect(
      messages.length,
      allFailures.length,
      reason: 'two TransferFailure subclasses share copy',
    );
  });
}
