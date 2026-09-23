import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/banco.dart';
import '../../data/repos/patrimonios.dart';
import '../../data/schema.dart';
import '../../domain/patrimonio.dart';

/// Estado de sessão do levantamento.
///
/// Guardado por inventário num mapa dentro de um único notifier, em vez de um
/// notifier por família: o Riverpod 3 não expõe o argumento da família a uma
/// classe `Notifier` escrita à mão, e um mapa resolve o mesmo problema sem
/// depender de geração de código.
///
/// Nada aqui é dado do inventário, e nada sincroniza. A configuração vai para
/// a tabela `config` do aparelho, para sobreviver ao Android encerrar o
/// aplicativo; o histórico e o modo de leitura vivem só em memória.

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

  /// Passa a valer a partir de agora, e fica gravada.
  void definir(String inventarioId, ConfiguracaoLevantamento config) {
    final vigente = config.copyWith(desde: DateTime.now());
    ref
        .read(bancoProvider)
        .gravarConfig(
          Config.configuracaoLevantamento(inventarioId),
          jsonEncode(vigente.toJson()),
        );
    state = {...state, inventarioId: vigente};
  }

  /// A mesma configuração, reconfirmada depois de um intervalo longo.
  void reconfirmar(String inventarioId) {
    final atual = configuracaoGravada(ref.read(bancoProvider), inventarioId);
    if (atual != null) definir(inventarioId, atual);
  }

  void limpar(String inventarioId) {
    ref
        .read(bancoProvider)
        .apagarConfig(Config.configuracaoLevantamento(inventarioId));
    state = {...state}..remove(inventarioId);
  }
}

/// A configuração gravada de um inventário, se houver.
ConfiguracaoLevantamento? configuracaoGravada(
  Banco banco,
  String inventarioId,
) {
  final texto = banco.lerConfig(Config.configuracaoLevantamento(inventarioId));
  if (texto == null) return null;
  try {
    return ConfiguracaoLevantamento.fromJson(
      jsonDecode(texto) as Map<String, dynamic>,
    );
  } on FormatException {
    return null;
  } on TypeError {
    return null;
  }
}

/// Depois de quanto tempo sem ler nada a sala é confirmada antes de seguir.
///
/// Voltar no dia seguinte e continuar gravando "Auditório" por engano é pior
/// que uma pergunta: a sala errada contamina tudo o que for lido em seguida,
/// e achar depois quais itens foram é trabalhoso.
const intervaloParaConfirmarSala = Duration(hours: 4);

/// Se a sala precisa ser confirmada antes da próxima leitura.
///
/// Conta a partir do que for mais recente: a última leitura deste aparelho
/// neste inventário ou o momento em que a configuração passou a valer.
bool precisaConfirmarSala({
  required ConfiguracaoLevantamento config,
  required DateTime? ultimaLeitura,
  required DateTime agora,
}) {
  final marcos = [?ultimaLeitura, ?config.desde];
  if (marcos.isEmpty) return false;
  final referencia = marcos.reduce((a, b) => a.isAfter(b) ? a : b);
  return agora.difference(referencia) > intervaloParaConfirmarSala;
}

final configuracoesProvider =
    NotifierProvider<
      ControladorConfiguracoes,
      Map<String, ConfiguracaoLevantamento>
    >(ControladorConfiguracoes.new);

/// Configuração corrente de um inventário, ou `null` se ainda não definida.
///
/// A da sessão tem precedência; sem ela, vale a gravada — é o que devolve a
/// sala a quem reabre o aplicativo no meio do levantamento.
final configuracaoProvider = Provider.family<ConfiguracaoLevantamento?, String>(
  (ref, inventarioId) {
    return ref.watch(configuracoesProvider)[inventarioId] ??
        configuracaoGravada(ref.watch(bancoProvider), inventarioId);
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
