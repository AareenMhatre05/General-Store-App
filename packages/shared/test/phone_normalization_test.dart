import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// The client's normalisation has to agree with the database's, or the
/// "is this number free?" check answers a different question from the
/// unique index that actually decides. These are the same cases the
/// index was tested against.
void main() {
  group('normalizePhone', () {
    const canonical = '8766008705';

    for (final written in [
      '8766008705',
      '+918766008705',
      '08766008705',
      '+91 87660 08705',
      '876-600-8705',
      '  8766008705  ',
      '+91-87660-08705',
      '(876) 600 8705',
    ]) {
      test('"$written" is the same number', () {
        expect(AuthRepository.normalizePhone(written), canonical);
      });
    }

    test('a short number is left alone rather than padded', () {
      expect(AuthRepository.normalizePhone('12345'), '12345');
    });
  });

  group('isValidMobile', () {
    test('accepts Indian mobile prefixes in any written form', () {
      for (final number in ['9812345678', '+91 87660 08705', '7012345678']) {
        expect(AuthRepository.isValidMobile(number), isTrue, reason: number);
      }
    });

    test('rejects short, empty and landline-style numbers', () {
      for (final number in ['', '12345', '0224001234', '5123456789']) {
        expect(AuthRepository.isValidMobile(number), isFalse, reason: number);
      }
    });
  });
}
