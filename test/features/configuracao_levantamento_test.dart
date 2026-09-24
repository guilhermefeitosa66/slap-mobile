import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:slap_mobile/app/app.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/core/formato.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/domain/patrimonio.dart';
import 'package:slap_mobile/domain/valores.dart';
import 'package:slap_mobile/features/inventory/tela_dashboard.dart';
import 'package:slap_mobile/features/inventory/tela_inventarios.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';
import 'package:slap_mobile/features/survey/tela_camera.dart';
import 'package:slap_mobile/features/survey/tela_levantamento.dart';

import '../apoio/app_de_teste.dart';

/// A configuração do levantamento sobrevive ao Android encerrar o app.
void main() {
  late Banco banco;
  late Inventario inventario;

  setUp(() {
    banco = Banco.emMemoria();
    final ops = RepositorioOperacoes(banco);
    inventario = RepositorioInventarios(
      banco,
      ops,
    ).criar(nome: 'Campus Picos', ano: 2026);
    RepositorioPatrimonios(banco, ops).inserirLote(inventario.id, const [
      PatrimonioImportado(tombo: '023101', descricao: 'MESA'),
    ]);
  });

  tearDown(() => banco.fechar());

  ProviderContainer aplicativo() {
    final c = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        sonsProvider.overrideWithValue(SonsMudos()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  void gravarConfiguracao(DateTime desde) {
    banco.gravarConfig(
      Config.configuracaoLevantamento(inventario.id),
      jsonEncode(
        ConfiguracaoLevantamento(
          sala: 'Auditório',
          conservacao: EstadoConservacao.regular,
          responsavel: 'Carla Menezes',
          desde: desde,
        ).toJson(),
      ),
    );
  }

  test('reabrir o aplicativo devolve a configuração e desde quando vale', () {
    final antes = aplicativo();
    antes
        .read(configuracoesProvider.notifier)
        .definir(
          inventario.id,
          const ConfiguracaoLevantamento(
            sala: 'Auditório',
            situacao: SituacaoUso.ocioso,
            responsavel: 'Carla Menezes',
          ),
        );
    antes.dispose();

    // Processo novo: nada em memória, só o banco.
    final depois = aplicativo();
    final config = depois.read(configuracaoProvider(inventario.id));
    expect(config, isNotNull);
    expect(config!.sala, 'Auditório');
    expect(config.situacao, SituacaoUso.ocioso);
    expect(config.responsavel, 'Carla Menezes');
    expect(DateTime.now().difference(config.desde!).inSeconds, lessThan(5));
  });

  test('cada inventário tem a sua configuração', () {
    final c = aplicativo();
    final outro = RepositorioInventarios(
      banco,
      RepositorioOperacoes(banco),
    ).criar(nome: 'Biblioteca', ano: 2026);

    c
        .read(configuracoesProvider.notifier)
        .definir(inventario.id, const ConfiguracaoLevantamento(sala: 'A'));
    c
        .read(configuracoesProvider.notifier)
        .definir(outro.id, const ConfiguracaoLevantamento(sala: 'B'));

    expect(configuracaoGravada(banco, inventario.id)!.sala, 'A');
    expect(configuracaoGravada(banco, outro.id)!.sala, 'B');
  });

  test('gravação ilegível pede a sala de novo, sem quebrar', () {
    banco.gravarConfig(Config.configuracaoLevantamento(inventario.id), '{x');
    expect(configuracaoGravada(banco, inventario.id), isNull);
    banco.gravarConfig(Config.configuracaoLevantamento(inventario.id), '[]');
    expect(configuracaoGravada(banco, inventario.id), isNull);
  });

  group('confirmação da sala', () {
    final agora = DateTime(2026, 9, 24, 8);
    const config = ConfiguracaoLevantamento(sala: 'Auditório');

    test('leitura recente segue sem perguntar', () {
      expect(
        precisaConfirmarSala(
          config: config.copyWith(
            desde: agora.subtract(const Duration(days: 1)),
          ),
          ultimaLeitura: agora.subtract(const Duration(minutes: 40)),
          agora: agora,
        ),
        isFalse,
      );
    });

    test('voltar no dia seguinte pergunta', () {
      expect(
        precisaConfirmarSala(
          config: config.copyWith(
            desde: agora.subtract(const Duration(days: 1)),
          ),
          ultimaLeitura: agora.subtract(const Duration(hours: 15)),
          agora: agora,
        ),
        isTrue,
      );
    });

    test('configuração antiga sem nenhuma leitura também pergunta', () {
      expect(
        precisaConfirmarSala(
          config: config.copyWith(
            desde: agora.subtract(const Duration(hours: 5)),
          ),
          ultimaLeitura: null,
          agora: agora,
        ),
        isTrue,
      );
    });

    test('marca no futuro, de quando a data estava adiantada, pergunta', () {
      // Ontem a data do aparelho estava um dia à frente; à noite foi
      // corrigida. A última leitura ficou marcada para daqui a 8 h.
      final adiantada = agora.add(const Duration(hours: 8));
      expect(
        precisaConfirmarSala(
          config: config.copyWith(
            desde: agora.subtract(const Duration(days: 1)),
          ),
          ultimaLeitura: adiantada,
          agora: agora,
        ),
        isTrue,
      );
      expect(
        precisaConfirmarSala(
          config: config.copyWith(desde: adiantada),
          ultimaLeitura: adiantada,
          agora: agora,
        ),
        isTrue,
        reason: 'a configuração também veio da data adiantada',
      );

      // Confirmada a sala, o desde novo vale, e não pergunta de novo.
      expect(
        precisaConfirmarSala(
          config: config.copyWith(desde: agora),
          ultimaLeitura: adiantada,
          agora: agora.add(const Duration(minutes: 1)),
        ),
        isFalse,
      );
      // Uns minutos à frente é diferença de relógio, não data errada.
      expect(
        precisaConfirmarSala(
          config: config.copyWith(
            desde: agora.subtract(const Duration(days: 1)),
          ),
          ultimaLeitura: agora.add(const Duration(minutes: 3)),
          agora: agora,
        ),
        isFalse,
      );
    });

    test('banco sem a marca a tira do log, das leituras deste aparelho', () {
      // Banco gravado antes da marca: há leitura no log, mas não a chave.
      final ops = RepositorioOperacoes(banco);
      final patrimonios = RepositorioPatrimonios(banco, ops);
      gravarConfiguracao(DateTime.now().subtract(const Duration(hours: 15)));
      patrimonios.registrarVerificacao(
        patrimonio: patrimonios.todos(inventario.id).single,
        config: configuracaoGravada(banco, inventario.id)!,
      );
      final leitura = DateTime.fromMillisecondsSinceEpoch(
        DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch,
      );
      banco.db.execute(
        "UPDATE ops SET criado_em = ? WHERE entidade = 'patrimonio'",
        [leitura.millisecondsSinceEpoch],
      );
      banco.apagarConfig(Config.ultimaLeitura(inventario.id));

      // Mais recentes, mas não contam: operação do inventário e leitura de
      // outro aparelho.
      RepositorioInventarios(banco, ops)
        ..encerrar(inventario.id)
        ..reabrir(inventario.id);
      banco.db.execute(
        'INSERT INTO ops (op_id, inventario_id, entidade, entidade_id, campo, '
        'valor, hlc, dispositivo, seq, criado_em) '
        "SELECT 'de-outro', inventario_id, entidade, entidade_id, campo, "
        "valor, hlc, 'outro-aparelho', 1, ? FROM ops "
        "WHERE entidade = 'patrimonio' LIMIT 1",
        [DateTime.now().millisecondsSinceEpoch],
      );

      expect(ops.ultimaLeituraLocal(inventario.id), leitura);
      expect(
        banco.lerConfig(Config.ultimaLeitura(inventario.id)),
        '${leitura.millisecondsSinceEpoch}',
        reason: 'preenchida uma vez',
      );
      expect(
        precisaConfirmarSala(
          config: configuracaoGravada(banco, inventario.id)!,
          ultimaLeitura: ops.ultimaLeituraLocal(inventario.id),
          agora: DateTime.now(),
        ),
        isFalse,
        reason: 'leu há 1 h: a atualização não faz perguntar',
      );
    });

    test('sem leitura no log, a marca vazia não volta a ele', () {
      final ops = RepositorioOperacoes(banco);
      expect(ops.ultimaLeituraLocal(inventario.id), isNull);
      expect(banco.lerConfig(Config.ultimaLeitura(inventario.id)), '');

      // Uma edição depois não é leitura, e não é mais conferida no log.
      final patrimonios = RepositorioPatrimonios(banco, ops);
      gravarConfiguracao(DateTime.now());
      patrimonios.registrarVerificacao(
        patrimonio: patrimonios.todos(inventario.id).single,
        config: configuracaoGravada(banco, inventario.id)!,
      );
      banco.gravarConfig(Config.ultimaLeitura(inventario.id), '');
      expect(ops.ultimaLeituraLocal(inventario.id), isNull);
    });

    test('só leitura conta: reabrir o inventário de manhã ainda pergunta', () {
      // Última leitura ontem à tarde. De manhã, antes de levantar, a pessoa
      // encerra e reabre o inventário — operações deste aparelho, mas não
      // leituras.
      gravarConfiguracao(DateTime.now().subtract(const Duration(hours: 15)));
      final ops = RepositorioOperacoes(banco);
      RepositorioInventarios(banco, ops)
        ..encerrar(inventario.id)
        ..reabrir(inventario.id);

      bool precisa() => precisaConfirmarSala(
        config: configuracaoGravada(banco, inventario.id)!,
        ultimaLeitura: ops.ultimaLeituraLocal(inventario.id),
        agora: DateTime.now(),
      );
      expect(precisa(), isTrue);

      // Uma leitura de verdade conta.
      final patrimonios = RepositorioPatrimonios(banco, ops);
      patrimonios.registrarVerificacao(
        patrimonio: patrimonios.todos(inventario.id).single,
        config: configuracaoGravada(banco, inventario.id)!,
      );
      expect(precisa(), isFalse);
    });

    testWidgets('pergunta ao reabrir depois de horas, e continuar reconfirma', (
      tester,
    ) async {
      gravarConfiguracao(DateTime.now().subtract(const Duration(hours: 6)));
      final c = await montar(
        tester,
        TelaLevantamento(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pumpAndSettle();

      expect(find.text('Ainda em Auditório?'), findsOneWidget);
      await tester.tap(find.text('Continuar em Auditório'));
      await tester.pumpAndSettle();

      expect(find.text('Ainda em Auditório?'), findsNothing);
      final config = c.read(configuracaoProvider(inventario.id))!;
      expect(config.sala, 'Auditório');
      expect(config.responsavel, 'Carla Menezes', reason: 'nada se perde');
      expect(DateTime.now().difference(config.desde!).inMinutes, 0);
      expect(find.textContaining('desde'), findsOneWidget);
    });

    group('com a tela aberta a noite inteira', () {
      /// As horas passam sem que a tela saia: a configuração e a última
      /// leitura ficam para trás, como na manhã seguinte.
      void envelhecer(ProviderContainer c) {
        final antes = DateTime.now().subtract(const Duration(hours: 15));
        gravarConfiguracao(antes);
        banco.gravarConfig(
          Config.ultimaLeitura(inventario.id),
          '${antes.millisecondsSinceEpoch}',
        );
        c.invalidate(configuracaoProvider(inventario.id));
      }

      Future<ProviderContainer> abrir(WidgetTester tester) async {
        gravarConfiguracao(DateTime.now());
        final c = await montar(
          tester,
          TelaLevantamento(inventarioId: inventario.id),
          banco: banco,
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Ainda em'), findsNothing);
        return c;
      }

      Future<void> ler(WidgetTester tester, String codigo) async {
        await tester.enterText(find.byType(TextField), codigo);
        await tester.testTextInput.receiveAction(TextInputAction.go);
        await tester.pumpAndSettle();
      }

      /// O aparelho é desbloqueado e o aplicativo volta ao primeiro plano.
      Future<void> voltarAoAplicativo(WidgetTester tester) async {
        for (final estado in const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(estado);
        }
        await tester.pumpAndSettle();
      }

      Patrimonio item() => RepositorioPatrimonios(
        banco,
        RepositorioOperacoes(banco),
      ).todos(inventario.id).single;

      testWidgets('a leitura seguinte pergunta a sala antes de gravar', (
        tester,
      ) async {
        final c = await abrir(tester);
        envelhecer(c);

        await ler(tester, '023101');
        expect(find.text('Ainda em Auditório?'), findsOneWidget);
        expect(item().verificado, isFalse, reason: 'nada gravado ainda');

        await tester.tap(find.text('Continuar em Auditório'));
        await tester.pumpAndSettle();
        expect(item().verificado, isFalse, reason: 'lê de novo, já confirmada');

        await ler(tester, '023101');
        expect(find.textContaining('Ainda em'), findsNothing);
        expect(item().verificado, isTrue);
        expect(item().salaAtual, 'Auditório');
      });

      testWidgets('regravar também pergunta antes', (tester) async {
        final c = await abrir(tester);
        await ler(tester, '023101');
        await ler(tester, '023101');
        expect(find.textContaining('já foi verificado'), findsOneWidget);
        final operacoes = RepositorioOperacoes(
          banco,
        ).vetorDe(inventario.id)[banco.dispositivoId];

        envelhecer(c);
        await tester.tap(find.text('Regravar'));
        await tester.pumpAndSettle();
        expect(find.text('Ainda em Auditório?'), findsOneWidget);
        expect(
          RepositorioOperacoes(
            banco,
          ).vetorDe(inventario.id)[banco.dispositivoId],
          operacoes,
        );

        // A pessoa está em outra sala. O item foi lido ontem no Auditório:
        // o "Regravar" de ontem não pode levá-lo para a sala nova.
        await tester.tap(find.text('Mudar de sala'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Sala onde você está'),
          'Sala 205',
        );
        await tester.ensureVisible(find.text('Aplicar e continuar'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Aplicar e continuar'));
        await tester.pumpAndSettle();

        expect(c.read(configuracaoProvider(inventario.id))!.sala, 'Sala 205');
        expect(find.text('Regravar'), findsNothing);
        expect(find.textContaining('já foi verificado'), findsNothing);
        expect(item().salaAtual, 'Auditório');
      });

      testWidgets('voltar ao aplicativo pergunta, uma vez só', (tester) async {
        final c = await abrir(tester);
        envelhecer(c);

        await voltarAoAplicativo(tester);
        expect(find.text('Ainda em Auditório?'), findsOneWidget);
        await voltarAoAplicativo(tester);
        expect(find.text('Ainda em Auditório?'), findsOneWidget);

        await tester.tap(find.text('Continuar em Auditório'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Ainda em'), findsNothing);
      });

      testWidgets('a câmera não grava com a sala de ontem', (tester) async {
        final c = await abrir(tester);
        await tester.tap(find.byTooltip('Abrir câmera'));
        await tester.pumpAndSettle();
        expect(find.byType(TelaCamera), findsOneWidget);

        envelhecer(c);
        tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
          const BarcodeCapture(barcodes: [Barcode(rawValue: '023101')]),
        );
        await tester.pumpAndSettle();

        expect(item().verificado, isFalse);
        expect(find.byType(TelaCamera), findsNothing);
        expect(find.text('Ainda em Auditório?'), findsOneWidget);
      });
    });

    testWidgets('configuração recente retoma direto, sem perguntar', (
      tester,
    ) async {
      gravarConfiguracao(DateTime.now().subtract(const Duration(minutes: 20)));
      await montar(
        tester,
        TelaLevantamento(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Ainda em'), findsNothing);
      expect(find.text('Auditório'), findsOneWidget);
    });
  });

  group('reabrir no levantamento', () {
    testWidgets('a tela marca que está aberta e desmarca ao sair', (
      tester,
    ) async {
      gravarConfiguracao(DateTime.now());
      await montar(
        tester,
        TelaLevantamento(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pumpAndSettle();
      expect(banco.lerConfig(Config.levantamentoAberto), inventario.id);
      expect(
        rotaInicial(
          banco,
          RepositorioInventarios(banco, RepositorioOperacoes(banco)),
        ),
        '/inventario/${inventario.id}/levantamento',
      );

      await tester.pumpWidget(const SizedBox());
      expect(banco.lerConfig(Config.levantamentoAberto), isNull);
    });

    testWidgets('voltar do painel chega à lista, sem fechar o aplicativo', (
      tester,
    ) async {
      // O Android encerrou o aplicativo com o levantamento aberto.
      banco.gravarConfig(Config.usuarioNome, 'Ana Souza');
      gravarConfiguracao(DateTime.now());
      banco.gravarConfig(Config.levantamentoAberto, inventario.id);

      final c = aplicativo();
      await tester.pumpWidget(
        UncontrolledProviderScope(container: c, child: const AplicativoSlap()),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TelaLevantamento), findsOneWidget);

      // O botão voltar do sistema, duas vezes.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(TelaDashboard), findsOneWidget);

      expect(
        await tester.binding.handlePopRoute(),
        isTrue,
        reason: 'sem nada embaixo, o Android fecharia o aplicativo',
      );
      await tester.pumpAndSettle();
      expect(find.byType(TelaInventarios), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    test('inventário que não existe mais abre na lista', () {
      banco.gravarConfig(Config.levantamentoAberto, 'apagado');
      expect(
        rotaInicial(
          banco,
          RepositorioInventarios(banco, RepositorioOperacoes(banco)),
        ),
        '/',
      );
    });
  });

  test('momentos ditos em relação a hoje', () {
    final agora = DateTime(2026, 9, 24, 15);
    expect(
      descreverMomento(DateTime(2026, 9, 24, 9, 10), agora: agora),
      'hoje às 09:10',
    );
    expect(
      descreverMomento(DateTime(2026, 9, 23, 16, 5), agora: agora),
      'ontem às 16:05',
    );
    expect(
      descreverMomento(DateTime(2026, 9, 12, 16, 5), agora: agora),
      'em 12/09 às 16:05',
    );
    expect(
      descreverDesde(DateTime(2026, 9, 24, 14, 32), agora: agora),
      'desde 14:32',
    );
    expect(
      descreverDesde(DateTime(2026, 9, 23, 16, 5), agora: agora),
      'desde ontem, 16:05',
    );
    expect(descreverDesde(DateTime(2026, 9, 12), agora: agora), 'desde 12/09');
  });
}
