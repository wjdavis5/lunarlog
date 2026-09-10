/// Contract for the plan/preview/apply seam a restore-from-file UI drives
/// (Issue #140; R4). It reads enough of the local store to plan an
/// [AccountImportDocument] against it, then applies the resulting plan.
///
/// The concrete coordinator in `lib/data/import/` is built from repositories
/// and storage; the UI depends only on this contract, which speaks in the
/// domain import models.
library;

import 'account_import.dart';

abstract interface class AccountImportCoordinator {
  /// Builds the plan for [document] against the local store's current state.
  Future<ImportPlan> buildPlan(AccountImportDocument document);

  /// Applies [plan], returning its own summary.
  Future<ImportPlanSummary> apply(ImportPlan plan);
}
