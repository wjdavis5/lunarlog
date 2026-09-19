/// Widget tests for issue #877: the Settings "Show predictions" toggle must
/// not read ON (and inert) while the profile's life-stage mode — or a
/// continuous birth-control method — has predictions suppressed.
///
/// The predictor owns the suppression policy (#528's
/// `CyclePredictionService.suppressesPrediction` for modes, #233's
/// `birthControlPredictionKind` for methods); these tests pin that the
/// settings tile delegates to it: disabled with a reason subtitle while
/// suppressed, and, crucially, that the stored `showPredictions` flag is left
/// untouched so the user's preference returns when the mode does.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/db/db.dart' show LunarLogDatabase;
import 'package:lunarlog/data/repositories/drift_profile_modes_repository.dart';
import 'package:lunarlog/data/repositories/drift_profiles_repository.dart';
import 'package:lunarlog/data/repositories/drift_settings_store.dart';
import 'package:lunarlog/domain/models/lifecycle_mode.dart';
import 'package:lunarlog/domain/models/profile.dart';
import 'package:lunarlog/domain/prediction/cycle_history.dart';
import 'package:lunarlog/domain/repositories/profile_modes_repository.dart';
import 'package:lunarlog/domain/repositories/profiles_repository.dart';
import 'package:lunarlog/domain/repositories/settings_store.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/profiles/profile_controller.dart';
import 'package:lunarlog/ui/settings/predictions_settings_section.dart';
import 'package:provider/provider.dart';

class _Harness {
  _Harness(this.tester) : db = LunarLogDatabase(NativeDatabase.memory()) {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    profiles = DriftProfilesRepository(db.storage);
    settings = DriftSettingsStore(db.storage);
    modes = DriftProfileModesRepository(db.storage);
  }

  final WidgetTester tester;
  final LunarLogDatabase db;
  late final DriftProfilesRepository profiles;
  late final DriftSettingsStore settings;
  late final DriftProfileModesRepository modes;

  Future<Profile> createProfile(String name) =>
      profiles.create(displayName: name, isMinor: false);

  Future<ProfileController> controller() async {
    final controller = ProfileController(
      profilesRepository: profiles,
      settingsStore: settings,
      profileModesRepository: modes,
    );
    await controller.load();
    return controller;
  }

  Widget appFor(ProfileController controller) {
    return MultiProvider(
      providers: [
        Provider<ProfilesRepository>.value(value: profiles),
        Provider<SettingsStore>.value(value: settings),
        Provider<ProfileModesRepository>.value(value: modes),
        ChangeNotifierProvider<ProfileController>.value(value: controller),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SingleChildScrollView(child: PredictionsSettingsSection()),
        ),
      ),
    );
  }

  AppLocalizations l10n() => AppLocalizations.of(
    tester.element(find.byType(PredictionsSettingsSection)),
  );

  Future<void> dispose() async {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await db.close();
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const suppressing = <LifecycleMode>[
    LifecycleMode.pregnancy,
    LifecycleMode.postpartum,
    LifecycleMode.perimenopause,
  ];

  for (final mode in suppressing) {
    testWidgets(
      '${mode.name}: the toggle is disabled and names the mode as the '
      'reason (issue #877)',
      (tester) async {
        final h = _Harness(tester);
        final profile = await h.createProfile('Alice');
        final c = await h.controller();
        await h.modes.save(profileId: profile.id, mode: mode);

        await tester.pumpWidget(h.appFor(c));
        await tester.pumpAndSettle();

        final toggle = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('predictions-toggle')),
        );
        expect(
          toggle.value,
          isTrue,
          reason: 'the stored flag is untouched and still reads ON',
        );
        expect(
          toggle.onChanged,
          isNull,
          reason: 'a suppressed profile cannot toggle the flag',
        );
        expect(
          find.text(
            h.l10n().settingsPredictionsSuppressedByModeSubtitle(mode.label),
          ),
          findsOneWidget,
          reason: 'the subtitle must name the real cause, not the generic copy',
        );
        expect(find.text(h.l10n().settingsPredictionsSubtitle), findsNothing);

        await h.dispose();
      },
    );
  }

  for (final mode in const [LifecycleMode.tracking, LifecycleMode.conceive]) {
    testWidgets(
      '${mode.name}: the toggle stays enabled with the normal subtitle '
      '(issue #877)',
      (tester) async {
        final h = _Harness(tester);
        final profile = await h.createProfile('Alice');
        final c = await h.controller();
        await h.modes.save(profileId: profile.id, mode: mode);

        await tester.pumpWidget(h.appFor(c));
        await tester.pumpAndSettle();

        final toggle = tester.widget<SwitchListTile>(
          find.byKey(const ValueKey('predictions-toggle')),
        );
        expect(toggle.onChanged, isNotNull);
        expect(find.text(h.l10n().settingsPredictionsSubtitle), findsOneWidget);

        await h.dispose();
      },
    );
  }

  testWidgets(
    'a continuous birth-control method suppresses the toggle and names the '
    'method (issue #877)',
    (tester) async {
      final h = _Harness(tester);
      final profile = await h.createProfile('Alice');
      final c = await h.controller();
      await h.modes.save(
        profileId: profile.id,
        mode: LifecycleMode.tracking,
        birthControlMethod: 'hormonal_iud',
      );

      await tester.pumpWidget(h.appFor(c));
      await tester.pumpAndSettle();

      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('predictions-toggle')),
      );
      expect(toggle.onChanged, isNull);
      final l10n = h.l10n();
      expect(
        find.text(
          l10n.settingsPredictionsSuppressedByMethodSubtitle(
            l10n.birthControlHormonalIud,
          ),
        ),
        findsOneWidget,
      );

      await h.dispose();
    },
  );

  testWidgets('a cyclic (withdrawal-bleed) method does not suppress the toggle '
      '(issue #877)', (tester) async {
    final h = _Harness(tester);
    final profile = await h.createProfile('Alice');
    final c = await h.controller();
    await h.modes.save(
      profileId: profile.id,
      mode: LifecycleMode.tracking,
      birthControlMethod: 'pill',
    );

    await tester.pumpWidget(h.appFor(c));
    await tester.pumpAndSettle();

    final toggle = tester.widget<SwitchListTile>(
      find.byKey(const ValueKey('predictions-toggle')),
    );
    expect(toggle.onChanged, isNotNull);
    expect(find.text(h.l10n().settingsPredictionsSubtitle), findsOneWidget);

    await h.dispose();
  });

  testWidgets(
    'while suppressed the flag cannot be toggled and is unchanged after '
    'the mode is cleared (issue #877 regression)',
    (tester) async {
      final h = _Harness(tester);
      final profile = await h.createProfile('Alice');
      final c = await h.controller();
      await h.settings.set(predictionsEnabledSettingKey(profile.id), 'true');
      await h.modes.save(
        profileId: profile.id,
        mode: LifecycleMode.perimenopause,
      );

      await tester.pumpWidget(h.appFor(c));
      await tester.pumpAndSettle();

      // The switch is disabled: tapping it must not write either way.
      await tester.tap(find.byKey(const ValueKey('predictions-toggle')));
      await tester.pumpAndSettle();
      expect(
        await h.settings.get(predictionsEnabledSettingKey(profile.id)),
        'true',
        reason: 'a suppressed profile must not rewrite the stored preference',
      );

      // Clear the mode: the user's own preference returns.
      await h.modes.save(profileId: profile.id, mode: LifecycleMode.tracking);
      await tester.pumpAndSettle();

      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('predictions-toggle')),
      );
      expect(
        toggle.onChanged,
        isNotNull,
        reason: 'clearing the suppressing mode re-enables the toggle',
      );
      expect(
        toggle.value,
        isTrue,
        reason: 'the stored preference survived the suppressed interval',
      );
      expect(
        await h.settings.get(predictionsEnabledSettingKey(profile.id)),
        'true',
      );

      await h.dispose();
    },
  );
}
