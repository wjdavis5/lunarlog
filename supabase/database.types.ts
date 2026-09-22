export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      account_consents: {
        Row: {
          acknowledged_at: string
          app_version: string
          consent_via: string
          policy_version: string
          updated_at: string
          user_id: string
        }
        Insert: {
          acknowledged_at: string
          app_version: string
          consent_via: string
          policy_version: string
          updated_at?: string
          user_id: string
        }
        Update: {
          acknowledged_at?: string
          app_version?: string
          consent_via?: string
          policy_version?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      account_deletion_progress: {
        Row: {
          apple_identity_id: string | null
          apple_revoked_at: string | null
          created_at: string
          user_id: string
        }
        Insert: {
          apple_identity_id?: string | null
          apple_revoked_at?: string | null
          created_at?: string
          user_id: string
        }
        Update: {
          apple_identity_id?: string | null
          apple_revoked_at?: string | null
          created_at?: string
          user_id?: string
        }
        Relationships: []
      }
      care_notes: {
        Row: {
          body: string
          created_at: string
          deleted_at: string | null
          id: string
          last_modified_by_user_id: string | null
          logged_by_user_id: string | null
          profile_id: string
          server_version: number
          updated_at: string
        }
        Insert: {
          body?: string
          created_at?: string
          deleted_at?: string | null
          id: string
          last_modified_by_user_id?: string | null
          logged_by_user_id?: string | null
          profile_id: string
          server_version?: number
          updated_at: string
        }
        Update: {
          body?: string
          created_at?: string
          deleted_at?: string | null
          id?: string
          last_modified_by_user_id?: string | null
          logged_by_user_id?: string | null
          profile_id?: string
          server_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "care_notes_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      cycle_overrides: {
        Row: {
          cycle_start_date: string
          deleted_at: string | null
          excluded_from_average: boolean
          id: string
          manual_start: boolean
          note_id: string | null
          profile_id: string
          server_version: number
          updated_at: string
        }
        Insert: {
          cycle_start_date: string
          deleted_at?: string | null
          excluded_from_average?: boolean
          id: string
          manual_start?: boolean
          note_id?: string | null
          profile_id: string
          server_version?: number
          updated_at: string
        }
        Update: {
          cycle_start_date?: string
          deleted_at?: string | null
          excluded_from_average?: boolean
          id?: string
          manual_start?: boolean
          note_id?: string | null
          profile_id?: string
          server_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "cycle_overrides_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      day_entries: {
        Row: {
          created_at: string
          deleted_at: string | null
          flow: string
          id: string
          import_id: string | null
          last_modified_by_user_id: string | null
          local_date: string
          logged_by_user_id: string | null
          note: string | null
          pms: boolean
          profile_id: string
          server_version: number
          source: string
          source_id: string | null
          tags: Json
          tz: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          deleted_at?: string | null
          flow: string
          id: string
          import_id?: string | null
          last_modified_by_user_id?: string | null
          local_date: string
          logged_by_user_id?: string | null
          note?: string | null
          pms?: boolean
          profile_id: string
          server_version?: number
          source?: string
          source_id?: string | null
          tags?: Json
          tz: string
          updated_at: string
          user_id?: string
        }
        Update: {
          created_at?: string
          deleted_at?: string | null
          flow?: string
          id?: string
          import_id?: string | null
          last_modified_by_user_id?: string | null
          local_date?: string
          logged_by_user_id?: string | null
          note?: string | null
          pms?: boolean
          profile_id?: string
          server_version?: number
          source?: string
          source_id?: string | null
          tags?: Json
          tz?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "day_entries_import_id_fkey"
            columns: ["import_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "day_entries_profile_fk"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      day_entry_history: {
        Row: {
          change_kind: string
          changed_at: string
          changed_by_user_id: string
          changed_fields: string[]
          entry_id: string
          id: string
          profile_id: string
          server_version: number
        }
        Insert: {
          change_kind: string
          changed_at?: string
          changed_by_user_id: string
          changed_fields: string[]
          entry_id: string
          id: string
          profile_id: string
          server_version?: number
        }
        Update: {
          change_kind?: string
          changed_at?: string
          changed_by_user_id?: string
          changed_fields?: string[]
          entry_id?: string
          id?: string
          profile_id?: string
          server_version?: number
        }
        Relationships: [
          {
            foreignKeyName: "day_entry_history_entry_id_fkey"
            columns: ["entry_id"]
            isOneToOne: false
            referencedRelation: "day_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "day_entry_history_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      day_entry_merge_events: {
        Row: {
          created_at: string
          field: string
          id: string
          local_date: string
          losing_author_user_id: string | null
          losing_row_id: string
          losing_value_text: string
          profile_id: string
          server_version: number
          updated_at: string
          winning_author_user_id: string | null
          winning_row_id: string
        }
        Insert: {
          created_at?: string
          field: string
          id: string
          local_date: string
          losing_author_user_id?: string | null
          losing_row_id: string
          losing_value_text?: string
          profile_id: string
          server_version?: number
          updated_at?: string
          winning_author_user_id?: string | null
          winning_row_id: string
        }
        Update: {
          created_at?: string
          field?: string
          id?: string
          local_date?: string
          losing_author_user_id?: string | null
          losing_row_id?: string
          losing_value_text?: string
          profile_id?: string
          server_version?: number
          updated_at?: string
          winning_author_user_id?: string | null
          winning_row_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "day_entry_merge_events_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      deleted_profiles: {
        Row: {
          deleted_at: string
          guardian_user_ids: string[]
          profile_id: string
          server_version: number | null
        }
        Insert: {
          deleted_at?: string
          guardian_user_ids?: string[]
          profile_id: string
          server_version?: number | null
        }
        Update: {
          deleted_at?: string
          guardian_user_ids?: string[]
          profile_id?: string
          server_version?: number | null
        }
        Relationships: []
      }
      feedback_replies: {
        Row: {
          author_type: string
          created_at: string
          id: string
          message: string
          ticket_id: string
        }
        Insert: {
          author_type: string
          created_at?: string
          id?: string
          message: string
          ticket_id: string
        }
        Update: {
          author_type?: string
          created_at?: string
          id?: string
          message?: string
          ticket_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "feedback_replies_ticket_id_fkey"
            columns: ["ticket_id"]
            isOneToOne: false
            referencedRelation: "feedback_tickets"
            referencedColumns: ["id"]
          },
        ]
      }
      feedback_tickets: {
        Row: {
          attachment_paths: string[]
          category: string
          created_at: string
          device_info: Json
          id: string
          message: string
          notified_at: string | null
          reply_email: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          attachment_paths?: string[]
          category: string
          created_at?: string
          device_info?: Json
          id?: string
          message: string
          notified_at?: string | null
          reply_email: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          attachment_paths?: string[]
          category?: string
          created_at?: string
          device_info?: Json
          id?: string
          message?: string
          notified_at?: string | null
          reply_email?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      guardian_invitation_preview_attempts: {
        Row: {
          attempted_at: string
          id: number
          user_id: string
        }
        Insert: {
          attempted_at?: string
          id?: never
          user_id: string
        }
        Update: {
          attempted_at?: string
          id?: never
          user_id?: string
        }
        Relationships: []
      }
      guardian_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          created_at: string
          expires_at: string
          id: string
          invited_by: string
          is_subject: boolean
          profile_id: string
          recipient_label: string | null
          revoked_at: string | null
          role: string
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          expires_at: string
          id?: string
          invited_by: string
          is_subject?: boolean
          profile_id: string
          recipient_label?: string | null
          revoked_at?: string | null
          role: string
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          invited_by?: string
          is_subject?: boolean
          profile_id?: string
          recipient_label?: string | null
          revoked_at?: string | null
          role?: string
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "guardian_invitations_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      guardian_notes: {
        Row: {
          body: string
          created_at: string
          deleted_at: string | null
          id: string
          last_modified_by_user_id: string | null
          local_date: string
          logged_by_user_id: string | null
          profile_id: string
          server_version: number
          tz: string
          updated_at: string
        }
        Insert: {
          body?: string
          created_at?: string
          deleted_at?: string | null
          id: string
          last_modified_by_user_id?: string | null
          local_date: string
          logged_by_user_id?: string | null
          profile_id: string
          server_version?: number
          tz: string
          updated_at: string
        }
        Update: {
          body?: string
          created_at?: string
          deleted_at?: string | null
          id?: string
          last_modified_by_user_id?: string | null
          local_date?: string
          logged_by_user_id?: string | null
          profile_id?: string
          server_version?: number
          tz?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "guardian_notes_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      import_jobs: {
        Row: {
          completed_at: string | null
          created_at: string
          created_by: string
          error_kind: string | null
          id: string
          processed_rows: number
          profile_id: string
          source: string
          status: string
          total_rows: number
        }
        Insert: {
          completed_at?: string | null
          created_at?: string
          created_by: string
          error_kind?: string | null
          id?: string
          processed_rows?: number
          profile_id: string
          source: string
          status?: string
          total_rows: number
        }
        Update: {
          completed_at?: string | null
          created_at?: string
          created_by?: string
          error_kind?: string | null
          id?: string
          processed_rows?: number
          profile_id?: string
          source?: string
          status?: string
          total_rows?: number
        }
        Relationships: [
          {
            foreignKeyName: "import_jobs_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      missed_entry_alert_state: {
        Row: {
          kind: string
          last_enqueued_for: string | null
          profile_id: string
          user_id: string
        }
        Insert: {
          kind?: string
          last_enqueued_for?: string | null
          profile_id: string
          user_id: string
        }
        Update: {
          kind?: string
          last_enqueued_for?: string | null
          profile_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "missed_entry_alert_state_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_outbox: {
        Row: {
          attempts: number
          claimed_at: string | null
          created_at: string
          deliver_after: string
          id: string
          kind: string
          last_error_kind: string | null
          profile_id: string
          recipient_user_id: string
          sent_at: string | null
        }
        Insert: {
          attempts?: number
          claimed_at?: string | null
          created_at?: string
          deliver_after?: string
          id?: string
          kind: string
          last_error_kind?: string | null
          profile_id: string
          recipient_user_id: string
          sent_at?: string | null
        }
        Update: {
          attempts?: number
          claimed_at?: string | null
          created_at?: string
          deliver_after?: string
          id?: string
          kind?: string
          last_error_kind?: string | null
          profile_id?: string
          recipient_user_id?: string
          sent_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "notification_outbox_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_outbox_deliveries: {
        Row: {
          device_id: string
          outbox_id: string
          sent_at: string
        }
        Insert: {
          device_id: string
          outbox_id: string
          sent_at?: string
        }
        Update: {
          device_id?: string
          outbox_id?: string
          sent_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_outbox_deliveries_device_id_fkey"
            columns: ["device_id"]
            isOneToOne: false
            referencedRelation: "push_devices"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "notification_outbox_deliveries_outbox_id_fkey"
            columns: ["outbox_id"]
            isOneToOne: false
            referencedRelation: "notification_outbox"
            referencedColumns: ["id"]
          },
        ]
      }
      notification_preferences: {
        Row: {
          alert_on_cycle_start_only: boolean
          alert_on_high_severity: boolean
          alert_on_log: boolean
          alert_on_period_soon: boolean
          alert_on_pms_soon: boolean
          alert_on_restock: boolean
          cycle_start_cadence: string
          digest_local_time: string | null
          high_severity_cadence: string
          log_cadence: string
          missed_entry_days: number | null
          profile_id: string
          quiet_hours_end: string | null
          quiet_hours_start: string | null
          time_zone: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          alert_on_cycle_start_only?: boolean
          alert_on_high_severity?: boolean
          alert_on_log?: boolean
          alert_on_period_soon?: boolean
          alert_on_pms_soon?: boolean
          alert_on_restock?: boolean
          cycle_start_cadence?: string
          digest_local_time?: string | null
          high_severity_cadence?: string
          log_cadence?: string
          missed_entry_days?: number | null
          profile_id: string
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          time_zone?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          alert_on_cycle_start_only?: boolean
          alert_on_high_severity?: boolean
          alert_on_log?: boolean
          alert_on_period_soon?: boolean
          alert_on_pms_soon?: boolean
          alert_on_restock?: boolean
          cycle_start_cadence?: string
          digest_local_time?: string | null
          high_severity_cadence?: string
          log_cadence?: string
          missed_entry_days?: number | null
          profile_id?: string
          quiet_hours_end?: string | null
          quiet_hours_start?: string | null
          time_zone?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notification_preferences_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      observations: {
        Row: {
          category: string | null
          code: string | null
          created_at: string
          day_entry_id: string
          deleted_at: string | null
          excluded: boolean
          exported_to_platform_at: string | null
          id: string
          import_id: string | null
          intensity: number | null
          last_modified_by_user_id: string | null
          local_date: string
          logged_by_user_id: string | null
          observed_at: string | null
          profile_id: string
          raw: Json | null
          server_version: number
          source: string
          source_id: string | null
          tz: string
          unit: string | null
          updated_at: string
          value_num: number | null
          value_text: string | null
        }
        Insert: {
          category?: string | null
          code?: string | null
          created_at?: string
          day_entry_id: string
          deleted_at?: string | null
          excluded?: boolean
          exported_to_platform_at?: string | null
          id: string
          import_id?: string | null
          intensity?: number | null
          last_modified_by_user_id?: string | null
          local_date: string
          logged_by_user_id?: string | null
          observed_at?: string | null
          profile_id: string
          raw?: Json | null
          server_version?: number
          source?: string
          source_id?: string | null
          tz: string
          unit?: string | null
          updated_at: string
          value_num?: number | null
          value_text?: string | null
        }
        Update: {
          category?: string | null
          code?: string | null
          created_at?: string
          day_entry_id?: string
          deleted_at?: string | null
          excluded?: boolean
          exported_to_platform_at?: string | null
          id?: string
          import_id?: string | null
          intensity?: number | null
          last_modified_by_user_id?: string | null
          local_date?: string
          logged_by_user_id?: string | null
          observed_at?: string | null
          profile_id?: string
          raw?: Json | null
          server_version?: number
          source?: string
          source_id?: string | null
          tz?: string
          unit?: string | null
          updated_at?: string
          value_num?: number | null
          value_text?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "observations_day_entry_id_fkey"
            columns: ["day_entry_id"]
            isOneToOne: false
            referencedRelation: "day_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "observations_import_id_fkey"
            columns: ["import_id"]
            isOneToOne: false
            referencedRelation: "import_jobs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "observations_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      ownership_transfers: {
        Row: {
          accepted_at: string | null
          accepted_by: string | null
          cancelled_at: string | null
          created_at: string
          expires_at: string
          id: string
          initiated_by: string
          parent_post_transfer_role: string
          profile_id: string
          recipient_label: string | null
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by?: string | null
          cancelled_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          initiated_by: string
          parent_post_transfer_role: string
          profile_id: string
          recipient_label?: string | null
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by?: string | null
          cancelled_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          initiated_by?: string
          parent_post_transfer_role?: string
          profile_id?: string
          recipient_label?: string | null
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "ownership_transfers_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      prediction_connections: {
        Row: {
          accepted_at: string | null
          created_at: string
          expires_at: string
          id: string
          owner_user_id: string
          profile_id: string
          recipient_label: string | null
          recipient_user_id: string | null
          revoked_at: string | null
          token_hash: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          owner_user_id: string
          profile_id: string
          recipient_label?: string | null
          recipient_user_id?: string | null
          revoked_at?: string | null
          token_hash: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          owner_user_id?: string
          profile_id?: string
          recipient_label?: string | null
          recipient_user_id?: string | null
          revoked_at?: string | null
          token_hash?: string
        }
        Relationships: [
          {
            foreignKeyName: "prediction_connections_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      prediction_projections: {
        Row: {
          profile_id: string
          projection: Json
          published_at: string
          published_by: string
        }
        Insert: {
          profile_id: string
          projection: Json
          published_at?: string
          published_by: string
        }
        Update: {
          profile_id?: string
          projection?: Json
          published_at?: string
          published_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "prediction_projections_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_guardians: {
        Row: {
          created_at: string
          display_name: string | null
          id: string
          invited_by: string | null
          is_subject: boolean | null
          profile_id: string
          revoked_at: string | null
          role: string
          server_version: number
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          id?: string
          invited_by?: string | null
          is_subject?: boolean | null
          profile_id: string
          revoked_at?: string | null
          role: string
          server_version?: number
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          id?: string
          invited_by?: string | null
          is_subject?: boolean | null
          profile_id?: string
          revoked_at?: string | null
          role?: string
          server_version?: number
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_guardians_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_modes: {
        Row: {
          birth_control_method: string | null
          birth_control_started_on: string | null
          birth_control_stopped_on: string | null
          estimated_due_date: string | null
          health_sync_consent: boolean
          mode: string
          mode_started_on: string | null
          postpartum_birth_date: string | null
          profile_id: string
          server_version: number
          updated_at: string
        }
        Insert: {
          birth_control_method?: string | null
          birth_control_started_on?: string | null
          birth_control_stopped_on?: string | null
          estimated_due_date?: string | null
          health_sync_consent?: boolean
          mode?: string
          mode_started_on?: string | null
          postpartum_birth_date?: string | null
          profile_id: string
          server_version?: number
          updated_at: string
        }
        Update: {
          birth_control_method?: string | null
          birth_control_started_on?: string | null
          birth_control_stopped_on?: string | null
          estimated_due_date?: string | null
          health_sync_consent?: boolean
          mode?: string
          mode_started_on?: string | null
          postpartum_birth_date?: string | null
          profile_id?: string
          server_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_modes_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_reminder_windows: {
        Row: {
          episode_open: boolean
          estimated_next_start: string
          profile_id: string
          updated_at: string
        }
        Insert: {
          episode_open?: boolean
          estimated_next_start: string
          profile_id: string
          updated_at?: string
        }
        Update: {
          episode_open?: boolean
          estimated_next_start?: string
          profile_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_reminder_windows_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: true
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profile_tag_registry: {
        Row: {
          category: string
          code: string
          created_at: string
          created_by: string | null
          deleted_at: string | null
          display_name: string
          hidden_at: string | null
          id: string
          intensity_enabled: boolean
          profile_id: string
          server_version: number
          sort_order: number | null
          updated_at: string
        }
        Insert: {
          category: string
          code: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          display_name: string
          hidden_at?: string | null
          id: string
          intensity_enabled?: boolean
          profile_id: string
          server_version?: number
          sort_order?: number | null
          updated_at?: string
        }
        Update: {
          category?: string
          code?: string
          created_at?: string
          created_by?: string | null
          deleted_at?: string | null
          display_name?: string
          hidden_at?: string | null
          id?: string
          intensity_enabled?: boolean
          profile_id?: string
          server_version?: number
          sort_order?: number | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "profile_tag_registry_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          archived_at: string | null
          bbt_unit: string
          birth_year: number | null
          created_at: string
          deleted_at: string | null
          display_name: string
          id: string
          irregular_framing: boolean | null
          is_minor: boolean
          last_period_start: string | null
          mode: string
          relationship: string | null
          server_version: number
          sort_order: number
          tracking_preferences: Json | null
          transferred_at: string | null
          transferred_to_user_id: string | null
          typical_cycle_length_days: number | null
          typical_period_length_days: number | null
          updated_at: string
          user_id: string
          weight_unit: string
        }
        Insert: {
          archived_at?: string | null
          bbt_unit?: string
          birth_year?: number | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string
          id: string
          irregular_framing?: boolean | null
          is_minor?: boolean
          last_period_start?: string | null
          mode?: string
          relationship?: string | null
          server_version?: number
          sort_order?: number
          tracking_preferences?: Json | null
          transferred_at?: string | null
          transferred_to_user_id?: string | null
          typical_cycle_length_days?: number | null
          typical_period_length_days?: number | null
          updated_at: string
          user_id?: string
          weight_unit?: string
        }
        Update: {
          archived_at?: string | null
          bbt_unit?: string
          birth_year?: number | null
          created_at?: string
          deleted_at?: string | null
          display_name?: string
          id?: string
          irregular_framing?: boolean | null
          is_minor?: boolean
          last_period_start?: string | null
          mode?: string
          relationship?: string | null
          server_version?: number
          sort_order?: number
          tracking_preferences?: Json | null
          transferred_at?: string | null
          transferred_to_user_id?: string | null
          typical_cycle_length_days?: number | null
          typical_period_length_days?: number | null
          updated_at?: string
          user_id?: string
          weight_unit?: string
        }
        Relationships: []
      }
      push_devices: {
        Row: {
          disabled_at: string | null
          id: string
          platform: string
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          disabled_at?: string | null
          id?: string
          platform: string
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          disabled_at?: string | null
          id?: string
          platform?: string
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      settings: {
        Row: {
          key: string
          server_version: number
          updated_at: string
          user_id: string
          value: string
        }
        Insert: {
          key: string
          server_version?: number
          updated_at?: string
          user_id?: string
          value: string
        }
        Update: {
          key?: string
          server_version?: number
          updated_at?: string
          user_id?: string
          value?: string
        }
        Relationships: []
      }
      sync_inflight: {
        Row: {
          created_at: string
          min_version: number
          xid: number
        }
        Insert: {
          created_at?: string
          min_version: number
          xid: number
        }
        Update: {
          created_at?: string
          min_version?: number
          xid?: number
        }
        Relationships: []
      }
      sync_signals: {
        Row: {
          profile_id: string
          updated_at: string
        }
        Insert: {
          profile_id: string
          updated_at?: string
        }
        Update: {
          profile_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      visit_prep_items: {
        Row: {
          body: string
          checked_at: string | null
          checked_by_user_id: string | null
          created_at: string
          deleted_at: string | null
          id: string
          is_checked: boolean
          kind: string
          last_modified_by_user_id: string | null
          logged_by_user_id: string | null
          profile_id: string
          server_version: number
          updated_at: string
        }
        Insert: {
          body?: string
          checked_at?: string | null
          checked_by_user_id?: string | null
          created_at?: string
          deleted_at?: string | null
          id: string
          is_checked?: boolean
          kind?: string
          last_modified_by_user_id?: string | null
          logged_by_user_id?: string | null
          profile_id: string
          server_version?: number
          updated_at: string
        }
        Update: {
          body?: string
          checked_at?: string | null
          checked_by_user_id?: string | null
          created_at?: string
          deleted_at?: string | null
          id?: string
          is_checked?: boolean
          kind?: string
          last_modified_by_user_id?: string | null
          logged_by_user_id?: string | null
          profile_id?: string
          server_version?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "visit_prep_items_profile_id_fkey"
            columns: ["profile_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_guardian_invitation: {
        Args: { p_guardian_display_name?: string; p_token_hash: string }
        Returns: Json
      }
      accept_ownership_transfer: {
        Args: {
          p_child_display_name?: string
          p_parent_display_name?: string
          p_token_hash: string
        }
        Returns: Json
      }
      accept_prediction_connection: {
        Args: { p_token_hash: string }
        Returns: Json
      }
      ahead_of_time_lead_days: { Args: never; Returns: number }
      ahead_of_time_min_pms_intervals: { Args: never; Returns: number }
      alert_coalesce_window: { Args: never; Returns: string }
      alert_daily_push_ceiling: { Args: never; Returns: number }
      bulk_import_entries: {
        Args: { p_import_id: string; p_on_date_conflict?: string; p_rows: Json }
        Returns: Json
      }
      bulk_import_observations: {
        Args: { p_import_id: string; p_rows: Json }
        Returns: Json
      }
      bulk_import_safe_date: { Args: { p_text: string }; Returns: string }
      bulk_import_safe_timestamptz: {
        Args: { p_text: string }
        Returns: string
      }
      cancel_ownership_transfer: {
        Args: { p_transfer_id: string }
        Returns: boolean
      }
      create_guardian_invitation: {
        Args: {
          p_profile_id: string
          p_recipient_label: string
          p_role: string
          p_subject?: boolean
          p_token_hash: string
          p_ttl_hours?: number
        }
        Returns: Json
      }
      create_ownership_transfer: {
        Args: {
          p_parent_post_transfer_role: string
          p_profile_id: string
          p_recipient_label?: string
          p_token_hash: string
          p_ttl_hours?: number
        }
        Returns: Json
      }
      create_prediction_connection: {
        Args: {
          p_profile_id: string
          p_recipient_label?: string
          p_token_hash: string
          p_ttl_hours?: number
        }
        Returns: Json
      }
      delete_account_data: { Args: never; Returns: Json }
      delete_profile_data: {
        Args: { p_profile_id: string; p_source?: string }
        Returns: Json
      }
      enforce_retention: { Args: never; Returns: Json }
      export_account_data: { Args: never; Returns: Json }
      get_prediction_projection: {
        Args: { p_profile_id: string }
        Returns: Json
      }
      is_allowed_device_info: {
        Args: { p_device_info: Json }
        Returns: boolean
      }
      is_guardian_with_roles: {
        Args: { p_profile_id: string; p_roles: string[]; p_user_id: string }
        Returns: boolean
      }
      is_profile_guardian: {
        Args: { p_profile_id: string; p_user_id: string }
        Returns: boolean
      }
      is_supported_timestamp: { Args: { p_ts: string }; Returns: boolean }
      is_valid_changed_fields: {
        Args: { p_fields: string[] }
        Returns: boolean
      }
      is_valid_flow_level: { Args: { p_flow: string }; Returns: boolean }
      is_valid_tags_array: { Args: { p_tags: Json }; Returns: boolean }
      is_valid_timezone: { Args: { tz: string }; Returns: boolean }
      is_valid_tracking_preferences: { Args: { p_doc: Json }; Returns: boolean }
      leave_prediction_connection: {
        Args: { p_connection_id: string }
        Returns: boolean
      }
      local_day_start: {
        Args: { p_now: string; p_zone: string }
        Returns: string
      }
      merge_tag_arrays: { Args: { a: Json; b: Json }; Returns: Json }
      owns_feedback_ticket: {
        Args: { p_ticket_id: string; p_user_id: string }
        Returns: boolean
      }
      preview_guardian_invitation: {
        Args: { p_token_hash: string }
        Returns: Json
      }
      profile_counts_as_minor: {
        Args: { p_birth_year: number; p_is_minor: boolean }
        Returns: boolean
      }
      reconcile_realtime_publication: { Args: never; Returns: undefined }
      record_day_entry_merge_discard: {
        Args: {
          p_field: string
          p_local_date: string
          p_losing_author: string
          p_losing_row_id: string
          p_losing_value: string
          p_profile_id: string
          p_winning_author: string
          p_winning_row_id: string
        }
        Returns: undefined
      }
      record_day_entry_merge_history: {
        Args: {
          p_changed_by: string
          p_entry_id: string
          p_field: string
          p_profile_id: string
        }
        Returns: undefined
      }
      record_minimum_age_acknowledgement: {
        Args: {
          p_app_version: string
          p_consent_via: string
          p_policy_version: string
        }
        Returns: undefined
      }
      register_push_device: {
        Args: { p_id: string; p_platform: string; p_token: string }
        Returns: undefined
      }
      rehome_stray_day_entries: { Args: { p_user_id: string }; Returns: number }
      release_notification_outbox_claim: {
        Args: { p_claimed_at: string; p_error_kind: string; p_id: string }
        Returns: undefined
      }
      resolve_deliver_after: {
        Args: {
          p_now: string
          p_quiet_end: string
          p_quiet_start: string
          p_zone: string
        }
        Returns: string
      }
      resolve_notification_outbox_dispatch: {
        Args: { p_id: string }
        Returns: Json
      }
      retract_prediction_projection: {
        Args: { p_profile_id: string }
        Returns: undefined
      }
      retract_reminder_window: {
        Args: { p_profile_id: string }
        Returns: undefined
      }
      revoke_guardian: {
        Args: { p_profile_id: string; p_target_user_id: string }
        Returns: boolean
      }
      revoke_guardian_invitation: {
        Args: { p_invitation_id: string }
        Returns: Json
      }
      revoke_prediction_connection: {
        Args: { p_connection_id: string }
        Returns: boolean
      }
      run_caregiver_alert_drain: { Args: never; Returns: undefined }
      run_nightly_caregiver_alerts_job: { Args: never; Returns: undefined }
      scan_ahead_of_time_alerts: { Args: never; Returns: number }
      scan_missed_entry_reminders: { Args: never; Returns: number }
      sweep_alert_digests: { Args: never; Returns: number }
      sweep_notification_outbox: { Args: never; Returns: number }
      sync_pull: { Args: { p_cursors?: Json }; Returns: Json }
      sync_push: {
        Args: {
          p_care_notes?: Json
          p_cycle_overrides?: Json
          p_day_entries: Json
          p_guardian_notes?: Json
          p_merge_events?: Json
          p_observations?: Json
          p_profile_modes?: Json
          p_profiles: Json
          p_tag_registry?: Json
          p_visit_prep_items?: Json
        }
        Returns: Json
      }
      sync_push_payload_keys: { Args: { p_table: string }; Returns: string[] }
      sync_watermark: { Args: never; Returns: number }
      tombstone_profile_content: {
        Args: { p_now?: string; p_profile_id: string }
        Returns: Json
      }
      trigger_push_dispatch: { Args: never; Returns: undefined }
      update_guardian_role: {
        Args: {
          p_new_role: string
          p_profile_id: string
          p_target_user_id: string
        }
        Returns: Json
      }
      upsert_prediction_projection: {
        Args: { p_profile_id: string; p_projection: Json }
        Returns: undefined
      }
      upsert_reminder_window: {
        Args: {
          p_episode_open: boolean
          p_estimated_next_start: string
          p_profile_id: string
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const

