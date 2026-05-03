/// Indian Standard Time helpers — streaks, birthday journey, week math.
class IstDates {
  IstDates._();

  static const istOffset = Duration(hours: 5, minutes: 30);

  static DateTime nowInIst() => DateTime.now().toUtc().add(istOffset);

  /// Returns the IST calendar date (midnight-aligned) for the given UTC time.
  static DateTime istDate(DateTime utc) {
    final ist = utc.toUtc().add(istOffset);
    return DateTime(ist.year, ist.month, ist.day);
  }

  /// Returns the Monday of the IST week containing the given date.
  /// Streaks count weeks Monday–Sunday.
  static DateTime istWeekStart(DateTime utc) {
    final d = istDate(utc);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  static int daysBetween(DateTime fromUtc, DateTime toUtc) =>
      istDate(toUtc).difference(istDate(fromUtc)).inDays;
}
