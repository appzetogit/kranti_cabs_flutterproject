import 'package:intl/intl.dart';

class Formatters {
  Formatters._();

  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final NumberFormat _currencyDecimal = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static String currency(num value, {bool decimals = false}) {
    return decimals ? _currencyDecimal.format(value) : _currency.format(value);
  }

  static String date(DateTime date) => DateFormat('dd MMM yyyy').format(date);

  static String time(DateTime date) => DateFormat('hh:mm a').format(date);

  static String dateTime(DateTime date) => DateFormat('dd MMM yyyy, hh:mm a').format(date);

  static String relativeDay(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date);
    return date.toString().split(' ').first;
  }

  static String distance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  static String duration(int minutes) {
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final rem = minutes % 60;
    return rem == 0 ? '$hours hr' : '$hours hr $rem min';
  }

  static String maskPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return phone;
    return '${'x' * (digits.length - 4)}${digits.substring(digits.length - 4)}';
  }
}
