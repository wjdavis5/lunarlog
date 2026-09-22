/// Drift-backed [LocalRowCountRepository] (issue #551 part 3): the
/// repository seam over `LunarLogStorage.countAllRows`, so `lib/app.dart`
/// can provide the upload-consent [LocalRowCounter] without reaching past
/// `AppDependencies` into the raw storage object.
library;

import 'package:lunarlog/data/db/storage.dart';
import 'package:lunarlog/domain/repositories/local_row_count_repository.dart';
import 'package:lunarlog/domain/sync/local_row_counts.dart';

class DriftLocalRowCountRepository implements LocalRowCountRepository {
  DriftLocalRowCountRepository(this._storage);

  final LunarLogStorage _storage;

  @override
  Future<LocalRowCounts> countAllRows() => _storage.countAllRows();
}
