import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/domain/patrimonio.dart';
import 'package:slap_mobile/domain/valores.dart';
import 'package:slap_mobile/features/divergence/tela_itens.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// O detalhe de um item: três seções, tom por divergência e edição do
/// levantamento pelo log de operações.
void main() {
  late Aparelho a;
  late Inventario inventario;

  setUp(() {
    a = Aparelho('Ana Souza');
    a.banco.gravarConfig(Config.usuarioMatricula, '2091234');
    inventario = a.inventarios.criar(nome: 'Campus', ano: 2026);
    a.patrimonios.inserirLote(inventario.id, const [
      PatrimonioImportado(
        ordem: '1',
        tombo: '000001',
        codigoBarras: '887001',
        ed: '449052',
        descricao: 'MESA DE REUNIÃO',
        sala: 'Biblioteca',
        responsavel: 'Carla Menezes',
        valor: '350,00',
      ),
      PatrimonioImportado(
        ordem: '2',
        tombo: '000002',
        descricao: 'CADEIRA',
        sala: 'Biblioteca',
        responsavel: 'Carla Menezes',
      ),
    ]);
  });

  tearDown(() => a.fechar());

  Patrimonio item(String tombo) =>
      a.patrimonios.todos(inventario.id).firstWhere((p) => p.tombo == tombo);

  int operacoes(Patrimonio p) => a.ops.historicoDe(p.id).length;

  Patrimonio verificar(
    String tombo, {
    String sala = 'Biblioteca',
    String? responsavel,
  }) => a.patrimonios.registrarVerificacao(
    patrimonio: item(tombo),
    config: ConfiguracaoLevantamento(sala: sala, responsavel: responsavel),
    usuarioNome: 'Ana Souza',
    usuarioMatricula: '2091234',
  );

  group('alterarLevantamento', () {
    test('grava só os campos que mudaram, e quem encontrou permanece', () {
      verificar('000001', sala: 'Auditório');
      final antes = operacoes(item('000001'));

      // O mesmo valor escrito diferente não é mudança.
      a.patrimonios.alterarLevantamento(
        patrimonio: item('000001'),
        sala: 'auditório ',
        responsavel: '',
        conservacao: EstadoConservacao.bom,
        situacao: SituacaoUso.ativo,
      );
      expect(operacoes(item('000001')), antes, reason: 'nada mudou');
      expect(item('000001').salaAtual, 'Auditório');

      a.patrimonios.alterarLevantamento(
        patrimonio: item('000001'),
        sala: 'Sala 3',
        responsavel: '',
        conservacao: EstadoConservacao.regular,
        situacao: SituacaoUso.ativo,
        usuarioNome: 'Bruno',
      );
      expect(operacoes(item('000001')), antes + 2);
      expect(
        a.ops
            .historicoDe(item('000001').id)
            .take(2)
            .map((o) => o.campo)
            .toSet(),
        {CampoPatrimonio.salaAtual, CampoPatrimonio.conservacao},
      );
      final depois = item('000001');
      expect(depois.salaAtual, 'Sala 3');
      expect(depois.conservacao, EstadoConservacao.regular);
      expect(depois.situacao, SituacaoUso.ativo);
      expect(depois.verificadoPor, 'Ana Souza', reason: 'quem encontrou fica');
    });

    test('item não localizado passa a verificado por quem salvou', () {
      final antes = item('000002');
      expect(antes.verificado, isFalse);

      a.patrimonios.alterarLevantamento(
        patrimonio: antes,
        sala: 'Auditório',
        responsavel: 'Servidor Novo',
        conservacao: EstadoConservacao.ruim,
        situacao: SituacaoUso.ocioso,
        usuarioNome: 'Bruno',
        usuarioMatricula: '77',
      );

      final depois = item('000002');
      expect(depois.verificado, isTrue);
      expect(depois.verificadoPor, 'Bruno');
      expect(depois.verificadoPorMatricula, '77');
      expect(depois.verificadoPorDispositivo, a.dispositivoId);
      expect(depois.verificadoEm, isNotNull);
      expect(depois.salaAtual, 'Auditório');
      expect(depois.responsavelAtual, 'Servidor Novo');
      expect(depois.conservacao, EstadoConservacao.ruim);
      expect(depois.situacao, SituacaoUso.ocioso);
      expect(operacoes(depois), 5);
    });

    test('responsável em branco volta ao da planilha', () {
      verificar('000001', responsavel: 'Elisa Prado');
      expect(item('000001').responsavelEfetivo, 'Elisa Prado');
      final antes = operacoes(item('000001'));

      a.patrimonios.alterarLevantamento(
        patrimonio: item('000001'),
        sala: 'Biblioteca',
        responsavel: '  ',
        conservacao: EstadoConservacao.bom,
        situacao: SituacaoUso.ativo,
      );

      expect(operacoes(item('000001')), antes + 1);
      final ultima = a.ops.historicoDe(item('000001').id).first;
      expect(ultima.campo, CampoPatrimonio.responsavelAtual);
      expect(ultima.valor, isNull);
      expect(item('000001').responsavelAtual, isNull);
      expect(item('000001').responsavelEfetivo, 'Carla Menezes');
    });

    test('a alteração chega ao outro aparelho pela sincronização', () {
      final b = Aparelho('Bruno');
      addTearDown(b.fechar);
      RedeSimulada.distribuir(a, [b], inventario);
      verificar('000001');

      a.patrimonios.alterarLevantamento(
        patrimonio: item('000001'),
        sala: 'Sala 3',
        responsavel: 'Servidor Novo',
        conservacao: EstadoConservacao.regular,
        situacao: SituacaoUso.ativo,
      );
      RedeSimulada.sincronizar(a, b, inventario.id);

      final id = item('000001').id;
      expect(impressaoDe(b, id), impressaoDe(a, id));
      expect(b.patrimonios.porId(id)!.salaAtual, 'Sala 3');
      expect(
        b.patrimonios.responsaveis(inventario.id),
        contains('Servidor Novo'),
      );
    });
  });

  group('painel', () {
    /// Tela alta de propósito: a folha ocupa 70% dela e a lista só constrói o
    /// que cabe, então numa tela de celular um `findsNothing` passaria só
    /// porque o widget ficou abaixo da dobra.
    Future<void> abrir(WidgetTester tester, String tombo) async {
      tester.view.physicalSize = const Size(1080, 7200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await montar(
        tester,
        Scaffold(body: DetalhePatrimonio(patrimonioId: item(tombo).id)),
        banco: a.banco,
      );
      await tester.pumpAndSettle();
    }

    Finder rolavel() => find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(Scrollable),
        )
        .first;

    Future<void> tocar(WidgetTester tester, String texto) async {
      // Sem foco, a lista de sugestões fecha e não cobre o botão.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(texto),
        100,
        scrollable: rolavel(),
      );
      await tester.tap(find.text(texto));
      await tester.pumpAndSettle();
    }

    Finder icone(String significado) => find.byWidgetPredicate(
      (w) => w is Icon && w.semanticLabel == significado,
    );

    Finder campo(String rotulo) => find.widgetWithText(TextField, rotulo);

    testWidgets('três seções, em verde quando confere com a planilha', (
      tester,
    ) async {
      verificar('000001'); // mesma sala; responsável não alterado
      await abrir(tester, '000001');

      expect(find.text('OK'), findsOneWidget);
      expect(find.text('MESA DE REUNIÃO'), findsOneWidget);
      expect(find.text('Dados da planilha (SUAP)'), findsOneWidget);
      expect(find.text('887001'), findsOneWidget);
      expect(find.text('449052'), findsOneWidget);
      expect(find.text('350,00'), findsOneWidget);
      expect(find.text('Levantamento'), findsOneWidget);
      expect(find.text('Divergências'), findsNothing);

      expect(icone('igual à planilha'), findsNWidgets(2));
      expect(icone('diferente da planilha'), findsNothing);
      for (final i in tester.widgetList<Icon>(icone('igual à planilha'))) {
        expect(i.color, CoresResultado.claro.registrado.texto);
      }
      expect(find.text('não alterado'), findsOneWidget);
      expect(find.text('Ana Souza (2091234)'), findsOneWidget);
      expect(find.text('Este aparelho'), findsOneWidget);
    });

    testWidgets('em laranja quando diverge', (tester) async {
      verificar('000001', sala: 'Auditório', responsavel: 'Elisa Prado');
      await abrir(tester, '000001');

      expect(find.text('Divergente'), findsOneWidget);
      expect(icone('diferente da planilha'), findsNWidgets(2));
      expect(icone('igual à planilha'), findsNothing);
      for (final i in tester.widgetList<Icon>(icone('diferente da planilha'))) {
        expect(i.color, CoresResultado.claro.jaVerificado.texto);
      }
      expect(find.text('Auditório'), findsOneWidget);
      expect(find.text('Elisa Prado'), findsOneWidget);
      expect(find.text('Carla Menezes'), findsOneWidget, reason: 'da planilha');
    });

    testWidgets('diz quando a verificação veio de outro aparelho', (
      tester,
    ) async {
      final b = Aparelho('Bruno');
      addTearDown(b.fechar);
      RedeSimulada.distribuir(a, [b], inventario);
      b.patrimonios.registrarVerificacao(
        patrimonio: b.patrimonios.porId(item('000001').id)!,
        config: const ConfiguracaoLevantamento(sala: 'Biblioteca'),
        usuarioNome: 'Bruno',
      );
      RedeSimulada.sincronizar(a, b, inventario.id);

      await abrir(tester, '000001');
      expect(find.text('Outro aparelho'), findsOneWidget);
      expect(find.text('Bruno'), findsOneWidget);
      expect(find.text('Este aparelho'), findsNothing);
    });

    testWidgets('editar grava pelo log só o que mudou, e o painel reflete', (
      tester,
    ) async {
      verificar('000001');
      final antes = operacoes(item('000001'));
      await abrir(tester, '000001');

      await tocar(tester, 'Editar levantamento');
      expect(
        tester.widget<TextField>(campo('Sala atual')).controller!.text,
        'Biblioteca',
      );
      // Editando, o painel termina em Cancelar e Salvar.
      expect(find.text('Desfazer verificação'), findsNothing);
      expect(find.text('Histórico de alterações'), findsNothing);
      // Quem verificou continua à vista: é o levantamento que vai mudar.
      expect(find.text('Ana Souza (2091234)'), findsOneWidget);

      await tester.enterText(campo('Sala atual'), 'Auditório');
      await tocar(tester, 'Salvar');

      final depois = item('000001');
      expect(depois.salaAtual, 'Auditório');
      expect(depois.responsavelAtual, isNull);
      expect(operacoes(depois), antes + 1);
      expect(find.text('Salvar'), findsNothing, reason: 'volta à leitura');
      expect(find.text('Divergente'), findsOneWidget);
      expect(icone('diferente da planilha'), findsOneWidget);
      expect(icone('igual à planilha'), findsOneWidget);
      expect(find.text('Desfazer verificação'), findsOneWidget);
      expect(find.text('Histórico de alterações'), findsOneWidget);
    });

    testWidgets('cancelar não grava nada', (tester) async {
      verificar('000001');
      final antes = operacoes(item('000001'));
      await abrir(tester, '000001');

      await tocar(tester, 'Editar levantamento');
      await tester.enterText(campo('Sala atual'), 'Auditório');
      await tocar(tester, 'Cancelar');

      expect(operacoes(item('000001')), antes);
      expect(item('000001').salaAtual, 'Biblioteca');
      expect(find.text('Salvar'), findsNothing);
    });

    testWidgets('verificar manualmente um item não localizado', (tester) async {
      await abrir(tester, '000002');
      expect(find.text('Não localizado'), findsOneWidget);
      expect(
        find.text('Ainda não encontrado no levantamento.'),
        findsOneWidget,
      );
      expect(find.text('Editar levantamento'), findsNothing);
      expect(find.text('Desfazer verificação'), findsNothing);

      await tocar(tester, 'Verificar manualmente');
      expect(find.textContaining('sem leitura de código'), findsOneWidget);
      await tester.enterText(campo('Sala atual'), 'Auditório');
      await tocar(tester, 'Salvar');

      final depois = item('000002');
      expect(depois.verificado, isTrue);
      expect(depois.verificadoPor, 'Ana Souza');
      expect(depois.verificadoPorMatricula, '2091234');
      expect(depois.salaAtual, 'Auditório');
      expect(depois.responsavelAtual, isNull);
      expect(depois.conservacao, EstadoConservacao.bom);
      expect(depois.situacao, SituacaoUso.ativo);
      expect(find.text('Divergente'), findsOneWidget);
      expect(find.text('Este aparelho'), findsOneWidget);
      expect(find.text('Desfazer verificação'), findsOneWidget);
    });

    testWidgets('inventário encerrado: sem editar nem desfazer', (
      tester,
    ) async {
      verificar('000001');
      a.inventarios.encerrar(inventario.id);
      await abrir(tester, '000001');

      expect(find.text('Editar levantamento'), findsNothing);
      expect(find.text('Desfazer verificação'), findsNothing);
      expect(find.textContaining('Inventário encerrado'), findsOneWidget);
      expect(icone('igual à planilha'), findsNWidgets(2), reason: 'só lê');
    });
  });

  group('acessibilidade', () {
    /// Monta o painel com o tema e a escala de fonte pedidos. Um item
    /// divergente e verificado: é o caso com mais cor e mais texto na tela.
    Future<void> abrir(
      WidgetTester tester, {
      double escala = 1,
      ThemeMode modo = ThemeMode.light,
      bool editando = false,
    }) async {
      verificar('000001', sala: 'Auditório', responsavel: 'Elisa Prado');

      final container = ProviderContainer(
        overrides: [bancoProvider.overrideWithValue(a.banco)],
      );
      addTearDown(container.dispose);

      // Tela alta pelo mesmo motivo do grupo anterior: o que a lista não
      // constrói também não é auditado.
      tester.view.physicalSize = const Size(1080, 7200);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: temaClaro,
            darkTheme: temaEscuro,
            themeMode: modo,
            home: MediaQuery.withClampedTextScaling(
              minScaleFactor: escala,
              maxScaleFactor: escala,
              child: Scaffold(
                body: DetalhePatrimonio(patrimonioId: item('000001').id),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      if (editando) {
        // Com a fonte grande o botão fica bem abaixo da dobra, e o que a
        // lista não construiu não existe para o `tap`.
        await tester.scrollUntilVisible(
          find.text('Editar levantamento'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(DraggableScrollableSheet),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(find.text('Editar levantamento'));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('alvos de toque, rótulos e contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      await abrir(tester);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('contraste no tema escuro', (tester) async {
      final semantica = tester.ensureSemantics();
      await abrir(tester, modo: ThemeMode.dark);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('fonte do sistema em 200% não estoura o layout', (
      tester,
    ) async {
      await abrir(tester, escala: 2);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('editando, a fonte em 200% não estoura o layout', (
      tester,
    ) async {
      await abrir(tester, escala: 2, editando: true);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
