/// Prediction service: computes [CyclePrediction]s as a map over day-entry
/// repository streams. Nothing is persisted and no write path triggers
/// computation (KTD5) — consumers subscribe, writes re-derive.
library;

import '../models/local_date.dart';
import '../repositories/day_entries_repository.dart';
import 'prediction.dart';

class CyclePredictionService {
  CyclePredictionService(this._dayEntries);

  final DayEntriesRepository _dayEntries;

  /// Recomputed on every emission of the profile's day-entry stream.
  /// [today] is evaluated per emission so long-lived subscriptions stay
  /// correct across midnight; it defaults to the local civil date.
  Stream<CyclePrediction> watch(String profileId, {LocalDate Function()? today}) {
    final todayOf = today ?? LocalDate.today;
    return _dayEntries.watchForProfile(profileId).map(
          (entries) => computePredictionFromEntries(
            entries: entries,
            today: todayOf(),
          ),
        );
  }

  /// One-shot computation from current stored entries.
  Future<CyclePrediction> current(String profileId,
      {LocalDate Function()? today}) async {
    final todayOf = today ?? LocalDate.today;
    return computePredictionFromEntries(
      entries: await _dayEntries.listForProfile(profileId),
      today: todayOf(),
    );
  }
}
