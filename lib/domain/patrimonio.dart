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

  final String? ordem;

  /// Número de tombo, como veio do SUAP. Sempre texto: zeros à esquerda são
  /// significativos e um inteiro os perderia.
  final String tombo;

  /// Código de barras. Campo **independente** do tombo: em bens antigos os
  /// dois divergem, e a base real tem códigos negativos.
  final String? codigoBarras;

  /// Elemento de despesa. Usado para excluir categorias do inventário.
  final String? ed;

  final String? descricao;
  final String? responsavelOriginal;
  final String? salaOriginal;
  final String? valor;

  /// Estado e situação de origem, quando a planilha os traz.
  ///
  /// A exportação padrão do SUAP **não** traz esses campos — por isso o SLAP
  /// os grava mas nunca os compara com nada. Quando ausentes, o valor
  /// levantado é informação nova, não divergência.
  final EstadoConservacao? conservacaoOriginal;
  final SituacaoUso? situacaoOriginal;

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
    this.ordem,
    this.codigoBarras,
    this.ed,
    this.descricao,
    this.responsavelOriginal,
    this.salaOriginal,
    this.valor,
    this.conservacaoOriginal,
    this.situacaoOriginal,
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

  /// Item que precisa de providência independentemente de haver valor anterior
  /// para comparar: bem em mau estado ou inservível.
  bool get exigeAtencao =>
      (conservacao?.exigeAtencao ?? false) || (situacao?.exigeAtencao ?? false);

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
      ordem: ordem,
      codigoBarras: codigoBarras,
      ed: ed,
      descricao: descricao,
      responsavelOriginal: responsavelOriginal,
      salaOriginal: salaOriginal,
      valor: valor,
      conservacaoOriginal: conservacaoOriginal,
      situacaoOriginal: situacaoOriginal,
      ignorado: ignorado ?? this.ignorado,
      verificado: verificado ?? this.verificado,
      salaAtual: salaAtual ?? this.salaAtual,
      responsavelAtual: responsavelAtual ?? this.responsavelAtual,
      conservacao: conservacao ?? this.conservacao,
      situacao: situacao ?? this.situacao,
      verificadoEm: verificadoEm ?? this.verificadoEm,
      verificadoPor: verificadoPor ?? this.verificadoPor,
      verificadoPorMatricula: verificadoPorMatricula ?? this.verificadoPorMatricula,
      verificadoPorDispositivo:
          verificadoPorDispositivo ?? this.verificadoPorDispositivo,
    );
  }
}
