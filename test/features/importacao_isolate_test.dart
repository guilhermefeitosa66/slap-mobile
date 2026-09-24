import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/import/importacao_em_segundo_plano.dart';

/// A importação de uma planilha de campus não pode travar a interface.
///
/// Usa banco em arquivo, como no aparelho: é o que permite a segunda conexão
/// no isolate.
void main() {
  late Directory pasta;
  late Banco banco;
  late Inventario inventario;

  setUp(() async {
    pasta = await Directory.systemTemp.createTemp('slap_importacao_');
    banco = await Banco.abrir(caminho: '${pasta.path}/slap.db');
    inventario = RepositorioInventarios(
      banco,
      RepositorioOperacoes(banco),
    ).criar(nome: 'Campus Picos', ano: 2026);
  });

  tearDown(() async {
    banco.fechar();
    await pasta.delete(recursive: true);
  });

  /// CSV como o SUAP exporta, com [linhas] patrimônios.
  Uint8List planilha(int linhas) {
    final texto = StringBuffer(
      'Nº;Tombo;Código de Barras;ED;Descrição;Responsável;Sala\n',
    );
    for (var i = 1; i <= linhas; i++) {
      final tombo = i.toString().padLeft(6, '0');
      texto.writeln(
        '$i;$tombo;-$tombo;44905242;CADEIRA $i;Fulano;Sala ${i % 40}',
      );
    }
    return Uint8List.fromList(utf8.encode(texto.toString()));
  }

  int contar() => RepositorioPatrimonios(
    banco,
    RepositorioOperacoes(banco),
  ).progresso(inventario.id).total;

  test('10 mil linhas entram sem bloquear e com progresso', () async {
    final (lida, mapeamento) = await lerPlanilhaEmSegundoPlano(
      nomeArquivo: 'suap.csv',
      bytes: planilha(10000),
    );
    expect(mapeamento.valido, isTrue);
    final previa = await prepararEmSegundoPlano(lida, mapeamento);
    expect(previa.total, 10000);

    // Enquanto grava, a thread "de interface" continua respondendo: o
    // cronômetro abaixo só avança se o laço de eventos estiver livre.
    var batidas = 0;
    final cronometro = Timer.periodic(
      const Duration(milliseconds: 1),
      (_) => batidas++,
    );
    final progressos = <ProgressoImportacao>[];

    final resultado = await importarEmSegundoPlano(
      banco: banco,
      inventarioId: inventario.id,
      previa: previa,
      aoProgredir: progressos.add,
    );
    cronometro.cancel();

    expect(resultado.inseridos, 10000);
    expect(
      contar(),
      10000,
      reason: 'a primeira conexão enxerga o que o isolate gravou',
    );

    expect(progressos, isNotEmpty);
    expect(progressos.last.feitos, 10000);
    expect(progressos.last.total, 10000);
    for (var i = 1; i < progressos.length; i++) {
      expect(
        progressos[i].feitos,
        greaterThanOrEqualTo(progressos[i - 1].feitos),
      );
    }
    expect(
      batidas,
      greaterThan(0),
      reason: 'o laço de eventos rodou durante a gravação',
    );
  });

  test('falha no meio não deixa importação parcial', () async {
    // Uma linha no meio do arquivo é recusada pelo banco.
    banco.db.execute(
      "CREATE TRIGGER falha_simulada BEFORE INSERT ON patrimonios "
      "WHEN NEW.tombo = '005000' "
      "BEGIN SELECT RAISE(ABORT, 'falha simulada'); END",
    );

    final (lida, mapeamento) = await lerPlanilhaEmSegundoPlano(
      nomeArquivo: 'suap.csv',
      bytes: planilha(8000),
    );
    final previa = await prepararEmSegundoPlano(lida, mapeamento);
    final progressos = <ProgressoImportacao>[];

    await expectLater(
      importarEmSegundoPlano(
        banco: banco,
        inventarioId: inventario.id,
        previa: previa,
        aoProgredir: progressos.add,
      ),
      throwsA(
        isA<FalhaImportacao>().having(
          (e) => e.mensagem,
          'mensagem',
          contains('falha simulada'),
        ),
      ),
    );

    expect(progressos, isNotEmpty, reason: 'chegou a gravar parte');
    expect(contar(), 0, reason: 'e desfez tudo');
  });

  test('reimportar pelo isolate preserva o que já existe', () async {
    final (lida, mapeamento) = await lerPlanilhaEmSegundoPlano(
      nomeArquivo: 'suap.csv',
      bytes: planilha(300),
    );
    final previa = await prepararEmSegundoPlano(lida, mapeamento);

    await importarEmSegundoPlano(
      banco: banco,
      inventarioId: inventario.id,
      previa: previa,
    );
    final segunda = await importarEmSegundoPlano(
      banco: banco,
      inventarioId: inventario.id,
      previa: previa,
    );

    expect(segunda.inseridos, 0);
    expect(segunda.preservados, 300);
    expect(contar(), 300);
  });
}
