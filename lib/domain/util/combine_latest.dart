/// A binary `combineLatest` for watch streams (issue #132).
///
/// `dart:async` ships no combineLatest, and the repo avoids rxdart; the
/// prediction and history services both need "recompute whenever the
/// day-entry stream *or* the omitted-cycles setting changes", so the one
/// helper lives here, pure Dart, with the standard semantics:
///
/// * nothing is emitted until both sources have emitted at least once
///   (both are watch streams that replay their current value on listen);
/// * afterwards every event from either source re-emits the latest pair;
/// * errors from either source are forwarded;
/// * the output closes once both sources have closed, and cancelling the
///   output cancels both subscriptions.
library;

import 'dart:async';

/// Combines [left] and [right] into a stream of their latest pair.
Stream<(A, B)> combineLatest2<A, B>(Stream<A> left, Stream<B> right) {
  late final StreamController<(A, B)> controller;
  StreamSubscription<A>? leftSub;
  StreamSubscription<B>? rightSub;
  A? latestLeft;
  B? latestRight;
  var seenLeft = false;
  var seenRight = false;
  var doneLeft = false;
  var doneRight = false;

  void maybeClose() {
    if (doneLeft && doneRight && !controller.isClosed) {
      controller.close();
    }
  }

  void maybeEmit() {
    if (seenLeft && seenRight && !controller.isClosed) {
      controller.add((latestLeft as A, latestRight as B));
    }
  }

  controller = StreamController<(A, B)>(
    onListen: () {
      leftSub = left.listen(
        (value) {
          latestLeft = value;
          seenLeft = true;
          maybeEmit();
        },
        onError: controller.addError,
        onDone: () {
          doneLeft = true;
          maybeClose();
        },
      );
      rightSub = right.listen(
        (value) {
          latestRight = value;
          seenRight = true;
          maybeEmit();
        },
        onError: controller.addError,
        onDone: () {
          doneRight = true;
          maybeClose();
        },
      );
    },
    onCancel: () async {
      await leftSub?.cancel();
      await rightSub?.cancel();
    },
  );
  return controller.stream;
}
