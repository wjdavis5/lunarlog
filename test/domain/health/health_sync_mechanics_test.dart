/// Coverage for Issue #186's health-store sync mechanics
/// (`lib/domain/health/health_sync_mechanics.dart`): the anchor controller's
/// token-expiry fallback (AC4), the own-write loop-breaker (AC5), and the
/// v1 deletion-as-no-op classification — all against injected fakes.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_sync_mechanics.dart';
import 'package:lunarlog/domain/health/health_sync_state_repository.dart';

class _FakeAnchors implements HealthSyncStateRepository {
  final Map<String, HealthSyncAnchor> rows = {};
  int writes = 0;

  @override
  Future<HealthSyncAnchor?> readAnchor(String platform) async => rows[platform];

  @override
  Future<void> writeAnchor(HealthSyncAnchor anchor) async {
    writes++;
    rows[anchor.platform] = anchor;
  }
}

class _FakeSource implements HealthStoreChangeSource {
  _FakeSource(this.handler);

  final Future<HealthStoreChanges> Function(String? anchor) handler;
  final List<String?> anchorsAsked = [];
  int calls = 0;

  @override
  Future<HealthStoreChanges> getChanges({String? anchor}) {
    calls++;
    anchorsAsked.add(anchor);
    return handler(anchor);
  }
}

const _ownOrigin = 'com.wjdavis5.lunarlog';

HealthStoreChange _change(
  String externalId, {
  String? origin,
  bool deletion = false,
}) =>
    HealthStoreChange(
      externalId: externalId,
      dataOrigin: origin,
      isDeletion: deletion,
    );

void main() {
  test('AC4: a stored anchor is passed to the source and advanced on success',
      () async {
    final anchors = _FakeAnchors();
    anchors.rows['health_connect'] = const HealthSyncAnchor(
      platform: 'health_connect',
      anchor: 'token-1',
    );
    final source = _FakeSource((anchor) async {
      expect(anchor, 'token-1');
      return const HealthStoreChanges(
        newAnchor: 'token-2',
        changes: [
          HealthStoreChange(externalId: 'foreign-1', dataOrigin: 'com.other'),
        ],
      );
    });
    final controller = HealthSyncAnchorController(
      anchors: anchors,
      source: source,
      filter: const HealthOwnSourceFilter(),
      ownDataOrigin: _ownOrigin,
      ownExternalIds: () => const {},
    );

    final report = await controller.syncForPlatform('health_connect');

    expect(source.calls, 1);
    expect(report.hadAnchor, isTrue);
    expect(report.fellBackToFullRead, isFalse);
    expect(report.importsEligible, 1);
    expect(report.ownWritesSkipped, 0);
    expect(report.deletionsSkipped, 0);
    expect(report.advancedAnchor, isTrue);
    expect(anchors.rows['health_connect']!.anchor, 'token-2');
  });

  test(
      'AC4: ChangesTokenExpiredException clears the anchor and falls back '
      'to a full time-range read (anchor null), retrying once', () async {
    final anchors = _FakeAnchors();
    anchors.rows['health_connect'] = const HealthSyncAnchor(
      platform: 'health_connect',
      anchor: 'stale-token',
    );
    var calls = 0;
    final source = _FakeSource((anchor) async {
      calls++;
      if (calls == 1) {
        expect(anchor, 'stale-token');
        throw const ChangesTokenExpiredException('expired');
      }
      // The fallback read must be a full time-range read (anchor null).
      expect(anchor, isNull);
      return const HealthStoreChanges(
        newAnchor: 'fresh-token',
        changes: [
          HealthStoreChange(externalId: 'foreign-1', dataOrigin: 'com.other'),
        ],
      );
    });
    final controller = HealthSyncAnchorController(
      anchors: anchors,
      source: source,
      filter: const HealthOwnSourceFilter(),
      ownDataOrigin: _ownOrigin,
      ownExternalIds: () => const {},
    );

    final report = await controller.syncForPlatform('health_connect');

    expect(calls, 2, reason: 'the expired token must be retried exactly once');
    expect(report.hadAnchor, isTrue);
    expect(report.fellBackToFullRead, isTrue);
    expect(report.importsEligible, 1);
    // The cleared anchor was written before the retry, then advanced.
    expect(anchors.rows['health_connect']!.anchor, 'fresh-token');
    expect(source.anchorsAsked, ['stale-token', null]);
  });

  test(
      'AC5: own-origin changes are filtered (the primary loop-breaker) and '
      'own external ids are the backup loop-breaker', () async {
    final anchors = _FakeAnchors();
    final source = _FakeSource((_) async => const HealthStoreChanges(
          newAnchor: 't2',
          changes: [
            // Our own write, primary signal: dataOrigin matches.
            HealthStoreChange(
                externalId: 'entry-A',
                dataOrigin: 'com.wjdavis5.lunarlog'),
            // A foreign write carrying one of our exported ids: backup
            // signal catches it even though the origin is not ours.
            HealthStoreChange(
                externalId: 'entry-B', dataOrigin: 'com.someone.else'),
            // A genuinely foreign write: eligible.
            HealthStoreChange(
                externalId: 'foreign-1', dataOrigin: 'com.other'),
            // A deletion change: not an own-write, but a no-op for v1.
            HealthStoreChange(externalId: 'foreign-2', isDeletion: true),
          ],
        ));
    final controller = HealthSyncAnchorController(
      anchors: anchors,
      source: source,
      filter: const HealthOwnSourceFilter(),
      ownDataOrigin: _ownOrigin,
      ownExternalIds: () => const {'entry-A', 'entry-B'},
    );

    final report = await controller.syncForPlatform('healthkit');

    expect(report.ownWritesSkipped, 2,
        reason: 'both the origin match and the external-id match are own '
            'writes, whichever fired');
    expect(report.deletionsSkipped, 1,
        reason: 'a deletion change is a no-op on import for v1');
    expect(report.importsEligible, 1);
  });

  test(
      'a change with a null dataOrigin and an unknown external id is not '
      'filtered (no false-positive loop-break)', () async {
    const filter = HealthOwnSourceFilter();
    expect(
      filter.isOwnWrite(
        _change('foreign-3'),
        ownDataOrigin: _ownOrigin,
        ownExternalIds: const {},
      ),
      isFalse,
    );
    expect(
      filter.shouldImport(
        _change('foreign-3'),
        ownDataOrigin: _ownOrigin,
        ownExternalIds: const {},
      ),
      isTrue,
    );
  });

  test('no anchor yet: a full time-range read happens without a fallback',
      () async {
    final anchors = _FakeAnchors();
    final source = _FakeSource((anchor) async {
      expect(anchor, isNull);
      return const HealthStoreChanges(
        newAnchor: 'first-token',
        changes: [],
      );
    });
    final controller = HealthSyncAnchorController(
      anchors: anchors,
      source: source,
      filter: const HealthOwnSourceFilter(),
      ownDataOrigin: _ownOrigin,
      ownExternalIds: () => const {},
    );

    final report = await controller.syncForPlatform('health_connect');

    expect(report.hadAnchor, isFalse);
    expect(report.fellBackToFullRead, isFalse);
    expect(report.advancedAnchor, isTrue);
    expect(anchors.rows['health_connect']!.anchor, 'first-token');
  });
}
