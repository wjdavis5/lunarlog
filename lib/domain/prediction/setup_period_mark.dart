/// The day a calendar marks as "last period start from setup" (issue #1469).
///
/// It lives in the domain layer, not beside the app's month grid, because
/// two calendars draw the mark: the app's and the web client's (issue
/// #1476). The web reads it through `tool/web_domain/facade.dart`, so both
/// take the same answer from this one function and neither restates the
/// rules.
library;

import '../models/local_date.dart';
import 'prediction.dart';

/// The day to mark as "last period start from setup", or null when there
/// is nothing to mark.
///
/// The decision is the engine's, read off [prediction] and never re-derived
/// by a caller: [ActivePrediction.cycleStartIsSupplied] says the current
/// cycle still counts from the date given at setup, and
/// [ActivePrediction.lastEpisodeStart] is that date. So the mark follows
/// the estimate everywhere the estimate is withheld — estimates turned off
/// ([PredictionsDisabled]), a life-stage mode or continuous method that
/// suppresses them ([PredictionsSuppressed]), answers that cannot seed one
/// ([NotEnoughHistory]) — and goes away once a logged period takes over as
/// the cycle start or real cycles displace the seed.
///
/// A stale history ([ActivePrediction.staleHistory], issue #859) hides it
/// too: the calendars already withhold the whole forecast off that flag
/// (issue #982), and an input to an estimate that is no longer shown has
/// nothing left to explain. A supplied date after [today] is never marked —
/// future cells keep their own rendering.
///
/// A caller still has one thing to check for itself: a day with a logged
/// entry shows what was logged, not the mark.
LocalDate? setupPeriodMarkDateFor(
  CyclePrediction prediction,
  LocalDate today,
) => switch (prediction) {
  ActivePrediction(
    cycleStartIsSupplied: true,
    staleHistory: false,
    :final lastEpisodeStart,
  )
      when !lastEpisodeStart.isAfter(today) =>
    lastEpisodeStart,
  _ => null,
};
