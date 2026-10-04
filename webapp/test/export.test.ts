import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  buildExportDocument,
  exportFileName,
  fetchServerExportDocument,
  downloadAccountExport,
  toExportProfile,
  type ServerExportDocument,
  type ServerProfile,
} from '../src/lib/export';
import type { AppSupabaseClient } from '../src/lib/supabase';

/**
 * The web JSON export (issue #1256): the `export_account_data()` document
 * mapped into the export-shaped profiles the domain facade decodes, the
 * app's filename convention, and the in-memory Blob download. The domain
 * module itself is a fake here (its parity with the Dart side is the
 * domain/parity suite's business); this pins the web-side plumbing around
 * it.
 */

const SERVER_PROFILE: ServerProfile = {
  id: '01ARZ3NDEKTSV4RRFFQ69G5FAV',
  display_name: 'Maya',
  is_minor: true,
  mode: 'cycle',
  sort_order: 2,
  archived_at: null,
  created_at: '2026-01-01T00:00:00Z',
  updated_at: '2026-02-02T03:04:05Z',
  birth_year: 2013,
  relationship: 'daughter',
  tracking_preferences: { predictions: true },
  day_entries: [
    {
      id: '01ARZ3NDEKTSV4RRFFQ69G5FAW',
      local_date: '2026-02-01',
      tz: 'America/New_York',
      flow: 'light',
      tags: ['cramps'],
      note: 'private note',
      note_private: true,
      updated_at: '2026-02-02T03:04:05Z',
    },
    {
      id: '01ARZ3NDEKTSV4RRFFQ69G5FAX',
      local_date: '2026-02-02',
      tz: null,
      flow: null,
      tags: null,
      note: null,
      note_private: null,
      updated_at: '2026-02-03T00:00:00Z',
    },
  ],
};

function fakeClient(rpcResult: { data: unknown; error: unknown }): AppSupabaseClient {
  return {
    rpc: vi.fn(async () => rpcResult),
  } as unknown as AppSupabaseClient;
}

describe('toExportProfile (issue #1256)', () => {
  it('maps the RPC snake_case row into the export-shaped camelCase profile', () => {
    const profile = toExportProfile(SERVER_PROFILE);

    expect(profile.id).toBe(SERVER_PROFILE.id);
    expect(profile.displayName).toBe('Maya');
    expect(profile.isMinor).toBe(true);
    expect(profile.mode).toBe('cycle');
    expect(profile.sortOrder).toBe(2);
    expect(profile.createdAt).toBe('2026-01-01T00:00:00Z');
    expect(profile.updatedAt).toBe('2026-02-02T03:04:05Z');
    expect(profile.birthYear).toBe(2013);
    expect(profile.relationship).toBe('daughter');
    expect(profile.trackingPreferences).toEqual({ predictions: true });
    expect(profile.dayEntries).toHaveLength(2);
    expect(profile.dayEntries[0]).toMatchObject({
      id: '01ARZ3NDEKTSV4RRFFQ69G5FAW',
      localDate: '2026-02-01',
      tz: 'America/New_York',
      flow: 'light',
      tags: ['cramps'],
      note: 'private note',
      notePrivate: true,
    });
  });

  it('defaults the nullable columns the way the facade does, never inventing data', () => {
    const profile = toExportProfile({
      ...SERVER_PROFILE,
      is_minor: null,
      mode: null,
      sort_order: null,
      birth_year: null,
      relationship: null,
      tracking_preferences: null,
      day_entries: null,
    });

    expect(profile.isMinor).toBe(false);
    expect(profile.mode).toBeUndefined();
    expect(profile.sortOrder).toBe(0);
    expect(profile.birthYear).toBeNull();
    expect(profile.relationship).toBeNull();
    expect(profile.trackingPreferences).toBeNull();
    expect(profile.dayEntries).toEqual([]);
  });

  it('defaults a null entry row to an unlogged manual entry (FlowLevel.none territory)', () => {
    const profile = toExportProfile(SERVER_PROFILE);

    expect(profile.dayEntries[1]).toEqual({
      id: '01ARZ3NDEKTSV4RRFFQ69G5FAX',
      localDate: '2026-02-02',
      tz: 'UTC',
      flow: '',
      tags: [],
      note: null,
      notePrivate: false,
      pms: false,
      source: 'manual',
      sourceId: null,
      importId: null,
      updatedAt: '2026-02-03T00:00:00Z',
    });
  });
});

describe('fetchServerExportDocument (issue #1256)', () => {
  it('returns the profiles section of the RPC document', async () => {
    const document = await fetchServerExportDocument(
      fakeClient({ data: { profiles: [SERVER_PROFILE], settings: [] }, error: null }),
    );

    expect(document.profiles).toEqual([SERVER_PROFILE]);
    expect(fakeClient({ data: null, error: null }).rpc).toBeDefined();
  });

  it('throws the RPC error up (the page maps it to the export-failure copy)', async () => {
    await expect(
      fetchServerExportDocument(
        fakeClient({ data: null, error: { message: 'permission denied' } }),
      ),
    ).rejects.toMatchObject({ message: 'permission denied' });
  });

  it('throws when the answer carries no profiles array (a signed-out or malformed response)', async () => {
    await expect(
      fetchServerExportDocument(fakeClient({ data: null, error: null })),
    ).rejects.toThrow(/no profiles array/);
    await expect(
      fetchServerExportDocument(fakeClient({ data: { unexpected: true }, error: null })),
    ).rejects.toThrow(/no profiles array/);
  });
});

describe('buildExportDocument (issue #1256)', () => {
  it('sends the mapped profiles through the domain module and stamps the web version', () => {
    const requests: unknown[] = [];
    const module = {
      version: 'v1',
      invoke: (method: string, requestJson: string) => {
        requests.push({ method, request: JSON.parse(requestJson) });
        // The fake module's answer satisfies the web side's own export
        // schema (the parity suite pins the real module's shapes).
        return JSON.stringify({
          ok: true,
          data: {
            schemaVersion: 99,
            exportedAt: '2026-10-03T00:00:00.000Z',
            app: { name: 'lunarlog', version: '0.1.0' },
            profiles: [],
          },
        });
      },
    };

    const document = buildExportDocument(
      module,
      { profiles: [SERVER_PROFILE] } satisfies ServerExportDocument,
      '2026-10-03T00:00:00.000Z',
    );

    expect(document.schemaVersion).toBe(99);
    expect(requests).toHaveLength(1);
    const request = requests[0] as { method: string; request: Record<string, unknown> };
    expect(request.method).toBe('buildExport');
    expect(request.request.exportedAt).toBe('2026-10-03T00:00:00.000Z');
    expect(request.request.appVersion).toBe('0.1.0');
    const profiles = request.request.profiles as Array<Record<string, unknown>>;
    expect(profiles).toHaveLength(1);
    expect(profiles[0].displayName).toBe('Maya');
  });
});

describe('exportFileName (issue #1256)', () => {
  it('follows the app export writer convention, UTC-stamped', () => {
    expect(exportFileName(new Date('2026-10-03T09:08:07Z'))).toBe(
      'lunarlog-export-20261003-090807.json',
    );
    // Zero-padding on every component.
    expect(exportFileName(new Date('2026-01-02T03:04:05Z'))).toBe(
      'lunarlog-export-20260102-030405.json',
    );
  });
});

describe('downloadAccountExport (issue #1256)', () => {
  const originalCreateObjectURL = URL.createObjectURL;
  const originalRevokeObjectURL = URL.revokeObjectURL;

  beforeEach(() => {
    vi.spyOn(URL, 'createObjectURL').mockImplementation(
      () => 'blob:https://app.test/fake-object-url',
    );
    vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => undefined);
  });

  afterEach(() => {
    URL.createObjectURL = originalCreateObjectURL;
    URL.revokeObjectURL = originalRevokeObjectURL;
    vi.restoreAllMocks();
    document.body.innerHTML = '';
  });

  /** The domain module fake: echoes a minimal valid export document, and
   * records the requests it received so a test can assert what was sent. */
  function installFakeDomainModule(): { requests: Array<Record<string, unknown>> } {
    const requests: Array<Record<string, unknown>> = [];
    (window as unknown as { lunarlogDomain?: unknown }).lunarlogDomain = {
      version: 'v1',
      invoke: (method: string, requestJson: string) => {
        requests.push({ method, request: JSON.parse(requestJson) });
        return JSON.stringify({
          ok: true,
          data: {
            schemaVersion: 99,
            exportedAt: '2026-10-03T00:00:00.000Z',
            app: { name: 'lunarlog', version: '0.1.0' },
            profiles: [],
          },
        });
      },
    };
    return { requests };
  }

  it('downloads the shaped document as an in-memory Blob and revokes the URL', async () => {
    const { requests } = installFakeDomainModule();
    // jsdom's Blob cannot be read back through a Node Response, so the test
    // records what the Blob was constructed from instead.
    const constructed: Array<{ body: string; type: string }> = [];
    vi.spyOn(window, 'Blob').mockImplementation(function (
      this: unknown,
      parts?: BlobPart[],
      options?: BlobPropertyBag,
    ) {
      constructed.push({ body: String(parts?.[0] ?? ''), type: options?.type ?? '' });
      return { size: 0, type: options?.type ?? '' } as unknown as Blob;
    });
    const client = fakeClient({ data: { profiles: [SERVER_PROFILE] }, error: null });

    await downloadAccountExport(client);

    // The mapped server row reached the domain module (the earlier
    // buildExportDocument test pins the mapping's details).
    expect(requests).toHaveLength(1);
    expect(requests[0].method).toBe('buildExport');
    expect(requests[0].request as Record<string, unknown>).toHaveProperty('profiles');

    // The module's answer is what lands in the Blob, typed as JSON.
    expect(constructed).toHaveLength(1);
    expect(constructed[0].type).toBe('application/json');
    const downloaded = JSON.parse(constructed[0].body) as { schemaVersion: number };
    expect(downloaded.schemaVersion).toBe(99);

    expect(URL.createObjectURL).toHaveBeenCalledTimes(1);
    // One anonymous anchor click, then cleaned up.
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:https://app.test/fake-object-url');
    expect(document.body.querySelector('a')).toBeNull();
  });

  it('never creates the Blob when the RPC fails (nothing to download)', async () => {
    const client = fakeClient({ data: null, error: { message: 'permission denied' } });

    await expect(downloadAccountExport(client)).rejects.toThrow();
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  });
});
