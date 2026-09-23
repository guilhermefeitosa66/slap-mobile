import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/divergence/tela_itens.dart';
import '../features/identity/tela_identidade.dart';
import '../features/import/tela_importacao.dart';
import '../features/inventory/tela_dashboard.dart';
import '../features/inventory/tela_inventarios.dart';
import '../features/reports/tela_relatorios.dart';
import '../features/survey/tela_levantamento.dart';
import '../features/sync/tela_conflitos.dart';
import '../features/sync/tela_sincronizacao.dart';
import '../domain/divergencia.dart';
import 'providers.dart';

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
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const TelaInventarios(),
          redirect: (context, state) {
            // Sem identidade não há a quem atribuir as verificações, e o
            // relatório final sairia sem autor.
            final identidade = ref.read(identidadeProvider);
            return identidade.configurada ? null : '/identidade';
          },
        ),
        GoRoute(
          path: '/identidade',
          builder: (_, estado) => TelaIdentidade(
            primeiraVez: estado.uri.queryParameters['inicial'] != 'false',
          ),
        ),
        GoRoute(
          path: '/inventario/:id',
          builder: (_, estado) =>
              TelaDashboard(inventarioId: estado.pathParameters['id']!),
          routes: [
            GoRoute(
              path: 'importar',
              builder: (_, estado) =>
                  TelaImportacao(inventarioId: estado.pathParameters['id']!),
            ),
            GoRoute(
              path: 'levantamento',
              builder: (_, estado) =>
                  TelaLevantamento(inventarioId: estado.pathParameters['id']!),
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
              builder: (_, estado) =>
                  TelaSincronizacao(inventarioId: estado.pathParameters['id']!),
            ),
            GoRoute(
              path: 'conflitos',
              builder: (_, estado) =>
                  TelaConflitos(inventarioId: estado.pathParameters['id']!),
            ),
            GoRoute(
              path: 'relatorios',
              builder: (_, estado) =>
                  TelaRelatorios(inventarioId: estado.pathParameters['id']!),
            ),
          ],
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
    );
  }
}

const _semente = Color(0xFF00695C);

ThemeData _tema(Brightness brilho) {
  final esquema = ColorScheme.fromSeed(seedColor: _semente, brightness: brilho);

  return ThemeData(
    colorScheme: esquema,
    useMaterial3: true,
    // Alvos de toque generosos: o levantamento é feito em pé, andando, muitas
    // vezes com uma das mãos ocupada pelo leitor de código de barras.
    visualDensity: VisualDensity.comfortable,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    cardTheme: const CardThemeData(margin: EdgeInsets.symmetric(vertical: 6)),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
  );
}

final temaClaro = _tema(Brightness.light);
final temaEscuro = _tema(Brightness.dark);

/// Cores dos três resultados de leitura e das classificações.
///
/// Sempre acompanhadas de ícone e texto: cor sozinha não serve a quem tem
/// daltonismo, e o levantamento depende de reconhecer o resultado num relance.
class CoresResultado {
  static const sucesso = Color(0xFF2E7D32);
  static const alerta = Color(0xFFE65100);
  static const erro = Color(0xFFC62828);
  static const neutro = Color(0xFF546E7A);

  static Color de(Classificacao c) => switch (c) {
    Classificacao.ok => sucesso,
    Classificacao.divergente => alerta,
    Classificacao.naoLocalizado => erro,
    Classificacao.ignorado => neutro,
  };

  static IconData icone(Classificacao c) => switch (c) {
    Classificacao.ok => Icons.check_circle_outline,
    Classificacao.divergente => Icons.swap_horiz,
    Classificacao.naoLocalizado => Icons.search_off,
    Classificacao.ignorado => Icons.block,
  };
}
