/// Ordered element-wise equality for the small string lists domain models
/// carry (`DayEntry.tags`, `AuthUser.providers`). Pure Dart: the domain
/// layer imports neither Flutter's `listEquals` nor `package:collection`.
library;

bool listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
