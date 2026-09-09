/// Payload limits mirrored from the server's CHECK constraints in
/// `supabase/migrations/20260903014208_initial_sync_schema.sql`
/// (`profiles_display_name_length_check`, `day_entries_note_length_check`),
/// and from `is_valid_tags_array` in
/// `supabase/migrations/20260907010000_tags_element_length_check.sql`
/// (`day_entries_tags_check`) for the tag bounds. `sync_push` rejects a row
/// past them forever, so the UI caps input and
/// the storage layer refuses to persist such a row in the first place.
/// Dart's `String.length` counts UTF-16 code units, never fewer than the
/// server's `char_length` code points, so the client check is conservative.
library;

/// Maximum `day_entries.note` length.
const int kMaxNoteLength = 2000;

/// Maximum `profiles.display_name` length.
const int kMaxDisplayNameLength = 80;

/// Maximum length of a single `day_entries.tags` element.
const int kMaxTagLength = 64;

/// Maximum number of elements in `day_entries.tags`.
const int kMaxTagCount = 32;

/// Maximum `observations.category`/`observations.code` length (Issue #240,
/// `observations_category_length_check`/`observations_code_length_check` in
/// `supabase/migrations/20260908160000_observations.sql`).
const int kMaxObservationCategoryLength = 64;
const int kMaxObservationCodeLength = 64;

/// Maximum `observations.value_text` length (`observations_value_text_length_check`).
const int kMaxObservationValueTextLength = 2000;

/// Maximum `observations.unit` length (`observations_unit_length_check`).
const int kMaxObservationUnitLength = 32;

/// Maximum `observations.source_id` length (`observations_source_id_length_check`).
const int kMaxObservationSourceIdLength = 128;

/// Maximum serialized size of `observations.raw`, bounding the client-side
/// check by UTF-8 **bytes** (`utf8.encode(raw).length`, not
/// `String.length`/UTF-16 code units — a non-ASCII `raw` payload can encode
/// to more UTF-8 bytes than UTF-16 code units, so counting code units could
/// pass a value the server's byte-based CHECK rejects), against a value
/// deliberately below the server's `pg_column_size(raw) <= 8192` bound
/// (`observations_raw_size_check`): `pg_column_size` measures the on-disk
/// jsonb binary encoding, which carries some header/container overhead over
/// the raw JSON text's own byte length, so a client-side check pinned to
/// exactly 8192 UTF-8 bytes of *text* could still pass here and be rejected
/// by the server. 7936 (8192 - 256) leaves a fixed margin for that overhead
/// (jsonb's per-value/container header is a small, bounded number of
/// bytes — 256 is generous, not a measured worst case) while still catching
/// an oversized payload before a push the server would reject forever.
const int kMaxObservationRawLength = 7936;

/// Minimum/maximum `observations.intensity` (`observations_intensity_check`).
const int kMinObservationIntensity = 1;
const int kMaxObservationIntensity = 5;

/// Per-(profile, local_date) cap on live observations, enforced server-side
/// in `sync_push` (a CHECK cannot count sibling rows) — mirrored here only
/// as a documented constant a future write path can reference, not enforced
/// client-side in this foundation PR.
const int kMaxObservationsPerDay = 200;

/// Maximum `day_entries.source_id` length (Issue #159,
/// `day_entries_source_id_length_check` in
/// `supabase/migrations/20260908170000_import_provenance.sql`). Same bound
/// as `kMaxObservationSourceIdLength`, kept as its own named constant since
/// the two tables' provenance columns are validated independently.
const int kMaxDayEntrySourceIdLength = 128;
