/// Contract for writing and sharing a FHIR clinical export bundle
/// (Issue #157; R4).
///
/// The UI needs to deliver an already-built bundle to the platform share
/// sheet but must not depend on the `path_provider`/`share_plus` adapter in
/// `lib/data/export/`; the contract takes a plain bundle map and the export
/// instant.
library;

abstract interface class FhirBundleWriter {
  /// Encodes [bundle], names the file from [exportedAt], and hands both to
  /// the platform delivery step.
  Future<void> exportAndShare({
    required Map<String, Object?> bundle,
    required DateTime exportedAt,
  });
}
