import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/inventory/acoes_inventario.dart';
import 'package:slap_mobile/features/inventory/tela_dashboard.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// Editar, duplicar e apagar: a manutenção básica de um inventário.
void main() {
  late Aparelho a;
  late Aparelho b;
  late Inventario inventario;

  setUp(() {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    a.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 4; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: '$i',
          sala: 'Sala $i',
          ed: i == 4 ? '44905218' : '44905242',
        ),
    ]);
    a.inventarios.definirEdsExcluidos(inventario.id, ['44905218']);
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

  group('editar', () {
    test('nome e ano mudam em todos os aparelhos', () {
      b.inventarios.editar(
        inventario.id,
        nome: 'Campus Picos — Geral',
        ano: 2027,
      );
      RedeSimulada.sincronizar(a, b, inventario.id);

      final noA = a.inventarios.porId(inventario.id)!;
      expect(noA.nome, 'Campus Picos — Geral');
      expect(noA.ano, 2027);
    });

    test('só o que mudou vai para o log', () {
      final antes = a.ops.historicoDe(inventario.id).length;
      a.inventarios.editar(inventario.id, nome: 'Campus Picos', ano: 2027);
      final novas = a.ops.historicoDe(inventario.id).length - antes;
      expect(novas, 1, reason: 'o nome não mudou');

      a.inventarios.editar(inventario.id, nome: 'Campus Picos', ano: 2027);
      expect(a.ops.historicoDe(inventario.id).length - antes, 1);
    });
  });

  group('duplicar', () {
    test('mesmos patrimônios e EDs, levantamento do zero', () async {
      verificar(a, 'item-1');

      final novo = await duplicarEstrutura(
        banco: a.banco,
        inventarios: a.inventarios,
        patrimonios: a.patrimonios,
        origem: a.inventarios.porId(inventario.id)!,
        nome: 'Campus Picos',
        ano: 2027,
      );

      expect(novo.id, isNot(inventario.id));
      expect(novo.ano, 2027);
      expect(a.inventarios.porId(novo.id)!.edsExcluidos, ['44905218']);

      final copia = a.patrimonios.todos(novo.id, incluirIgnorados: true);
      expect(copia.map((p) => p.tombo), ['1', '2', '3', '4']);
      expect(copia.where((p) => p.verificado), isEmpty);
      expect(copia.map((p) => p.salaOriginal), [
        'Sala 1',
        'Sala 2',
        'Sala 3',
        'Sala 4',
      ]);
      expect(copia.where((p) => p.ignorado).map((p) => p.tombo), ['4']);
      expect(
        copia
            .map((p) => p.id)
            .toSet()
            .intersection(
              a.patrimonios
                  .todos(inventario.id, incluirIgnorados: true)
                  .map((p) => p.id)
                  .toSet(),
            ),
        isEmpty,
        reason: 'são outros patrimônios, em outro inventário',
      );

      // O original fica como estava.
      expect(a.patrimonios.porId('item-1')!.verificado, isTrue);
    });
  });

  group('apagar', () {
    test('sem nunca ter sincronizado, tudo o que foi feito aqui se perde', () {
      final c = Aparelho('Carla');
      addTearDown(c.fechar);
      final so = c.inventarios.criar(nome: 'Só aqui', ano: 2026);
      c.patrimonios.inserirRecebidos([
        patrimonioDeTeste(id: 'x1', inventarioId: so.id, tombo: '1'),
        patrimonioDeTeste(id: 'x2', inventarioId: so.id, tombo: '2'),
      ]);
      verificar(c, 'x1');
      verificar(c, 'x2');

      final perda = c.ops.trabalhoNaoEntregue(so.id);
      expect(perda.jaSincronizou, isFalse);
      expect(perda.verificacoes, 2);
      expect(perda.nada, isFalse);
    });

    test('apagar é local, e sincronizar traz tudo de volta', () {
      verificar(a, 'item-1');
      RedeSimulada.sincronizar(a, b, inventario.id);
      b.banco.gravarConfig(
        Config.configuracaoLevantamento(inventario.id),
        '{}',
      );
      b.banco.gravarConfig(Config.levantamentoAberto, inventario.id);

      b.inventarios.removerLocalmente(inventario.id);
      expect(b.inventarios.porId(inventario.id), isNull);
      expect(b.patrimonios.todos(inventario.id), isEmpty);
      expect(
        b.banco.lerConfig(Config.configuracaoLevantamento(inventario.id)),
        isNull,
      );
      expect(b.banco.lerConfig(Config.levantamentoAberto), isNull);
      expect(
        a.inventarios.porId(inventario.id),
        isNotNull,
        reason: 'o outro não é afetado',
      );

      // Entrar de novo pelo QR code: pacote inicial e sincronização.
      RedeSimulada.distribuir(a, [b], a.inventarios.porId(inventario.id)!);
      RedeSimulada.sincronizar(a, b, inventario.id);
      expect(impressaoDe(b, 'item-1'), impressaoDe(a, 'item-1'));
      expect(b.inventarios.porId(inventario.id)!.edsExcluidos, ['44905218']);
    });

    testWidgets('a confirmação diz quantas verificações se perdem', (
      tester,
    ) async {
      verificar(b, 'item-1');
      verificar(b, 'item-2');
      verificar(b, 'item-3');

      await montar(
        tester,
        TelaDashboard(inventarioId: inventario.id),
        banco: b.banco,
      );
      await tester.tap(find.byTooltip('Mais ações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apagar deste aparelho'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          '3 verificações feitas neste aparelho ainda não chegaram',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Os outros aparelhos'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(b.inventarios.porId(inventario.id), isNotNull);
    });
  });
}
