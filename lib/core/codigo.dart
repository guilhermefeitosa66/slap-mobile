/// Normalização de tombo e código de barras.
///
/// A base real do IFPI tem sujeira que faz a busca do SLAP falhar. A planilha
/// exportada do SUAP traz códigos de barras **negativos** (`-19281`), e o SLAP
/// normaliza tudo com `to_i`, que preserva o sinal. Quem lê `19281` no leitor
/// nunca encontra o item gravado como `-19281` — o patrimônio existe na base e
/// mesmo assim aparece como "não localizado".
///
/// Aqui o valor original nunca é alterado: ele é exibido e exportado
/// exatamente como veio do SUAP. O que se normaliza é apenas a **chave de
/// busca**, guardada em coluna própria e indexada.
library;

/// Reduz um código à forma usada para busca.
///
/// Faz `-19281`, `19281`, `019281` e `19.281` casarem entre si, sem que
/// nenhum deles deixe de ser exibido como está no cadastro.
///
/// Devolve string vazia quando não sobra nada aproveitável, o que sinaliza ao
/// chamador que não vale a pena consultar o banco.
String chaveBusca(String? bruto) {
  if (bruto == null) return '';

  var texto = bruto.trim();
  if (texto.isEmpty) return '';

  // Células numéricas do Excel chegam como "19281.0". Remover o separador sem
  // tratar isso produziria "192810" — um código diferente e inexistente.
  final inteiroComDecimalZerado = RegExp(
    r'^([+-]?\d+)[.,]0+$',
  ).firstMatch(texto);
  if (inteiroComDecimalZerado != null) {
    texto = inteiroComDecimalZerado.group(1)!;
  }

  // Separadores de formatação e o sinal negativo espúrio da exportação do SUAP.
  texto = texto.toUpperCase().replaceAll(RegExp(r'[\s.,\-_/\\()]'), '');

  if (texto.isEmpty) return '';

  // Zeros à esquerda somem na chave de busca, mas continuam no valor gravado:
  // é assim que 000123 e 123 se encontram sem que o cadastro perca o formato.
  final semZeros = texto.replaceFirst(RegExp(r'^0+'), '');

  // Um código composto só de zeros é degenerado, mas não é vazio; preserva-se
  // um zero para que ele ainda seja distinguível de um campo em branco.
  return semZeros.isEmpty ? '0' : semZeros;
}

/// Verdadeiro quando os dois códigos se referem ao mesmo patrimônio, ignorando
/// diferenças de formatação.
bool mesmoCodigo(String? a, String? b) {
  final ca = chaveBusca(a);
  if (ca.isEmpty) return false;
  return ca == chaveBusca(b);
}

/// Normaliza o texto de um cabeçalho de planilha para comparar com sinônimos.
///
/// Tira acento, pontuação e caixa, de modo que `Nº Patrimonial`,
/// `N. PATRIMONIAL` e `no patrimonial` virem a mesma coisa.
String chaveCabecalho(String bruto) {
  const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const semAcento = 'aaaaaeeeeiiiiooooouuuucn';

  var texto = bruto.toLowerCase().trim();

  // A exportação do SUAP chama a coluna de ordem de `#`. Só de pontuação, ela
  // viraria chave vazia e ninguém a reivindicaria. Sozinha, `#` é o símbolo de
  // número — o mesmo que `Nº` —, e vira a mesma chave; no meio de outro
  // cabeçalho continua sendo pontuação descartada.
  if (texto == '#') return 'n';

  final buffer = StringBuffer();

  for (final ch in texto.split('')) {
    final i = comAcento.indexOf(ch);
    buffer.write(i >= 0 ? semAcento[i] : ch);
  }
  texto = buffer.toString();

  // "nº" e "n°" aparecem muito em cabeçalho do SUAP; viram "n".
  texto = texto.replaceAll(RegExp(r'[º°ªᵒ]'), '');

  return texto.replaceAll(RegExp(r'[^a-z0-9]'), '');
}
