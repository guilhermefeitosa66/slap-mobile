@Tags(['capturas'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/divergencia.dart';
import 'package:slap_mobile/features/divergence/tela_itens.dart';
import 'package:slap_mobile/features/identity/tela_identidade.dart';
import 'package:slap_mobile/features/inventory/tela_dashboard.dart';
import 'package:slap_mobile/features/inventory/tela_inventarios.dart';
import 'package:slap_mobile/features/reports/tela_relatorios.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';
import 'package:slap_mobile/features/survey/tela_levantamento.dart';

import 'cenario.dart';

/// Capturas das telas principais, com dados de demonstração.
///
/// Não é teste de regressão: gera as imagens da documentação e da listagem
/// na loja. Fica fora da rodada normal (ver `dart_test.yaml`) e se gera com
///
///     flutter test --run-skipped --tags capturas --update-goldens
///
/// As imagens saem em `docs/loja/capturas/`.
void main() {
  const destino = '../../docs/loja/capturas';

  final formatos = {
    // 1080 × 1920: proporção 9:16 aceita pela Play Store.
    'celular': (const Size(360, 640), 3.0),
    // 1600 × 2560 em retrato, tablet de 10 polegadas.
    'tablet': (const Size(800, 1280), 2.0),
  };

  setUpAll(carregarFontes);

  Future<void> capturar(
    WidgetTester tester, {
    required String nome,
    required Widget Function(ProviderContainer) tela,
    void Function(ProviderContainer)? preparar,
    ThemeMode modo = ThemeMode.light,
    String formato = 'celular',
  }) async {
    // O flutter_test troca sombras por um contorno preto, para os testes de
    // imagem não dependerem do desfoque. Aqui a captura precisa da sombra.
    // Precisa voltar ao padrão antes do fim do corpo do teste, que é quando
    // o flutter_test confere essas variáveis.
    debugDisableShadows = false;

    final (tamanho, densidade) = formatos[formato]!;
    tester.view.physicalSize = tamanho * densidade;
    tester.view.devicePixelRatio = densidade;
    addTearDown(tester.view.reset);

    final cenario = Cenario();
    addTearDown(cenario.fechar);

    final container = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(cenario.banco),
        sonsProvider.overrideWithValue(SonsMudos()),
      ],
    );
    addTearDown(container.dispose);
    preparar?.call(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaro,
          darkTheme: temaEscuro,
          themeMode: modo,
          home: Builder(builder: (_) => tela(container)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    try {
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('$destino/$formato-$nome.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  for (final formato in formatos.keys) {
    testWidgets('$formato: inventários', (tester) async {
      await capturar(
        tester,
        formato: formato,
        nome: '1-inventarios',
        tela: (_) => const TelaInventarios(),
      );
    });

    testWidgets('$formato: painel', (tester) async {
      await capturar(
        tester,
        formato: formato,
        nome: '2-painel',
        tela: (c) => TelaDashboard(inventarioId: _geral(c)),
      );
    });

    testWidgets('$formato: levantamento', (tester) async {
      await capturar(
        tester,
        formato: formato,
        nome: '3-levantamento',
        preparar: _levantamentoEmAndamento,
        tela: (c) => TelaLevantamento(inventarioId: _geral(c)),
      );
    });

    testWidgets('$formato: divergentes', (tester) async {
      await capturar(
        tester,
        formato: formato,
        nome: '4-divergentes',
        tela: (c) => TelaItens(
          inventarioId: _geral(c),
          classificacao: Classificacao.divergente,
        ),
      );
    });

    testWidgets('$formato: relatórios', (tester) async {
      await capturar(
        tester,
        formato: formato,
        nome: '5-relatorios',
        tela: (c) => TelaRelatorios(inventarioId: _geral(c)),
      );
    });

    testWidgets('$formato: identidade', (tester) async {
      await capturar(
        tester,
        formato: formato,
        nome: '6-identidade',
        tela: (_) => const TelaIdentidade(),
      );
    });
  }

  testWidgets('escuro: levantamento', (tester) async {
    await capturar(
      tester,
      nome: '7-levantamento-escuro',
      modo: ThemeMode.dark,
      preparar: _levantamentoEmAndamento,
      tela: (c) => TelaLevantamento(inventarioId: _geral(c)),
    );
  });

  testWidgets('escuro: painel', (tester) async {
    await capturar(
      tester,
      nome: '8-painel-escuro',
      modo: ThemeMode.dark,
      tela: (c) => TelaDashboard(inventarioId: _geral(c)),
    );
  });
}

String _geral(ProviderContainer c) => c
    .read(listaInventariosProvider)
    .firstWhere((i) => i.nome.endsWith('Patrimônio Geral'))
    .id;

/// Configuração aplicada e as três leituras recentes que o design mostra.
void _levantamentoEmAndamento(ProviderContainer c) {
  final id = _geral(c);
  c
      .read(configuracoesProvider.notifier)
      .definir(id, const ConfiguracaoLevantamento(sala: 'Auditório'));

  final repo = c.read(patrimoniosProvider);
  final historico = c.read(historicosProvider.notifier);

  Leitura ler(String codigo) =>
      repo.procurar(inventarioId: id, codigo: codigo, modo: ModoLeitura.tombo);

  // Ordem de leitura: a mais recente fica no topo.
  final pendente = ler('023300');
  final depois = repo.registrarVerificacao(
    patrimonio: pendente.patrimonio!,
    config: const ConfiguracaoLevantamento(sala: 'Auditório'),
    usuarioNome: 'Ana Souza',
  );
  historico.registrar(
    id,
    LeituraRegistrada(leitura: pendente, codigoLido: '023300', depois: depois),
  );
  historico.registrar(
    id,
    LeituraRegistrada(
      leitura: const Leitura(resultado: ResultadoLeitura.naoLocalizado),
      codigoLido: '887401',
    ),
  );
  historico.registrar(
    id,
    LeituraRegistrada(leitura: ler('023101'), codigoLido: '023101'),
  );
}
