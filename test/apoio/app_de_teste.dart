import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/core/atualizacao.dart';
import 'package:slap_mobile/core/sons.dart';
import 'package:slap_mobile/data/banco.dart';

/// Sons que só registram o que foi pedido: o teste não tem saída de áudio
/// nem motor de vibração.
class SonsMudos extends Sons {
  final tocados = <Som>[];

  @override
  Future<void> preparar() async {}

  @override
  void tocar(Som som) => tocados.add(som);

  @override
  Future<void> dispose() async {}
}

/// Monta [tela] com o tema do aplicativo e um banco em memória.
///
/// Devolve o container, para o teste ler e alterar o estado como o
/// aplicativo faria.
Future<ProviderContainer> montar(
  WidgetTester tester,
  Widget tela, {
  Banco? banco,
  Sons? sons,
  VerificadorAtualizacao? atualizacao,
  void Function(ProviderContainer)? preparar,
}) async {
  final container = ProviderContainer(
    overrides: [
      bancoProvider.overrideWithValue(banco ?? Banco.emMemoria()),
      sonsProvider.overrideWithValue(sons ?? SonsMudos()),
      // Sem rede nos testes: por padrão, a consulta não devolve nada.
      verificadorAtualizacaoProvider.overrideWithValue(
        atualizacao ?? VerificadorAtualizacao(buscar: (_) async => null),
      ),
    ],
  );
  addTearDown(container.dispose);
  preparar?.call(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: temaClaro, home: tela),
    ),
  );
  return container;
}
