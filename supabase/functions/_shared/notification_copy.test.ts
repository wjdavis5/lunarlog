import { assertEquals } from "jsr:@std/assert@1";
import { buildPushMessage } from "./notification_copy.ts";

Deno.test("buildPushMessage carries only profile_id in data", () => {
  const message = buildPushMessage("01ABCDEFGHJKMNPQRSTVWXYZ00", "device-token");
  assertEquals(Object.keys(message.message.data), ["profile_id"]);
  assertEquals(message.message.data.profile_id, "01ABCDEFGHJKMNPQRSTVWXYZ00");
});

Deno.test("buildPushMessage uses the exact literal title and body", () => {
  const message = buildPushMessage("profile-1", "token-1");
  assertEquals(message.message.notification.title, "A reminder from Lunarlog");
  assertEquals(message.message.notification.body, "Open Lunarlog to see what it is about.");
});

Deno.test("buildPushMessage's serialized form has no key beyond token/notification/data", () => {
  const message = buildPushMessage("profile-1", "token-1");
  const serialized = JSON.stringify(message);
  const parsed = JSON.parse(serialized);
  assertEquals(Object.keys(parsed.message).sort(), ["data", "notification", "token"]);
  assertEquals(Object.keys(parsed.message.notification).sort(), ["body", "title"]);
  // Nothing beyond profile_id ever appears in the serialized payload -- no
  // note/tags/flow/local_date/display_name key can leak in here (R9).
  assertEquals(serialized.includes("note"), false);
  assertEquals(serialized.includes("tags"), false);
  assertEquals(serialized.includes("flow"), false);
});
