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
/// minimal boundary).
private enum PayloadKey {
    static let state = "ll_widget_state"
    static let cycleDay = "ll_widget_cycle_day"
    static let daysUntilNext = "ll_widget_days_until_next"
    static let canQuickLog = "ll_widget_can_quick_log"
    static let profileId = "ll_widget_profile_id"
    static let asOf = "ll_widget_as_of"
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

    /// The em dash: every "nothing to show" state (thin history,
    /// suppressed predictions, predictions off) renders identically.
    static let neutral = WidgetRender(
        title: "—", cycleDay: nil, daysUntilNext: nil,
        canQuickLog: false, profileId: nil)
}

/// Reads the app's latest payload from the shared suite, unrolled.
func readRender() -> WidgetRender {
    guard let defaults = UserDefaults(suiteName: appGroupId) else {
        return .neutral
    }
    let profileId = defaults.string(forKey: PayloadKey.profileId)
    let canQuickLog =
        (defaults.string(forKey: PayloadKey.canQuickLog) ?? "0") == "1"
        && profileId != nil
    // Any state other than a live cycle ("day") renders the neutral dash.
    guard defaults.string(forKey: PayloadKey.state) == "day",
        let baseDayText = defaults.string(forKey: PayloadKey.cycleDay),
        let baseDay = Int(baseDayText)
    else {
        return WidgetRender(
            title: "—", cycleDay: nil, daysUntilNext: nil,
            canQuickLog: canQuickLog, profileId: profileId)
    }
    let untilNext = defaults
        .string(forKey: PayloadKey.daysUntilNext)
        .flatMap(Int.init)
    return WidgetRender(
        title: "Day \(baseDay)", cycleDay: baseDay, daysUntilNext: untilNext,
        canQuickLog: canQuickLog, profileId: profileId)
}

/// Rolls a render forward by `days` whole civil days (the timeline's
/// future entries): the day count advances; the countdown advances and
/// stops rendering once it would cross zero — the app republishes a fresh
/// estimate long before that in any ordinary rhythm.
extension WidgetRender {
    func rolled(by days: Int) -> WidgetRender {
        guard let baseDay = cycleDay else { return self }
        let subtitle = daysUntilNext
            .map { $0 - days }
            .filter { $0 > 0 }
            .map { "≈\($0) d" }
        return WidgetRender(
            title: "Day \(baseDay + days)", cycleDay: baseDay + days,
            daysUntilNext: daysUntilNext, canQuickLog: canQuickLog,
            profileId: profileId)
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
        let render = context.isPreview ? WidgetRender.neutral : readRender()
        completion(WidgetEntry(date: Date(), render: render))
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void
    ) {
        let base = readRender()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var entries: [WidgetEntry] = []
        for offset in 0...7 {
            let date =
                calendar.date(byAdding: .day, value: offset, to: today)
                ?? today
            entries.append(
                WidgetEntry(date: date, render: base.rolled(by: offset)))
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
