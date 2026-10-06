/// Unit tests for [healthAccessState] (Issue #1515): what the Health sync
/// screen's status line says, as a pure function of the write-side and
/// read-side OS-permission answers.
///
/// The case the issue is about is reads on and writes off, which used to
/// be told "denied". The property that must never break is the other one:
/// where the store does not disclose read access (an iPhone), the caller
/// passes no read answer, and the two one-direction states cannot come out.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lunarlog/domain/health/health_access_state.dart';
import 'package:lunarlog/domain/health/health_platform.dart';

const _granted = HealthPermissionStatus.granted;
const _writingSome = HealthPermissionStatus.writingSome;
const _notAsked = HealthPermissionStatus.notAsked;
const _denied = HealthPermissionStatus.denied;
const _unavailable = HealthPermissionStatus.unavailable;

/// What the line said before Issue #1515: the write answer on its own.
HealthAccessState _writeAlone(HealthPermissionStatus write) => switch (write) {
      HealthPermissionStatus.granted => HealthAccessState.granted,
      HealthPermissionStatus.writingSome => HealthAccessState.writingSome,
      HealthPermissionStatus.notAsked => HealthAccessState.notAsked,
      HealthPermissionStatus.denied => HealthAccessState.denied,
      HealthPermissionStatus.unavailable => HealthAccessState.unavailable,
    };

void main() {
  group('where the store discloses read access (Android)', () {
    test('reads on, writes off: reading only, never denied', () {
      // Asked for the writes and declined them.
      expect(
        healthAccessState(write: _denied, read: _granted),
        HealthAccessState.readingOnly,
      );
      // Not yet asked for the writes: she has only ever tapped Import.
      expect(
        healthAccessState(write: _notAsked, read: _granted),
        HealthAccessState.readingOnly,
      );
    });

    test('writes on: granted, as before, while reading is on too', () {
      expect(
        healthAccessState(write: _granted, read: _granted),
        HealthAccessState.granted,
      );
    });

    test('writes on, reads off: writing only, not a bare "granted"', () {
      expect(
        healthAccessState(write: _granted, read: _denied),
        HealthAccessState.writingOnly,
      );
      expect(
        healthAccessState(write: _granted, read: _notAsked),
        HealthAccessState.writingOnly,
      );
    });

    test('some writes on: writingSome, regardless of read status', () {
      expect(
        healthAccessState(write: _writingSome, read: _granted),
        HealthAccessState.writingSome,
      );
      expect(
        healthAccessState(write: _writingSome, read: _denied),
        HealthAccessState.writingSome,
      );
      expect(
        healthAccessState(write: _writingSome, read: _notAsked),
        HealthAccessState.writingSome,
      );
    });

    test('neither on, never asked: not yet asked, as before', () {
      expect(
        healthAccessState(write: _notAsked, read: _notAsked),
        HealthAccessState.notAsked,
      );
    });

    test('neither on, asked: denied, as before', () {
      expect(
        healthAccessState(write: _denied, read: _denied),
        HealthAccessState.denied,
      );
    });

    test('neither on: the write answer decides which of the two it is', () {
      // Asked for the reads by Import and declined them, not yet asked for
      // the writes: the write path will still ask, so nothing is "denied".
      expect(
        healthAccessState(write: _notAsked, read: _denied),
        HealthAccessState.notAsked,
      );
      expect(
        healthAccessState(write: _denied, read: _notAsked),
        HealthAccessState.denied,
      );
    });

    test('a read side that cannot tell leaves the write answer alone', () {
      for (final write in HealthPermissionStatus.values) {
        expect(
          healthAccessState(write: write, read: _unavailable),
          _writeAlone(write),
          reason: 'write=$write',
        );
      }
    });

    test('a write side that cannot tell is unavailable, whatever the read '
        'side says', () {
      for (final read in HealthPermissionStatus.values) {
        expect(
          healthAccessState(write: _unavailable, read: read),
          HealthAccessState.unavailable,
          reason: 'read=$read',
        );
      }
    });
  });

  group('where the store does not disclose read access (iPhone)', () {
    test('with no read answer the line is the write answer alone, for '
        'every write answer', () {
      for (final write in HealthPermissionStatus.values) {
        expect(
          healthAccessState(write: write, read: null),
          _writeAlone(write),
          reason: 'write=$write',
        );
      }
    });

    test('neither one-direction state can come out without a read answer',
        () {
      final reachable = {
        for (final write in HealthPermissionStatus.values)
          healthAccessState(write: write, read: null),
      };
      expect(reachable, isNot(contains(HealthAccessState.readingOnly)));
      expect(reachable, isNot(contains(HealthAccessState.writingOnly)));
    });
  });

  group('every state is reachable and each means one thing', () {
    test('the six states are exactly the outcomes over every pair', () {
      final reachable = <HealthAccessState>{
        for (final write in HealthPermissionStatus.values)
          for (final read in <HealthPermissionStatus?>[
            null,
            ...HealthPermissionStatus.values,
          ])
            healthAccessState(write: write, read: read),
      };
      expect(reachable, HealthAccessState.values.toSet());
    });

    test('a one-direction state always has the granted side it names', () {
      for (final write in HealthPermissionStatus.values) {
        for (final read in HealthPermissionStatus.values) {
          final state = healthAccessState(write: write, read: read);
          if (state == HealthAccessState.readingOnly) {
            expect(read, _granted);
            expect(write, isNot(_granted));
          }
          if (state == HealthAccessState.writingOnly) {
            expect(write, _granted);
            expect(read, isNot(_granted));
          }
        }
      }
    });
  });

  group('changedInSettings', () {
    test('the states the health store\'s own settings are the way out of',
        () {
      expect(HealthAccessState.denied.changedInSettings, isTrue);
      expect(HealthAccessState.readingOnly.changedInSettings, isTrue);
      expect(HealthAccessState.writingOnly.changedInSettings, isTrue);
      expect(HealthAccessState.writingSome.changedInSettings, isTrue);
    });

    test('nothing to change there when granted, not yet asked or unavailable',
        () {
      expect(HealthAccessState.granted.changedInSettings, isFalse);
      expect(HealthAccessState.notAsked.changedInSettings, isFalse);
      expect(HealthAccessState.unavailable.changedInSettings, isFalse);
    });
  });
}
