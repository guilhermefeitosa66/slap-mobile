import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/atualizacao.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/ajustes/tela_ajustes.dart';

import '../apoio/app_de_teste.dart';

/// Os ajustes do aparelho.
void main() {
  testWidgets('a versão instalada fica à vista', (tester) async {
    // É o que se pergunta a quem relata um problema, e o que a pessoa compara
    // com o aviso de versão nova.
    final banco = Banco.emMemoria();
    addTearDown(banco.fechar);
    banco.gravarConfig(Config.usuarioNome, 'Ana');

    await montar(tester, const TelaAjustes(), banco: banco);
    await tester.pumpAndSettle();

    // "Sobre" é a última seção da tela.
    await tester.scrollUntilVisible(
      find.text('Versão do aplicativo'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Versão do aplicativo'), findsOneWidget);
    expect(find.text(versaoApp), findsOneWidget);
  });
}
