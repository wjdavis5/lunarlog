/// Issue #850 (U8): the lens-aware ARB selectors. The subject lens must be
/// byte-identical to the base ARB string (a subject's view is unchanged);
/// the guardian lens must return the third-person variant and differ from
/// the subject's.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/sharing/guardian_lens.dart';
import 'package:lunarlog/l10n/app_localizations_en.dart';
import 'package:lunarlog/ui/l10n/lens_copy.dart';

final AppLocalizationsEn _l10n = AppLocalizationsEn();

void main() {
  group('lens-aware ARB copy (issue #850 U8)', () {
    test('subject lens returns the base ARB string verbatim', () {
      expect(
        lensOverviewEstimateLoadError(_l10n, GuardianLens.subject),
        _l10n.overviewEstimateLoadError,
      );
      expect(
        lensAnalysisLoadError(_l10n, GuardianLens.subject),
        _l10n.analysisLoadError,
      );
      expect(
        lensPredictionsDisabledBody(_l10n, GuardianLens.subject),
        _l10n.predictionsDisabledBody,
      );
      expect(
        lensCycleComparisonNotEnoughBody(_l10n, GuardianLens.subject),
        _l10n.cycleComparisonNotEnoughBody,
      );
      expect(
        lensDaySheetCycleStartDialogBody(
          _l10n,
          GuardianLens.subject,
          17,
          'Medium',
          16,
        ),
        _l10n.daySheetCycleStartDialogBody(17, 'Medium', 16),
      );
    });

    test('guardian lens returns the third-person variant', () {
      expect(
        lensOverviewEstimateLoadError(_l10n, GuardianLens.guardian),
        _l10n.overviewEstimateLoadErrorGuardian,
      );
      expect(
        lensAnalysisLoadError(_l10n, GuardianLens.guardian),
        _l10n.analysisLoadErrorGuardian,
      );
      expect(
        lensPredictionsDisabledBody(_l10n, GuardianLens.guardian),
        _l10n.predictionsDisabledBodyGuardian,
      );
      expect(
        lensCycleComparisonNotEnoughBody(_l10n, GuardianLens.guardian),
        _l10n.cycleComparisonNotEnoughBodyGuardian,
      );
      expect(
        lensDaySheetCycleStartDialogBody(
          _l10n,
          GuardianLens.guardian,
          17,
          'Medium',
          16,
        ),
        _l10n.daySheetCycleStartDialogBodyGuardian(17, 'Medium', 16),
      );
    });

    test('no variant assumes the reader is the subject', () {
      // Every guardian variant must differ from its base string and must not
      // open with the subject-first "your" phrasing (voice-and-copy rule 2).
      final pairs = <String, String>{
        _l10n.overviewEstimateLoadError: _l10n.overviewEstimateLoadErrorGuardian,
        _l10n.analysisLoadError: _l10n.analysisLoadErrorGuardian,
        _l10n.predictionsDisabledBody: _l10n.predictionsDisabledBodyGuardian,
        _l10n.cycleComparisonNotEnoughBody:
            _l10n.cycleComparisonNotEnoughBodyGuardian,
        _l10n.daySheetCycleStartDialogBody(17, 'Medium', 16):
            _l10n.daySheetCycleStartDialogBodyGuardian(17, 'Medium', 16),
      };
      for (final entry in pairs.entries) {
        expect(entry.value, isNot(entry.key));
        expect(
          entry.value.contains('your'),
          isFalse,
          reason: 'guardian variant still says "your": ${entry.value}',
        );
      }
    });
  });
}
