/// E.164 phone normaliser for Indian numbers (+91XXXXXXXXXX).
class PhoneNormalizer {
  PhoneNormalizer._();

  /// Returns canonical E.164 (+91XXXXXXXXXX) or null if invalid.
  /// Handles common user inputs: '9876543210', '+91 9876543210',
  /// '91-98765-43210', '098765 43210'.
  static String? toE164(String input) {
    var digits = input.replaceAll(RegExp(r'[^\d]'), '');

    // Strip 91 prefix if present (without +)
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }

    // Strip leading 0
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length != 10) return null;
    if (!RegExp(r'^[6-9]').hasMatch(digits)) return null;

    return '+91$digits';
  }

  static bool isValid(String input) => toE164(input) != null;

  /// Format for display: '+91 98765-43210'.
  static String forDisplay(String e164) {
    if (!RegExp(r'^\+91\d{10}$').hasMatch(e164)) return e164;
    return '+91 ${e164.substring(3, 8)}-${e164.substring(8)}';
  }
}
