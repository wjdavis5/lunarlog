# Voice & copy

How lunarlog talks. Written for whoever edits an `.arb` string or a widget
label next — the rules below are meant to be applied, not admired.

The app logs intimate health data for people who may not be the person holding
the phone: a parent logging a teenager's cycle, an adult logging her own, a
caregiver helping a partner. Copy that is clinical, coy, or that assumes the
reader is the subject breaks trust exactly where it matters most.

## The voice in five rules

1. **Plain and warm.** Write the way a calm, competent friend explains
   something: short sentences, concrete words, no bureaucratic passive voice.
   *Do:* "Keep logging — estimates appear once a few cycles are recorded."
   *Not:* "The entry for 2026-09-08 is removed from the calendar."
2. **Second person for the reader, third for the subject.** "You" is whoever
   is looking at the screen. The person whose cycle is logged is named or
   referred to in the third person ("Maya's profile", "the profile", "they").
   Never write "your data" on a surface that may be guarding someone else's
   record — say *this device* or *this profile* instead.
3. **Say the thing.** No euphemisms, no clinical scares. Use the words people
   actually use for their bodies, and only reach for medical terminology in
   clinician-facing output (FHIR/CSV export), never in the UI.
4. **Gender-neutral, always.** Not everyone who tracks a cycle is a woman, and
   not everyone who reads the screen is the person being tracked. "They/them"
   or the profile's name; "people who menstruate", never "women" as a synonym.
5. **One term per concept.** Pick the word once (see the glossary) and use it
   everywhere — the same idea must not wear two names on two screens.

## The product name

**`lunarlog` — lowercase, one word, no space, no capital L.** It is the name in
`pubspec.yaml`, the repo, the bundle id, and every user-visible string. Never
`LunarLog`, `Lunarlog`, `Lunar Log`, or `lunarlog app`. Sentence-initial use is
still lowercase ("lunarlog requires users to be at least 13"). The bundle id
(`com.wjdavis5.lunarlog`) and the Dart package name (`lunarlog`) are frozen
identifiers and do not follow copy rules.

## Glossary — one term per concept

| Concept | The word | Notes |
| --- | --- | --- |
| Anyone with access to a profile, collectively | **guardian** | The umbrella term in all UI copy: "Manage Guardians", "No guardians linked yet", "Guardian alerts". |
| The lowest logging role specifically | **caregiver** | Only when naming that exact role, beside "Primary Guardian", "Co-Parent", and "Viewer". Never as the umbrella. |
| The logged person's record | **profile** | Not "account", not "member". |
| One day's logged data | **entry** | "No entry for this day." |
| Bleeding | **period** / **flow** / **spotting** | Use the user's word, not "menses" or "bleeding episode". |
| The reader | **you** | Whoever is holding the phone. |

Wire values (`primary_guardian`, `co_parent`, `caregiver`, `viewer`), Dart
identifiers, database columns, and RLS policy names are frozen — UI copy
converges on "guardian" without renaming any of them.

## Do / Don't

The **Don't** column quotes copy that is in the app today; fixing the
remaining rows is follow-up work, tracked as it touches each screen.

| Context | Don't | Do |
| --- | --- | --- |
| Delete confirmation | "The entry for 2026-09-08 is removed from the calendar." | "This removes your 8 Sep entry from the calendar." |
| Save failure | "Couldn't save — try again" | "Couldn't save. Your changes are kept — please try again." |
| Estimates not ready | "Insufficient data" | "Keep logging — estimates appear once a few cycles are recorded." |
| Lock screen, data ownership | "Your data is protected." | "Everything logged on this device stays protected." |
| Periods | "time of the month", "feminine hygiene" | "period", "bleeding", "flow", "spotting" |
| Symptoms | "dysmenorrhea", "menorrhagia" | "painful cramps", "heavy bleeding" |
| The subject | "she", "her cycle" | "they", "Maya's cycle", the profile's name |
| Collective noun | "Caregivers" (as the umbrella) | "Guardians" |
| Product name | "LunarLog", "Lunarlog" | "lunarlog" |
| Validation error | "Invalid input", "You failed to…" | "Enter a number between 15 and 60" |
| Failure blame | "The server rejected your request." | "Couldn't save. Check your connection and try again." |

## Stating what makes lunarlog different (a later change)

lunarlog's real advantages — family/guardian co-management, offline-first
reliability, no ads and no paywall, minor-appropriate custodianship, and
import/portability — are not stated anywhere in the UI today, and this change
deliberately does not add them: that is a product-writing pass of its own, best
landed at the moments the advantages matter (onboarding, the empty calendar,
the shared-profile header, the Your-data section) rather than as one marketing
screen. What those lines should sound like is governed by the five rules above;
*where* they go belongs to the issues that own those screens. See the "Not
done" note in the PR that introduced this guide.

## Applying this — PR checklist

- [ ] New or changed user-visible copy follows the five rules above.
- [ ] The product name reads `lunarlog` (lowercase, one word).
- [ ] The collective noun is "guardian"; "caregiver" only names the role.
- [ ] No string assumes the reader is the person whose cycle is logged.
- [ ] New strings live in `lib/l10n/app_en.arb`, not inline in a widget.
