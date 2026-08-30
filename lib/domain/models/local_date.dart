/// A civil calendar date (year, month, day) with no time or timezone.
///
/// All domain date math is done on civil dates (R11/KTD5): callers convert
/// wall-clock instants to the profile's local civil date at the boundary
/// (`fromDateTime` on a locally-resolved [DateTime] or `fromIso` on a stored
/// `yyyy-MM-dd` string). Arithmetic is pure integer day math over the
/// proleptic Gregorian calendar — never instant/Duration math — so DST
/// transitions and timezone offsets cannot shift a date by accident.
library;

final RegExp _isoPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

const List<int> _monthLengths = [
  31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31,
];

bool _isLeapYear(int year) =>
    (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

int _daysInMonth(int year, int month) =>
    month == 2 && _isLeapYear(year) ? 29 : _monthLengths[month - 1];

class LocalDate implements Comparable<LocalDate> {
  /// Throws [ArgumentError] unless (year, month, day) is a real calendar
  /// date. Years are limited to 0–9999 to match the stored `yyyy-MM-dd`
  /// format.
  LocalDate(this.year, this.month, this.day) {
    if (year < 0 || year > 9999) {
      throw ArgumentError.value(year, 'year', 'must be within 0000-9999');
    }
    if (month < 1 || month > 12) {
      throw ArgumentError.value(month, 'month', 'must be within 1-12');
    }
    if (day < 1 || day > _daysInMonth(year, month)) {
      throw ArgumentError.value(day, 'day', 'not a valid day of $year-$month');
    }
  }

  factory LocalDate.fromIso(String iso) {
    if (!_isoPattern.hasMatch(iso)) {
      throw ArgumentError.value(iso, 'iso', 'must be formatted yyyy-MM-dd');
    }
    return LocalDate(
      int.parse(iso.substring(0, 4)),
      int.parse(iso.substring(5, 7)),
      int.parse(iso.substring(8, 10)),
    );
  }

  /// The date part of [dateTime] as-is (no offset conversion): the caller
  /// passes a DateTime already resolved to the relevant local time.
  factory LocalDate.fromDateTime(DateTime dateTime) =>
      LocalDate(dateTime.year, dateTime.month, dateTime.day);

  /// Today in the caller's local zone.
  factory LocalDate.today() => LocalDate.fromDateTime(DateTime.now());

  final int year;
  final int month;
  final int day;

  /// Canonical `yyyy-MM-dd` string (matches the storage format exactly).
  String get iso =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Days since 1970-01-01 in the proleptic Gregorian calendar
  /// (Howard Hinnant's days-from-civil / civil-from-days algorithms).
  int get _dayNumber {
    final y = month <= 2 ? year - 1 : year;
    final era = (y >= 0 ? y : y - 399) ~/ 400;
    final yoe = y - era * 400;
    final mp = (month + 9) % 12;
    final doy = (153 * mp + 2) ~/ 5 + day - 1;
    final doe = yoe * 365 + yoe ~/ 4 - yoe ~/ 100 + doy;
    return era * 146097 + doe - 719468;
  }

  LocalDate _fromDayNumber(int dayNumber) {
    final z = dayNumber + 719468;
    final era = (z >= 0 ? z : z - 146096) ~/ 146097;
    final doe = z - era * 146097;
    final yoe = (doe - doe ~/ 1460 + doe ~/ 36524 - doe ~/ 146096) ~/ 365;
    final y = yoe + era * 400;
    final doy = doe - (365 * yoe + yoe ~/ 4 - yoe ~/ 100);
    final mp = (5 * doy + 2) ~/ 153;
    final d = doy - (153 * mp + 2) ~/ 5 + 1;
    final m = mp + (mp < 10 ? 3 : -9);
    return LocalDate(y + (m <= 2 ? 1 : 0), m, d);
  }

  LocalDate addDays(int days) => _fromDayNumber(_dayNumber + days);

  /// Whole civil days from [other] to this date (positive when later).
  int difference(LocalDate other) => _dayNumber - other._dayNumber;

  bool isBefore(LocalDate other) => compareTo(other) < 0;
  bool isAfter(LocalDate other) => compareTo(other) > 0;

  @override
  int compareTo(LocalDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  @override
  String toString() => iso;
}
