/// Version vector: o que uma réplica sabe sobre o que cada aparelho escreveu.
///
/// Cada aparelho numera suas próprias operações com um `seq` monotônico
/// (1, 2, 3, ...). A version vector guarda o maior `seq` conhecido de cada
/// aparelho: `{A: 412, B: 87, C: 0}` significa "vi as 412 primeiras operações
/// de A, as 87 primeiras de B e nenhuma de C".
///
/// Ela serve a duas coisas ao mesmo tempo:
///
/// 1. **Sincronização incremental** — para saber o que falta a um par, basta
///    comparar a vector dele com a nossa e enviar só a diferença. Nunca é
///    preciso retransmitir o inventário inteiro.
/// 2. **Detecção de concorrência** — guardada junto de cada operação, ela diz
///    o que o autor já conhecia no momento da escrita, e portanto se duas
///    escritas foram feitas com ou sem conhecimento uma da outra.
library;

import 'dart:convert';

class VersionVector {
  final Map<String, int> _seqs;

  const VersionVector._(this._seqs);

  VersionVector(Map<String, int> seqs)
    : _seqs = Map.unmodifiable({...seqs}..removeWhere((_, s) => s <= 0));

  static const VersionVector vazia = VersionVector._({});

  /// Maior `seq` conhecido de um aparelho. Zero quando nunca vimos nada dele.
  int operator [](String deviceId) => _seqs[deviceId] ?? 0;

  Iterable<String> get dispositivos => _seqs.keys;

  bool get isEmpty => _seqs.isEmpty;

  /// Registra que conhecemos as operações de [deviceId] até [seq].
  VersionVector com(String deviceId, int seq) {
    if (seq <= this[deviceId]) return this;
    return VersionVector({..._seqs, deviceId: seq});
  }

  /// União de dois conhecimentos: o maior `seq` de cada aparelho.
  ///
  /// É o que acontece ao terminar uma sincronização — passamos a saber tudo
  /// que sabíamos mais tudo que o par sabia.
  VersionVector unir(VersionVector outra) {
    final resultado = {..._seqs};
    for (final device in outra._seqs.keys) {
      final seq = outra[device];
      if (seq > (resultado[device] ?? 0)) resultado[device] = seq;
    }
    return VersionVector(resultado);
  }

  /// Verdadeiro quando esta réplica já conhecia a operação `(deviceId, seq)`.
  bool conhece(String deviceId, int seq) => this[deviceId] >= seq;

  /// Verdadeiro quando esta vector inclui tudo que [outra] inclui.
  bool contem(VersionVector outra) =>
      outra._seqs.entries.every((e) => this[e.key] >= e.value);

  String codificar() {
    final ordenado = _seqs.keys.toList()..sort();
    return jsonEncode({for (final d in ordenado) d: _seqs[d]});
  }

  static VersionVector decodificar(String? texto) {
    if (texto == null || texto.isEmpty) return vazia;
    final bruto = jsonDecode(texto) as Map<String, dynamic>;
    return VersionVector(bruto.map((d, s) => MapEntry(d, (s as num).toInt())));
  }

  /// Chave estável usada para deduplicar contextos causais no banco.
  ///
  /// Como a parte remota da vector só muda quando ocorre uma sincronização,
  /// uma sessão inteira de levantamento compartilha a mesma chave — é o que
  /// permite guardar uma linha de contexto por sincronização em vez de uma
  /// por operação.
  String get impressao => codificar();

  @override
  bool operator ==(Object outro) =>
      outro is VersionVector && codificar() == outro.codificar();

  @override
  int get hashCode => codificar().hashCode;

  @override
  String toString() => codificar();
}

/// Faixa contígua de operações que faltam de um aparelho, inclusiva nas duas
/// pontas.
class Faixa {
  final int de;
  final int ate;

  const Faixa(this.de, this.ate);

  bool contem(int seq) => seq >= de && seq <= ate;

  @override
  bool operator ==(Object outro) =>
      outro is Faixa && de == outro.de && ate == outro.ate;

  @override
  int get hashCode => Object.hash(de, ate);

  @override
  String toString() => '[$de, $ate]';
}

/// Quantas faixas de um mesmo aparelho viajam num pedido.
///
/// Uma réplica cheia de buracos é rara — vem de réplica apagada e de operações
/// que se perderam pelo caminho —, mas o limite existe porque a lista vai na
/// rede e é escrita por quem está do outro lado. O que passar do limite fica
/// para a sincronização seguinte: as faixas vão das mais antigas para as mais
/// novas, então cada encontro fecha as primeiras e descobre as próximas.
const int maximoFaixasPorAparelho = 64;

/// O que falta **abaixo** do máximo conhecido de cada aparelho.
///
/// A version vector sozinha não sabe dizer isto: ela guarda um número por
/// aparelho, e `{B: 100}` tanto pode ser "tenho as cem primeiras de B" quanto
/// "tenho da 51 à 100". A diferença decide se um intervalo perdido volta ou
/// some para sempre.
///
/// Anunciar só o prefixo contíguo — dizer `{B: 50}` quando falta o começo —
/// não resolve: o par reenvia tudo acima do buraco a cada encontro, trava
/// quando o que está acima passa do limite de um lote e nunca fecha a
/// diferença se o intervalo se perdeu de vez. Com as lacunas declaradas, o que
/// falta é pedido nominalmente; o que não existe mais em lugar nenhum é pedido
/// uma vez por encontro e simplesmente não chega.
class Lacunas {
  final Map<String, List<Faixa>> _faixas;

  const Lacunas._(this._faixas);

  Lacunas(Map<String, List<Faixa>> faixas)
    : _faixas = Map.unmodifiable({
        for (final e in faixas.entries)
          if (e.value.isNotEmpty)
            e.key: List<Faixa>.unmodifiable(
              (e.value.toList()..sort((a, b) => a.de.compareTo(b.de))).take(
                maximoFaixasPorAparelho,
              ),
            ),
      });

  static const Lacunas vazia = Lacunas._({});

  List<Faixa> operator [](String dispositivo) =>
      _faixas[dispositivo] ?? const [];

  Iterable<String> get dispositivos => _faixas.keys;

  bool get isEmpty => _faixas.isEmpty;

  String codificar() => jsonEncode({
    for (final e in _faixas.entries)
      e.key: [
        for (final f in e.value) [f.de, f.ate],
      ],
  });

  /// Lê o que veio da rede, descartando o que não faz sentido.
  ///
  /// Faixa invertida, com número não positivo ou fora de formato é ignorada
  /// em silêncio: o outro lado escreve isto, e uma lacuna estranha não pode
  /// derrubar a sincronização inteira.
  static Lacunas decodificar(Object? bruto) {
    if (bruto == null) return vazia;
    Object? json = bruto;
    if (bruto is String) {
      if (bruto.isEmpty) return vazia;
      try {
        json = jsonDecode(bruto);
      } on FormatException {
        return vazia;
      }
    }
    if (json is! Map) return vazia;

    final faixas = <String, List<Faixa>>{};
    for (final e in json.entries) {
      final lista = e.value;
      if (e.key is! String || lista is! List) continue;
      final doAparelho = <Faixa>[];
      for (final f in lista) {
        if (f is! List || f.length != 2) continue;
        final de = f[0], ate = f[1];
        if (de is! num || ate is! num) continue;
        if (de < 1 || ate < de) continue;
        doAparelho.add(Faixa(de.toInt(), ate.toInt()));
      }
      if (doAparelho.isNotEmpty) faixas[e.key as String] = doAparelho;
    }
    return Lacunas(faixas);
  }

  @override
  String toString() => codificar();
}

/// Relação causal entre duas operações.
enum RelacaoCausal {
  /// A primeira aconteceu antes da segunda: quem escreveu a segunda já
  /// conhecia a primeira. Substituir não é conflito, é atualização.
  anterior,

  /// A segunda aconteceu antes da primeira.
  posterior,

  /// Nenhuma das duas conhecia a outra. É a concorrência de verdade — o caso
  /// de duas pessoas conferindo o mesmo patrimônio sem se falar.
  concorrente,

  /// São a mesma operação.
  identica,
}

/// Compara duas operações pela relação causal entre elas.
///
/// O contexto de uma operação é a parte remota da version vector do autor no
/// momento da escrita; a componente do próprio autor é implícita e vale o
/// `seq` da operação. Ver `docs/02-arquitetura.md`, seção 5.3.
RelacaoCausal compararCausalidade({
  required String deviceA,
  required int seqA,
  required VersionVector contextoA,
  required String deviceB,
  required int seqB,
  required VersionVector contextoB,
}) {
  if (deviceA == deviceB) {
    if (seqA == seqB) return RelacaoCausal.identica;
    // Operações do mesmo aparelho são sempre sequenciais, nunca concorrentes.
    return seqA < seqB ? RelacaoCausal.anterior : RelacaoCausal.posterior;
  }

  final bAconteceuDepois = contextoB.conhece(deviceA, seqA);
  final aAconteceuDepois = contextoA.conhece(deviceB, seqB);

  if (bAconteceuDepois && !aAconteceuDepois) return RelacaoCausal.anterior;
  if (aAconteceuDepois && !bAconteceuDepois) return RelacaoCausal.posterior;

  // Ambas se conhecem é impossível sem relógio corrompido; tratar como
  // concorrente é o comportamento seguro, porque leva o caso ao usuário em
  // vez de escolher em silêncio.
  return RelacaoCausal.concorrente;
}
