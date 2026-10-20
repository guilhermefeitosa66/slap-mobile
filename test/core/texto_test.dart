import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/texto.dart';

void main() {
  test('tira caracteres de controle e mantém tab e quebras de linha', () {
    expect(semCaracteresDeControle('A\u0000B\u000BC\u001FD'), 'ABCD');
    expect(
      semCaracteresDeControle('linha 1\r\nlinha 2\tfim'),
      'linha 1\r\nlinha 2\tfim',
    );
    expect(semCaracteresDeControle('Coordenação'), 'Coordenação');
  });

  test('o \\x02 entre letras ou dígitos volta a ser hífen', () {
    // Casos reais do cadastro do SUAP do IFPI.
    expect(semCaracteresDeControle('TRUE ON\u0002LINE'), 'TRUE ON-LINE');
    expect(semCaracteresDeControle('MODELO HI\u0002WALL'), 'MODELO HI-WALL');
    expect(semCaracteresDeControle('BIV\u0002PROT/AUTO'), 'BIV-PROT/AUTO');
  });

  test('o \\x02 no fim da linha ou do texto só sai', () {
    expect(semCaracteresDeControle('NA COR BEGE\u0002'), 'NA COR BEGE');
    expect(semCaracteresDeControle('MARCA SÓ\r\nAÇO\u0002'), 'MARCA SÓ\r\nAÇO');
    expect(semCaracteresDeControle('ON \u0002 LINE'), 'ON  LINE');
  });
}
