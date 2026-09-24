import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/features/sync/compartilhar_inventario.dart';

import '../apoio/rede_simulada.dart';

/// O diálogo do QR code é a base do compartilhamento: se ele não desenha, o
/// fluxo de entrada por QR não existe.
void main() {
  late Aparelho a;
  late Inventario inventario;

  setUp(() {
    a = Aparelho('Ana');
    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
  });

  tearDown(() => a.fechar());

  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => mostrarQrDoInventario(context, inventario),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('o diálogo do QR é desenhado, com o código em tamanho real', (
    tester,
  ) async {
    await abrir(tester);

    // `AlertDialog` mede o conteúdo por largura intrínseca, e `QrImageView`
    // usa um `LayoutBuilder`, que não responde a isso: sem tamanho fixo o
    // layout do diálogo inteiro falha e só a barreira escurecida aparece.
    expect(tester.takeException(), isNull);

    final qr = find.byType(QrImageView);
    expect(qr, findsOneWidget);
    final tamanho = tester.getSize(qr);
    expect(tamanho.width, 240);
    expect(tamanho.height, 240);

    expect(find.text('Compartilhar inventário'), findsOneWidget);
    expect(find.text('Campus Picos — 2026'), findsOneWidget);
    expect(find.text('Fechar'), findsOneWidget);
  });

  testWidgets('fechar tira o diálogo da tela', (tester) async {
    await abrir(tester);

    await tester.tap(find.text('Fechar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(QrImageView), findsNothing);
  });
}
