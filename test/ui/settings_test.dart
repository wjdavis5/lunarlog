import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/ui/settings/settings_screen.dart';
import 'package:provider/provider.dart';

class FakeSettingsStore implements SettingsStore {
  final Map<String, String> _values = {};
  final _controllers = <String, StreamController<String?>>{};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async {
    _values[key] = value;
    _controllers[key]?.add(value);
  }

  @override
  Stream<String?> watch(String key) {
    final c = _controllers.putIfAbsent(
      key,
      () => StreamController<String?>.broadcast(),
    );
    return Stream.value(_values[key]).concatWith([c.stream]);
  }
}

extension on Stream<String?> {
  Stream<String?> concatWith(List<Stream<String?>> others) async* {
    yield* this;
    for (final s in others) {
      yield* s;
    }
  }
}

void main() {
  testWidgets('SettingsScreen displays Privacy policy tile and opens dialog',
      (tester) async {
    final settingsStore = FakeSettingsStore();

    await tester.pumpWidget(
      MaterialApp(
        home: Provider<SettingsStore>.value(
          value: settingsStore,
          child: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify relock toggle is present
    expect(find.byKey(const ValueKey('relock-toggle')), findsOneWidget);

    // Verify privacy policy tile is present
    final privacyTile = find.byKey(const ValueKey('privacy-policy-tile'));
    expect(privacyTile, findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Local-first, encrypted, zero tracking'), findsOneWidget);

    // Tap privacy policy tile
    await tester.tap(privacyTile);
    await tester.pumpAndSettle();

    // Verify dialog opened
    expect(find.text('LunarLog Privacy Policy'), findsOneWidget);
    expect(find.textContaining('Local & Encrypted'), findsOneWidget);
    expect(find.textContaining('Zero Ads & Tracking'), findsOneWidget);

    // Tap Close button
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Verify dialog closed
    expect(find.text('LunarLog Privacy Policy'), findsNothing);
  });
}
