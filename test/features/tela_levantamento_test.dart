import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/sons.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';
import 'package:slap_mobile/features/survey/linha_leitura.dart';
import 'package:slap_mobile/features/survey/tela_levantamento.dart';

import '../apoio/app_de_teste.dart';

/// A tela de levantamento: o caminho quente, e o comportamento que uma
/// refatoração quebra sem ninguém perceber até a sala seguinte.
void main() {
  late Banco banco;
  late RepositorioPatrimonios repo;
  late RepositorioOperacoes ops;
  late Inventario inventario;
  late SonsMudos sons;

  setUp(() {
    banco = Banco.emMemoria();
    ops = RepositorioOperacoes(banco);
    repo = RepositorioPatrimonios(banco, ops);
    inventario = RepositorioInventarios(
      banco,
      ops,
    ).criar(nome: 'Campus', ano: 2026);
    repo.inserirLote(inventario.id, const [
      PatrimonioImportado(
        tombo: '023101',
        codigoBarras: '887101',
        descricao: 'MESA DE REUNIÃO',
        sala: 'Biblioteca',
      ),
      PatrimonioImportado(
        tombo: '023102',
        codigoBarras: '887102',
        descricao: 'CADEIRA FIXA',
        sala: 'Biblioteca',
      ),
    ]);
    sons = SonsMudos();
  });

  tearDown(() => banco.fechar());

  Future<ProviderContainer> abrir(WidgetTester tester) async {
    final c = await montar(
      tester,
      TelaLevantamento(inventarioId: inventario.id),
      banco: banco,
      sons: sons,
      preparar: (c) => c
          .read(configuracoesProvider.notifier)
          .definir(
            inventario.id,
            const ConfiguracaoLevantamento(sala: 'Auditório'),
          ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  /// Como o leitor externo: digita o código e manda "Enter".
  Future<void> ler(WidgetTester tester, String codigo) async {
    await tester.enterText(find.byType(TextField), codigo);
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
  }

  bool campoComFoco(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

  int operacoes() => ops.vetorDe(inventario.id)[banco.dispositivoId];

  testWidgets('o foco volta ao campo depois de cada leitura', (tester) async {
    await abrir(tester);
    expect(campoComFoco(tester), isTrue, reason: 'pronto para o leitor');

    await ler(tester, '887101');
    expect(repo.porId(repo.todos(inventario.id).first.id)!.verificado, isTrue);
    expect(campoComFoco(tester), isTrue);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
      reason: 'o campo limpa para a próxima leitura',
    );

    await ler(tester, '999999');
    expect(campoComFoco(tester), isTrue, reason: 'também depois de não achar');

    await ler(tester, '887102');
    expect(campoComFoco(tester), isTrue);
    expect(sons.tocados, [Som.sucesso, Som.naoLocalizado, Som.sucesso]);
  });

  testWidgets('item já verificado pede confirmação e não regrava sozinho', (
    tester,
  ) async {
    await abrir(tester);
    await ler(tester, '887101');
    final antes = operacoes();

    await ler(tester, '887101');
    expect(sons.tocados.last, Som.jaVerificado);
    expect(find.textContaining('já foi verificado'), findsOneWidget);
    expect(operacoes(), antes, reason: 'nada gravado sem confirmação');

    await tester.tap(find.text('Manter'));
    await tester.pumpAndSettle();
    expect(find.textContaining('já foi verificado'), findsNothing);
    expect(operacoes(), antes);
    expect(campoComFoco(tester), isTrue);

    await ler(tester, '887101');
    await tester.tap(find.text('Regravar'));
    await tester.pumpAndSettle();
    expect(operacoes(), greaterThan(antes), reason: 'regravou por escolha');
    expect(campoComFoco(tester), isTrue);
  });

  testWidgets('trocar entre código de barras e tombo não perde o foco', (
    tester,
  ) async {
    final c = await abrir(tester);
    expect(c.read(modoLeituraProvider), ModoLeitura.codigoBarras);

    await tester.tap(find.text('Tombo'));
    await tester.pumpAndSettle();
    expect(c.read(modoLeituraProvider), ModoLeitura.tombo);
    expect(campoComFoco(tester), isTrue);

    // E a leitura seguinte procura primeiro no tombo.
    await ler(tester, '023102');
    expect(sons.tocados.last, Som.sucesso);

    await tester.tap(find.text('Cód. barras'));
    await tester.pumpAndSettle();
    expect(campoComFoco(tester), isTrue);
  });

  testWidgets(
    'o histórico mostra os três resultados, cada um com o seu ícone',
    (tester) async {
      await abrir(tester);
      await ler(tester, '887101'); // registrado
      await ler(tester, '887101'); // já verificado
      await tester.tap(find.text('Manter'));
      await tester.pumpAndSettle();
      await ler(tester, '555555'); // não localizado

      final linhas = tester
          .widgetList<LinhaLeitura>(find.byType(LinhaLeitura))
          .toList();
      expect(linhas.map((l) => l.registro.resultado), [
        ResultadoLeitura.naoLocalizado,
        ResultadoLeitura.jaVerificado,
        ResultadoLeitura.sucesso,
      ]);

      for (final (resultado, icone, texto) in [
        (
          ResultadoLeitura.sucesso,
          Icons.check_circle_outline,
          'Tombo 023101 · Registrado',
        ),
        (ResultadoLeitura.jaVerificado, Icons.replay, 'Já verificado'),
        (
          ResultadoLeitura.naoLocalizado,
          Icons.search_off,
          'Não localizado neste inventário',
        ),
      ]) {
        final linha = find.byWidgetPredicate(
          (w) => w is LinhaLeitura && w.registro.resultado == resultado,
        );
        expect(
          find.descendant(of: linha, matching: find.byIcon(icone)),
          findsOneWidget,
          reason: resultado.name,
        );
        expect(
          find.descendant(of: linha, matching: find.textContaining(texto)),
          findsOneWidget,
          reason: resultado.name,
        );
      }
    },
  );

  testWidgets('sem sala definida, a configuração aparece antes de ler', (
    tester,
  ) async {
    await montar(
      tester,
      TelaLevantamento(inventarioId: inventario.id),
      banco: banco,
      sons: sons,
    );
    await tester.pumpAndSettle();
    expect(find.text('Aplicar às próximas leituras'), findsOneWidget);
  });
}
