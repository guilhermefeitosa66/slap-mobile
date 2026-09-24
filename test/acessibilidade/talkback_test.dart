import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/app.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';

import '../apoio/app_de_teste.dart';

/// Registrar um patrimônio do início ao fim só pelo que o TalkBack oferece.
///
/// Nada aqui toca a tela por coordenada ou procura widget por tipo: cada passo
/// acha o elemento pelo rótulo na árvore de semântica — o que o leitor de tela
/// fala — e aciona pela ação que ele expõe. Se um botão perder o rótulo, ou
/// um cartão deixar de ser um elemento só, este teste quebra.
void main() {
  late Banco banco;
  late Inventario inventario;
  final anuncios = <String>[];

  setUp(() {
    banco = Banco.emMemoria()..gravarConfig(Config.usuarioNome, 'Ana Souza');
    final ops = RepositorioOperacoes(banco);
    inventario = RepositorioInventarios(
      banco,
      ops,
    ).criar(nome: 'Campus Picos', ano: 2026);
    RepositorioPatrimonios(banco, ops).inserirLote(inventario.id, const [
      PatrimonioImportado(
        tombo: '023101',
        codigoBarras: '887101',
        descricao: 'MESA DE REUNIÃO',
        sala: 'Biblioteca',
      ),
    ]);

    anuncios.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (
          mensagem,
        ) async {
          if (mensagem case {
            'type': 'announce',
            'data': {'message': final String texto},
          }) {
            anuncios.add(texto);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        );
  });

  Future<void> acionar(WidgetTester tester, Pattern rotulo) async {
    tester.semantics.tap(find.semantics.byLabel(rotulo));
    await tester.pumpAndSettle();
  }

  testWidgets('da lista de inventários ao item registrado', (tester) async {
    final semantica = tester.ensureSemantics();
    final container = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        sonsProvider.overrideWithValue(SonsMudos()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AplicativoSlap(),
      ),
    );
    await tester.pumpAndSettle();

    // Lista → painel: o cartão do inventário é um elemento só, acionável.
    await acionar(tester, RegExp('Campus Picos'));
    // Painel → levantamento.
    await acionar(tester, 'Levantar');

    // Sem sala definida, a configuração abre: o campo tem rótulo.
    await acionar(tester, RegExp('Sala onde você está'));
    tester.testTextInput.enterText('Auditório');
    await tester.pumpAndSettle();
    await acionar(tester, 'Aplicar e continuar');

    // O leitor externo digita no campo, que está com o foco.
    tester.testTextInput.enterText('887101');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();

    expect(
      anuncios,
      contains(allOf(startsWith('Registrado.'), contains('MESA DE REUNIÃO'))),
      reason: 'o resultado é falado, não só colorido',
    );
    final item = RepositorioPatrimonios(
      banco,
      RepositorioOperacoes(banco),
    ).todos(inventario.id).single;
    expect(item.verificado, isTrue);
    expect(item.salaAtual, 'Auditório');

    // Os outros dois resultados também são falados.
    tester.testTextInput.enterText('887101');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(anuncios.last, contains('Manter ou regravar'));
    await acionar(tester, 'Manter');

    tester.testTextInput.enterText('000000');
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(anuncios.last, 'Não localizado. Código 000000.');

    semantica.dispose();
    await tester.pumpWidget(const SizedBox());
  });
}
