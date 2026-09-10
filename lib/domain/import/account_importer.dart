/// Contract for the effectful half of import (Issue #140): applies one
/// already-built [ImportPlan] to local storage, returning its own summary.
///
/// The concrete implementation lives in
/// `lib/data/import/account_importer.dart`; the contract speaks in the
/// domain import models, so no storage or Drift type crosses it.
library;

import 'account_import.dart';

abstract interface class AccountImporter {
  /// Writes every planned row in one transaction and returns [plan]'s own
  /// summary (accurate because the transaction is all-or-nothing).
  Future<ImportPlanSummary> apply(ImportPlan plan);
}
