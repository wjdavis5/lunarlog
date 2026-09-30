/**
 * Build-time configuration, read from Vite env (`VITE_*` defines).
 *
 * Both values are the client-safe pair the app ships today (the project URL
 * and the publishable key — the same posture as the Flutter client's
 * `--dart-define`s; see AGENTS.md "Config & Credential Locations"). Empty
 * means unconfigured: the client renders without an account surface and
 * creates no Supabase client, exactly like an unconfigured app build.
 */
export const supabaseUrl: string = import.meta.env.VITE_SUPABASE_URL ?? '';
export const supabasePublishableKey: string =
  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY ?? '';

export const hasSupabase: boolean = supabaseUrl !== '' && supabasePublishableKey !== '';
