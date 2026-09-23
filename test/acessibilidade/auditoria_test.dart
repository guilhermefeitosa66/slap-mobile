import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/divergencia.dart';
import 'package:slap_mobile/features/ajustes/tela_ajustes.dart';
import 'package:slap_mobile/features/divergence/tela_itens.dart';
import 'package:slap_mobile/features/identity/tela_identidade.dart';
import 'package:slap_mobile/features/import/tela_importacao.dart';
import 'package:slap_mobile/features/inventory/tela_dashboard.dart';
import 'package:slap_mobile/features/inventory/tela_inventarios.dart';
import 'package:slap_mobile/features/reports/tela_relatorios.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';
import 'package:slap_mobile/features/survey/tela_levantamento.dart';
import 'package:slap_mobile/features/sync/tela_conflitos.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// Auditoria de acessibilidade das telas, pelo que o TalkBack enxerga: a
/// árvore de semântica.
///
/// - todo alvo de toque tem pelo menos 48 dp;
/// - todo alvo de toque tem rótulo — botão só de ícone incluído;
/// - texto com contraste de 4,5:1 (3:1 a partir de 24 px);
/// - com a fonte do sistema em 200%, nada estoura o layout.
void main() {
  late Aparelho a;
  late Aparelho b;
  late Inventario inventario;

  setUp(() {
    a = Aparelho('Ana Souza');
    b = Aparelho('Bruno');
    inventario = a.inventarios.criar(
      nome: 'Campus Picos — Patrimônio Geral',
      ano: 2026,
    );
    a.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 8; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: (23100 + i).toString().padLeft(6, '0'),
          sala: 'Coordenação de Tecnologia da Informação',
          responsavel: 'Responsável $i',
        ),
    ]);
    RedeSimulada.distribuir(a, [b], inventario);
    // Um conflito, para a tela de conflitos ter o que mostrar.
    a.patrimonios.registrarVerificacao(
      patrimonio: a.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Auditório'),
      usuarioNome: 'Ana',
    );
    b.patrimonios.registrarVerificacao(
      patrimonio: b.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Biblioteca Central'),
      usuarioNome: 'Bruno',
    );
    RedeSimulada.sincronizar(a, b, inventario.id);
    a.patrimonios.registrarVerificacao(
      patrimonio: a.patrimonios.porId('item-2')!,
      config: const ConfiguracaoLevantamento(sala: 'Auditório'),
      usuarioNome: 'Ana',
    );
  });

  tearDown(() {
    a.fechar();
    b.fechar();
  });

  void comConfiguracao(ProviderContainer c) {
    c
        .read(configuracoesProvider.notifier)
        .definir(
          inventario.id,
          const ConfiguracaoLevantamento(
            sala: 'Coordenação de Tecnologia da Informação',
            responsavel: 'Maria José da Silva',
          ),
        );
    final repo = c.read(patrimoniosProvider);
    final historico = c.read(historicosProvider.notifier);
    Leitura ler(String codigo) => repo.procurar(
      inventarioId: inventario.id,
      codigo: codigo,
      modo: ModoLeitura.tombo,
    );
    historico.registrar(
      inventario.id,
      LeituraRegistrada(leitura: ler('023103'), codigoLido: '023103'),
    );
    historico.registrar(
      inventario.id,
      LeituraRegistrada(
        leitura: const Leitura(resultado: ResultadoLeitura.naoLocalizado),
        codigoLido: '999999',
      ),
    );
    historico.registrar(
      inventario.id,
      LeituraRegistrada(leitura: ler('023102'), codigoLido: '023102'),
    );
  }

  final telas =
      <String, (Widget Function(), void Function(ProviderContainer)?)>{
        'inventários': (() => const TelaInventarios(), null),
        'painel': (() => TelaDashboard(inventarioId: inventario.id), null),
        'levantamento': (
          () => TelaLevantamento(inventarioId: inventario.id),
          comConfiguracao,
        ),
        'itens': (
          () => TelaItens(
            inventarioId: inventario.id,
            classificacao: Classificacao.divergente,
          ),
          null,
        ),
        'conflitos': (() => TelaConflitos(inventarioId: inventario.id), null),
        'relatórios': (() => TelaRelatorios(inventarioId: inventario.id), null),
        'ajustes': (() => const TelaAjustes(), null),
        'identidade': (() => const TelaIdentidade(), null),
        'importação': (() => TelaImportacao(inventarioId: inventario.id), null),
      };

  Future<void> abrir(
    WidgetTester tester,
    String nome, {
    double escala = 1,
    ThemeMode modo = ThemeMode.light,
  }) async {
    final (tela, preparar) = telas[nome]!;
    final container = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(a.banco),
        sonsProvider.overrideWithValue(SonsMudos()),
      ],
    );
    addTearDown(container.dispose);
    preparar?.call(container);

    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: temaClaro,
          darkTheme: temaEscuro,
          themeMode: modo,
          home: MediaQuery.withClampedTextScaling(
            minScaleFactor: escala,
            maxScaleFactor: escala,
            child: tela(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final nome in telas.keys) {
    group(nome, () {
      testWidgets('alvos de toque, rótulos e contraste', (tester) async {
        final semantica = tester.ensureSemantics();
        await abrir(tester, nome);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('contraste no tema escuro', (tester) async {
        final semantica = tester.ensureSemantics();
        await abrir(tester, nome, modo: ThemeMode.dark);
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        semantica.dispose();
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('fonte do sistema em 200% não estoura o layout', (
        tester,
      ) async {
        await abrir(tester, nome, escala: 2);
        await tester.pumpWidget(const SizedBox());
      });
    });
  }
}
