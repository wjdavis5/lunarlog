/// Observable permission state consumed by the overview hint (U6 seam).
/// The composition root seeds it with
/// [NotificationAvailability.available] and hands it to the reminder
/// coordinator as a [NotificationAvailabilitySink]; U8 wires the real
/// permission query behind that seam.
library;

import 'package:flutter/foundation.dart';
import 'package:lunarlog/domain/notifications/notification_availability.dart';

class NotificationPermissionState extends ChangeNotifier
    implements NotificationAvailabilitySink {
  NotificationPermissionState(this.value);

  NotificationAvailability value;

  @override
  void update(NotificationAvailability next) {
    if (value == next) return;
    value = next;
    notifyListeners();
  }
}
