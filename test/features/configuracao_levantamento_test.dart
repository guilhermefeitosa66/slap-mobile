import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/app.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/core/formato.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/domain/valores.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';
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
