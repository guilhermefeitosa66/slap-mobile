import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/codigo.dart';

void main() {
  group('chaveBusca', () {
    test('o código negativo da base real casa com a leitura positiva', () {
      // A planilha do SUAP exporta códigos de barras negativos. No SLAP, ler
      // 19281 no leitor não encontra o item gravado como -19281, e o
      // patrimônio aparece como não localizado mesmo estando na base.
      expect(chaveBusca('-19281'), chaveBusca('19281'));
      expect(chaveBusca('-17033'), '17033');
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
      expect(chaveBusca('-19281.0'), '19281');
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
      expect(mesmoCodigo('-19281', '19281'), isTrue);
      expect(mesmoCodigo('019281', '19281'), isTrue);
    });

    test('código vazio não casa com nada, nem com outro vazio', () {
      expect(mesmoCodigo('', ''), isFalse);
      expect(mesmoCodigo(null, '123'), isFalse);
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
