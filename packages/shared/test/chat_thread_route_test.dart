import 'package:flutter_test/flutter_test.dart';
import 'package:shared/shared.dart';

/// The staff app opened every general conversation blank.
///
/// A route path parameter cannot be null, and the general conversation
/// with the shop has no product. The two apps answered that differently:
/// the customer app used a 'general' sentinel, the staff app
/// interpolated the null directly, and Dart renders that as the literal
/// string "null" -- which matches no message. Every conversation the
/// shop opened was a general one, so it looked completely broken rather
/// than intermittently.
///
/// One shared encode/decode pair now, and these tests hold the round
/// trip -- including that a real product id is never mistaken for the
/// general thread.
void main() {
  test('the general conversation survives the round trip', () {
    expect(ChatThreadRoute.encode(null), 'general');
    expect(ChatThreadRoute.decode(ChatThreadRoute.encode(null)), isNull);
  });

  test('a real product id survives the round trip unchanged', () {
    const id = '4f3c8a91-2b7d-4e15-9c33-0a1b2c3d4e5f';
    expect(ChatThreadRoute.encode(id), id);
    expect(ChatThreadRoute.decode(ChatThreadRoute.encode(id)), id);
  });

  test('the literal "null" left by the old build still opens the right thread',
      () {
    // Anything already navigated or deep-linked with the broken form
    // resolves to the general conversation rather than to nothing.
    expect(ChatThreadRoute.decode('null'), isNull);
  });

  test('encode never produces an empty or null-looking segment', () {
    for (final input in [null, 'abc', 'general-store-rice']) {
      final segment = ChatThreadRoute.encode(input);
      expect(segment, isNotEmpty);
      expect(segment, isNot('null'));
    }
  });

  test('a product genuinely named "general" is the one ambiguity', () {
    // Product ids are uuids, so this cannot occur in practice -- pinned
    // so the assumption is visible if ids ever stop being uuids.
    expect(ChatThreadRoute.decode('general'), isNull);
  });
}
