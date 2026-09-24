import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/ajustes/tela_ajustes.dart';
import '../features/divergence/tela_itens.dart';
import '../features/identity/tela_identidade.dart';
import '../features/import/tela_importacao.dart';
import '../features/inventory/tela_dashboard.dart';
import '../features/inventory/tela_inventarios.dart';
import '../features/reports/tela_relatorios.dart';
import '../features/survey/tela_levantamento.dart';
import '../features/sync/tela_conflitos.dart';
import '../features/sync/tela_sincronizacao.dart';
import '../data/banco.dart';
import '../data/repos/inventarios.dart';
import '../data/schema.dart';
import '../domain/divergencia.dart';
import 'preferencias.dart';
import 'providers.dart';
import 'tema.dart';

export 'tema.dart';

class AplicativoSlap extends ConsumerStatefulWidget {
  const AplicativoSlap({super.key});

  @override
  ConsumerState<AplicativoSlap> createState() => _AplicativoSlapState();
}

class _AplicativoSlapState extends ConsumerState<AplicativoSlap> {
  late final GoRouter _rotas;

  @override
  void initState() {
    super.initState();

    // O áudio é preparado na inicialização para que a primeira leitura já
    // tenha retorno imediato, sem o atraso de carregar o arquivo.
    ref.read(sonsProvider).preparar();

    _rotas = GoRouter(
      initialLocation: rotaInicial(
        ref.read(bancoProvider),
        ref.read(inventariosProvider),
      ),
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const TelaInventarios(),
          redirect: (context, state) {
            // Sem identidade não há a quem atribuir as verificações, e o
            // relatório final sairia sem autor.
            final identidade = ref.read(identidadeProvider);
            return identidade.configurada ? null : '/identidade';
          },
          // O inventário fica debaixo da lista, mesmo quando o aplicativo abre
          // direto no levantamento: voltar do painel chega à lista, em vez de
          // fechar o aplicativo.
          routes: [
            GoRoute(
              path: 'inventario/:id',
              builder: (_, estado) =>
                  TelaDashboard(inventarioId: estado.pathParameters['id']!),
              routes: [
                GoRoute(
                  path: 'importar',
                  builder: (_, estado) => TelaImportacao(
                    inventarioId: estado.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'levantamento',
                  builder: (_, estado) => TelaLevantamento(
                    inventarioId: estado.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'itens',
                  builder: (_, estado) => TelaItens(
                    inventarioId: estado.pathParameters['id']!,
                    classificacao: _classificacaoDe(
                      estado.uri.queryParameters['grupo'],
                    ),
                  ),
                ),
                GoRoute(
                  path: 'sincronizar',
                  builder: (_, estado) => TelaSincronizacao(
                    inventarioId: estado.pathParameters['id']!,
                  ),
                ),
                GoRoute(
                  path: 'conflitos',
                  builder: (_, estado) =>
                      TelaConflitos(inventarioId: estado.pathParameters['id']!),
                ),
                GoRoute(
                  path: 'relatorios',
                  builder: (_, estado) => TelaRelatorios(
                    inventarioId: estado.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(path: '/ajustes', builder: (_, _) => const TelaAjustes()),
        GoRoute(
          path: '/identidade',
          builder: (_, estado) => TelaIdentidade(
            primeiraVez: estado.uri.queryParameters['inicial'] != 'false',
          ),
        ),
      ],
    );
  }

  static Classificacao? _classificacaoDe(String? nome) {
    for (final c in Classificacao.values) {
      if (c.name == nome) return c;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'SLAP',
      debugShowCheckedModeBanner: false,
      routerConfig: _rotas,
      theme: temaClaro,
      darkTheme: temaEscuro,
      themeMode: ref.watch(preferenciasProvider).tema.modo,
      builder: (_, filho) => BarrasDoSistema(child: filho!),
    );
  }
}

/// Onde o aplicativo abre.
///
/// Se o Android o encerrou no meio de um levantamento, ele volta direto para
/// a sala em que a pessoa estava, com a configuração gravada. Nos outros
/// casos, a lista de inventários.
String rotaInicial(Banco banco, RepositorioInventarios inventarios) {
  final aberto = banco.lerConfig(Config.levantamentoAberto);
  if (aberto != null && inventarios.porId(aberto) != null) {
    return '/inventario/$aberto/levantamento';
  }
  return '/';
}
