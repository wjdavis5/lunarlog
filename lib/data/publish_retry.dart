/// Shared retry policy (issue #547) behind the background "publish this
/// derived snapshot to the server on prediction change" publishers
/// (`LocalPredictionProjectionPublisher`, `ReminderWindowPublisher`) — two
/// copy-pasted implementations that each re-armed a fixed 5-minute retry on
/// *every* failure: no backoff, no attempt cap, and no distinction between
/// a transient network blip and a permanent rejection (a 403 after the
/// sharer revoked access, a malformed payload, a client bug surfacing as a
/// `TypeError`). A sharer hitting a permanent rejection performed a select
/// plus upsert every 5 minutes indefinitely on cellular, per shared
/// profile, forever — nothing ever stopped it, and nothing ever reported
/// it either.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:sentry_flutter/sentry_flutter.dart' show Sentry;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Whether [error] looks transient enough to retry: a socket-level
/// failure, a timeout, or a PostgREST error reporting an HTTP 5xx status.
/// PostgREST stores the HTTP status as [PostgrestException.code] only when
/// the response body carries no SQLSTATE — a SQLSTATE is five characters
/// (`22023`), a status three (`503`) — matching
/// `supabase_sync_transport.dart`'s own status-vs-SQLSTATE distinction.
/// Everything else (a 4xx rejection, a malformed-payload `TypeError`, an
/// `ArgumentError`, …) is treated as permanent: retrying it would never
/// succeed, only waste battery and data on a schedule nothing will ever
/// change.
bool isRetryablePublishError(Object error) {
  if (error is SocketException || error is TimeoutException) return true;
  if (error is PostgrestException) {
    final code = error.code;
    if (code != null && code.length == 3) {
      final status = int.tryParse(code);
      if (status != null && status >= 500) return true;
    }
  }
  return false;
}

/// Exponential backoff, doubling from [initial] on every attempt and
/// capped at [ceiling]. [attempt] is 1 on the first retry.
Duration exponentialPublishBackoff(
  int attempt, {
  Duration initial = const Duration(minutes: 5),
  Duration ceiling = const Duration(minutes: 30),
}) {
  // 1 << 62 would overflow Duration's microsecond range long before this
  // clamp matters at realistic attempt counts, but the clamp keeps this
  // total even if a caller passes an attempt count far past kMaxPublishRetryAttempts.
  final factor = 1 << (attempt - 1).clamp(0, 20);
  final scaled = initial * factor;
  return scaled > ceiling ? ceiling : scaled;
}

/// Retry attempts allowed per pending item before giving up until the next
/// genuine change re-arms it (a fresh prediction resets the count).
const int kMaxPublishRetryAttempts = 5;

/// What a publisher's failure handler should do next: retry after [delay]
/// ([shouldRetry] true), or give up ([shouldRetry] false — [error] has
/// already been captured to Sentry exactly once by
/// [decidePublishRetry]).
class PublishRetryDecision {
  const PublishRetryDecision.retry(this.delay);
  const PublishRetryDecision.stop() : delay = null;

  final Duration? delay;

  bool get shouldRetry => delay != null;
}

/// The shared decision behind both publishers' `_flush` catch blocks.
/// [attempt] is 1 on the first failure for this pending item, incrementing
/// on every consecutive retry of the *same* unchanged item.
///
/// Retries only [isRetryablePublishError] failures, up to [maxAttempts],
/// backing off via [backoff] (exponential by default,
/// [exponentialPublishBackoff]). Every non-retryable error, and the
/// attempt cap being reached, is captured to Sentry exactly once (never
/// repeatedly — a permanently failing item must not spam Sentry once per
/// retry) and reported as [PublishRetryDecision.stop]; the caller must not
/// retry further for this item until a fresh change re-arms it.
PublishRetryDecision decidePublishRetry(
  Object error,
  StackTrace stackTrace, {
  required int attempt,
  Duration Function(int attempt) backoff = exponentialPublishBackoff,
  int maxAttempts = kMaxPublishRetryAttempts,
}) {
  if (isRetryablePublishError(error) && attempt <= maxAttempts) {
    return PublishRetryDecision.retry(backoff(attempt));
  }
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
  return const PublishRetryDecision.stop();
}

/// The shared tail of a publisher's `_flush`/`_flushRetraction` catch
/// block (issues #547/LLA-062), extracted so
/// `LocalPredictionProjectionPublisher` and `ReminderWindowPublisher` stop
/// duplicating it byte-for-byte (both tripped CI's CRAP gate carrying it
/// inline). The caller has already done its own disposed/staleness checks
/// — those are the caller's concerns, not this policy's — and passes in
/// its own per-profile [retryAttempts]/[timers] maps plus [attempt]-
/// independent hooks: [onRetry] reinstates whatever caller-specific
/// pending state the eventual [retry] call will need (run synchronously,
/// before the timer is armed, so a genuine prediction arriving before the
/// timer fires still finds the right thing to overwrite), [retry] is what
/// actually runs when the backoff elapses, and [onGiveUp] does any
/// caller-specific cleanup beyond clearing [retryAttempts] (which this
/// function always does on giving up).
void schedulePublishRetry({
  required String profileId,
  required Object error,
  required StackTrace stackTrace,
  required Map<String, int> retryAttempts,
  required Map<String, Timer> timers,
  required Duration retryDelay,
  required void Function() onRetry,
  required Future<void> Function() retry,
  required void Function() onGiveUp,
}) {
  final attempt = (retryAttempts[profileId] ?? 0) + 1;
  final decision = decidePublishRetry(
    error,
    stackTrace,
    attempt: attempt,
    backoff: (a) => exponentialPublishBackoff(a, initial: retryDelay),
  );
  if (!decision.shouldRetry) {
    retryAttempts.remove(profileId);
    onGiveUp();
    return;
  }
  retryAttempts[profileId] = attempt;
  onRetry();
  timers[profileId]?.cancel();
  timers[profileId] = Timer(decision.delay!, () => unawaited(retry()));
}
