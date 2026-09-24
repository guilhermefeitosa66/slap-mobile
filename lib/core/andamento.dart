import 'formato.dart';

/// O andamento de uma espera longa.
///
/// As três esperas demoradas do aplicativo — importar a planilha, entrar num
/// inventário pela rede e sincronizar — fazem a mesma pergunta a quem está
/// com o celular na mão: falta muito? A resposta tem a mesma forma nas três,
/// e por isso a mesma peça: o que está acontecendo, quanto já foi e de
/// quanto.
///
/// Sem número para dar, [fracao] é nula e a barra fica indeterminada. Isso é
/// honesto: procurar aparelhos na rede não tem fim previsível, e inventar uma
/// fração seria pior que admitir que não se sabe.
class Andamento {
  /// O que está acontecendo, numa frase: "Lendo planilha.xlsx…".
  final String etapa;

  /// Quanto já foi feito e de quanto, quando se sabe.
  final int? feitos;
  final int? total;

  /// O que está sendo contado, no plural: "patrimônios gravados".
  final String? unidade;

  /// Texto pronto, para o que não se conta em unidades inteiras — bytes de um
  /// download, por exemplo. Tem precedência sobre [unidade].
  final String? detalhe;

  const Andamento(
    this.etapa, {
    this.feitos,
    this.total,
    this.unidade,
    this.detalhe,
  });

  /// Há progresso mensurável.
  bool get medido => feitos != null && total != null && total! > 0;

  /// De 0 a 1, ou nulo quando não há como saber.
  double? get fracao => medido ? (feitos! / total!).clamp(0.0, 1.0) : null;

  /// A segunda linha da barra: "4.312 de 10.010 linhas conferidas".
  String? get contagem {
    if (detalhe != null) return detalhe;
    if (!medido || unidade == null) return null;
    return '${formatarInteiro(feitos!)} de ${formatarInteiro(total!)} '
        '$unidade';
  }

  Andamento comEtapa(String outra) => Andamento(
    outra,
    feitos: feitos,
    total: total,
    unidade: unidade,
    detalhe: detalhe,
  );
}
