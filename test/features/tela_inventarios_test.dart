import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:slap_mobile/app/app.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/import/tela_importacao.dart';
import 'package:slap_mobile/features/inventory/tela_inventarios.dart';

import '../apoio/app_de_teste.dart';

/// A lista de inventários: "Novo" pergunta de onde vem o inventário.
void main() {
  late Banco banco;

  setUp(() {
    banco = Banco.emMemoria();
    banco.gravarConfig(Config.usuarioNome, 'Ana Souza');
  });

  tearDown(() => banco.fechar());

  /// O aplicativo inteiro, e não só a tela: a lista navega pelo go_router.
  Future<void> abrir(WidgetTester tester) async {
    final c = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(banco),
        sonsProvider.overrideWithValue(SonsMudos()),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const AplicativoSlap()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TelaInventarios), findsOneWidget);
  }

  void criarInventario() {
    RepositorioInventarios(
      banco,
      RepositorioOperacoes(banco),
    ).criar(nome: 'Campus Picos', ano: 2026);
  }

  Future<void> tocarNovo(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Novo'));
    await tester.pumpAndSettle();
  }

  testWidgets('só o botão "Novo" fica flutuando; o leitor de QR saiu', (
    tester,
  ) async {
    criarInventario();
    await abrir(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Novo'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner), findsNothing);
  });

  testWidgets('"Novo" abre a folha com as duas origens', (tester) async {
    criarInventario();
    await abrir(tester);

    await tocarNovo(tester);

    expect(find.text('Novo inventário'), findsOneWidget);
    expect(find.text(rotuloLerQr), findsOneWidget);
    expect(find.text(rotuloImportar), findsOneWidget);
    expect(find.textContaining('mesma rede Wi-Fi'), findsOneWidget);
  });

  testWidgets('"Importar de arquivo" segue para nome, ano e planilha', (
    tester,
  ) async {
    criarInventario();
    await abrir(tester);

    await tocarNovo(tester);
    await tester.tap(find.text(rotuloImportar));
    await tester.pumpAndSettle();

    // O fluxo de sempre: nome e ano, depois a planilha do SUAP.
    expect(find.text('Criar'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nome'),
      'Campus Floriano',
    );
    await tester.tap(find.text('Criar'));
    await tester.pumpAndSettle();

    expect(find.byType(TelaImportacao), findsOneWidget);
    expect(
      RepositorioInventarios(
        banco,
        RepositorioOperacoes(banco),
      ).listar().map((i) => i.nome),
      contains('Campus Floriano'),
    );
  });

  testWidgets('"Ler o QR code" abre o leitor', (tester) async {
    criarInventario();
    await abrir(tester);

    await tocarNovo(tester);
    await tester.tap(find.text(rotuloLerQr));
    await tester.pumpAndSettle();

    expect(find.text('Entrar em um inventário'), findsOneWidget);
    expect(find.byType(MobileScanner), findsOneWidget);
  });

  testWidgets('o estado vazio oferece as mesmas duas origens', (tester) async {
    await abrir(tester);

    expect(find.text('Nenhum inventário neste aparelho'), findsOneWidget);
    // `FilledButton.icon` e `OutlinedButton.icon` devolvem subclasses
    // privadas, que `find.byType` não enxerga: os botões são achados pelo
    // rótulo, que é o que a pessoa lê.
    expect(find.text(rotuloLerQr), findsOneWidget);
    expect(find.text(rotuloImportar), findsOneWidget);

    await tester.tap(find.text(rotuloImportar));
    await tester.pumpAndSettle();
    expect(find.text('Criar'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(rotuloLerQr));
    await tester.pumpAndSettle();
    expect(find.byType(MobileScanner), findsOneWidget);
  });
}
