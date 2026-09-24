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

  Future<ProviderContainer> abrir(
    WidgetTester tester, {
    String sala = 'Auditório',
  }) async {
    final c = await montar(
      tester,
      TelaLevantamento(inventarioId: inventario.id),
      banco: banco,
      sons: sons,
      preparar: (c) => c
          .read(configuracoesProvider.notifier)
          .definir(inventario.id, ConfiguracaoLevantamento(sala: sala)),
    );
    await tester.pumpAndSettle();
    return c;
  }

  /// O contador da barra do alto, como ele aparece na tela.
  String contador(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(
          of: find.byType(ContadorSala),
          matching: find.byType(Text),
        ),
      )
      .textSpan!
      .toPlainText();

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

  testWidgets('o contador é o da sala atual, e anda a cada leitura', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    await abrir(tester, sala: 'biblioteca');
    expect(contador(tester), '0/2', reason: 'o que a planilha manda procurar');

    await ler(tester, '887101');
    expect(contador(tester), '1/2');

    await ler(tester, '887102');
    expect(contador(tester), '2/2');
    expect(
      find.bySemanticsLabel('Sala biblioteca: 2 de 2 verificados'),
      findsOneWidget,
    );
    semantica.dispose();
  });

  testWidgets('sala fora da planilha conta o que foi lido ali, sem fração', (
    tester,
  ) async {
    final semantica = tester.ensureSemantics();
    final c = await abrir(tester, sala: 'Almoxarifado');
    expect(contador(tester), '0 lidos', reason: 'nunca "0/0"');

    await ler(tester, '887101');
    expect(contador(tester), '1 lido');
    expect(
      find.bySemanticsLabel('Sala Almoxarifado, fora da planilha: 1 item lido'),
      findsOneWidget,
    );

    // Trocar de sala refaz a conta: o item continua verificado na sala de
    // origem, que é onde ninguém precisa mais procurá-lo.
    c
        .read(configuracoesProvider.notifier)
        .definir(
          inventario.id,
          const ConfiguracaoLevantamento(sala: 'BIBLIOTECA'),
        );
    await tester.pumpAndSettle();
    expect(contador(tester), '1/2');
    semantica.dispose();
  });

  testWidgets('item de outra sala conta ao lado, fora do denominador', (
    tester,
  ) async {
    repo.inserirLote(inventario.id, const [
      PatrimonioImportado(
        tombo: '023201',
        codigoBarras: '887201',
        descricao: 'ARMÁRIO',
        sala: 'Almoxarifado',
      ),
    ]);
    final semantica = tester.ensureSemantics();
    await abrir(tester, sala: 'Almoxarifado');
    expect(contador(tester), '0/1');

    // Item da Biblioteca encontrado no Almoxarifado: não entra no que há para
    // procurar ali, mas a leitura precisa aparecer em algum lugar.
    await ler(tester, '887101');
    expect(contador(tester), '0/1 +1');
    expect(
      find.bySemanticsLabel(
        'Sala Almoxarifado: 0 de 1 verificados, mais 1 item de outra sala',
      ),
      findsOneWidget,
    );

    await ler(tester, '887201');
    expect(contador(tester), '1/1 +1');
    semantica.dispose();
  });

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
