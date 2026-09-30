/// The compiled module's entrypoint (issue #1251): installs the facade on
/// the global object as `window.lunarlogDomain` and exits — dart2js output
/// is a plain same-origin script (`script-src 'self'`, no eval, no WASM),
/// so `webapp/index.html` loads it with a static `<script>` tag and the
/// TypeScript wrapper (`webapp/src/domain/client.ts`) calls it.
///
/// This file is the ONLY `dart:js_interop` glue in the module; everything
/// real lives in `facade.dart` so `flutter test` can pin it without a
/// browser.
///
/// Compile from the repo root (the Flutter SDK's dart, because the root
/// package's pubspec needs the Flutter SDK to resolve):
///
/// ```
/// flutter pub get
/// dart compile js -O2 tool/web_domain/main.dart \
///   -o webapp/public/domain/lunarlog_domain.js
/// ```
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'facade.dart';

void main() {
  final exports = JSObject();
  exports.setProperty('version'.toJS, kWebDomainFacadeVersion.toJS);
  exports.setProperty(
    'invoke'.toJS,
    ((JSString method, JSString requestJson) => handleFacadeCall(
      method.toDart,
      requestJson.toDart,
    ).toJS).toJS,
  );
  globalContext.setProperty('lunarlogDomain'.toJS, exports);
}
