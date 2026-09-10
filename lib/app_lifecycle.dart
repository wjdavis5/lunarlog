/// Backwards-compatibility barrel for the issue #433 split.
///
/// `lib/app_lifecycle.dart` was split into `lib/gate_controller.dart` (the
/// [GateController] state machine plus its timer typedef/impl and gate-only
/// constants) and `lib/app_root.dart` (the [LunarLogRoot] widget plus
/// [LunarLogRootState], [GateShell], [PrivacyCover], the [SyncEngineBuilder]
/// typedef and the push/notification callback classes). Pure move: no
/// behavior change. Existing import sites keep working through this barrel.
library;

export 'gate_controller.dart';
export 'app_root.dart';
