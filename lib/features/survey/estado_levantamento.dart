import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/patrimonios.dart';
import '../../domain/patrimonio.dart';

/// Estado de sessão do levantamento.
///
/// Guardado por inventário num mapa dentro de um único notifier, em vez de um
/// notifier por família: o Riverpod 3 não expõe o argumento da família a uma
/// classe `Notifier` escrita à mão, e um mapa resolve o mesmo problema sem
/// depender de geração de código.
///
/// Tudo aqui vive em memória. É preferência de sessão, não dado do inventário:
/// não vai para o banco nem é sincronizado.

// --------------------------------------------------------- configuração ---

/// Valores aplicados automaticamente às próximas leituras.
///
/// É o mecanismo que dá a velocidade ao processo, herdado do SLAP: o usuário
/// define sala, estado, situação e responsável uma vez ao entrar no ambiente,
/// e cada leitura seguinte herda tudo. Uma leitura não exige nenhum toque na
/// tela — é isso que permite inventariar uma sala inteira em minutos.
class ControladorConfiguracoes
    extends Notifier<Map<String, ConfiguracaoLevantamento>> {
  @override
  Map<String, ConfiguracaoLevantamento> build() => const {};

  void definir(String inventarioId, ConfiguracaoLevantamento config) {
    state = {...state, inventarioId: config};
  }

  void limpar(String inventarioId) {
    state = {...state}..remove(inventarioId);
  }
}

final configuracoesProvider =
    NotifierProvider<
      ControladorConfiguracoes,
      Map<String, ConfiguracaoLevantamento>
    >(ControladorConfiguracoes.new);

/// Configuração corrente de um inventário, ou `null` se ainda não definida.
final configuracaoProvider = Provider.family<ConfiguracaoLevantamento?, String>(
  (ref, inventarioId) {
    return ref.watch(configuracoesProvider)[inventarioId];
  },
);

// ------------------------------------------------------------- histórico ---

/// Uma leitura desta sessão, para a lista de conferência na tela.
class LeituraRegistrada {
  final Leitura leitura;
  final String codigoLido;
  final DateTime quando;

  /// Mantido à parte porque o patrimônio dentro de [leitura] é o estado de
  /// *antes* da gravação, e a lista precisa mostrar o de depois.
  final Patrimonio? depois;

  LeituraRegistrada({
    required this.leitura,
    required this.codigoLido,
    this.depois,
  }) : quando = DateTime.now();

  ResultadoLeitura get resultado => leitura.resultado;
  Patrimonio? get patrimonio => depois ?? leitura.patrimonio;
}

class ControladorHistoricos
    extends Notifier<Map<String, List<LeituraRegistrada>>> {
  /// Só as últimas leituras ficam na tela. A lista serve para conferir o que
  /// acabou de passar, não para navegar o inventário — para isso existe a
  /// tela de itens.
  static const limite = 50;

  @override
  Map<String, List<LeituraRegistrada>> build() => const {};

  void registrar(String inventarioId, LeituraRegistrada leitura) {
    final atual = state[inventarioId] ?? const <LeituraRegistrada>[];
    state = {
      ...state,
      inventarioId: [leitura, ...atual].take(limite).toList(),
    };
  }

  void limpar(String inventarioId) {
    state = {...state}..remove(inventarioId);
  }
}

final historicosProvider =
    NotifierProvider<
      ControladorHistoricos,
      Map<String, List<LeituraRegistrada>>
    >(ControladorHistoricos.new);

final historicoProvider = Provider.family<List<LeituraRegistrada>, String>((
  ref,
  inventarioId,
) {
  return ref.watch(historicosProvider)[inventarioId] ?? const [];
});

// ------------------------------------------------------------------ modo ---

/// Campo em que a leitura procura primeiro.
class ControladorModo extends Notifier<ModoLeitura> {
  @override
  ModoLeitura build() => ModoLeitura.codigoBarras;

  void definir(ModoLeitura modo) => state = modo;
}

final modoLeituraProvider = NotifierProvider<ControladorModo, ModoLeitura>(
  ControladorModo.new,
);
