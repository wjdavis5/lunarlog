/// Placeholder for any platform that is not native.
library;

import 'package:lunarlog/domain/gate/app_gate.dart';

AppGate defaultAppGate() =>
    throw UnsupportedError('lunarlog does not support this platform');
