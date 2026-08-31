/// Placeholder for platforms neither native nor web.
library;

import 'app_gate.dart';

AppGate defaultAppGate() =>
    throw UnsupportedError('lunarlog does not support this platform');
