// _shared/notification_copy.ts (Issue #5, U5; KTD1)
//
// The fixed generic strings every caregiver alert shows, character-for-
// character identical to lib/data/notifications/scheduling.dart's
// kReminderTitle/kReminderBody -- so a guardian's lock screen cannot
// distinguish a remote caregiver alert from the app's own local reminder,
// and the "discreet by default" guarantee (R10) holds for both. If a future
// client-side copy change ever touches those two constants, this file's own
// test (below) is the thing that must change with it -- there is
// deliberately no shared source file between the Dart and Deno runtimes.

const TITLE = "A reminder from Lunarlog";
const BODY = "Open Lunarlog to see what it is about.";

/** The FCM HTTP v1 request body shape push-dispatch sends. */
export interface FcmMessage {
  message: {
    token: string;
    notification: { title: string; body: string };
    data: { profile_id: string };
  };
}

/**
 * Builds the FCM HTTP v1 message for [profileId] and device [token].
 * `data` carries only `profile_id` -- never a note, tag, flow, local date,
 * or profile display name (R9, KTD1). `notification` is always the fixed
 * generic copy (R10); there is no richer-copy variant (see the plan's Key
 * Decisions -- that opt-in was deliberately not built).
 */
export function buildPushMessage(profileId: string, token: string): FcmMessage {
  return {
    message: {
      token,
      notification: { title: TITLE, body: BODY },
      data: { profile_id: profileId },
    },
  };
}
