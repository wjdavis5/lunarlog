// The web JSON export (issue #1256): the `export_account_data()` RPC's
// document, shaped by the domain module (#1251) into the app's export file
// format, downloaded from an in-memory Blob. Nothing is held beyond the
// click that downloads it: no disk copy, no cache entry, no at-rest storage
// — the browser's own download dialog is the only place the bytes land.
//
// The web client is always signed-in when it exports (there is no local
// Drift store to fall back to), so unlike the phone's export this document
// is exactly one thing: the account's server data, dressed in the format
// the phone's Settings → Your data importer reads (its acceptance test: a
// file exported here restores on a phone). The payload kinds web v1 does
// not hold (observations, care notes, …) stay defaulted-empty — the
// documented v1 limitation of the shared facade (`tool/web_domain/
// facade.dart`'s buildExportFromJson), which the phone's importer treats as
// "nothing to add", not corruption.

import pkg from '../../package.json';

import {
  buildExport,
  getDomainModule,
  type DayEntryJson,
  type DomainModule,
  type ExportProfileJson,
} from '../domain/client';
import type { ExportDocument } from '../domain/schemas';
import type { AppSupabaseClient } from './supabase';

export const WEBAPP_VERSION: string = pkg.version;

/** One day entry as `export_account_data()` emits it (snake_case wire
 * shape — see the latest re-emission of the RPC under supabase/migrations/). */
export interface ServerDayEntry {
  id: string;
  local_date: string;
  tz: string | null;
  flow: string | null;
  tags: string[] | null;
  note: string | null;
  note_private: boolean | null;
  updated_at: string;
}

/** One profile row of the RPC document, entries nested. */
export interface ServerProfile {
  id: string;
  display_name: string;
  is_minor: boolean | null;
  mode: string | null;
  sort_order: number | null;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
  birth_year: number | null;
  relationship: string | null;
  tracking_preferences: Record<string, unknown> | null;
  day_entries: ServerDayEntry[] | null;
}

/** The shape this module reads off the RPC document — `profiles` and
 * nothing else (the document's remaining top-level keys are the phone-side
 * merge's business, not the web file's; see the file header). */
export interface ServerExportDocument {
  profiles: ServerProfile[];
}

/**
 * Maps one server profile row into the export-shaped profile the domain
 * facade decodes. The payload kinds web v1 does not hold are simply absent:
 * the facade defaults them (`pms` false, `source` manual, provenance ids
 * null) exactly as it does for the synced-cache rows it already decodes.
 */
export function toExportProfile(row: ServerProfile): ExportProfileJson {
  const dayEntries: DayEntryJson[] = (row.day_entries ?? []).map((entry) => ({
    id: entry.id,
    localDate: entry.local_date,
    tz: entry.tz ?? 'UTC',
    flow: entry.flow ?? '',
    tags: entry.tags ?? [],
    note: entry.note,
    notePrivate: entry.note_private ?? false,
    pms: false,
    source: 'manual',
    sourceId: null,
    importId: null,
    updatedAt: entry.updated_at,
  }));
  return {
    id: row.id,
    displayName: row.display_name,
    isMinor: row.is_minor ?? false,
    mode: row.mode ?? undefined,
    sortOrder: row.sort_order ?? 0,
    archivedAt: row.archived_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    birthYear: row.birth_year,
    relationship: row.relationship,
    trackingPreferences: row.tracking_preferences,
    dayEntries,
  };
}

/**
 * Calls `export_account_data()` as the signed-in caller and keeps only the
 * `profiles` section. Throws when the caller is signed out (the RPC's own
 * `authenticated`-only grant refuses first) or the answer is not the
 * document shape this module reads — the page maps both onto the catalogue's
 * export-failure copy.
 */
export async function fetchServerExportDocument(
  client: AppSupabaseClient,
): Promise<ServerExportDocument> {
  const { data, error } = await client.rpc('export_account_data');
  if (error !== null) throw error;
  const document = data as Record<string, unknown> | null;
  const profiles = (document as ServerExportDocument | null)?.profiles;
  if (!Array.isArray(profiles))
    throw new Error('export_account_data returned no profiles array');
  return { profiles };
}

/**
 * Shapes the server document into the app's export file format through the
 * domain module — the same `buildExport` the parity suite pins to the Dart
 * side, so the file a phone imports is byte-for-byte the family it knows.
 */
export function buildExportDocument(
  module: DomainModule,
  document: ServerExportDocument,
  exportedAt: string,
): ExportDocument {
  return buildExport(module, {
    exportedAt,
    appVersion: WEBAPP_VERSION,
    profiles: document.profiles.map(toExportProfile),
  });
}

/** The app's export filename convention (lib/data/export/
 * account_export_writer.dart), UTC-stamped the same way. */
export function exportFileName(exportedAt: Date): string {
  const two = (n: number) => String(n).padStart(2, '0');
  return `lunarlog-export-${exportedAt.getUTCFullYear()}${two(exportedAt.getUTCMonth() + 1)}${two(
    exportedAt.getUTCDate(),
  )}-${two(exportedAt.getUTCHours())}${two(exportedAt.getUTCMinutes())}${two(
    exportedAt.getUTCSeconds(),
  )}.json`;
}

/**
 * The whole export, end to end: RPC → domain module → Blob → one anonymous
 * anchor click. The Blob URL is revoked the moment the download is kicked
 * off; the document exists only inside this call's closure.
 */
export async function downloadAccountExport(
  client: AppSupabaseClient,
  win: Window = window,
): Promise<void> {
  const document = await fetchServerExportDocument(client);
  const exportedAt = new Date();
  const exportDocument = buildExportDocument(
    getDomainModule(win),
    document,
    exportedAt.toISOString(),
  );
  const blob = new Blob([JSON.stringify(exportDocument, null, 2)], {
    type: 'application/json',
  });
  const url = URL.createObjectURL(blob);
  try {
    const anchor = win.document.createElement('a');
    anchor.href = url;
    anchor.download = exportFileName(exportedAt);
    win.document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
  } finally {
    URL.revokeObjectURL(url);
  }
}
