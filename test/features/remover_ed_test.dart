import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/inventory/tela_configuracoes_inventario.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// Tirar um elemento de despesa do inventário com a coleta em andamento — o
/// material bibliográfico que ninguém desmarcou na importação.
void main() {
  const geral = '44905242';
  const livros = '44905218';

  late Aparelho a;
  late Aparelho b;
  late Inventario inventario;

  setUp(() {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    a.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 6; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: '$i',
          sala: 'Sala $i',
          ed: i <= 3 ? geral : (i <= 5 ? livros : null),
        ),
    ]);
    RedeSimulada.distribuir(a, [b], inventario);
    RedeSimulada.sincronizar(a, b, inventario.id);
  });

  tearDown(() {
    a.fechar();
    b.fechar();
  });

  void verificar(Aparelho x, String item) => x.patrimonios.registrarVerificacao(
    patrimonio: x.patrimonios.porId(item)!,
    config: const ConfiguracaoLevantamento(sala: 'Auditório'),
    usuarioNome: x.apelido,
  );

  int operacoes(Aparelho x) =>
      x.banco.db.select('SELECT COUNT(*) AS n FROM ops').first['n'] as int;

  test('remover não apaga a verificação, e devolver a traz de volta', () {
    verificar(a, 'item-4');

    a.inventarios.alterarEdsExcluidos(inventario.id, excluir: [livros]);
    var p = a.patrimonios.progresso(inventario.id);
    expect(p.total, 4);
    expect(p.ignorados, 2);
    expect(p.verificados, 0, reason: 'o livro verificado sai da contagem');
    expect(a.patrimonios.porId('item-4')!.verificado, isTrue);

    a.inventarios.alterarEdsExcluidos(inventario.id, incluir: [livros]);
    p = a.patrimonios.progresso(inventario.id);
    expect(p.total, 6);
    expect(p.ignorados, 0);
    expect(p.verificados, 1);
  });

  test('a remoção chega ao outro aparelho, sem apagar o que ele levantou', () {
    // Bruno verificou um livro antes de saber da remoção.
    verificar(b, 'item-5');
    a.inventarios.alterarEdsExcluidos(inventario.id, excluir: [livros]);

    RedeSimulada.sincronizar(a, b, inventario.id);

    for (final x in [a, b]) {
      expect(x.inventarios.porId(inventario.id)!.edsExcluidos, [livros]);
      final p = x.patrimonios.progresso(inventario.id);
      expect(p.total, 4, reason: x.apelido);
      expect(p.ignorados, 2, reason: x.apelido);
      // O trabalho do Bruno está nos dois aparelhos, guardado.
      expect(x.patrimonios.porId('item-5')!.verificado, isTrue);
    }

    // Devolver em qualquer aparelho também converge.
    b.inventarios.alterarEdsExcluidos(inventario.id, incluir: [livros]);
    RedeSimulada.sincronizar(a, b, inventario.id);
    for (final x in [a, b]) {
      expect(x.inventarios.porId(inventario.id)!.edsExcluidos, isEmpty);
      expect(x.patrimonios.progresso(inventario.id).verificados, 1);
    }
  });

  test('soma ao que a importação já tinha excluído', () {
    a.inventarios.definirEdsExcluidos(inventario.id, [geral]);
    final lista = a.inventarios.alterarEdsExcluidos(
      inventario.id,
      excluir: [livros],
    );
    expect(lista, [livros, geral]..sort());
    expect(a.patrimonios.progresso(inventario.id).total, 1);
  });

  test('sem mudança, nada vai para o log', () {
    a.inventarios.alterarEdsExcluidos(inventario.id, excluir: [livros]);
    final antes = operacoes(a);
    a.inventarios.alterarEdsExcluidos(inventario.id, excluir: [livros]);
    a.inventarios.alterarEdsExcluidos(inventario.id, incluir: [geral]);
    expect(operacoes(a), antes);
  });

  test('"sem elemento de despesa" também sai do inventário', () {
    a.inventarios.alterarEdsExcluidos(inventario.id, excluir: ['']);
    final p = a.patrimonios.progresso(inventario.id);
    expect(p.total, 5);
    expect(p.ignorados, 1);
    expect(a.patrimonios.porId('item-6')!.ignorado, isTrue);
  });

  test('o resumo por ED conta itens, verificados e o que está fora', () {
    verificar(a, 'item-4');
    a.inventarios.alterarEdsExcluidos(inventario.id, excluir: [livros]);

    final resumo = {
      for (final r in a.patrimonios.resumoPorEd(inventario.id)) r.ed: r,
    };
    expect(resumo.keys, unorderedEquals([geral, livros, '']));
    expect(resumo[geral]!.itens, 3);
    expect(resumo[geral]!.foraDoInventario, isFalse);
    expect(resumo[livros]!.itens, 2);
    expect(resumo[livros]!.verificados, 1);
    expect(resumo[livros]!.foraDoInventario, isTrue);
  });

  group('tela', () {
    Future<void> abrir(WidgetTester tester) => montar(
      tester,
      TelaConfiguracoesInventario(inventarioId: inventario.id),
      banco: a.banco,
    );

    testWidgets('remover pede confirmação e diz o que se perde', (
      tester,
    ) async {
      verificar(a, 'item-4');
      await abrir(tester);

      await tester.tap(find.text('ED $livros'));
      await tester.pumpAndSettle();
      expect(find.text('Remover ED $livros?'), findsOneWidget);
      expect(find.textContaining('2 itens saem do inventário'), findsOne);
      expect(find.textContaining('1 deles já foi verificado'), findsOne);

      // Cancelar não muda nada.
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(a.inventarios.porId(inventario.id)!.edsExcluidos, isEmpty);

      await tester.tap(find.text('ED $livros'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remover'));
      await tester.pumpAndSettle();
      expect(a.inventarios.porId(inventario.id)!.edsExcluidos, [livros]);
      expect(find.textContaining('fora do inventário'), findsWidgets);

      // Ligar de novo devolve sem perguntar.
      await tester.tap(find.text('ED $livros'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(a.inventarios.porId(inventario.id)!.edsExcluidos, isEmpty);
    });

    testWidgets('inventário encerrado não deixa alterar', (tester) async {
      a.inventarios.encerrar(inventario.id);
      await abrir(tester);

      expect(find.textContaining('Reabra para alterar'), findsOneWidget);
      await tester.tap(find.text('ED $livros'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
