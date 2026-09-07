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
