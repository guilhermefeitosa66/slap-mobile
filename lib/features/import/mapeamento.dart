import '../../core/codigo.dart';

/// Campo do patrimônio que uma coluna da planilha alimenta.
enum CampoImportacao {
  tombo('Tombo', obrigatorio: true),
  codigoBarras('Código de barras'),
  descricao('Descrição'),
  ed('Elemento de despesa'),
  responsavel('Responsável'),
  sala('Sala'),
  ordem('Ordem'),
  valor('Valor'),
  conservacao('Estado de conservação'),
  situacao('Situação de uso');

  final String rotulo;

  /// Sem tombo não há como identificar o bem, então a importação não prossegue.
  /// Todo o resto é opcional.
  final bool obrigatorio;

  const CampoImportacao(this.rotulo, {this.obrigatorio = false});
}

/// Nomes de cabeçalho reconhecidos para cada campo, já normalizados por
/// [chaveCabecalho] — sem acento, sem caixa, sem pontuação.
///
/// A lista é generosa de propósito. O SLAP identifica coluna por posição, e
/// qualquer mudança na exportação do SUAP quebra a importação em silêncio,
/// jogando dado no campo errado. Reconhecer pelo nome, com sinônimos, sobrevive
/// a versões diferentes da planilha.
const Map<CampoImportacao, List<String>> sinonimos = {
  CampoImportacao.tombo: [
    'tombo', 'notombo', 'numerodetombo', 'numerotombo', 'ntombo',
    'patrimonio', 'npatrimonio', 'nopatrimonio', 'numerodepatrimonio',
    'npatrimonial', 'nopatrimonial', 'numeropatrimonial',
    'plaqueta', 'chapa', 'numerodechapa', 'bempatrimonial',
  ],
  CampoImportacao.codigoBarras: [
    'codbarras', 'codbarra', 'codigodebarras', 'codigobarras', 'codigobarra',
    'cbarra', 'cbarras', 'barras', 'barcode', 'ean', 'codigodebarra',
  ],
  CampoImportacao.descricao: [
    'descricao', 'descricaodobem', 'descricaodomaterial', 'denominacao',
    'especificacao', 'material', 'bem', 'produto', 'nomedobem', 'discriminacao',
  ],
  CampoImportacao.ed: [
    'ed', 'elementodedespesa', 'elementodespesa', 'elemento',
    'naturezadedespesa', 'naturezadespesa', 'nd', 'contacontabil', 'conta',
    'subelemento', 'categoria',
  ],
  CampoImportacao.responsavel: [
    'responsavel', 'responsavelatual', 'responsavelpelacarga', 'detentor',
    'carga', 'cargaatual', 'responsavelpelobem', 'usuario', 'servidor',
  ],
  CampoImportacao.sala: [
    'sala', 'localizacao', 'local', 'ambiente', 'setor', 'dependencia',
    'salalocal', 'localizacaoatual', 'localdoitem', 'unidade', 'lotacao',
  ],
  CampoImportacao.ordem: [
    'ordem', 'ord', 'sequencia', 'seq', 'indice', 'numero', 'n',
  ],
  CampoImportacao.valor: [
    'valor', 'valoraquisicao', 'valordeaquisicao', 'valoratual',
    'valorliquido', 'valorcontabil', 'vlr', 'preco', 'custo',
  ],
  CampoImportacao.conservacao: [
    'estadodeconservacao', 'estadoconservacao', 'conservacao', 'estado',
    'estadodobem', 'estadofisico',
  ],
  CampoImportacao.situacao: [
    'situacaodeuso', 'situacaouso', 'situacao', 'uso', 'statusdeuso', 'status',
  ],
};

/// Uma coluna candidata da planilha.
class ColunaDetectada {
  final int indice;
  final String cabecalho;

  /// Primeiras células da coluna, mostradas ao usuário para conferir se o
  /// reconhecimento fez sentido.
  final List<String> amostra;

  const ColunaDetectada({
    required this.indice,
    required this.cabecalho,
    this.amostra = const [],
  });
}

/// De qual coluna vem cada campo.
class Mapeamento {
  /// Campo → índice da coluna. Campo ausente significa "não importar".
  final Map<CampoImportacao, int> colunas;

  /// Linha em que o cabeçalho foi encontrado.
  final int linhaCabecalho;

  final List<ColunaDetectada> disponiveis;

  const Mapeamento({
    required this.colunas,
    required this.linhaCabecalho,
    this.disponiveis = const [],
  });

  bool get valido => CampoImportacao.values
      .where((c) => c.obrigatorio)
      .every(colunas.containsKey);

  List<CampoImportacao> get faltando => CampoImportacao.values
      .where((c) => c.obrigatorio && !colunas.containsKey(c))
      .toList();

  int? colunaDe(CampoImportacao campo) => colunas[campo];

  /// Qual campo uma coluna alimenta, se algum.
  CampoImportacao? campoDaColuna(int indice) {
    for (final e in colunas.entries) {
      if (e.value == indice) return e.key;
    }
    return null;
  }

  Mapeamento definir(CampoImportacao campo, int? indice) {
    final novo = {...colunas};
    novo.remove(campo);
    // Uma coluna só pode alimentar um campo: atribuí-la a outro a libera do
    // anterior, para que nunca haja dois campos lendo a mesma coluna.
    novo.removeWhere((_, v) => v == indice);
    if (indice != null) novo[campo] = indice;

    return Mapeamento(
      colunas: novo,
      linhaCabecalho: linhaCabecalho,
      disponiveis: disponiveis,
    );
  }
}

/// Reconhece as colunas de uma planilha pelo nome do cabeçalho.
///
/// A ordem das colunas é irrelevante. Quando o reconhecimento não for
/// possível, o campo fica sem coluna e o usuário completa à mão — a tela de
/// confirmação aparece sempre, mesmo quando tudo foi reconhecido, porque um
/// mapeamento errado aceito em silêncio corrompe o inventário inteiro.
Mapeamento detectarMapeamento(List<List<String?>> linhas, {int procurarAte = 15}) {
  final limite = linhas.length < procurarAte ? linhas.length : procurarAte;

  var melhorLinha = 0;
  var melhorPontuacao = -1;
  Map<CampoImportacao, int> melhorMapa = {};

  for (var i = 0; i < limite; i++) {
    final candidato = _mapearLinha(linhas[i]);
    // Uma linha só é cabeçalho se identificar o tombo: exportações do SUAP
    // costumam trazer linhas de título antes da tabela, e elas casariam com
    // um ou outro sinônimo solto.
    final pontuacao = candidato.containsKey(CampoImportacao.tombo)
        ? candidato.length + 10
        : candidato.length;

    if (pontuacao > melhorPontuacao) {
      melhorPontuacao = pontuacao;
      melhorLinha = i;
      melhorMapa = candidato;
    }
  }

  return Mapeamento(
    colunas: melhorMapa,
    linhaCabecalho: melhorLinha,
    disponiveis: _colunasDe(linhas, melhorLinha),
  );
}

/// Atribui colunas a campos pela melhor correspondência, sem repetir coluna.
Map<CampoImportacao, int> _mapearLinha(List<String?> cabecalho) {
  final candidatos = <({CampoImportacao campo, int coluna, int pontos})>[];

  for (var coluna = 0; coluna < cabecalho.length; coluna++) {
    final chave = chaveCabecalho(cabecalho[coluna] ?? '');
    if (chave.isEmpty) continue;

    for (final entrada in sinonimos.entries) {
      final pontos = _pontuar(chave, entrada.value);
      if (pontos > 0) {
        candidatos.add((campo: entrada.key, coluna: coluna, pontos: pontos));
      }
    }
  }

  // Do mais confiante para o menos: assim "COD. BARRAS" fica com código de
  // barras antes que "CÓDIGO" solto tente reivindicar a mesma coluna.
  candidatos.sort((a, b) => b.pontos.compareTo(a.pontos));

  final mapa = <CampoImportacao, int>{};
  final colunasUsadas = <int>{};

  for (final c in candidatos) {
    if (mapa.containsKey(c.campo) || colunasUsadas.contains(c.coluna)) continue;
    mapa[c.campo] = c.coluna;
    colunasUsadas.add(c.coluna);
  }

  return mapa;
}

int _pontuar(String chave, List<String> sinonimosDoCampo) {
  for (final s in sinonimosDoCampo) {
    if (chave == s) return 100;
  }
  for (final s in sinonimosDoCampo) {
    // Sinônimos muito curtos ("n", "ed") casariam com quase tudo por
    // substring; só valem em correspondência exata.
    if (s.length >= 4 && chave.contains(s)) return 50;
  }
  return 0;
}

List<ColunaDetectada> _colunasDe(List<List<String?>> linhas, int linhaCabecalho) {
  if (linhas.isEmpty) return const [];

  final cabecalho = linhas[linhaCabecalho];
  return [
    for (var i = 0; i < cabecalho.length; i++)
      ColunaDetectada(
        indice: i,
        cabecalho: (cabecalho[i] ?? '').trim().isEmpty
            ? 'Coluna ${i + 1}'
            : cabecalho[i]!.trim(),
        amostra: [
          for (var l = linhaCabecalho + 1;
              l < linhas.length && l <= linhaCabecalho + 3;
              l++)
            if (i < linhas[l].length && (linhas[l][i] ?? '').trim().isNotEmpty)
              linhas[l][i]!.trim(),
        ],
      ),
  ];
}
