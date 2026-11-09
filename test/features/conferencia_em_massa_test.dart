import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/divergencia.dart';
import 'package:slap_mobile/domain/patrimonio.dart';
import 'package:slap_mobile/domain/valores.dart';
import 'package:slap_mobile/features/divergence/tela_itens.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';

import '../apoio/app_de_teste.dart';

/// Seleção, conferência em massa e o gesto de desfazer na lista de itens.
void main() {
  late Banco banco;
  late RepositorioPatrimonios repo;
  late RepositorioOperacoes ops;
  late RepositorioInventarios inventarios;
  late Inventario inventario;

  setUp(() {
    banco = Banco.emMemoria();
    ops = RepositorioOperacoes(banco);
    repo = RepositorioPatrimonios(banco, ops);
    inventarios = RepositorioInventarios(banco, ops);
    inventario = inventarios.criar(nome: 'Campus', ano: 2026);
    repo.inserirLote(inventario.id, const [
      PatrimonioImportado(tombo: '1', codigoBarras: '11', descricao: 'MESA'),
      PatrimonioImportado(tombo: '2', codigoBarras: '12', descricao: 'CADEIRA'),
      PatrimonioImportado(tombo: '3', codigoBarras: '13', descricao: 'ARMÁRIO'),
    ]);
  });

  tearDown(() => banco.fechar());

  Patrimonio item(String tombo) =>
      repo.todos(inventario.id).firstWhere((p) => p.tombo == tombo);

  void verificar(String tombo) => repo.registrarVerificacao(
    patrimonio: item(tombo),
    config: const ConfiguracaoLevantamento(sala: 'Sala 1'),
  );

  Future<void> abrir(
    WidgetTester tester, {
    Classificacao? classificacao,
    ConfiguracaoLevantamento? config,
  }) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await montar(
      tester,
      TelaItens(inventarioId: inventario.id, classificacao: classificacao),
      banco: banco,
      preparar: config == null
          ? null
          : (c) => c
                .read(configuracoesProvider.notifier)
                .definir(inventario.id, config),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, String texto) async {
    await tester.tap(find.text(texto));
    await tester.pumpAndSettle();
  }

  testWidgets('segurar um item entra na seleção, e desmarcar o último sai', (
    tester,
  ) async {
    await abrir(tester);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('Conferir em massa'), findsNothing);

    await tester.longPress(find.text('MESA'));
    await tester.pumpAndSettle();
    expect(find.text('1 selecionado'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(3));
    expect(find.text('Conferir em massa'), findsOneWidget);

    await tocar(tester, 'CADEIRA');
    expect(find.text('2 selecionados'), findsOneWidget);
    expect(find.byType(DetalhePatrimonio), findsNothing);

    await tocar(tester, 'CADEIRA');
    await tocar(tester, 'MESA');
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('selecionar todos pega também o que não foi carregado', (
    tester,
  ) async {
    repo.inserirLote(inventario.id, [
      for (var i = 100; i < 350; i++)
        PatrimonioImportado(tombo: '$i', descricao: 'ITEM $i'),
    ]);
    await abrir(tester);
    await tester.longPress(find.text('MESA'));
    await tester.pumpAndSettle();

    await tocar(tester, 'Selecionar todos');
    expect(find.text('253 selecionados'), findsOneWidget);

    await tocar(tester, 'Desmarcar todos');
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('a conferência vem preenchida e grava em todos os marcados', (
    tester,
  ) async {
    await abrir(
      tester,
      classificacao: Classificacao.naoLocalizado,
      config: const ConfiguracaoLevantamento(
        sala: 'Biblioteca',
        conservacao: EstadoConservacao.ocioso,
        situacao: SituacaoUso.ocioso,
        responsavel: 'Ana',
      ),
    );
    await tester.longPress(find.text('MESA'));
    await tester.pumpAndSettle();
    await tocar(tester, 'CADEIRA');
    await tocar(tester, 'Conferir em massa');

    expect(find.widgetWithText(TextField, 'Biblioteca'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Ana'), findsOneWidget);

    await tocar(tester, 'Conferir 2 itens');

    for (final tombo in ['1', '2']) {
      final p = item(tombo);
      expect(p.verificado, isTrue);
      expect(p.salaAtual, 'Biblioteca');
      expect(p.responsavelAtual, 'Ana');
      expect(p.conservacao, EstadoConservacao.ocioso);
      expect(p.situacao, SituacaoUso.ocioso);
    }
    expect(item('3').verificado, isFalse);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('2 itens conferidos'), findsOneWidget);
    expect(find.text('MESA'), findsNothing, reason: 'saiu de "não verificado"');
  });

  testWidgets('item já verificado na seleção é avisado antes de confirmar', (
    tester,
  ) async {
    verificar('1');
    await abrir(tester);
    await tester.longPress(find.text('MESA'));
    await tester.pumpAndSettle();
    await tocar(tester, 'Conferir em massa');

    expect(find.textContaining('1 item já foi verificado'), findsOneWidget);
  });

  testWidgets('desistir da conferência não grava nem muda a configuração', (
    tester,
  ) async {
    await abrir(tester);
    final antes = ops.vetorDe(inventario.id)[banco.dispositivoId];
    await tester.longPress(find.text('MESA'));
    await tester.pumpAndSettle();
    await tocar(tester, 'Conferir em massa');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(ops.vetorDe(inventario.id)[banco.dispositivoId], antes);
    expect(find.text('1 selecionado'), findsOneWidget);
  });

  testWidgets('voltar sai da seleção antes de sair da tela', (tester) async {
    await abrir(tester);
    await tester.longPress(find.text('MESA'));
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(TelaItens), findsOneWidget);
  });

  testWidgets('deslizar na lista de verificados limpa os campos do item', (
    tester,
  ) async {
    repo.inserirLote(inventario.id, const [
      PatrimonioImportado(tombo: '9', descricao: 'BANCO', sala: 'Sala 1'),
    ]);
    verificar('9');
    await abrir(tester, classificacao: Classificacao.ok);
    expect(find.text('BANCO'), findsOneWidget);

    await tester.drag(find.text('BANCO'), const Offset(-700, 0));
    await tester.pumpAndSettle();

    final p = item('9');
    expect(p.verificado, isFalse);
    expect(p.salaAtual, isNull);
    expect(p.situacao, isNull);
    expect(find.text('BANCO'), findsNothing);
  });

  testWidgets('em "todos", o item desfeito fica na lista, sem verificação', (
    tester,
  ) async {
    verificar('1');
    await abrir(tester);

    await tester.drag(find.text('MESA'), const Offset(-700, 0));
    await tester.pumpAndSettle();

    expect(item('1').verificado, isFalse);
    expect(find.text('MESA'), findsOneWidget);
  });

  testWidgets('item não verificado não tem o que desfazer', (tester) async {
    await abrir(tester);
    final antes = ops.vetorDe(inventario.id)[banco.dispositivoId];

    await tester.drag(find.text('MESA'), const Offset(-700, 0));
    await tester.pumpAndSettle();

    expect(ops.vetorDe(inventario.id)[banco.dispositivoId], antes);
  });

  testWidgets('inventário encerrado não seleciona nem desfaz', (tester) async {
    verificar('1');
    inventarios.encerrar(inventario.id);
    await abrir(tester);

    await tester.longPress(find.text('MESA'));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNothing);
    // Sem seleção, soltar o dedo é um toque comum: abre a ficha.
    Navigator.of(tester.element(find.byType(DetalhePatrimonio))).pop();
    await tester.pumpAndSettle();

    await tester.drag(find.text('MESA'), const Offset(-700, 0));
    await tester.pumpAndSettle();
    expect(item('1').verificado, isTrue);
  });
}
