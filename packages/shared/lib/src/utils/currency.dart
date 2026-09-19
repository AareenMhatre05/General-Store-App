import 'package:intl/intl.dart';

final _inrFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 2);

/// Formats an amount as Indian Rupees, e.g. `formatInr(249.5) == '₹249.50'`.
String formatInr(num amount) => _inrFormat.format(amount);
