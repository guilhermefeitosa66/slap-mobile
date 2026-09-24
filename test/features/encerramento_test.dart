import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/inventory/tela_dashboard.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';
import 'package:slap_mobile/features/survey/tela_levantamento.dart';
import 'package:sqlite3/sqlite3.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// Encerrar dá um marco ao inventário, e o marco sincroniza.
void main() {
  late Aparelho a;
  late Aparelho b;
  late Inventario inventario;

  setUp(() {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    a.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 3; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: '$i',
          sala: 'Sala',
        ),
    ]);
    RedeSimulada.distribuir(a, [b], inventario);
  });

  tearDown(() {
    a.fechar();
    b.fechar();
  });

  bool encerradoEm(Aparelho x) => x.inventarios.porId(inventario.id)!.encerrado;

  test('encerrar num aparelho reflete no outro depois de sincronizar', () {
    a.inventarios.encerrar(inventario.id);
    expect(encerradoEm(a), isTrue);
    expect(encerradoEm(b), isFalse);

    RedeSimulada.sincronizar(a, b, inventario.id);
    expect(encerradoEm(b), isTrue);
    expect(b.inventarios.encerradoPor(inventario.id), 'Ana');

    // E reabrir no outro volta ao primeiro.
    b.inventarios.reabrir(inventario.id);
    RedeSimulada.sincronizar(a, b, inventario.id);
    expect(encerradoEm(a), isFalse);
    expect(encerradoEm(b), isFalse);
  });

  test('encerrar e reabrir ficam no log, com autor', () {
    a.inventarios.encerrar(inventario.id);
    a.inventarios.reabrir(inventario.id);

    final historico = a.ops.historicoDe(inventario.id);
    expect(historico.map((o) => o.campo), ['encerrado_em', 'encerrado_em']);
    expect(historico.first.valor, isNull, reason: 'o mais recente reabre');
    expect(historico.every((o) => o.usuarioNome == 'Ana'), isTrue);
  });

  test('operação antiga chegando depois não desfaz a mais nova', () {
    a.inventarios.encerrar(inventario.id);
    a.inventarios.reabrir(inventario.id);
    final [reabertura, encerramento] = a.ops.historicoDe(inventario.id);

    // B recebe primeiro a reabertura e só depois, noutro lote, o
    // encerramento — como aconteceria vindo por caminhos diferentes.
    b.ops.aplicarRemotas([reabertura], inventarioId: inventario.id);
    b.ops.aplicarRemotas([encerramento], inventarioId: inventario.id);

    expect(encerradoEm(b), isFalse, reason: 'vale o de maior HLC');
    expect(encerradoEm(a), isFalse);
  });

  test('leitura feita antes de saber do encerramento não se perde', () {
    // Bruno estava longe da rede e continuou lendo.
    b.patrimonios.registrarVerificacao(
      patrimonio: b.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Auditório'),
      usuarioNome: 'Bruno',
    );
    a.inventarios.encerrar(inventario.id);

    RedeSimulada.sincronizar(a, b, inventario.id);
    expect(encerradoEm(b), isTrue);
    expect(a.patrimonios.porId('item-1')!.verificado, isTrue);
  });

  test('banco da versão 1 migra e aprende o vencedor pelo log', () async {
    final pasta = await Directory.systemTemp.createTemp('slap_migracao_');
    addTearDown(() => pasta.delete(recursive: true));
    final caminho = '${pasta.path}/v1.db';

    // Um banco como a versão anterior do aplicativo deixava.
    final antigo = sqlite3.open(caminho);
    for (final ddl in ddlEsquema) {
      antigo.execute(ddl);
    }
    antigo.execute('PRAGMA user_version = 1');
    antigo.execute(
      "INSERT INTO inventarios (id, nome, ano, criado_em, dispositivo_origem, "
      "chave_sync) VALUES ('inv', 'Nome novo', 2026, 0, 'd', 'k')",
    );
    for (final (seq, hlc, nome) in [
      (1, '000001000000000-0000-d', 'Nome antigo'),
      (2, '000002000000000-0000-d', 'Nome novo'),
    ]) {
      antigo.execute(
        'INSERT INTO ops (op_id, inventario_id, entidade, entidade_id, campo, '
        'valor, hlc, dispositivo, seq, criado_em) '
        "VALUES ('op$seq', 'inv', 'inventario', 'inv', 'nome', ?, ?, 'd', ?, 0)",
        [nome, hlc, seq],
      );
    }
    antigo.close();

    final banco = await Banco.abrir(caminho: caminho);
    addTearDown(banco.fechar);

    expect(
      banco.db.select('PRAGMA user_version').first['user_version'],
      versaoEsquema,
    );
    final vencedor = banco.db.select(
      "SELECT valor, op_id FROM campos_inventario WHERE inventario_id = 'inv'",
    );
    expect(vencedor.single['valor'], 'Nome novo');
    expect(vencedor.single['op_id'], 'op2');
  });

  group('tela', () {
    testWidgets(
      'encerrar pelo painel avisa quantos ficam como não localizados',
      (tester) async {
        a.patrimonios.registrarVerificacao(
          patrimonio: a.patrimonios.porId('item-1')!,
          config: const ConfiguracaoLevantamento(sala: 'Sala'),
        );
        await montar(
          tester,
          TelaDashboard(inventarioId: inventario.id),
          banco: a.banco,
        );
        expect(find.text('Levantar'), findsOneWidget);

        await tester.tap(find.byTooltip('Mais ações'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Encerrar inventário'));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('2 itens ainda não foram verificados'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Encerrar'));
        await tester.pumpAndSettle();

        expect(encerradoEm(a), isTrue);
        expect(find.text('Inventário encerrado'), findsOneWidget);
        expect(find.text('Levantar'), findsNothing);
        expect(find.text('Reabrir'), findsOneWidget);
      },
    );

    testWidgets('levantamento de inventário encerrado não grava nada', (
      tester,
    ) async {
      a.inventarios.encerrar(inventario.id);
      await montar(
        tester,
        TelaLevantamento(inventarioId: inventario.id),
        banco: a.banco,
        preparar: (c) => c
            .read(configuracoesProvider.notifier)
            .definir(inventario.id, const ConfiguracaoLevantamento(sala: 'X')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inventário encerrado'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        RepositorioPatrimonios(
          a.banco,
          a.ops,
        ).progresso(inventario.id).verificados,
        0,
      );
    });
  });
}
