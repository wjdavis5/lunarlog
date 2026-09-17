/// Issue #547: unit tests for the shared retry policy behind
/// `LocalPredictionProjectionPublisher` and `ReminderWindowPublisher` — a
/// replacement for the old fixed-5-minute-retry-on-every-failure shape.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/publish_retry.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

void main() {
  group('isRetryablePublishError', () {
    test('a SocketException is retryable', () {
      expect(isRetryablePublishError(const SocketException('down')), isTrue);
    });

    test('a TimeoutException is retryable', () {
      expect(isRetryablePublishError(TimeoutException('slow')), isTrue);
    });

    test('a PostgREST 5xx status is retryable', () {
      expect(
        isRetryablePublishError(const PostgrestException(
          message: 'server error',
          code: '503',
        )),
        isTrue,
      );
      expect(
        isRetryablePublishError(const PostgrestException(
          message: 'server error',
          code: '500',
        )),
        isTrue,
      );
    });

    test('a PostgREST 4xx status is not retryable', () {
      expect(
        isRetryablePublishError(const PostgrestException(
          message: 'forbidden',
          code: '403',
        )),
        isFalse,
      );
    });

    test('a PostgREST SQLSTATE (5 chars) is not treated as an HTTP status',
        () {
      // 22023 is a SQLSTATE (invalid_parameter_value), not a status code --
      // the three-vs-five-character length check must not misread it.
      expect(
        isRetryablePublishError(
            const PostgrestException(message: 'bad param', code: '22023')),
        isFalse,
      );
    });

    test('a PostgrestException with no code is not retryable', () {
      expect(
        isRetryablePublishError(
            const PostgrestException(message: 'unknown')),
        isFalse,
      );
    });

    test('a generic Exception/StateError/ArgumentError is not retryable', () {
      expect(isRetryablePublishError(Exception('boom')), isFalse);
      expect(isRetryablePublishError(StateError('boom')), isFalse);
      expect(isRetryablePublishError(ArgumentError('boom')), isFalse);
      expect(isRetryablePublishError(TypeError()), isFalse);
    });
  });

  group('exponentialPublishBackoff', () {
    test('doubles from the initial duration on each attempt', () {
      const initial = Duration(minutes: 5);
      const ceiling = Duration(hours: 10); // high enough not to clamp here
      expect(exponentialPublishBackoff(1, initial: initial, ceiling: ceiling),
          initial);
      expect(exponentialPublishBackoff(2, initial: initial, ceiling: ceiling),
          initial * 2);
      expect(exponentialPublishBackoff(3, initial: initial, ceiling: ceiling),
          initial * 4);
      expect(exponentialPublishBackoff(4, initial: initial, ceiling: ceiling),
          initial * 8);
    });

    test('is capped at ceiling and never exceeds it', () {
      const initial = Duration(minutes: 5);
      const ceiling = Duration(minutes: 30);
      // 5 * 2^3 = 40 min, which must clamp to the 30-minute ceiling.
      expect(
        exponentialPublishBackoff(4, initial: initial, ceiling: ceiling),
        ceiling,
      );
      // Higher attempts stay capped, never growing past ceiling.
      expect(
        exponentialPublishBackoff(10, initial: initial, ceiling: ceiling),
        ceiling,
      );
    });

    test('attempt 1 with a zero initial duration is zero delay', () {
      expect(exponentialPublishBackoff(1, initial: Duration.zero),
          Duration.zero);
    });
  });

  group('decidePublishRetry', () {
    test('a retryable error under the attempt cap retries with the given '
        'backoff', () {
      final decision = decidePublishRetry(
        const SocketException('down'),
        StackTrace.current,
        attempt: 1,
        backoff: (a) => const Duration(minutes: 1) * a,
      );
      expect(decision.shouldRetry, isTrue);
      expect(decision.delay, const Duration(minutes: 1));
    });

    test('a retryable error at the attempt cap stops, not retries', () {
      final decision = decidePublishRetry(
        const SocketException('down'),
        StackTrace.current,
        attempt: kMaxPublishRetryAttempts + 1,
        backoff: (a) => const Duration(minutes: 1),
      );
      expect(decision.shouldRetry, isFalse);
      expect(decision.delay, isNull);
    });

    test('a retryable error exactly at the attempt cap still retries '
        '(inclusive boundary)', () {
      final decision = decidePublishRetry(
        const SocketException('down'),
        StackTrace.current,
        attempt: kMaxPublishRetryAttempts,
        backoff: (a) => const Duration(minutes: 1),
      );
      expect(decision.shouldRetry, isTrue);
    });

    test('a custom maxAttempts is honoured', () {
      final decision = decidePublishRetry(
        const SocketException('down'),
        StackTrace.current,
        attempt: 2,
        maxAttempts: 1,
        backoff: (a) => const Duration(minutes: 1),
      );
      expect(decision.shouldRetry, isFalse);
    });

    test('a non-retryable error stops on the very first attempt', () {
      final decision = decidePublishRetry(
        StateError('permanent rejection'),
        StackTrace.current,
        attempt: 1,
      );
      expect(decision.shouldRetry, isFalse);
      expect(decision.delay, isNull);
    });

    test('the default backoff/maxAttempts are exponentialPublishBackoff and '
        'kMaxPublishRetryAttempts', () {
      final retry = decidePublishRetry(
        const SocketException('down'),
        StackTrace.current,
        attempt: 2,
      );
      expect(retry.shouldRetry, isTrue);
      expect(retry.delay, exponentialPublishBackoff(2));

      final stop = decidePublishRetry(
        const SocketException('down'),
        StackTrace.current,
        attempt: kMaxPublishRetryAttempts + 1,
      );
      expect(stop.shouldRetry, isFalse);
    });
  });
}
