/// Tests for the binary combineLatest helper (issue #132): wait for both,
/// re-emit on either, forward errors, and release both subscriptions on
/// cancel.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/util/combine_latest.dart';

void main() {
  test('nothing emits until both sources have emitted', () async {
    final a = StreamController<int>();
    final b = StreamController<String>();
    final seen = <(int, String)>[];
    final sub = combineLatest2(a.stream, b.stream).listen(seen.add);
    addTearDown(sub.cancel);
    addTearDown(a.close);
    addTearDown(b.close);

    a.add(1);
    await pumpEventQueue();
    expect(seen, isEmpty, reason: 'b has not emitted yet');

    b.add('x');
    await pumpEventQueue();
    expect(seen, [(1, 'x')]);
  });

  test('re-emits on every later event from either side, with the latest '
      'of the other', () async {
    final a = StreamController<int>(sync: true);
    final b = StreamController<String>(sync: true);
    final seen = <(int, String)>[];
    final sub = combineLatest2(a.stream, b.stream).listen(seen.add);
    addTearDown(sub.cancel);
    addTearDown(a.close);
    addTearDown(b.close);

    a
      ..add(1)
      ..add(2);
    b.add('x');
    a.add(3);
    b
      ..add('y')
      ..add('z');
    await pumpEventQueue();
    expect(seen, [(2, 'x'), (3, 'x'), (3, 'y'), (3, 'z')]);
  });

  test('errors from either side are forwarded', () async {
    final a = StreamController<int>(sync: true);
    final b = StreamController<String>(sync: true);
    final errors = <Object>[];
    final sub = combineLatest2(
      a.stream,
      b.stream,
    ).listen((pair) {}, onError: errors.add);
    addTearDown(sub.cancel);
    addTearDown(a.close);
    addTearDown(b.close);

    a.addError(StateError('left'));
    b.addError(StateError('right'));
    await pumpEventQueue();
    expect(errors, hasLength(2));
  });

  test('cancelling the output cancels both subscriptions', () async {
    final a = StreamController<int>();
    final b = StreamController<String>();
    final sub = combineLatest2(a.stream, b.stream).listen((pair) {});
    a.add(1);
    b.add('x');
    await pumpEventQueue();
    await sub.cancel();
    expect(a.hasListener, isFalse);
    expect(b.hasListener, isFalse);
    await a.close();
    await b.close();
  });

  test('closes once both sources have closed', () async {
    final a = StreamController<int>(sync: true);
    final b = StreamController<String>(sync: true);
    var done = false;
    final sub = combineLatest2(
      a.stream,
      b.stream,
    ).listen((pair) {}, onDone: () => done = true);
    a.add(1);
    b.add('x');
    await a.close();
    await pumpEventQueue();
    expect(done, isFalse, reason: 'b is still open');

    await b.close();
    await pumpEventQueue();
    expect(done, isTrue);
    await sub.cancel();
  });
}
