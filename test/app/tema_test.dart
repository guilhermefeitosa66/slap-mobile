import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/app.dart';
import 'package:slap_mobile/app/preferencias.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/ajustes/tela_ajustes.dart';

import '../apoio/app_de_teste.dart';

/// O tema escolhido nos ajustes vale no aplicativo inteiro, sobrevive ao
/// reinício e leva as barras do sistema junto.
void main() {
  /// Com identidade, o aplicativo abre na lista de inventários em vez de
  /// pedir o nome.
  Banco bancoComIdentidade() =>
      Banco.emMemoria()..gravarConfig(Config.usuarioNome, 'Ana');

  /// Monta o aplicativo de verdade — rotas, tema e preferências — sobre
  /// [banco]. Chamar de novo com o mesmo banco é o reinício do aplicativo.
  Future<ProviderContainer> abrir(WidgetTester tester, Banco banco) async {
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
    return container;
  }

  void sistemaEm(WidgetTester tester, Brightness brilho) {
    tester.platformDispatcher.platformBrightnessTestValue = brilho;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  ThemeData temaEmUso(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(Scaffold).first));

  CoresResultado coresEmUso(WidgetTester tester) =>
      CoresResultado.of(tester.element(find.byType(Scaffold).first));

  group('Preferencias', () {
    test('sem nada gravado, segue o sistema', () {
      expect(Preferencias.doBanco(Banco.emMemoria()).tema, Tema.sistema);
    });

    test('valor desconhecido no banco não derruba o aplicativo', () {
      final banco = Banco.emMemoria()
        ..gravarConfig(Preferencias.chaveTema, 'sépia');
      expect(Preferencias.doBanco(banco).tema, Tema.sistema);
    });

    test('a escolha fica gravada e volta depois do reinício', () {
      final banco = Banco.emMemoria();
      final container = ProviderContainer(
        overrides: [bancoProvider.overrideWithValue(banco)],
      );
      addTearDown(container.dispose);

      container.read(preferenciasProvider.notifier).tema(Tema.escuro);

      expect(container.read(preferenciasProvider).tema, Tema.escuro);
      expect(banco.lerConfig(Preferencias.chaveTema), 'escuro');
      // Um container novo é o aplicativo aberto de novo.
      final reaberto = ProviderContainer(
        overrides: [bancoProvider.overrideWithValue(banco)],
      );
      addTearDown(reaberto.dispose);
      expect(reaberto.read(preferenciasProvider).tema, Tema.escuro);
    });
  });

  group('no aplicativo', () {
    testWidgets('por padrão acompanha o sistema, para os dois lados', (
      tester,
    ) async {
      sistemaEm(tester, Brightness.dark);
      await abrir(tester, bancoComIdentidade());

      expect(temaEmUso(tester).brightness, Brightness.dark);
      expect(coresEmUso(tester), same(CoresResultado.escuro));

      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpAndSettle();

      expect(temaEmUso(tester).brightness, Brightness.light);
      expect(coresEmUso(tester), same(CoresResultado.claro));
    });

    testWidgets('escuro gravado vence o sistema claro', (tester) async {
      sistemaEm(tester, Brightness.light);
      final banco = bancoComIdentidade()
        ..gravarConfig(Preferencias.chaveTema, 'escuro');
      await abrir(tester, banco);

      expect(temaEmUso(tester).brightness, Brightness.dark);
      expect(coresEmUso(tester), same(CoresResultado.escuro));
      expect(
        coresEmUso(tester).registrado.fundo,
        CoresResultado.escuro.registrado.fundo,
      );
    });

    testWidgets('claro gravado vence o sistema escuro', (tester) async {
      sistemaEm(tester, Brightness.dark);
      final banco = bancoComIdentidade()
        ..gravarConfig(Preferencias.chaveTema, 'claro');
      await abrir(tester, banco);

      expect(temaEmUso(tester).brightness, Brightness.light);
      expect(coresEmUso(tester), same(CoresResultado.claro));
    });

    testWidgets('as barras do sistema acompanham o brilho', (tester) async {
      sistemaEm(tester, Brightness.light);
      final banco = bancoComIdentidade();
      await abrir(tester, banco);

      var barras = SystemChrome.latestStyle!;
      expect(barras.statusBarIconBrightness, Brightness.dark);
      expect(barras.systemNavigationBarIconBrightness, Brightness.dark);
      expect(barras.systemNavigationBarColor, PaletaClara.fundo);

      banco.gravarConfig(Preferencias.chaveTema, 'escuro');
      await abrir(tester, banco);

      barras = SystemChrome.latestStyle!;
      expect(barras.statusBarIconBrightness, Brightness.light);
      expect(barras.systemNavigationBarIconBrightness, Brightness.light);
      expect(barras.systemNavigationBarColor, PaletaEscura.fundo);
    });
  });

  group('nos ajustes', () {
    testWidgets('o seletor troca o tema na hora e a escolha sobrevive', (
      tester,
    ) async {
      sistemaEm(tester, Brightness.light);
      final banco = bancoComIdentidade();
      final container = await abrir(tester, banco);

      await tester.tap(find.byTooltip('Meus dados e ajustes'));
      await tester.pumpAndSettle();
      expect(find.byType(TelaAjustes), findsOneWidget);
      expect(find.text('Aparência'.toUpperCase()), findsOneWidget);

      // A seção fica abaixo da dobra na tela pequena dos testes.
      await tester.ensureVisible(find.text('Escuro'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Escuro'));
      await tester.pumpAndSettle();

      expect(temaEmUso(tester).brightness, Brightness.dark);
      expect(coresEmUso(tester), same(CoresResultado.escuro));
      expect(container.read(preferenciasProvider).tema, Tema.escuro);
      expect(banco.lerConfig(Preferencias.chaveTema), 'escuro');

      await tester.tap(find.text('Sistema'));
      await tester.pumpAndSettle();
      expect(temaEmUso(tester).brightness, Brightness.light);
      expect(banco.lerConfig(Preferencias.chaveTema), 'sistema');

      await tester.tap(find.text('Escuro'));
      await tester.pumpAndSettle();

      // Reinício: o aplicativo abre de novo sobre o mesmo banco, já escuro.
      await abrir(tester, banco);
      expect(temaEmUso(tester).brightness, Brightness.dark);
    });
  });
}
