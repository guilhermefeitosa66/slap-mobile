import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/componentes.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/ajustes/tela_ajustes.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// Apagar tudo do aparelho, e separar o aparelho de uma cópia sua.
///
/// As duas ações apagam os inventários daqui, e é só isso que têm em comum:
/// uma limpa o celular e mantém a identidade; a outra existe para trocar a
/// identidade, e apaga porque a história escrita sob a antiga está em disputa.
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

  group('apagar tudo', () {
    test('tira os inventários e mantém identidade, nome e numeração', () {
      verificar(b, 'item-1');
      // Entregue ao outro aparelho antes de apagar: é dele que o trabalho
      // volta.
      RedeSimulada.sincronizar(a, b, inventario.id);
      final antes = b.banco.dispositivoId;
      final seqAntes = b.ops.vetorDe(inventario.id)[antes];
      expect(seqAntes, greaterThan(0));

      b.inventarios.apagarTudoLocalmente();

      expect(b.inventarios.listar(), isEmpty);
      expect(b.patrimonios.todos(inventario.id), isEmpty);
      expect(b.banco.dispositivoId, antes, reason: 'a identidade não muda');
      expect(b.banco.lerConfig(Config.usuarioNome), 'Bruno');
      expect(
        b.banco.lerConfig(Config.seqMinimo(inventario.id)),
        '$seqAntes',
        reason: 'o piso fica: o outro aparelho ainda tem essas operações',
      );

      // O inventário volta pelo QR code, e a numeração continua de onde
      // parou — é o piso que garante isso.
      RedeSimulada.distribuir(a, [b], a.inventarios.porId(inventario.id)!);
      RedeSimulada.sincronizar(a, b, inventario.id);
      expect(b.patrimonios.porId('item-1')!.verificado, isTrue);

      verificar(b, 'item-2');
      expect(
        b.ops.vetorDe(inventario.id)[b.banco.dispositivoId],
        greaterThan(seqAntes),
      );
    });

    test('o trabalho não entregue de todos os inventários soma', () {
      final segundo = b.inventarios.criar(nome: 'Só aqui', ano: 2026);
      b.patrimonios.inserirRecebidos([
        patrimonioDeTeste(id: 'x1', inventarioId: segundo.id, tombo: '9'),
      ]);
      verificar(b, 'item-1');
      verificar(b, 'x1');

      final soma = b.inventarios
          .listar()
          .map((i) => b.ops.trabalhoNaoEntregue(i.id))
          .fold(TrabalhoNaoEntregue.nenhum, (x, y) => x + y);

      expect(soma.verificacoes, 2);
      expect(soma.nada, isFalse);
      expect(
        soma.jaSincronizou,
        isTrue,
        reason:
            'um dos dois já sincronizou, e isso basta para não dizer '
            'que o aparelho nunca sincronizou',
      );
    });

    testWidgets('a confirmação diz o que se perde, e cancelar não apaga', (
      tester,
    ) async {
      verificar(b, 'item-1');
      verificar(b, 'item-2');

      await montar(tester, const TelaAjustes(), banco: b.banco);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Apagar tudo deste aparelho'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apagar tudo deste aparelho'));
      await tester.pumpAndSettle();

      // O aviso fica fora do texto corrido: é o que decide a ação.
      expect(find.byType(CaixaDeAviso), findsOneWidget);
      expect(
        find.textContaining('2 verificações feitas aqui ainda não chegaram'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Exportar cópia'),
        ),
        findsOneWidget,
        reason: 'a cópia é oferecida no caminho de quem vai apagar',
      );

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(b.inventarios.listar(), isNotEmpty);

      await tester.tap(find.text('Apagar tudo deste aparelho'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apagar mesmo assim'));
      await tester.pumpAndSettle();

      expect(b.inventarios.listar(), isEmpty);
      expect(b.banco.dispositivoId, isNotEmpty);
    });
  });

  group('separar de uma cópia', () {
    test('a identidade troca, e a numeração recomeça', () {
      verificar(b, 'item-1');
      final antes = b.banco.dispositivoId;

      b.inventarios.renovarIdentidade();

      expect(b.banco.dispositivoId, isNot(antes));
      expect(b.inventarios.listar(), isEmpty);
      expect(b.banco.lerConfig(Config.seqMinimo(inventario.id)), isNull);
      expect(b.banco.lerConfig(Config.usuarioNome), 'Bruno');
    });

    testWidgets('o diálogo destaca a perda e troca a identidade', (
      tester,
    ) async {
      verificar(b, 'item-1');
      final antes = b.banco.dispositivoId;

      await montar(tester, const TelaAjustes(), banco: b.banco);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Separar este aparelho de uma cópia'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Separar este aparelho de uma cópia'));
      await tester.pumpAndSettle();

      expect(find.byType(CaixaDeAviso), findsOneWidget);
      expect(
        find.textContaining('O inventário deste aparelho será apagado'),
        findsOneWidget,
      );
      // Não é mais "gerar nova identidade": o nome diz o fim, não o meio.
      expect(find.textContaining('Gerar'), findsNothing);

      await tester.tap(find.text('Apagar e separar'));
      await tester.pumpAndSettle();

      expect(b.banco.dispositivoId, isNot(antes));
      expect(b.inventarios.listar(), isEmpty);
    });
  });
}
