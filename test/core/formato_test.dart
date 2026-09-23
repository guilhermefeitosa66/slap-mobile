import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/formato.dart';

void main() {
  test('tempo de uma operação, em português', () {
    expect(descreverTempo(const Duration(milliseconds: 820)), '0,8 s');
    expect(descreverTempo(const Duration(milliseconds: 3450)), '3,5 s');
    expect(descreverTempo(const Duration(milliseconds: 14400)), '14 s');
    expect(descreverTempo(const Duration(seconds: 120)), '2 min');
    expect(descreverTempo(const Duration(seconds: 125)), '2 min 5 s');
  });
}
