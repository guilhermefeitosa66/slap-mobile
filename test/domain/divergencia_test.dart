import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/domain/divergencia.dart';
import 'package:slap_mobile/domain/patrimonio.dart';
import 'package:slap_mobile/domain/valores.dart';

/// Estado de conservação no vocabulário do SUAP, comparado com o do cadastro.
void main() {
  Patrimonio item({
    EstadoConservacao? noSuap,
    EstadoConservacao? lido,
    bool verificado = true,
  }) => Patrimonio(
    id: 'p',
    inventarioId: 'i',
    tombo: '23254',
    codigoBarras: '-19281',
    salaOriginal: 'Biblioteca',
    responsavelOriginal: 'Ana',
    conservacaoOriginal: noSuap,
    verificado: verificado,
    conservacao: lido,
  );

  group('estado de conservação', () {
    test('manter o do SUAP não é divergência', () {
      final p = item(noSuap: EstadoConservacao.ocioso);
      expect(p.conservacaoEfetiva, EstadoConservacao.ocioso);
      expect(divergenciasDe(p), isEmpty);
      expect(classificar(p), Classificacao.ok);
    });

    test('estado diferente do SUAP é divergência, com os rótulos dele', () {
      final p = item(
        noSuap: EstadoConservacao.bom,
        lido: EstadoConservacao.recuperavel,
      );
      final d = divergenciasDe(p).single;
      expect(d.campo, CampoDivergente.conservacao);
      expect(d.valorSuap, 'Bom');
      expect(d.valorEncontrado, 'Recuperável');
      expect(classificar(p), Classificacao.divergente);
    });

    test('sem estado no SUAP, o lido é informação nova', () {
      final p = item(lido: EstadoConservacao.antieconomico);
      expect(divergenciasDe(p), isEmpty);
      expect(p.exigeAtencao, isTrue);
    });

    test('inservível no SUAP continua pedindo providência', () {
      expect(item(noSuap: EstadoConservacao.irreversivel).exigeAtencao, isTrue);
      expect(
        item(
          noSuap: EstadoConservacao.irreversivel,
          verificado: false,
        ).exigeAtencao,
        isFalse,
        reason: 'não encontrado: não se sabe como está',
      );
      expect(item(noSuap: EstadoConservacao.ocioso).exigeAtencao, isFalse);
    });

    test('o vocabulário antigo diverge do SUAP e é sinalizado', () {
      final p = item(
        noSuap: EstadoConservacao.bom,
        lido: EstadoConservacao.ruim,
      );
      expect(divergenciasDe(p).single.valorEncontrado, 'Ruim (antigo)');
      expect(p.exigeAtencao, isTrue);
      expect(
        EstadoConservacao.selecionaveis,
        isNot(contains(EstadoConservacao.ruim)),
      );
    });
  });

  group('valores do SUAP', () {
    test('os valores gravados são exatamente os do SUAP', () {
      // suap/patrimonio/models.py, Inventario.CHOICES_CONSERVACAO.
      expect(EstadoConservacao.selecionaveis.map((e) => e.valor), [
        'bom',
        'ocioso',
        'recuperavel',
        'antieconomico',
        'irreversivel',
      ]);
    });

    test('a planilha é lida pelo rótulo, pelo valor ou pelo código', () {
      expect(
        EstadoConservacao.daPlanilha('Antieconômico'),
        EstadoConservacao.antieconomico,
      );
      expect(
        EstadoConservacao.daPlanilha('ANTIECONOMICO'),
        EstadoConservacao.antieconomico,
      );
      expect(
        EstadoConservacao.daPlanilha('Irrecuperável'),
        EstadoConservacao.irreversivel,
      );
      expect(
        EstadoConservacao.daPlanilha('Irreversível'),
        EstadoConservacao.irreversivel,
      );
      expect(EstadoConservacao.daPlanilha('4'), EstadoConservacao.ocioso);
      expect(EstadoConservacao.daPlanilha('-'), isNull);
      expect(EstadoConservacao.daPlanilha('Não aplicar'), isNull);
      expect(EstadoConservacao.daPlanilha('Regular'), isNull);
      expect(EstadoConservacao.daPlanilha(null), isNull);
    });
  });
}
