/// The platform port for the shared widget container (issue #141).
///
/// The widget reads a shared container — the iOS App Group's
/// `UserDefaults` suite, or Android's `HomeWidgetPreferences`
/// SharedPreferences - that lives **outside the app's Drift store**, and
/// outside the OS at-rest protection that covers it. This port exists so everything above it (the state publisher,
/// the executor, the Settings UI) is pure Dart against an interface; the
/// only concrete `home_widget`-touching implementation is
/// `lib/data/widget/home_widget_data_store.dart`, a platform adapter kept
/// to the same seam discipline as every other platform surface in this
/// repo (`lib/data/**` adapter + domain port).
library;

/// Writes the discreet payload and refreshes the platform widget.
///
/// A no-op implementation ([NoopWidgetDataStore]) backs web/desktop, the
/// same zero-conditional posture as `NoopReminderScheduler`: callers never
/// branch on the platform themselves, they just get a store that does
/// nothing.
abstract interface class WidgetDataStore {
  /// Writes the payload ([WidgetCycleStatePayload.encode]'s output) into
  /// the shared container. The map is the complete write: it is serialized
  /// as one JSON object under [WidgetCycleStatePayload.keyPayload] and
  /// written in a single container entry (issue #1731), so a failed or
  /// interrupted write leaves the previous payload in place rather than a
  /// mix of two. A failed write is reported by throwing.
  Future<void> savePayload(Map<String, String> payload);

  /// Asks the OS to re-render the widget(s) from the container.
  Future<void> refresh();

  /// The app was cold-started by a widget tap, if any.
  Future<Uri?> initialLaunch();

  /// Widget taps arriving while the app is running (warm).
  Stream<Uri> get launches;
}

/// The inert store for platforms without a widget surface (web, desktop
/// tests): every write is dropped, the launch stream is empty.
class NoopWidgetDataStore implements WidgetDataStore {
  @override
  Future<void> savePayload(Map<String, String> payload) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<Uri?> initialLaunch() async => null;

  @override
  Stream<Uri> get launches => const Stream<Uri>.empty();
}
