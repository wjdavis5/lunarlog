/// Issue #257: the custom-tag manager sheet — the create flow's
/// validation matrix (duplicate/taxonomy/empty errors rendered as
/// field-level copy, never exceptions), the retire confirmation writing
/// `hidden_at` through the repository, and the retired row's status
/// label.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/logging/custom_tag_registry.dart';
import 'package:lunarlog/domain/repositories/tag_registry_repository.dart';
import 'package:lunarlog/l10n/app_localizations.dart';
import 'package:lunarlog/ui/logging/widgets/custom_tag_manager_sheet.dart';

const profileId = '01J8ZQ9K7MC2X3V4B5N6P7Q8R9';

CustomTag tag(
  String code,
  String label, {
  DateTime? hiddenAt,
}) =>
    CustomTag(
      id: '01J8ZQ9K7MC2X3V4B5N6P7Q${code.length.toString().padLeft(2, '0')}',
      profileId: profileId,
      code: code,
      displayName: label,
      category: 'custom',
      hiddenAt: hiddenAt,
      createdAt: DateTime.utc(2026, 9, 1),
      updatedAt: DateTime.utc(2026, 9, 1),
    );

class FakeRegistry implements TagRegistryRepository {
  FakeRegistry(this.rows, {this.failNextCreate = false});

  List<CustomTag> rows;
  final List<String> retiredIds = [];
  final List<({String tagId, String label})> renames = [];

  /// Simulates a concurrent co-guardian write invalidating the UI's
  /// pre-check (the repository create throwing ArgumentError).
  bool failNextCreate;

  @override
  Future<CustomTag> create({
    required String profileId,
    required String label,
  }) async {
    if (failNextCreate) {
      failNextCreate = false;
      throw ArgumentError.value(label, 'label', 'duplicate');
    }
    final created = tag(customTagCodeFromLabel(label)!, label.trim());
    rows = [...rows, created];
    _controller.add(rows);
    return created;
  }

  @override
  Future<List<CustomTag>> listForProfile(String profileId) async => rows;

  @override
  Future<CustomTag> rename({required String tagId, required String label}) async {
    renames.add((tagId: tagId, label: label));
    final renamed = tag(
      rows.firstWhere((t) => t.id == tagId).code,
      label.trim(),
    );
    rows = [
      for (final t in rows)
        if (t.id == tagId) renamed else t,
    ];
    _controller.add(rows);
    return renamed;
  }

  @override
  Future<void> retire(String tagId) async => retiredIds.add(tagId);

  final StreamController<List<CustomTag>> _controller =
      StreamController<List<CustomTag>>.broadcast();

  @override
  Stream<List<CustomTag>> watchForProfile(String profileId) async* {
    // The repository contract: the watch emits the current rows first,
    // then updates (the drift watch's own behavior).
    yield rows;
    await for (final next in _controller.stream) {
      yield next;
    }
  }
}

Future<AppLocalizations> pumpSheet(
  WidgetTester tester,
  FakeRegistry registry,
) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // A bottom sheet supplies the Material ancestor in production; the
      // bare harness needs a Scaffold for the create TextField.
      home: Scaffold(
        body: CustomTagManagerSheet(
          repository: registry,
          profileId: profileId,
        ),
      ),
    ),
  );
  await tester.pump();
  return AppLocalizations.of(tester.element(find.byType(CustomTagManagerSheet)));
}

void main() {
  testWidgets('create validates before writing: a duplicate renders '
      'field-level copy and writes nothing', (tester) async {
    final registry = FakeRegistry([tag('back_cracking', 'Back cracking')]);
    final l10n = await pumpSheet(tester, registry);

    await tester.enterText(
      find.byKey(const ValueKey('custom-tag-create-field')),
      'BACK CRACKING',
    );
    await tester.tap(find.byKey(const ValueKey('custom-tag-create')));
    await tester.pump();

    expect(find.text(l10n.customTagsErrorDuplicate), findsOneWidget);
    expect(registry.rows, hasLength(1));
  });

  testWidgets('create writes a fresh label and clears the field',
      (tester) async {
    final registry = FakeRegistry(const []);
    await pumpSheet(tester, registry);

    await tester.enterText(
      find.byKey(const ValueKey('custom-tag-create-field')),
      'Vulva pain?!',
    );
    await tester.tap(find.byKey(const ValueKey('custom-tag-create')));
    await tester.pump();

    expect(registry.rows.single.code, 'vulva_pain');
    expect(registry.rows.single.displayName, 'Vulva pain?!');
    expect(
      find
          .byKey(const ValueKey('custom-tag-create-field'))
          .evaluate()
          .single
          .widget,
      isA<TextField>().having((f) => f.controller!.text, 'text', ''),
    );
  });

  testWidgets('retire confirms, then writes hidden_at through the '
      'repository', (tester) async {
    final registry = FakeRegistry([tag('back_cracking', 'Back cracking')]);
    final l10n = await pumpSheet(tester, registry);

    await tester.tap(find.byKey(const ValueKey('custom-tag-retire-back_cracking')));
    await tester.pumpAndSettle();

    // The confirm dialog names the retirement semantics, not deletion.
    expect(find.text(l10n.customTagsRetireBody), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('custom-tag-retire-confirm')));
    await tester.pumpAndSettle();

    expect(registry.retiredIds, [
      '01J8ZQ9K7MC2X3V4B5N6P7Q13',
    ], reason: 'retire writes hidden_at for exactly the chosen row');
  });

  testWidgets('rename validates against the other rows, then writes the '
      'new label with the code unchanged', (tester) async {
    final registry = FakeRegistry([
      tag('back_cracking', 'Back cracking'),
      tag('neck_pain', 'Neck pain'),
    ]);
    final l10n = await pumpSheet(tester, registry);

    await tester.tap(find.byKey(const ValueKey('custom-tag-rename-back_cracking')));
    await tester.pumpAndSettle();

    // A rename onto another entry's code is refused as a duplicate.
    await tester.enterText(
      find.byKey(const ValueKey('custom-tag-rename-field')),
      'NECK PAIN',
    );
    await tester.tap(find.byKey(const ValueKey('custom-tag-rename-save')));
    await tester.pump();
    expect(find.text(l10n.customTagsErrorDuplicate), findsOneWidget);
    expect(registry.renames, isEmpty);

    // A fresh label saves through the repository.
    await tester.enterText(
      find.byKey(const ValueKey('custom-tag-rename-field')),
      'Back cracking (upper)',
    );
    await tester.tap(find.byKey(const ValueKey('custom-tag-rename-save')));
    await tester.pumpAndSettle();

    expect(registry.renames.single.label, 'Back cracking (upper)');
    expect(registry.rows.first.code, 'back_cracking',
        reason: 'a rename never changes the code');
  });

  testWidgets('create renders the empty and taxonomy errors without '
      'writing', (tester) async {
    final registry = FakeRegistry(const []);
    final l10n = await pumpSheet(tester, registry);

    await tester.tap(find.byKey(const ValueKey('custom-tag-create')));
    await tester.pump();
    expect(find.text(l10n.customTagsErrorEmpty), findsOneWidget);
    expect(registry.rows, isEmpty);

    await tester.enterText(
      find.byKey(const ValueKey('custom-tag-create-field')),
      'Cramps',
    );
    await tester.tap(find.byKey(const ValueKey('custom-tag-create')));
    await tester.pump();
    expect(find.text(l10n.customTagsErrorTaxonomy), findsOneWidget,
        reason: 'a label deriving a curated code must not shadow it');
    expect(registry.rows, isEmpty);
  });

  testWidgets('create renders the cap error at 100 live rows', (tester) async {
    final registry = FakeRegistry([
      // 100 offered rows: the server-side cap mirrored client-side.
      for (var i = 0; i < 100; i++)
        tag('tag_$i'.padRight(13, 'x'), 'Tag $i'),
    ]);
    final l10n = await pumpSheet(tester, registry);

    await tester.enterText(
      find.byKey(const ValueKey('custom-tag-create-field')),
      'Fresh tag',
    );
    await tester.tap(find.byKey(const ValueKey('custom-tag-create')));
    await tester.pump();

    expect(
      find.text(l10n.customTagsErrorCap(kMaxCustomTagsPerProfile)),
      findsOneWidget,
    );
    expect(registry.rows, hasLength(100));
  });

  testWidgets('a repository create failure (a concurrent co-guardian write) '
      'surfaces the duplicate against the fresh registry', (tester) async {
    final registry = FakeRegistry([tag('back_cracking', 'Back cracking')])
      ..failNextCreate = true;
    final l10n = await pumpSheet(tester, registry);

    // Enter a label the pre-check cannot see as a duplicate (the watch has
    // not delivered the conflicting row yet), then let the repository
    // reject it — the catch re-validates against the now-current list.
    await tester.enterText(
      find.byKey(const ValueKey('custom-tag-create-field')),
      'BACK CRACKING',
    );
    await tester.tap(find.byKey(const ValueKey('custom-tag-create')));
    await tester.pump();

    expect(registry.rows, hasLength(1));
    expect(find.text(l10n.customTagsErrorDuplicate), findsOneWidget);
  });
}
