import '../../core/codigo.dart';
import '../../data/repos/patrimonios.dart';
import '../../domain/valores.dart';
import 'leitor_planilha.dart';
import 'mapeamento.dart';

/// O que será importado, calculado antes de tocar no banco.
///
/// Serve para a tela de confirmação: o usuário vê quantos itens entram, quais
/// elementos de despesa existem e o que foi descartado, antes de decidir.
class PreviaImportacao {
  final List<PatrimonioImportado> itens;

  /// Linhas de dados examinadas, sem contar o cabeçalho.
  final int linhasExaminadas;

  /// Descartadas por não ter tombo. Normalmente são rodapés e linhas de total.
  final int semTombo;

  /// Tombos repetidos dentro do próprio arquivo.
  ///
  /// O SLAP importa todos e depois escolhe um com `.first` na hora da busca,
  /// sem avisar ninguém.
  final List<String> tombosDuplicados;

  /// Elementos de despesa presentes, com a contagem de cada um. Alimenta a
  /// escolha do que ignorar.
  final Map<String, int> contagemPorEd;

  /// Linhas sem tombo, mas com número, que receberam o tombo pela regra do
  /// SUAP (`tombo = numero + 42535`) em vez de serem descartadas.
  final int tombosPeloNumero;

  /// Tombos cuja linha traz um número que não segue a regra do SUAP
  /// (`tombo = numero + 42535`). Entram como vieram, mas a tela avisa: ou a
  /// planilha foi editada à mão, ou a coluna de tombo não é a do SUAP — e aí
  /// a busca pela plaqueta pode achar o bem errado.
  final List<String> foraDaRegraDoSuap;

  /// Células de estado de conservação preenchidas com algo que não é do
  /// vocabulário do SUAP. O item entra sem estado de origem.
  final int estadosNaoReconhecidos;

  const PreviaImportacao({
    required this.itens,
    required this.linhasExaminadas,
    required this.semTombo,
    required this.tombosDuplicados,
    required this.contagemPorEd,
    this.tombosPeloNumero = 0,
    this.foraDaRegraDoSuap = const [],
    this.estadosNaoReconhecidos = 0,
  });

  int get total => itens.length;

  /// Quantos itens entram, dados os EDs marcados para ignorar.
  int totalConsiderando(Set<String> edsExcluidos) {
    if (edsExcluidos.isEmpty) return itens.length;
    return itens.where((i) => !edsExcluidos.contains(i.ed ?? '')).length;
  }
}

/// O que a importação de fato fez.
class ResultadoImportacao {
  /// Linhas gravadas no aparelho, inclusive as de elemento de despesa
  /// excluído — elas ficam no banco, fora do inventário, para não sumirem do
  /// histórico.
  final int inseridos;

  /// Já estavam no inventário e foram preservados, com o levantamento intacto.
  final int preservados;

  /// Dos [inseridos], quantos ficaram fora do inventário por elemento de
  /// despesa.
  final int ignoradosPorEd;

  const ResultadoImportacao({
    required this.inseridos,
    required this.preservados,
    required this.ignoradosPorEd,
  });

  /// Quantos itens passam a contar no inventário.
  ///
  /// É este o número que quem importou espera ver, e o mesmo que a tela
  /// prometeu no passo anterior com "N entrarão no inventário". [inseridos]
  /// conta também os que foram deixados de fora, e dizê-lo como resultado
  /// contradiz a escolha que a pessoa acabou de fazer.
  int get entraram => inseridos - ignoradosPorEd;
}

class Importador {
  /// De quantas em quantas linhas a conferência informa o progresso. Mesmo
  /// critério da leitura e da gravação: avisar a cada linha custaria mais que
  /// conferir a linha.
  static const passoProgresso = 250;

  /// Converte as linhas da planilha em patrimônios, sem gravar nada.
  ///
  /// [aoProgredir] recebe quantas linhas de dados já foram conferidas e
  /// quantas são.
  static PreviaImportacao preparar(
    PlanilhaLida planilha,
    Mapeamento mapeamento, {
    void Function(int feitas, int total)? aoProgredir,
  }) {
    final itens = <PatrimonioImportado>[];
    final vistos = <String>{};
    final duplicados = <String>[];
    final porEd = <String, int>{};
    var semTombo = 0;
    var pelosNumeros = 0;
    final foraDaRegra = <String>[];
    var estadosDesconhecidos = 0;
    var examinadas = 0;
    final aConferir = planilha.linhas.length - mapeamento.linhaCabecalho - 1;

    for (
      var i = mapeamento.linhaCabecalho + 1;
      i < planilha.linhas.length;
      i++
    ) {
      final linha = planilha.linhas[i];
      examinadas++;
      if (aoProgredir != null && examinadas % passoProgresso == 0) {
        aoProgredir(examinadas, aConferir);
      }

      final codigoBarras = _celula(
        linha,
        mapeamento.colunaDe(CampoImportacao.codigoBarras),
      );
      var tombo = _celula(linha, mapeamento.colunaDe(CampoImportacao.tombo));
      if (tombo == null || chaveBusca(tombo).isEmpty) {
        // O SUAP deixa o tombo em branco em parte dos bens, e a exportação
        // dele escreve "-" no vazio. O número basta: o tombo é dado pela
        // regra fixa do próprio SUAP.
        tombo = tomboPeloNumero(codigoBarras);
        if (tombo == null) {
          semTombo++;
          continue;
        }
        pelosNumeros++;
      } else if (tomboPeloNumero(codigoBarras) case final esperado?
          when int.tryParse(chaveBusca(tombo)) != null &&
              esperado != chaveBusca(tombo)) {
        foraDaRegra.add(tombo);
      }

      final celulaEstado = _celula(
        linha,
        mapeamento.colunaDe(CampoImportacao.conservacao),
      );
      final conservacao = EstadoConservacao.daPlanilha(celulaEstado);
      if (conservacao == null && _estadoPreenchido(celulaEstado)) {
        estadosDesconhecidos++;
      }

      final chave = chaveBusca(tombo);
      if (!vistos.add(chave)) duplicados.add(tombo);

      final ed = _celula(linha, mapeamento.colunaDe(CampoImportacao.ed));
      porEd[ed ?? ''] = (porEd[ed ?? ''] ?? 0) + 1;

      itens.add(
        PatrimonioImportado(
          tombo: tombo,
          codigoBarras: codigoBarras,
          ed: ed,
          descricao: _celula(
            linha,
            mapeamento.colunaDe(CampoImportacao.descricao),
          ),
          responsavel: _celula(
            linha,
            mapeamento.colunaDe(CampoImportacao.responsavel),
          ),
          sala: _celula(linha, mapeamento.colunaDe(CampoImportacao.sala)),
          valor: _celula(linha, mapeamento.colunaDe(CampoImportacao.valor)),
          conservacao: conservacao,
        ),
      );
    }

    aoProgredir?.call(examinadas, aConferir);

    final ordenados = porEd.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return PreviaImportacao(
      itens: itens,
      linhasExaminadas: examinadas,
      semTombo: semTombo,
      tombosDuplicados: duplicados,
      contagemPorEd: {for (final e in ordenados) e.key: e.value},
      tombosPeloNumero: pelosNumeros,
      foraDaRegraDoSuap: foraDaRegra,
      estadosNaoReconhecidos: estadosDesconhecidos,
    );
  }

  /// Grava os patrimônios no inventário.
  ///
  /// **Reconcilia, não substitui.** Itens que já existem são preservados com
  /// todo o levantamento feito neles; só os novos entram. O SLAP faz
  /// `items.destroy_all` antes de importar, de modo que reimportar a planilha
  /// — para corrigir uma coluna, por exemplo — apaga o trabalho de dias sem
  /// nenhum aviso.
  static ResultadoImportacao aplicar({
    required RepositorioPatrimonios repositorio,
    required String inventarioId,
    required PreviaImportacao previa,
    Set<String> edsExcluidos = const {},
    void Function(int feitos, int total)? aoProgredir,
  }) {
    final existentes = repositorio.chavesExistentes(inventarioId);

    final novos = <PatrimonioImportado>[];
    var preservados = 0;
    var ignorados = 0;
    final chavesDoLote = <String>{};

    for (final item in previa.itens) {
      final chave = chaveBusca(item.tombo);

      if (existentes.contains(chave)) {
        preservados++;
        continue;
      }
      // Tombo repetido dentro do arquivo entra uma vez só.
      if (!chavesDoLote.add(chave)) continue;

      if (edsExcluidos.contains(item.ed ?? '')) ignorados++;

      novos.add(item);
    }

    repositorio.inserirLote(
      inventarioId,
      novos,
      aoProgredir: aoProgredir == null
          ? null
          : (feitos) => aoProgredir(feitos, novos.length),
    );

    return ResultadoImportacao(
      inseridos: novos.length,
      preservados: preservados,
      ignoradosPorEd: ignorados,
    );
  }

  /// Célula de estado com conteúdo de verdade. "-" é o vazio da exportação do
  /// SUAP, e "Não aplicar" é o estado vazio dele.
  static bool _estadoPreenchido(String? celula) {
    final t = formaComparavel(celula);
    return t.isNotEmpty && t != '-' && t != 'nao aplicar';
  }

  static String? _celula(List<String?> linha, int? coluna) {
    if (coluna == null || coluna >= linha.length) return null;
    final valor = linha[coluna]?.trim();
    return (valor == null || valor.isEmpty) ? null : valor;
  }
}
