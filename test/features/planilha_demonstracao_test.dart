import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/features/import/importador.dart';
import 'package:slap_mobile/features/import/leitor_planilha.dart';
import 'package:slap_mobile/features/import/mapeamento.dart';

/// A planilha de demonstração é o que quem revisa o aplicativo na loja usa
/// para ver o levantamento funcionando: se ela deixar de importar, a revisão
/// fica sem ter o que olhar.
void main() {
  test('planilha de demonstração importa inteira, com todas as colunas', () {
    final arquivo = File('docs/loja/planilha-demonstracao.xlsx');
    final planilha = LeitorPlanilha.ler(
      nomeArquivo: 'planilha-demonstracao.xlsx',
      bytes: arquivo.readAsBytesSync(),
    );

    final mapeamento = detectarMapeamento(planilha.linhas);
    expect(mapeamento.valido, isTrue);
    for (final campo in CampoImportacao.values) {
      expect(mapeamento.colunaDe(campo), isNotNull, reason: campo.rotulo);
    }

    final previa = Importador.preparar(planilha, mapeamento);
    expect(previa.total, 60);
    expect(previa.semTombo, 0);
    expect(previa.tombosDuplicados, isEmpty);
    expect(previa.itens.first.tombo, '023101');
  });
}
