import 'valores.dart';

/// Um bem patrimonial dentro de um inventário.
///
/// A regra que organiza a classe: **o que veio do SUAP e o que foi encontrado
/// no levantamento nunca se misturam.** No SLAP os dois convivem na mesma
/// linha, distinguidos só por convenção de nome (`sala` vs `sala_atual`), e o
/// dado original é irrecuperável depois de sobrescrito. Aqui os campos
/// `Original` são imutáveis após a importação, e o levantamento só escreve nos
/// campos correspondentes de levantamento.
class Patrimonio {
  final String id;
  final String inventarioId;

  // ---------------------------------------------------------------- SUAP ---
  // Imutáveis após a importação.

  /// Número de tombo, como veio do SUAP. Sempre texto: zeros à esquerda são
  /// significativos e um inteiro os perderia.
  final String tombo;

  /// Código de barras — o `NUMERO` do SUAP. No SUAP, `tombo = numero +
  /// 42535`; nos bens de plaqueta antiga o número é negativo, e o sinal faz
  /// parte dele (ver `chaveBusca`).
  final String? codigoBarras;

  /// Elemento de despesa. Usado para excluir categorias do inventário.
  final String? ed;

  final String? descricao;
  final String? responsavelOriginal;
  final String? salaOriginal;
  final String? valor;

  /// Estado de conservação registrado no SUAP, quando a planilha o traz.
  ///
  /// Mesmo vocabulário do levantamento, por isso comparável: é a base da
  /// divergência de estado. Situação de uso não tem versão original — o SUAP
  /// não tem esse campo.
  final EstadoConservacao? conservacaoOriginal;

  /// Item cujo ED foi excluído do inventário. Fica fora dos relatórios e fora
  /// do denominador do progresso — não é pendência de ninguém.
  final bool ignorado;

  // --------------------------------------------------------- Levantamento ---

  final bool verificado;
  final String? salaAtual;
  final String? responsavelAtual;
  final EstadoConservacao? conservacao;
  final SituacaoUso? situacao;
  final DateTime? verificadoEm;
  final String? verificadoPor;
  final String? verificadoPorMatricula;
  final String? verificadoPorDispositivo;

  const Patrimonio({
    required this.id,
    required this.inventarioId,
    required this.tombo,
    this.codigoBarras,
    this.ed,
    this.descricao,
    this.responsavelOriginal,
    this.salaOriginal,
    this.valor,
    this.conservacaoOriginal,
    this.ignorado = false,
    this.verificado = false,
    this.salaAtual,
    this.responsavelAtual,
    this.conservacao,
    this.situacao,
    this.verificadoEm,
    this.verificadoPor,
    this.verificadoPorMatricula,
    this.verificadoPorDispositivo,
  });

  /// Sala que vale hoje: a encontrada, ou a do SUAP se nada foi alterado.
  String? get salaEfetiva => salaAtual ?? salaOriginal;

  /// Responsável que vale hoje.
  ///
  /// Reproduz a regra do `before_save` do SLAP: não informar responsável novo
  /// significa manter o original, não esvaziar o campo.
  String? get responsavelEfetivo => responsavelAtual ?? responsavelOriginal;

  /// Estado que vale hoje: o encontrado, ou o do SUAP se o levantamento o
  /// manteve. Mesma regra da sala e do responsável.
  EstadoConservacao? get conservacaoEfetiva =>
      conservacao ?? conservacaoOriginal;

  /// Item que precisa de providência independentemente de haver valor anterior
  /// para comparar: bem inservível. Num item encontrado vale o estado efetivo
  /// — o inservível que já era inservível no SUAP continua pedindo baixa.
  bool get exigeAtencao =>
      ((verificado ? conservacaoEfetiva : conservacao)?.exigeAtencao ??
          false) ||
      (situacao?.exigeAtencao ?? false);

  Patrimonio copyWith({
    bool? verificado,
    String? salaAtual,
    String? responsavelAtual,
    EstadoConservacao? conservacao,
    SituacaoUso? situacao,
    DateTime? verificadoEm,
    String? verificadoPor,
    String? verificadoPorMatricula,
    String? verificadoPorDispositivo,
    bool? ignorado,
  }) {
    return Patrimonio(
      id: id,
      inventarioId: inventarioId,
      tombo: tombo,
      codigoBarras: codigoBarras,
      ed: ed,
      descricao: descricao,
      responsavelOriginal: responsavelOriginal,
      salaOriginal: salaOriginal,
      valor: valor,
      conservacaoOriginal: conservacaoOriginal,
      ignorado: ignorado ?? this.ignorado,

      verificado: verificado ?? this.verificado,
      salaAtual: salaAtual ?? this.salaAtual,
      responsavelAtual: responsavelAtual ?? this.responsavelAtual,
      conservacao: conservacao ?? this.conservacao,
      situacao: situacao ?? this.situacao,
      verificadoEm: verificadoEm ?? this.verificadoEm,
      verificadoPor: verificadoPor ?? this.verificadoPor,
      verificadoPorMatricula:
          verificadoPorMatricula ?? this.verificadoPorMatricula,
      verificadoPorDispositivo:
          verificadoPorDispositivo ?? this.verificadoPorDispositivo,
    );
  }
}
