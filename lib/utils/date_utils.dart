import 'package:intl/intl.dart';

/// Calendar helpers. All ranges are half-open: [start, end).
///
/// Dates are built with the `DateTime(y, m, d)` constructor instead of adding
/// `Duration`s so that daylight-saving transitions never shift a day.
class DateUtilsX {
  DateUtilsX._();

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  /// Monday-based start of week.
  static DateTime startOfWeek(DateTime d) {
    final day = dateOnly(d);
    return addDays(day, -(day.weekday - DateTime.monday));
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

  static DateTime startOfNextMonth(DateTime d) => DateTime(d.year, d.month + 1);

  static DateTime addMonths(DateTime d, int months) =>
      DateTime(d.year, d.month + months);

  static int daysInMonth(DateTime d) => DateTime(d.year, d.month + 1, 0).day;

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  static final DateFormat _dayMonth = DateFormat('d MMM');
  static final DateFormat _dayMonthYear = DateFormat('d MMM yyyy');
  static final DateFormat _monthYear = DateFormat('MMMM yyyy');
  static final DateFormat _monthShort = DateFormat('MMM');
  static final DateFormat _weekdayShort = DateFormat('E');
  static final DateFormat _fullDay = DateFormat('EEEE, d MMM');

  static String dayMonth(DateTime d) => _dayMonth.format(d);
  static String dayMonthYear(DateTime d) => _dayMonthYear.format(d);
  static String monthYear(DateTime d) => _monthYear.format(d);
  static String monthShort(DateTime d) => _monthShort.format(d);
  static String weekdayShort(DateTime d) => _weekdayShort.format(d);
  static String fullDay(DateTime d) => _fullDay.format(d);

  /// "Today", "Yesterday" or a formatted date.
  static String relativeDay(DateTime d, {DateTime? now}) {
    final today = dateOnly(now ?? DateTime.now());
    final day = dateOnly(d);
    if (day == today) return 'Today';
    if (day == addDays(today, -1)) return 'Yesterday';
    if (day.year == today.year) return fullDay(day);
    return dayMonthYear(day);
  }
}

/// A half-open date range [start, end).
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// Number of calendar days covered (DST-safe via rounding).
  int get dayCount => (end.difference(start).inHours / 24).round();

  factory DateRange.month(DateTime anyDay) => DateRange(
        DateUtilsX.startOfMonth(anyDay),
        DateUtilsX.startOfNextMonth(anyDay),
      );

  factory DateRange.week(DateTime anyDay) {
    final s = DateUtilsX.startOfWeek(anyDay);
    return DateRange(s, DateUtilsX.addDays(s, 7));
  }

  factory DateRange.year(DateTime anyDay) =>
      DateRange(DateTime(anyDay.year), DateTime(anyDay.year + 1));

  /// The last [days] days including today.
  factory DateRange.lastDays(int days, DateTime now) {
    final end = DateUtilsX.addDays(DateUtilsX.dateOnly(now), 1);
    return DateRange(DateUtilsX.addDays(end, -days), end);
  }

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}
