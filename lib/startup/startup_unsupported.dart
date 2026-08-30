/// Placeholder for platforms neither native nor web.
library;

import 'package:lunarlog/data/db/db_factory.dart';

Future<LunarLogDbFactory> buildDbFactory() async =>
    throw UnsupportedError('lunarlog does not support this platform');
