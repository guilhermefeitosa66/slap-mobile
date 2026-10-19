/// Normalização de tombo e código de barras.
///
/// No SUAP os dois números são inteiros únicos e **com sinal**, ligados por
/// uma regra fixa (`suap/patrimonio/models.py`,
/// `EntradaPermanente._create_inventario_on_save_ifpi`):
///
///     tombo = numero + 42535
///
/// O bem migrado do sistema anterior tem a plaqueta antiga, com tombo até
/// 42535, e por isso um `numero` zero ou negativo: a plaqueta 23254 é o bem
/// de número `-19281`. O bem cadastrado no SUAP tem `numero` positivo. Assim,
/// `-19281` e `19281` são **dois bens diferentes** — o primeiro tem tombo
/// 23254; o segundo, tombo 61816. Tratar o sinal como sujeira de formatação,
/// como fazia esta normalização até a versão 1.2.4, fazia a leitura de um
/// registrar o outro.
///
/// O valor original nunca é alterado: ele é exibido e exportado exatamente
/// como veio do SUAP. O que se normaliza é apenas a **chave de busca**,
/// guardada em coluna própria e indexada.
library;

/// Diferença fixa entre tombo e número no SUAP: `tombo = numero + 42535`.
const int ajustePlaquetaAntiga = 42535;

/// Reduz um código à forma usada para busca.
///
/// Faz `19281`, `019281`, `19.281` e `19281.0` casarem entre si, e `-19281`
/// com `-019281`, sem que nenhum deles deixe de ser exibido como está no
/// cadastro. O sinal negativo **fica** na chave: no SUAP ele separa a plaqueta
/// antiga do bem novo com os mesmos dígitos.
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

  // O sinal só conta no começo, antes de qualquer dígito. Um hífen no meio
  // ("12-345") é formatação, como o ponto e o espaço.
  final negativo = RegExp(r'^-\s*\d').hasMatch(texto);
  if (negativo || texto.startsWith('+')) texto = texto.substring(1);

  texto = texto.toUpperCase().replaceAll(RegExp(r'[\s.,\-_/\\()+]'), '');

  if (texto.isEmpty) return '';

  // Zeros à esquerda somem na chave de busca, mas continuam no valor gravado:
  // é assim que 000123 e 123 se encontram sem que o cadastro perca o formato.
  final semZeros = texto.replaceFirst(RegExp(r'^0+'), '');

  // Um código composto só de zeros é degenerado, mas não é vazio; preserva-se
  // um zero para que ele ainda seja distinguível de um campo em branco. Zero
  // não tem sinal.
  if (semZeros.isEmpty) return '0';
  return negativo ? '-$semZeros' : semZeros;
}

/// Tombo que o SUAP atribui ao bem de [numero], pela regra
/// `tombo = numero + 42535`. `null` quando [numero] não é um inteiro.
String? tomboPeloNumero(String? numero) {
  final n = int.tryParse(chaveBusca(numero));
  return n == null ? null : '${n + ajustePlaquetaAntiga}';
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

  // `#` é o símbolo de número, o mesmo que `Nº`: a exportação do SUAP chama
  // assim a coluna de numeração das linhas. Só de pontuação, ela viraria chave
  // vazia; virando `n`, ela é uma coluna como as outras na tela de conferência
  // — nenhum campo a reivindica, e é isso mesmo.
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
