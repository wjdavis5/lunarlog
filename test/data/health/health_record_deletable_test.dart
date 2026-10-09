// Issue #1581: a delete is sent only when it is sure to reach the record.
// Both native halves pass over a type that is switched off and still
// answer allowed, so a delete sent then would be read as done.

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/data/health/health_record_ids.dart';
import 'package:lunarlog/domain/health/health_export_ledger.dart';
import 'package:lunarlog/domain/health/health_platform.dart';

const _entryId = '01HZX9ENTRY';
const _observationId = '01HZX9OBS';

HealthExportLedgerEntry _written(
  String recordId, {
  String sourceRowId = _entryId,
  HealthExportLedgerKind kind = HealthExportLedgerKind.entry,
  String? payloadSummary,
}) =>
    HealthExportLedgerEntry(
      recordId: recordId,
      profileId: 'p1',
      sourceRowId: sourceRowId,
      kind: kind,
      localDate: '2026-06-02',
      exportedAt: DateTime.utc(2026, 6, 2),
      payloadSummary: payloadSummary,
    );

/// Every write type but [off].
Set<String> _allBut(String off) => {
      HealthWriteTypes.menstrualFlow,
      HealthWriteTypes.spotting,
      HealthWriteTypes.cervicalMucus,
      HealthWriteTypes.ovulationTest,
      HealthWriteTypes.basalBodyTemperature,
      HealthWriteTypes.symptoms,
    }..remove(off);

void main() {
  final flow = _written(healthFlowRecordId(_entryId));
  final cervical = _written(healthCervicalMucusRecordId(_entryId));
  final ovulation = _written(
    healthOvulationRecordId(_entryId, 'luteinizingHormoneSurge'),
  );
  final symptom = _written(healthSymptomRecordId(_entryId, 'headache'));
  final bbt = _written(
    healthBbtRecordId(_observationId),
    sourceRowId: _observationId,
    kind: HealthExportLedgerKind.bbt,
  );
  final spotting = _written(
    healthSpottingRecordId(_observationId),
    sourceRowId: _observationId,
    kind: HealthExportLedgerKind.spotting,
  );
  final period = _written(
    'period-p1-2026-06-02',
    sourceRowId: '2026-06-02/2026-06-05',
    kind: HealthExportLedgerKind.period,
  );

  test('with every type on (no list at all), anything may be deleted', () {
    for (final written in [
      flow,
      cervical,
      ovulation,
      symptom,
      bbt,
      spotting,
      period,
    ]) {
      expect(healthRecordDeletable(written, null), isTrue);
    }
  });

  test('each record waits for its own type and for no other', () {
    final needs = {
      flow: HealthWriteTypes.menstrualFlow,
      period: HealthWriteTypes.menstrualFlow,
      cervical: HealthWriteTypes.cervicalMucus,
      ovulation: HealthWriteTypes.ovulationTest,
      bbt: HealthWriteTypes.basalBodyTemperature,
    };
    for (final MapEntry(key: written, value: type) in needs.entries) {
      expect(
        healthRecordDeletable(written, _allBut(type)),
        isFalse,
        reason: '${written.recordId} with $type off',
      );
      expect(
        healthRecordDeletable(written, {type}),
        isTrue,
        reason: '${written.recordId} with only $type on',
      );
    }
  });

  test('a symptom needs all symptoms on, or its own type', () {
    expect(healthRecordDeletable(symptom, {HealthWriteTypes.symptoms}), isTrue);
    expect(healthRecordDeletable(symptom, {'headache'}), isTrue);
    expect(healthRecordDeletable(symptom, {'acne'}), isFalse);
    expect(
      healthRecordDeletable(symptom, _allBut(HealthWriteTypes.symptoms)),
      isFalse,
    );
  });

  // A spotting observation is written as an intermenstrual marker, or as
  // a light flow sample when the day falls inside a period. A row written
  // before #1591 carries no summary of which it was, so it needs both.
  test('a spotting entry\'s record needs both flow and spotting', () {
    expect(
      healthRecordDeletable(spotting, _allBut(HealthWriteTypes.spotting)),
      isFalse,
    );
    expect(
      healthRecordDeletable(spotting, _allBut(HealthWriteTypes.menstrualFlow)),
      isFalse,
    );
    expect(
      healthRecordDeletable(spotting, {
        HealthWriteTypes.menstrualFlow,
        HealthWriteTypes.spotting,
      }),
      isTrue,
    );
  });

  // Since #1591 the ledger's payload summary says which type the record
  // was written as, and only that type's switch holds its removal back.
  test('a spotting record whose written type is known waits for its own '
      'type alone', () {
    final marker = _written(
      healthSpottingRecordId(_observationId),
      sourceRowId: _observationId,
      kind: HealthExportLedgerKind.spotting,
      payloadSummary: 'marker',
    );
    final flowSample = _written(
      healthSpottingRecordId(_observationId),
      sourceRowId: _observationId,
      kind: HealthExportLedgerKind.spotting,
      payloadSummary: 'flow:light:0',
    );
    // A marker is a spotting-type record.
    expect(
      healthRecordDeletable(marker, {HealthWriteTypes.spotting}),
      isTrue,
    );
    expect(
      healthRecordDeletable(marker, _allBut(HealthWriteTypes.spotting)),
      isFalse,
    );
    // A light flow sample inside a period is a flow-type record.
    expect(
      healthRecordDeletable(flowSample, {HealthWriteTypes.menstrualFlow}),
      isTrue,
    );
    expect(
      healthRecordDeletable(
        flowSample,
        _allBut(HealthWriteTypes.menstrualFlow),
      ),
      isFalse,
    );
  });

  test('a record the ledger knows nothing about, or of a shape these '
      'builders do not make, is not held back', () {
    expect(healthRecordDeletable(null, const {}), isTrue);
    expect(healthRecordDeletable(_written('something-else'), const {}), isTrue);
  });

  // Issue #1617: a gone row names a record the store does not hold, so a
  // delete is never sent for it, whatever the type switches say.
  test('a gone record is never deletable', () {
    final gone = _written(
      healthFlowRecordId(_entryId),
      kind: HealthExportLedgerKind.gone,
    );
    expect(healthRecordDeletable(gone, null), isFalse);
    expect(healthRecordDeletable(gone, const {}), isFalse);
    expect(
      healthRecordDeletable(gone, {HealthWriteTypes.menstrualFlow}),
      isFalse,
    );
  });

  test('an entry id that happens to start like another kind is still read '
      'as the flow record', () {
    final oddEntry = _written(
      healthFlowRecordId('symptom-x'),
      sourceRowId: 'symptom-x',
    );
    expect(
      healthRecordDeletable(oddEntry, {HealthWriteTypes.menstrualFlow}),
      isTrue,
    );
    expect(
      healthRecordDeletable(oddEntry, {HealthWriteTypes.symptoms}),
      isFalse,
    );
  });
}
