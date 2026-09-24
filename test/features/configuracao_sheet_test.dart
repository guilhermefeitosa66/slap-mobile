import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/survey/configuracao_sheet.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// A folha "Aplicar às próximas leituras": sala e responsável são texto
/// livre com sugestões, e responsável em branco mantém o da planilha.
void main() {
  late Banco banco;
  late Inventario inventario;

  setUp(() {
    banco = Banco.emMemoria();
    final ops = RepositorioOperacoes(banco);
    inventario = RepositorioInventarios(
      banco,
      ops,
    ).criar(nome: 'Campus', ano: 2026);
    RepositorioPatrimonios(banco, ops).inserirLote(inventario.id, const [
      PatrimonioImportado(
        tombo: '1',
        sala: 'Auditório',
        responsavel: 'Carla Menezes',
      ),
      PatrimonioImportado(
        tombo: '2',
        sala: 'Biblioteca',
        responsavel: 'Bruno Carvalho',
      ),
    ]);
  });

  tearDown(() => banco.fechar());

  /// Abre a folha a partir de uma tela mínima, como o levantamento faz.
  Future<ProviderContainer> abrir(
    WidgetTester tester, {
    ConfiguracaoLevantamento? inicial,
  }) async {
    final c = await montar(
      tester,
      Consumer(
        builder: (context, ref, _) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => abrirConfiguracao(context, ref, inventario.id),
              child: const Text('Configurar'),
            ),
          ),
        ),
      ),
      banco: banco,
      preparar: (c) {
        if (inicial != null) {
          c
              .read(configuracoesProvider.notifier)
              .definir(inventario.id, inicial);
        }
      },
    );
    await tester.tap(find.text('Configurar'));
    await tester.pumpAndSettle();
    return c;
  }

  Finder campo(String rotulo) => find.widgetWithText(TextField, rotulo);

  Future<void> aplicar(WidgetTester tester) async {
    // Sem foco, a lista de sugestões fecha e não cobre o botão.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Aplicar e continuar'));
    await tester.tap(find.text('Aplicar e continuar'));
    await tester.pumpAndSettle();
  }

  testWidgets('responsável que não está na planilha é aceito', (tester) async {
    final c = await abrir(tester);
    await tester.enterText(campo('Sala onde você está'), 'Auditório');
    await tester.enterText(campo('Responsável'), 'Servidor Novo');
    await aplicar(tester);

    final config = c.read(configuracaoProvider(inventario.id))!;
    expect(config.sala, 'Auditório');
    expect(config.responsavel, 'Servidor Novo');
  });

  testWidgets('responsável em branco vale "não alterar"', (tester) async {
    final c = await abrir(
      tester,
      inicial: const ConfiguracaoLevantamento(
        sala: 'Auditório',
        responsavel: 'Carla Menezes',
      ),
    );
    expect(
      tester.widget<TextField>(campo('Responsável')).controller!.text,
      'Carla Menezes',
    );

    await tester.tap(find.byTooltip('Limpar o responsável'));
    await tester.pumpAndSettle();
    await aplicar(tester);

    final config = c.read(configuracaoProvider(inventario.id))!;
    expect(config.sala, 'Auditório');
    expect(config.responsavel, isNull);
  });

  testWidgets('só espaços também é em branco', (tester) async {
    final c = await abrir(tester);
    await tester.enterText(campo('Sala onde você está'), 'Auditório');
    await tester.enterText(campo('Responsável'), '   ');
    await aplicar(tester);
    expect(c.read(configuracaoProvider(inventario.id))!.responsavel, isNull);
  });

  testWidgets(
    'as sugestões filtram sem caixa nem acento, e preenchem o campo',
    (tester) async {
      final c = await abrir(tester);
      await tester.enterText(campo('Sala onde você está'), 'auditorio');
      await tester.pumpAndSettle();
      expect(find.text('Auditório'), findsOneWidget, reason: 'sugerida');
      expect(find.text('Biblioteca'), findsNothing);

      await tester.tap(find.text('Auditório'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(campo('Sala onde você está')).controller!.text,
        'Auditório',
      );

      await tester.enterText(campo('Responsável'), 'carla');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carla Menezes'));
      await tester.pumpAndSettle();
      await aplicar(tester);

      final config = c.read(configuracaoProvider(inventario.id))!;
      expect(config.sala, 'Auditório');
      expect(config.responsavel, 'Carla Menezes');
    },
  );

  testWidgets('o botão de limpar só existe com texto no campo', (tester) async {
    await abrir(tester);
    expect(find.byTooltip('Limpar o responsável'), findsNothing);
    await tester.enterText(campo('Responsável'), 'Alguém');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Limpar o responsável'), findsOneWidget);
  });

  test('o nome novo vira sugestão aqui e no outro aparelho', () {
    final a = Aparelho('Ana');
    final b = Aparelho('Bruno');
    addTearDown(() {
      a.fechar();
      b.fechar();
    });
    final inv = a.inventarios.criar(nome: 'Campus', ano: 2026);
    a.patrimonios.inserirLote(inv.id, const [
      PatrimonioImportado(tombo: '1', responsavel: 'Carla Menezes'),
    ]);
    RedeSimulada.distribuir(a, [b], inv);

    a.patrimonios.registrarVerificacao(
      patrimonio: a.patrimonios.todos(inv.id).single,
      config: const ConfiguracaoLevantamento(
        sala: 'Auditório',
        responsavel: 'Servidor Novo',
      ),
    );
    expect(a.patrimonios.responsaveis(inv.id), [
      'Carla Menezes',
      'Servidor Novo',
    ]);
    expect(b.patrimonios.responsaveis(inv.id), ['Carla Menezes']);

    RedeSimulada.sincronizar(a, b, inv.id);
    expect(b.patrimonios.responsaveis(inv.id), [
      'Carla Menezes',
      'Servidor Novo',
    ]);
  });
}
