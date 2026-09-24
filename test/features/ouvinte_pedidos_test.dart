import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/ouvinte_pedidos.dart';
import 'package:slap_mobile/features/sync/protocolo.dart';
import 'package:slap_mobile/features/sync/servidor.dart';

import '../apoio/rede_simulada.dart';

/// O diálogo de aceite, com o pedido chegando por sockets de verdade.
///
/// É o ponto em que a decisão de segurança da issue #55 vira interface: sem
/// alguém tocando em "Aceitar", a chave do inventário não sai deste aparelho.
void main() {
  late Aparelho ana;
  late Aparelho bruno;
  late ServidorSync servidorDaAna;
  late ClienteSync clienteDoBruno;
  late Par paraAna;
  late Inventario inventario;

  // Curto para o teste da expiração não esperar um minuto.
  const validade = Duration(seconds: 3);

  setUp(() async {
    // O `TestWidgetsFlutterBinding` troca o `HttpClient` por um que devolve
    // 400 sem sair da máquina. Aqui o pedido precisa atravessar um socket de
    // verdade — é justamente o que está sendo testado.
    HttpOverrides.global = null;

    ana = Aparelho('Ana');
    bruno = Aparelho('Bruno');

    servidorDaAna = ServidorSync(
      banco: ana.banco,
      ops: ana.ops,
      inventarios: ana.inventarios,
      patrimonios: ana.patrimonios,
      validadePedido: validade,
    );
    final porta = await servidorDaAna.iniciar();
    paraAna = Par(
      dispositivoId: ana.dispositivoId,
      host: '127.0.0.1',
      porta: porta,
    );

    clienteDoBruno = ClienteSync(bruno.ops);
    inventario = ana.inventarios.criar(nome: 'Campus Picos', ano: 2026);
  });

  tearDown(() async {
    await servidorDaAna.dispose();
    ana.fechar();
    bruno.fechar();
  });

  /// O aplicativo da Ana, com o ouvinte por cima de uma tela qualquer — como
  /// o `builder` do `MaterialApp.router` monta de verdade.
  Future<void> montarAplicativoDaAna(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(ana.banco),
        servidorSyncProvider.overrideWithValue(servidorDaAna),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: temaClaro,
          home: const Scaffold(body: Center(child: Text('levantamento'))),
          builder: (_, filho) => OuvintePedidos(child: filho!),
        ),
      ),
    );
  }

  /// Dispara o pedido do Bruno e devolve o futuro dele, que termina com a
  /// chave ou com a falha — nunca com um erro sem dono.
  ///
  /// Um futuro dentro do outro porque são duas esperas diferentes: a de fora
  /// é o tempo de a requisição chegar ao servidor; a de dentro, a decisão.
  Future<Future<Object>> pedirEmSegundoPlano(WidgetTester tester) async {
    late Future<Object> resultado;
    await tester.runAsync(() async {
      resultado = clienteDoBruno
          .pedirEntrada(
            par: paraAna,
            inventarioId: inventario.id,
            usuarioNome: 'Bruno',
            matricula: '2024001',
            validade: validade,
          )
          .then<Object>((chave) => chave)
          .onError<Object>((erro, _) => erro);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    return resultado;
  }

  Future<void> esperarODialogo(WidgetTester tester) async {
    for (var i = 0; i < 60; i++) {
      await tester.pump();
      if (find.text('Pedido de entrada').evaluate().isNotEmpty) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
    }
  }

  testWidgets('o pedido aparece por cima da tela aberta, com quem pediu', (
    tester,
  ) async {
    await montarAplicativoDaAna(tester);
    final resultado = await pedirEmSegundoPlano(tester);
    await esperarODialogo(tester);

    expect(find.text('Pedido de entrada'), findsOneWidget);
    expect(find.textContaining('Bruno (aparelho '), findsOneWidget);
    expect(find.textContaining('Campus Picos — 2026'), findsOneWidget);
    expect(find.textContaining('2024001'), findsOneWidget);
    // Por cima, e não no lugar: quem está levantando não perde a tela.
    expect(find.text('levantamento'), findsOneWidget);

    await tester.tap(find.text('Aceitar'));
    await tester.pump();
    expect(find.text('Pedido de entrada'), findsNothing);

    expect(await tester.runAsync(() => resultado), inventario.chaveSync);
  });

  testWidgets('recusar não entrega a chave', (tester) async {
    await montarAplicativoDaAna(tester);
    final resultado = await pedirEmSegundoPlano(tester);
    await esperarODialogo(tester);

    await tester.tap(find.text('Recusar'));
    await tester.pump();
    expect(find.text('Pedido de entrada'), findsNothing);

    expect(
      await tester.runAsync(() => resultado),
      isA<EntradaRecusada>().having(
        (e) => e.motivo,
        'motivo',
        MotivoRecusa.recusado,
      ),
    );
  });

  testWidgets('sem resposta o diálogo some quando o pedido caduca', (
    tester,
  ) async {
    await montarAplicativoDaAna(tester);
    final resultado = await pedirEmSegundoPlano(tester);
    await esperarODialogo(tester);
    expect(find.text('Pedido de entrada'), findsOneWidget);

    // Um pedido que já caducou não pode continuar na tela prometendo uma
    // decisão que o outro lado não vai mais receber.
    await tester.pump(validade + const Duration(seconds: 1));
    expect(find.text('Pedido de entrada'), findsNothing);

    expect(
      await tester.runAsync(() => resultado),
      isA<EntradaRecusada>().having(
        (e) => e.motivo,
        'motivo',
        MotivoRecusa.expirou,
      ),
    );
  });

  testWidgets('tocar fora não decide nada', (tester) async {
    await montarAplicativoDaAna(tester);
    final resultado = await pedirEmSegundoPlano(tester);
    await esperarODialogo(tester);

    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    expect(
      find.text('Pedido de entrada'),
      findsOneWidget,
      reason: 'entrar num inventário é decisão explícita',
    );

    await tester.tap(find.text('Recusar'));
    await tester.pump();
    expect(await tester.runAsync(() => resultado), isA<EntradaRecusada>());
  });
}
