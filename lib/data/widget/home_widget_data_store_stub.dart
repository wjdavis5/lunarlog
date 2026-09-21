/// The web/desktop stub twin of `home_widget_data_store_io.dart` — same
/// public surface, every operation unsupported. Selected by the barrel's
/// conditional export wherever the `home_widget` plugin cannot exist: the
/// plugin's own Dart source imports `dart:io` unconditionally, so the real
/// file must never even be compiled on web. The composition root's
/// `createWidgetDataStore` gates on platform before ever constructing this
/// class, so nothing reaches the throw in practice — it exists so a
/// mistake fails loudly instead of silently no-op'ing.
library;

import 'dart:async';

import 'package:lunarlog/domain/widget/widget_data_store.dart';

/// Same constants as the IO twin (the boundary guard test pins them
/// through the barrel, and the values must not drift between branches).
const String kLunarLogAppGroup = 'group.com.wjdavis5.lunarlog.widgets';
const String kLunarLogWidgetName = 'LunarLogWidget';
const String kLunarLogWidgetAndroidName = 'LunarLogWidgetProvider';

/// The unsupported store: constructing it is already a mistake.
class HomeWidgetDataStore implements WidgetDataStore {
  HomeWidgetDataStore() {
    throw UnsupportedError(
      'home_widget has no web/desktop implementation; the composition '
      'root never constructs a store where no widget surface exists',
    );
  }

  @override
  Future<void> savePayload(Map<String, String> payload) async {
    throw UnsupportedError('no widget surface on this platform');
  }

  @override
  Future<void> refresh() async {
    throw UnsupportedError('no widget surface on this platform');
  }

  @override
  Future<Uri?> initialLaunch() async {
    throw UnsupportedError('no widget surface on this platform');
  }

  @override
  Stream<Uri> get launches => const Stream<Uri>.empty();
}
