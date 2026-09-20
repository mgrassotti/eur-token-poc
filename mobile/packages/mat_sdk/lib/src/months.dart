/// Symbolic month helpers — mirror of `mat-core::months`.
class Period {
  const Period({required this.startYear, required this.startMonth, required this.endYear, required this.endMonth});

  final int startYear;
  final int startMonth;
  final int endYear;
  final int endMonth;

  /// Parse ISO date strings (`YYYY-MM-DD` or `YYYY-MM-DDTHH:MM:SS...`).
  factory Period.fromIsoDates(String start, String end) {
    final s = DateTime.parse(start);
    final e = DateTime.parse(end);
    return Period(
      startYear: s.year,
      startMonth: s.month,
      endYear: e.year,
      endMonth: e.month,
    );
  }
}

int symbolicMonthsDuration(Period period) {
  final endMonths = period.endYear * 12 + period.endMonth;
  final startMonths = period.startYear * 12 + period.startMonth;
  final delta = endMonths - startMonths;
  return delta < 0 ? 0 : delta;
}
