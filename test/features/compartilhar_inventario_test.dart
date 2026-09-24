import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/features/sync/anuncio.dart';
import 'package:slap_mobile/features/sync/compartilhar_inventario.dart';
import 'package:slap_mobile/features/sync/protocolo.dart';
import 'package:slap_mobile/features/sync/servidor.dart';

import '../apoio/rede_simulada.dart';

/// Anúncio que não encosta na rede: o teste não tem Wi-Fi nem mDNS.
class AnuncioDeTeste extends AnuncioEntrada {
  int aberturas = 0;
  int fechamentos = 0;

  AnuncioDeTeste(Aparelho aparelho)
    : super(
        servidor: ServidorSync(
          banco: aparelho.banco,
          ops: aparelho.ops,
          inventarios: aparelho.inventarios,
          patrimonios: aparelho.patrimonios,
        ),
        banco: aparelho.banco,
        usuarioNome: () => null,
      );

  @override
  Future<void> abrir() async {
    aberturas++;
  }

  @override
  void fechar() {
    fechamentos++;
  }
}

/// A folha de compartilhar e o diálogo do QR code: se eles não desenham, o
/// fluxo de entrada não existe.
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

  group('folha de compartilhar', () {
    late AnuncioDeTeste anuncio;

    Future<void> abrirFolha(WidgetTester tester) async {
      anuncio = AnuncioDeTeste(a);
      final container = ProviderContainer(
        overrides: [
          bancoProvider.overrideWithValue(a.banco),
          anuncioEntradaProvider.overrideWithValue(anuncio),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: temaClaro,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () =>
                        compartilharInventario(context, ref, inventario),
                    child: const Text('compartilhar'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('compartilhar'));
      await tester.pumpAndSettle();
    }

    testWidgets('oferece o QR code e o link, com a condição da rede', (
      tester,
    ) async {
      await abrirFolha(tester);

      expect(find.text('Compartilhar inventário'), findsOneWidget);
      expect(find.text('Campus Picos — 2026'), findsOneWidget);
      expect(find.text(rotuloQr), findsOneWidget);
      expect(find.text(rotuloLink), findsOneWidget);
      expect(find.textContaining('mesma rede Wi-Fi'), findsOneWidget);
      // O que o link não leva é o que torna seguro mandá-lo por mensagem.
      expect(find.textContaining('não contém a chave'), findsOneWidget);
    });

    testWidgets('enquanto a folha está aberta, o aparelho se anuncia', (
      tester,
    ) async {
      await abrirFolha(tester);
      expect(anuncio.aberturas, 1);
      expect(anuncio.fechamentos, 0);

      // Sem o anúncio, quem recebeu o link não teria a quem pedir entrada.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(anuncio.fechamentos, 1);
    });

    testWidgets('"$rotuloQr" abre o diálogo do QR', (tester) async {
      await abrirFolha(tester);

      await tester.tap(find.text(rotuloQr));
      await tester.pumpAndSettle();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('texto do convite', () {
    test('leva o link, o inventário e o que a pessoa precisa fazer', () {
      final convite = ConviteLink.de(inventario, dispositivo: a.dispositivoId);
      final texto = textoDoConvite(convite);

      expect(texto, contains(convite.codificar()));
      expect(texto, contains('Campus Picos — 2026'));
      expect(texto, contains('mesma rede Wi-Fi'));
      expect(texto, contains('aceitar'));
      // Nunca a chave: o link é feito para ser encaminhado.
      expect(texto.contains(inventario.chaveSync), isFalse);
    });
  });
}
