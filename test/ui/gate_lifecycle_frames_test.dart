/// Pins the Flutter SDK mechanics the #121 fix in
/// `integration_test/gate_test.dart` depends on: driving the binding into
/// `hidden`/`paused` disables frame scheduling (host-mode pumps then render
/// nothing until a frame is forced), while `inactive`/`resumed` keep frames
/// enabled. If a future SDK changes any of this, the real-simulator gate
/// run starts hanging (or over-rendering) again and this file names the
/// reason before anyone has to rediscover it from a stuck CI job.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe();

  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe>
    with WidgetsBindingObserver {
  late String state = WidgetsBinding.instance.lifecycleState?.name ?? 'resumed';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    setState(() => state = s.name);
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(state),
      );
}

void main() {
  testWidgets('hidden/paused disable frame scheduling; a forced frame is '
      'what lets a pump render; inactive/resumed re-enable frames',
      (tester) async {
    await tester.pumpWidget(const _LifecycleProbe());
    await tester.pump();
    expect(find.text('resumed'), findsOneWidget);

    // inactive keeps frames enabled: the observer's setState schedules a
    // frame, and a plain pump renders it.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(tester.binding.framesEnabled, isTrue,
        reason: 'inactive is a focus loss, not a departure (#65 relies on '
            'this never disabling frames)');
    await tester.pump();
    expect(find.text('inactive'), findsOneWidget);

    // hidden disables frames. The observer's setState can no longer
    // schedule anything, so a plain pump renders nothing — the host-mode
    // shadow of #121, where on a live device binding that same pump waits
    // for a real engine frame forever.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse,
        reason: 'SchedulerBinding disables frame scheduling for hidden');
    await tester.pump();
    expect(find.text('inactive'), findsOneWidget,
        reason: 'no frame was scheduled, so the rebuild never happened');
    expect(find.text('hidden'), findsNothing);

    // scheduleForcedFrame is the escape hatch: it requests an engine frame
    // regardless of the lifecycle state, and the next pump renders.
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    expect(find.text('hidden'), findsOneWidget);

    // paused keeps frames disabled; the forced-frame path still renders.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(tester.binding.framesEnabled, isFalse);
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    expect(find.text('paused'), findsOneWidget);

    // Walking home: inactive already re-enables frames (the transition out
    // of paused on the way to resumed is why the #121 fix only forces while
    // frames are actually disabled), so plain pumps render again from here.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(tester.binding.framesEnabled, isTrue);
    await tester.pump();
    expect(find.text('inactive'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(tester.binding.framesEnabled, isTrue);
    await tester.pump();
    expect(find.text('resumed'), findsOneWidget);
  });
}
