import 'package:intl/intl.dart';

/// Indian currency formatter — paise → '₹1,10,000' style.
class Money {
  Money._();

  static final NumberFormat _formatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );
  static final NumberFormat _formatterWithDecimals = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  /// 80000 paise → '₹800'
  /// 110050 paise → '₹1,100.50'
  static String fromPaise(int paise, {bool forceDecimals = false}) {
    final rupees = paise / 100;
    if (!forceDecimals && rupees == rupees.truncate()) {
      return _formatter.format(rupees);
    }
    return _formatterWithDecimals.format(rupees);
  }

  /// Without symbol — for invoice line items.
  static String fromPaiseNoSymbol(int paise) =>
      NumberFormat.decimalPattern('en_IN').format(paise / 100);
}
