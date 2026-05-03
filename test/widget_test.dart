import 'package:diaries_club/core/utils/currency.dart';
import 'package:diaries_club/core/utils/phone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhoneNormalizer', () {
    test('accepts a 10-digit Indian mobile', () {
      expect(PhoneNormalizer.toE164('9876543210'), '+919876543210');
    });
    test('strips +91 prefix and reformats', () {
      expect(PhoneNormalizer.toE164('+91 98765 43210'), '+919876543210');
    });
    test('rejects landline (starts with 5)', () {
      expect(PhoneNormalizer.toE164('5876543210'), null);
    });
    test('rejects too-short input', () {
      expect(PhoneNormalizer.toE164('98765'), null);
    });
  });

  group('Money', () {
    test('formats whole rupees with Indian comma format', () {
      expect(Money.fromPaise(80000), '₹800');
      expect(Money.fromPaise(11000000), '₹1,10,000');
    });
    test('forces decimals when fractional', () {
      expect(Money.fromPaise(110050), '₹1,100.50');
    });
  });
}
