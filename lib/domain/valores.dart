/// Valores de domínio do inventário.
///
/// Os literais são exatamente os do SLAP (`app/views/items/check.html.erb`),
/// e não os que a especificação inicial supunha. O levantamento é a mesma
/// operação de sempre: mudar o vocabulário agora obrigaria a comissão a
/// reaprender o que já sabe, e faria os relatórios deixarem de casar com os
/// inventários anteriores.
///
/// Em particular: "inservível" é **situação de uso**, não estado de
/// conservação — a especificação havia trocado os dois.
library;

/// Estado físico do bem. Valores do SLAP: `bom`, `regular`, `ruim`.
enum EstadoConservacao {
  bom('bom', 'Bom'),
  regular('regular', 'Regular'),
  ruim('ruim', 'Ruim');

  /// Valor gravado no banco e exportado nos relatórios. Idêntico ao do SLAP,
  /// para que as planilhas continuem comparáveis entre inventários.
  final String valor;

  /// Como aparece na interface.
  final String rotulo;

  const EstadoConservacao(this.valor, this.rotulo);

  static EstadoConservacao? de(String? valor) {
    if (valor == null) return null;
    for (final e in values) {
      if (e.valor == valor) return e;
    }
    return null;
  }

  /// Estado que exige providência mesmo sem valor anterior para comparar.
  bool get exigeAtencao => this == ruim;
}

/// Uso corrente do bem. Valores do SLAP: `ativo`, `ocioso`, `inserv.`.
enum SituacaoUso {
  ativo('ativo', 'Ativo'),
  ocioso('ocioso', 'Ocioso'),
  // O ponto final faz parte do valor no SLAP; mantido para não quebrar a
  // comparação com os dados dos inventários anteriores.
  inservivel('inserv.', 'Inservível');

  final String valor;
  final String rotulo;

  const SituacaoUso(this.valor, this.rotulo);

  static SituacaoUso? de(String? valor) {
    if (valor == null) return null;
    for (final s in values) {
      if (s.valor == valor) return s;
    }
    return null;
  }

  bool get exigeAtencao => this == inservivel;
}

/// Reduz um texto livre à forma usada para comparação.
///
/// Sala e responsável são texto digitado. Sem isto, `Coordenação de TI`,
/// `COORDENACAO DE TI` e `Coordenação de TI ` apareceriam como três
/// transferências patrimoniais distintas, enchendo o relatório de divergências
/// falsas que a comissão teria de conferir uma a uma.
///
/// O valor comparável existe só para decidir se houve mudança; o valor exibido
/// e exportado continua sendo o que foi digitado.
String formaComparavel(String? texto) {
  if (texto == null) return '';

  const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const semAcento = 'aaaaaeeeeiiiiooooouuuucn';

  final buffer = StringBuffer();
  for (final ch in texto.toLowerCase().split('')) {
    final i = comAcento.indexOf(ch);
    buffer.write(i >= 0 ? semAcento[i] : ch);
  }

  return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Verdadeiro quando dois textos representam o mesmo valor, ignorando caixa,
/// acento e espaço sobrando.
bool mesmoTexto(String? a, String? b) => formaComparavel(a) == formaComparavel(b);
