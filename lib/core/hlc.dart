/// Relógio lógico híbrido (Hybrid Logical Clock).
///
/// Ordenar as operações do inventário só pelo relógio de parede não funciona:
/// celulares têm relógios desalinhados, e um aparelho atrasado gravaria
/// operações que parecem anteriores a outras que ele já conhecia. Ordenar só
/// por contador lógico também não serve: o usuário precisa ver *quando* a
/// leitura aconteceu.
///
/// O HLC resolve os dois: acompanha o relógio de parede quando ele avança e
/// cai no contador lógico quando não avança, preservando a ordem causal sem
/// perder o sentido humano do horário.
library;

/// Distância máxima aceita entre o relógio local e o de um par.
///
/// Se um aparelho chegar com o relógio muito adiantado, aceitar o valor
/// arrastaria o relógio de todos os outros para o futuro e nunca mais voltaria.
/// Rejeitar é melhor que corromper a ordenação de todo o inventário.
const Duration deslocamentoMaximoRelogio = Duration(minutes: 5);

class RelogioForaDeSincronia implements Exception {
  final Hlc recebido;
  final int agoraLocal;

  RelogioForaDeSincronia(this.recebido, this.agoraLocal);

  @override
  String toString() {
    final diferenca = Duration(milliseconds: recebido.millis - agoraLocal);
    return 'Relógio do aparelho ${recebido.nodeId} está '
        '${diferenca.inMinutes} min adiantado em relação a este. '
        'Ajuste a data e a hora dos aparelhos antes de sincronizar.';
  }
}

class Hlc implements Comparable<Hlc> {
  /// Componente de relógio de parede, em milissegundos desde a época.
  final int millis;

  /// Desempate lógico dentro do mesmo milissegundo.
  final int counter;

  /// Identificador do dispositivo que gerou a operação. Também é o desempate
  /// final, o que torna a ordem total e idêntica em todas as réplicas.
  final String nodeId;

  const Hlc(this.millis, this.counter, this.nodeId);

  /// Primeiro relógio de um dispositivo que ainda não gerou nenhuma operação.
  Hlc.zero(this.nodeId) : millis = 0, counter = 0;

  /// Gera o relógio de uma nova operação local.
  ///
  /// Quando o relógio de parede avançou desde a última operação, o contador
  /// volta a zero. Quando não avançou — o caso comum, porque várias leituras
  /// cabem no mesmo milissegundo — o contador incrementa, garantindo que duas
  /// operações do mesmo aparelho nunca empatem.
  factory Hlc.enviar(Hlc ultimo, {int? agora}) {
    final fisico = agora ?? DateTime.now().millisecondsSinceEpoch;
    if (fisico > ultimo.millis) {
      return Hlc(fisico, 0, ultimo.nodeId);
    }
    return Hlc(ultimo.millis, ultimo.counter + 1, ultimo.nodeId);
  }

  /// Avança o relógio local ao receber uma operação de outro aparelho.
  ///
  /// É isto que faz a ordem causal se propagar: depois de receber uma operação
  /// remota, toda operação local nova é necessariamente posterior a ela, mesmo
  /// que o relógio de parede deste aparelho esteja atrasado.
  static Hlc receber(Hlc local, Hlc remoto, {int? agora}) {
    final fisico = agora ?? DateTime.now().millisecondsSinceEpoch;

    if (remoto.millis - fisico > deslocamentoMaximoRelogio.inMilliseconds) {
      throw RelogioForaDeSincronia(remoto, fisico);
    }

    final millis = [fisico, local.millis, remoto.millis].reduce((a, b) => a > b ? a : b);

    final int counter;
    if (millis == local.millis && millis == remoto.millis) {
      counter = (local.counter > remoto.counter ? local.counter : remoto.counter) + 1;
    } else if (millis == local.millis) {
      counter = local.counter + 1;
    } else if (millis == remoto.millis) {
      counter = remoto.counter + 1;
    } else {
      counter = 0;
    }

    return Hlc(millis, counter, local.nodeId);
  }

  DateTime get momento => DateTime.fromMillisecondsSinceEpoch(millis);

  /// Serialização ordenável como texto: comparar duas strings dá o mesmo
  /// resultado que comparar dois HLC. Permite ordenar e filtrar em SQL, sem
  /// decodificar nada.
  ///
  /// 15 dígitos de milissegundos cobrem datas até o ano 33658.
  String codificar() =>
      '${millis.toString().padLeft(15, '0')}-'
      '${counter.toRadixString(16).padLeft(4, '0')}-'
      '$nodeId';

  static Hlc decodificar(String texto) {
    final corte1 = texto.indexOf('-');
    final corte2 = texto.indexOf('-', corte1 + 1);
    if (corte1 < 0 || corte2 < 0) {
      throw FormatException('HLC malformado', texto);
    }
    return Hlc(
      int.parse(texto.substring(0, corte1)),
      int.parse(texto.substring(corte1 + 1, corte2), radix: 16),
      texto.substring(corte2 + 1),
    );
  }

  @override
  int compareTo(Hlc outro) {
    if (millis != outro.millis) return millis.compareTo(outro.millis);
    if (counter != outro.counter) return counter.compareTo(outro.counter);
    return nodeId.compareTo(outro.nodeId);
  }

  bool operator >(Hlc outro) => compareTo(outro) > 0;
  bool operator <(Hlc outro) => compareTo(outro) < 0;

  @override
  bool operator ==(Object outro) =>
      outro is Hlc &&
      millis == outro.millis &&
      counter == outro.counter &&
      nodeId == outro.nodeId;

  @override
  int get hashCode => Object.hash(millis, counter, nodeId);

  @override
  String toString() => codificar();
}
