/// Tiny seam for U8's reminder notifications: whether the OS lets the app
/// show them at all. The app shell injects the value (default
/// [NotificationAvailability.available]); U8 wires the real permission
/// query. Nothing else in U6 depends on it beyond one hint line.
library;

enum NotificationAvailability { available, denied }
