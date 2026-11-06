import 'package:flutter_test/flutter_test.dart';
import 'package:koracle/src/join_screen.dart';

void main() {
  test('accepts a token and rejects anything else', () {
    expect(looksLikeInvite('  header.payload.signature\n'), isTrue);
    expect(looksLikeInvite(''), isFalse);
    expect(looksLikeInvite('header.payload'), isFalse);
    expect(looksLikeInvite('header..signature'), isFalse);
  });
}
