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

/// Combines [a], [b], and [c] into a stream of their latest triple —
/// the same semantics as [combineLatest2] (nothing until all three have
/// emitted; every later event re-emits the latest triple; errors forward;
/// output closes once all three close). Added for issue #233, where the
/// prediction combine gained the profile's birth-control state alongside
/// its day-entry history and cycle facts.
Stream<(A, B, C)> combineLatest3<A, B, C>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
) {
  late final StreamController<(A, B, C)> controller;
  StreamSubscription<A>? aSub;
  StreamSubscription<B>? bSub;
  StreamSubscription<C>? cSub;
  A? latestA;
  B? latestB;
  C? latestC;
  var seenA = false;
  var seenB = false;
  var seenC = false;
  var doneA = false;
  var doneB = false;
  var doneC = false;

  void maybeClose() {
    if (doneA && doneB && doneC && !controller.isClosed) {
      controller.close();
    }
  }

  void maybeEmit() {
    if (seenA && seenB && seenC && !controller.isClosed) {
      controller.add((latestA as A, latestB as B, latestC as C));
    }
  }

  controller = StreamController<(A, B, C)>(
    onListen: () {
      aSub = a.listen(
        (value) {
          latestA = value;
          seenA = true;
          maybeEmit();
        },
        onError: controller.addError,
        onDone: () {
          doneA = true;
          maybeClose();
        },
      );
      bSub = b.listen(
        (value) {
          latestB = value;
          seenB = true;
          maybeEmit();
        },
        onError: controller.addError,
        onDone: () {
          doneB = true;
          maybeClose();
        },
      );
      cSub = c.listen(
        (value) {
          latestC = value;
          seenC = true;
          maybeEmit();
        },
        onError: controller.addError,
        onDone: () {
          doneC = true;
          maybeClose();
        },
      );
    },
    onCancel: () async {
      await aSub?.cancel();
      await bSub?.cancel();
      await cSub?.cancel();
    },
  );
  return controller.stream;
}

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
