import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/preferencias.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/core/tela_ligada.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/ajustes/tela_ajustes.dart';
import 'package:slap_mobile/features/survey/manter_tela_ligada.dart';

import '../apoio/app_de_teste.dart';

/// A tela fica ligada no levantamento e na câmera, e só neles.
void main() {
  final pedidos = <bool>[];

  setUp(() {
    pedidos.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TelaLigada.canal, (chamada) async {
          if (chamada.method == 'manterLigada') {
            pedidos.add(chamada.arguments as bool);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TelaLigada.canal, null);
    expect(
      TelaLigada.instancia.ligada,
      isFalse,
      reason: 'nenhum teste pode deixar a tela presa ligada',
    );
  });

  /// Simula a pilha de navegação: levantamento e, por cima, a câmera.
  Widget pilha({required bool levantamento, required bool camera}) => Column(
    children: [
      if (levantamento) const ManterTelaLigada(child: Text('levantamento')),
      if (camera) const ManterTelaLigada(child: Text('câmera')),
      const Text('outra tela'),
    ],
  );

  testWidgets('liga ao entrar no levantamento e desliga ao sair', (
    tester,
  ) async {
    await montar(tester, pilha(levantamento: true, camera: false));
    expect(pedidos, [true]);
    expect(TelaLigada.instancia.ligada, isTrue);

    await tester.pumpWidget(const SizedBox());
    expect(pedidos, [true, false]);
  });

  testWidgets('abrir a câmera por cima não desliga no meio', (tester) async {
    final container = await montar(
      tester,
      pilha(levantamento: true, camera: false),
    );
    Future<void> trocar(Widget w) => tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: w),
      ),
    );

    await trocar(pilha(levantamento: true, camera: true));
    await trocar(pilha(levantamento: true, camera: false));
    expect(pedidos, [true], reason: 'fechar a câmera volta ao levantamento');

    await trocar(pilha(levantamento: false, camera: false));
    expect(pedidos, [true, false]);
  });

  testWidgets('quem desligou nos ajustes não é atendido', (tester) async {
    final banco = Banco.emMemoria()..gravarConfig(Config.manterTelaLigada, '0');
    await montar(tester, pilha(levantamento: true, camera: true), banco: banco);
    await tester.pumpWidget(const SizedBox());
    expect(pedidos, isEmpty);
  });

  group('ajustes', () {
    testWidgets('as preferências ficam gravadas e valem para os sons', (
      tester,
    ) async {
      final banco = Banco.emMemoria();
      final sons = SonsMudos();
      final container = await montar(
        tester,
        const TelaAjustes(),
        banco: banco,
        sons: sons,
      );

      await tester.tap(find.text('Manter a tela ligada'));
      await tester.tap(find.text('Som a cada leitura'));
      await tester.tap(find.text('Vibrar a cada leitura'));
      await tester.pump();

      final preferencias = container.read(preferenciasProvider);
      expect(preferencias.manterTelaLigada, isFalse);
      expect(preferencias.sons, isFalse);
      expect(preferencias.vibracao, isFalse);

      expect(banco.lerConfig(Config.manterTelaLigada), '0');
      expect(sons.silencioso, isTrue);
      expect(sons.vibrar, isFalse);

      // Reabrir o aplicativo lê o que foi gravado.
      expect(Preferencias.doBanco(banco).sons, isFalse);
    });

    testWidgets('o som começa como foi deixado', (tester) async {
      final banco = Banco.emMemoria()..gravarConfig(Config.sons, '0');
      final container = ProviderContainer(
        overrides: [bancoProvider.overrideWithValue(banco)],
      );
      addTearDown(container.dispose);
      expect(container.read(sonsProvider).silencioso, isTrue);
      expect(container.read(sonsProvider).vibrar, isTrue);
    });
  });
}
