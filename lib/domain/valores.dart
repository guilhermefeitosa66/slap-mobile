/// Valores de domínio do inventário.
///
/// O estado de conservação usa o vocabulário do SUAP (`Inventario.
/// CHOICES_CONSERVACAO`, app `patrimonio`): é o SUAP que recebe o resultado do
/// inventário, e um valor que ele não conhece teria de ser traduzido à mão,
/// item por item, por quem atualiza o cadastro. A situação de uso continua a
/// do SLAP — o SUAP não tem esse campo.
library;

/// Estado de conservação do bem, nos valores do SUAP.
///
/// `valor` é exatamente o que o SUAP grava em `Inventario.estado_conservacao`
/// e o que a exportação de inventários dele devolve; `rotulo` é o texto que o
/// SUAP mostra. "Irreversível" é como o SUAP chama o bem irrecuperável.
///
/// `regular` e `ruim` são o vocabulário antigo do SLAP. Não se escolhem mais,
/// mas continuam legíveis: um inventário levantado antes desta versão, ou um
/// aparelho que ainda não foi atualizado, tem esses valores no log. Eles
/// aparecem marcados como antigos e pedem reclassificação nos relatórios, em
/// vez de sumirem ou virarem "bom" em silêncio.
enum EstadoConservacao {
  bom('bom', 'Bom'),
  ocioso('ocioso', 'Ocioso'),
  recuperavel('recuperavel', 'Recuperável'),
  antieconomico('antieconomico', 'Antieconômico'),
  irreversivel('irreversivel', 'Irreversível'),

  regular('regular', 'Regular (antigo)', legado: true),
  ruim('ruim', 'Ruim (antigo)', legado: true);

  /// Valor gravado no banco, no log e nos relatórios. Idêntico ao do SUAP.
  final String valor;

  /// Como aparece na interface.
  final String rotulo;

  /// Vocabulário anterior do SLAP: só leitura, sem equivalente no SUAP.
  final bool legado;

  const EstadoConservacao(this.valor, this.rotulo, {this.legado = false});

  /// Os que se podem escolher em campo — só os do SUAP.
  static List<EstadoConservacao> get selecionaveis =>
      values.where((e) => !e.legado).toList();

  static EstadoConservacao? de(String? valor) {
    if (valor == null) return null;
    for (final e in values) {
      if (e.valor == valor) return e;
    }
    return null;
  }

  /// Reconhece o estado escrito numa planilha.
  ///
  /// A exportação do SUAP traz o rótulo ("Antieconômico"), o banco dele traz o
  /// valor ("antieconomico"), e a do `inventario.ifpi.edu.br` traz o rótulo ou
  /// o código numérico que ela usa (1 Bom, 2 Recuperável, 3 Irrecuperável,
  /// 4 Ocioso, 5 Antieconômico). Célula vazia, "-" (o vazio da exportação do
  /// SUAP) e "Não aplicar" não têm estado. Vocabulário antigo e texto
  /// desconhecido também devolvem `null`: o estado do SUAP é a base de
  /// comparação, e uma base inventada geraria divergência falsa.
  static EstadoConservacao? daPlanilha(String? texto) {
    final chave = formaComparavel(texto).replaceAll(RegExp(r'[^a-z0-9]'), '');
    return switch (chave) {
      'bom' || '1' => bom,
      'recuperavel' || '2' => recuperavel,
      'irreversivel' || 'irrecuperavel' || '3' => irreversivel,
      'ocioso' || '4' => ocioso,
      'antieconomico' || '5' => antieconomico,
      _ => null,
    };
  }

  /// Bem inservível na classificação do Decreto 9.373/2018 — antieconômico
  /// ou irrecuperável —, e o `ruim` do vocabulário antigo. Exige providência
  /// mesmo quando é o mesmo estado que o SUAP já registra.
  bool get exigeAtencao =>
      this == antieconomico || this == irreversivel || this == ruim;
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
bool mesmoTexto(String? a, String? b) =>
    formaComparavel(a) == formaComparavel(b);
