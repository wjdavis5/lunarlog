//
//  LunarLogWidget.swift
//  lunarlog
//
//  The home-screen widget (issue #141).
//
//  PRIVACY POSTURE (non-negotiable, issue #141's design constraints):
//
//  This extension renders on the home screen — a surface the app's
//  device-credential gate never sees and its FLAG_SECURE / app-switcher
//  snapshot suppression cannot reach (those protect the app's own windows;
//  the widget draws in the launcher's process). The only privacy control
//  that exists here is therefore discretion by construction:
//
//  - The ONLY data this widget reads is the shared App Group
//    UserDefaults suite written by the app's `WidgetStatePublisher`
//    (`lib/data/widget/widget_state_publisher.dart`). The exact key set —
//    a state word, a cycle-day count, a days-until-next count, a
//    quick-log flag, an opaque profile id, and the as-of date — is
//    documented and pinned in
//    `lib/domain/widget/widget_cycle_state.dart`. Nothing else is read,
//    nothing else is rendered: no profile name, no date, no flow, no
//    symptom, no health word.
//  - The render is numeric-only: "Day 14" and "≈7 d" (or an em dash).
//    The three "nothing to show" reasons are deliberately
//    indistinguishable, because *why* nothing shows is itself health
//    context.
//  - The quick-log affordance never writes. A tap opens the containing
//    app with a `lunarlog://` URL whose only payload is the opaque
//    profile id; the app stages the write and applies it only after the
//    device-credential gate is satisfied (the same after-the-gate shape
//    as the notification actions, issue #136).
//
//  Timeline mechanics: entries are pre-rolled one per day for the next
//  eight days (rolling the stored day count forward by whole civil days
//  from `ll_widget_as_of`, and dropping the countdown once it would cross
//  zero — the app is the only authority for a fresh estimate), then the
//  timeline asks WidgetKit for a refresh. No network, no app launch, and
//  no reads beyond the app-group suite.
//
//  The payload-key strings, the app group, and the widget kind below are
//  pinned to the Dart side (`WidgetCycleStatePayload`,
//  `HomeWidgetDataStore.kLunarLogAppGroup`, `kLunarLogWidgetName`); the
//  `home_widget` plugin is pinned exactly in pubspec.yaml for the same
//  reason.
//

import WidgetKit
import SwiftUI

/// The keys the app writes into the shared suite (see
/// `lib/domain/widget/widget_cycle_state.dart` — the documented,
/// minimal boundary). The whole payload travels as one JSON object under
/// `payload` (issue #1731), so a failed or interrupted write can never
/// leave half of a new payload beside half of the old one.
private enum PayloadKey {
    static let payload = "ll_widget_payload"
    static let state = "ll_widget_state"
    static let cycleDay = "ll_widget_cycle_day"
    static let daysUntilNext = "ll_widget_days_until_next"
    static let canQuickLog = "ll_widget_can_quick_log"
    static let profileId = "ll_widget_profile_id"
    static let asOf = "ll_widget_as_of"
}

/// The payload's fields, decoded from the single JSON entry the app writes
/// (issue #1731); nil when that entry is absent or malformed, which reads
/// as the neutral render.
private func readPayloadFields() -> [String: Any]? {
    guard let defaults = UserDefaults(suiteName: appGroupId),
        let json = defaults.string(forKey: PayloadKey.payload),
        let data = json.data(using: .utf8),
        let object = try? JSONSerialization.jsonObject(with: data),
        let fields = object as? [String: Any]
    else {
        return nil
    }
    return fields
}

/// The app group both Runner and this extension are entitled to; the suite
/// `HomeWidgetDataStore` (Dart) writes through the `home_widget` plugin.
private let appGroupId = "group.com.wjdavis5.lunarlog.widgets"

/// The `kind` the app's `HomeWidget.updateWidget(iOSName:)` reloads.
let lunarLogWidgetKind = "LunarLogWidget"

/// One neutral render of the widget: a title, an optional subtitle, and
/// the quick-log affordance's visibility. See the file header for why the
/// vocabulary is numeric-only.
struct WidgetRender {
    var title: String
    var cycleDay: Int?
    var daysUntilNext: Int?
    var canQuickLog: Bool
    var profileId: String?

    /// Optional countdown caption ("≈N d"); nil renders nothing.
    var subtitle: String? = nil

    /// The em dash: every "nothing to show" state (thin history,
    /// suppressed predictions, predictions off) renders identically.
    static let neutral = WidgetRender(
        title: "—", cycleDay: nil, daysUntilNext: nil,
        canQuickLog: false, profileId: nil)
}

/// Reads the app's latest payload from the shared suite, unrolled.
func readRender() -> WidgetRender {
    guard let fields = readPayloadFields() else {
        return .neutral
    }
    let profileId = fields[PayloadKey.profileId] as? String
    let canQuickLog =
        (fields[PayloadKey.canQuickLog] as? String ?? "0") == "1"
        && profileId != nil
    // Any state other than a live cycle ("day") renders the neutral dash.
    guard fields[PayloadKey.state] as? String == "day",
        let baseDayText = fields[PayloadKey.cycleDay] as? String,
        let baseDay = Int(baseDayText)
    else {
        return WidgetRender(
            title: "—", cycleDay: nil, daysUntilNext: nil,
            canQuickLog: canQuickLog, profileId: profileId)
    }
    let untilNext = (fields[PayloadKey.daysUntilNext] as? String)
        .flatMap(Int.init)
    return WidgetRender(
        title: "Day \(baseDay)", cycleDay: baseDay, daysUntilNext: untilNext,
        canQuickLog: canQuickLog, profileId: profileId)
}

/// The payload's as-of date, as the app wrote it: the day the stored
/// counts were right.
func readAsOf() -> String? {
    readPayloadFields()?[PayloadKey.asOf] as? String
}

/// Whole civil days from the payload's as-of date (`yyyy-MM-dd`) to
/// `today`. Zero when the date is missing or unreadable, and zero for a
/// date in the future: a clock set back shows the stored counts unchanged
/// rather than counting backwards. The Android widget does the same.
///
/// The date is read on the Gregorian calendar whatever calendar the phone
/// is set to, because that is the calendar the app wrote it on.
func daysSinceAsOf(_ asOf: String?, today: Date, timeZone: TimeZone) -> Int {
    guard let asOf = asOf else { return 0 }
    let parts = asOf.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
        let year = Int(parts[0]), let month = Int(parts[1]),
        let day = Int(parts[2])
    else { return 0 }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    guard
        let start = calendar.date(
            from: DateComponents(year: year, month: month, day: day))
    else { return 0 }
    let elapsed =
        calendar.dateComponents(
            [.day], from: start, to: calendar.startOfDay(for: today)
        ).day ?? 0
    return max(0, elapsed)
}

/// Rolls a render forward by `days` whole civil days (the days since the
/// app wrote the counts, plus the timeline entry's own offset): the day
/// count advances; the countdown advances and
/// stops rendering once it would cross zero — the app republishes a fresh
/// estimate long before that in any ordinary rhythm.
extension WidgetRender {
    func rolled(by days: Int) -> WidgetRender {
        guard let baseDay = cycleDay else { return self }
        let subtitle = daysUntilNext
            .map { $0 - days }
            .flatMap { $0 > 0 ? $0 : nil }
            .map { "≈\($0) d" }
        return WidgetRender(
            title: "Day \(baseDay + days)", cycleDay: baseDay + days,
            daysUntilNext: daysUntilNext, canQuickLog: canQuickLog,
            profileId: profileId, subtitle: subtitle)
    }
}

struct WidgetEntry: TimelineEntry {
    let date: Date
    let render: WidgetRender
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), render: .neutral)
    }

    func getSnapshot(
        in context: Context, completion: @escaping (WidgetEntry) -> Void
    ) {
        // Gallery previews render the neutral dash: never a real person's
        // state, not even the operator's own.
        let now = Date()
        let render =
            context.isPreview
            ? WidgetRender.neutral
            : readRender().rolled(
                by: daysSinceAsOf(
                    readAsOf(), today: now, timeZone: TimeZone.current))
        completion(WidgetEntry(date: now, render: render))
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void
    ) {
        let base = readRender()
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        // The stored counts were right on the day the app wrote them, and
        // that is not always today. The system rebuilds this timeline with
        // the app unopened in between: after a restart, and when the last
        // timeline runs out eight days on. Counting from today then showed
        // the day the app last wrote as today's.
        let elapsed = daysSinceAsOf(
            readAsOf(), today: now, timeZone: calendar.timeZone)
        var entries: [WidgetEntry] = []
        for offset in 0...7 {
            let date =
                calendar.date(byAdding: .day, value: offset, to: today)
                ?? today
            entries.append(
                WidgetEntry(
                    date: date, render: base.rolled(by: elapsed + offset)))
        }
        let refreshAfter =
            calendar.date(byAdding: .day, value: 8, to: today) ?? Date()
        completion(Timeline(entries: entries, policy: .after(refreshAfter)))
    }
}

struct LunarLogWidgetEntryView: View {
    var entry: Provider.Entry

    var body: some View {
        contentWithBackground
            // The whole widget is the tap target: quick-log when this
            // profile can be logged for, a plain open otherwise. The write
            // itself lands only after the app's gate — the widget opens
            // the app, nothing more.
            .widgetURL(tapUrl)
    }

    private var tapUrl: URL? {
        if entry.render.canQuickLog,
            let profileId = entry.render.profileId,
            let encoded = profileId.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
        {
            return URL(
                string:
                    "lunarlog://widget-quick-log?homeWidget=1&profile=\(encoded)"
            )
        }
        return URL(string: "lunarlog://widget-open?homeWidget=1")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("lunarlog")
                .font(.caption2)
                .opacity(0.7)
            Text(entry.render.title)
                .font(.title2)
                .fontWeight(.bold)
            if let subtitle = entry.render.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.8)
            }
            if entry.render.canQuickLog {
                // A neutral word (the same posture as the notification
                // actions' "Yes"/"A little"/"Not yet" copy, issue #844):
                // the meaning rides the URL, never this label.
                Text("Log")
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.white.opacity(0.18)))
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .frame(
            maxWidth: .infinity, maxHeight: .infinity,
            alignment: .topLeading)
    }

    /// The brand purple (`values/colors.xml`'s
    /// `ic_launcher_background`, #37156C) — the same surface the launch
    /// screen uses, so the widget reads as this app's surface and nothing
    /// brighter than the app itself.
    private var brandPurple: Color {
        Color(red: 0x37 / 255.0, green: 0x15 / 255.0, blue: 0x6C / 255.0)
    }

    /// iOS 17 requires widgets to declare a container background (else
    /// they render with a warning and clipped margins); earlier releases
    /// keep the plain content over the brand colour.
    @ViewBuilder
    private var contentWithBackground: some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content
                .containerBackground(for: .widget) { brandPurple }
        } else {
            content
                .background(brandPurple)
        }
    }
}

struct LunarLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: lunarLogWidgetKind, provider: Provider()) {
            entry in
            LunarLogWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("lunarlog")
        .description(Text("A discreet cycle-day glance."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// The bundle's single widget.
@main
struct LunarLogWidgetBundle: WidgetBundle {
    var body: some Widget {
        LunarLogWidget()
    }
}
