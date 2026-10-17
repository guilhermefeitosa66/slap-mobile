import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/codigo.dart';

void main() {
  group('chaveBusca', () {
    test('o sinal negativo do SUAP separa dois bens', () {
      // No SUAP, tombo = numero + 42535. O bem -19281 é a plaqueta antiga
      // 23254; o bem 19281 é outro, de tombo 61816. Até a versão 1.2.4 os
      // dois tinham a mesma chave, e ler um registrava o outro.
      expect(chaveBusca('-19281'), '-19281');
      expect(chaveBusca('-19281'), isNot(chaveBusca('19281')));
      expect(chaveBusca('-017033'), '-17033');
      expect(chaveBusca(' - 17033'), '-17033');
      expect(chaveBusca('+17033'), '17033');
    });

    test('zero não tem sinal', () {
      expect(chaveBusca('-0'), '0');
      expect(chaveBusca('-000'), '0');
    });

    test('zeros à esquerda não impedem o encontro', () {
      expect(chaveBusca('000123'), chaveBusca('123'));
      expect(chaveBusca('0000123'), '123');
    });

    test('separadores de formatação são ignorados', () {
      expect(chaveBusca('19.281'), '19281');
      expect(chaveBusca('19 281'), '19281');
      expect(chaveBusca('19-281'), '19281');
    });

    test('célula numérica do Excel não vira outro código', () {
      // "19281.0" com o ponto simplesmente removido viraria 192810 — um
      // código diferente, que não existe em lugar nenhum.
      expect(chaveBusca('19281.0'), '19281');
      expect(chaveBusca('19281.00'), '19281');
      expect(chaveBusca('-19281.0'), '-19281');
    });

    test('preserva dígitos internos e letras', () {
      expect(chaveBusca('19281'), '19281');
      expect(chaveBusca('abc123'), 'ABC123');
      expect(chaveBusca('1902810'), '1902810');
    });

    test('vazio e nulo não consultam o banco', () {
      expect(chaveBusca(null), '');
      expect(chaveBusca(''), '');
      expect(chaveBusca('   '), '');
      expect(chaveBusca('---'), '');
    });

    test('código composto só de zeros continua distinguível de vazio', () {
      expect(chaveBusca('0'), '0');
      expect(chaveBusca('0000'), '0');
      expect(chaveBusca('0').isEmpty, isFalse);
    });

    test('códigos diferentes continuam diferentes', () {
      expect(chaveBusca('12345'), isNot(chaveBusca('12346')));
      expect(chaveBusca('123'), isNot(chaveBusca('1230')));
    });
  });

  group('mesmoCodigo', () {
    test('reconhece as variações da base real', () {
      expect(mesmoCodigo('-019281', '-19281'), isTrue);
      expect(mesmoCodigo('019281', '19281'), isTrue);
    });

    test('a plaqueta antiga e o bem novo com os mesmos dígitos são outros', () {
      expect(mesmoCodigo('-19281', '19281'), isFalse);
    });

    test('código vazio não casa com nada, nem com outro vazio', () {
      expect(mesmoCodigo('', ''), isFalse);
      expect(mesmoCodigo(null, '123'), isFalse);
    });
  });

  group('tomboPeloNumero', () {
    test('segue a regra do SUAP: tombo = numero + 42535', () {
      // Os pares da planilha de exemplo do SLAP e do cadastro do SUAP.
      expect(tomboPeloNumero('-19281'), '23254');
      expect(tomboPeloNumero('-17033'), '25502');
      expect(tomboPeloNumero('-17025'), '25510');
      expect(tomboPeloNumero('19281'), '61816');
      expect(tomboPeloNumero('-19281.0'), '23254');
    });

    test('sem número, sem tombo', () {
      expect(tomboPeloNumero(null), isNull);
      expect(tomboPeloNumero('-'), isNull);
      expect(tomboPeloNumero('ABC'), isNull);
    });
  });

  group('chaveCabecalho', () {
    test('acento, caixa e pontuação não atrapalham o reconhecimento', () {
      expect(chaveCabecalho('DESCRIÇÃO'), 'descricao');
      expect(chaveCabecalho('Descrição'), 'descricao');
      expect(chaveCabecalho('descricao'), 'descricao');
    });

    test('o símbolo de número do SUAP some', () {
      expect(chaveCabecalho('Nº Patrimonial'), 'npatrimonial');
      expect(chaveCabecalho('N° PATRIMONIAL'), 'npatrimonial');
    });

    test('"#" sozinho é a coluna de número, como "Nº"', () {
      // A exportação do SUAP chama a ordem de `#`. Só de pontuação, ela
      // viraria chave vazia e ficaria sem campo.
      expect(chaveCabecalho('#'), 'n');
      expect(chaveCabecalho(' # '), chaveCabecalho('Nº'));
    });

    test('"#" no meio de outro cabeçalho é só pontuação', () {
      expect(chaveCabecalho('Item #'), 'item');
      expect(chaveCabecalho('# Tombo'), 'tombo');
    });

    test('"No." escrito com letra vira outra chave, e isso é proposital', () {
      // Apagar o "o" depois do "n" quebraria qualquer cabeçalho começado por
      // "no" — "nome", por exemplo. As duas grafias são resolvidas no
      // dicionário de sinônimos, não aqui.
      expect(chaveCabecalho('No. Patrimonial'), 'nopatrimonial');
      expect(chaveCabecalho('Nome'), 'nome');
    });

    test('espaço sobrando some', () {
      expect(chaveCabecalho('  COD. BARRAS  '), 'codbarras');
      expect(chaveCabecalho('Elemento de Despesa'), 'elementodedespesa');
    });
  });
}
