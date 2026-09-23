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

  const PreviaImportacao({
    required this.itens,
    required this.linhasExaminadas,
    required this.semTombo,
    required this.tombosDuplicados,
    required this.contagemPorEd,
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
  final int inseridos;

  /// Já estavam no inventário e foram preservados, com o levantamento intacto.
  final int preservados;

  final int ignoradosPorEd;

  const ResultadoImportacao({
    required this.inseridos,
    required this.preservados,
    required this.ignoradosPorEd,
  });
}

class Importador {
  /// Converte as linhas da planilha em patrimônios, sem gravar nada.
  static PreviaImportacao preparar(PlanilhaLida planilha, Mapeamento mapeamento) {
    final itens = <PatrimonioImportado>[];
    final vistos = <String>{};
    final duplicados = <String>[];
    final porEd = <String, int>{};
    var semTombo = 0;
    var examinadas = 0;

    for (var i = mapeamento.linhaCabecalho + 1; i < planilha.linhas.length; i++) {
      final linha = planilha.linhas[i];
      examinadas++;

      final tombo = _celula(linha, mapeamento.colunaDe(CampoImportacao.tombo));
      if (tombo == null || chaveBusca(tombo).isEmpty) {
        semTombo++;
        continue;
      }

      final chave = chaveBusca(tombo);
      if (!vistos.add(chave)) duplicados.add(tombo);

      final ed = _celula(linha, mapeamento.colunaDe(CampoImportacao.ed));
      porEd[ed ?? ''] = (porEd[ed ?? ''] ?? 0) + 1;

      itens.add(PatrimonioImportado(
        tombo: tombo,
        ordem: _celula(linha, mapeamento.colunaDe(CampoImportacao.ordem)),
        codigoBarras: _celula(linha, mapeamento.colunaDe(CampoImportacao.codigoBarras)),
        ed: ed,
        descricao: _celula(linha, mapeamento.colunaDe(CampoImportacao.descricao)),
        responsavel: _celula(linha, mapeamento.colunaDe(CampoImportacao.responsavel)),
        sala: _celula(linha, mapeamento.colunaDe(CampoImportacao.sala)),
        valor: _celula(linha, mapeamento.colunaDe(CampoImportacao.valor)),
        conservacao: _conservacao(
          _celula(linha, mapeamento.colunaDe(CampoImportacao.conservacao)),
        ),
        situacao: _situacao(
          _celula(linha, mapeamento.colunaDe(CampoImportacao.situacao)),
        ),
      ));
    }

    final ordenados = porEd.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return PreviaImportacao(
      itens: itens,
      linhasExaminadas: examinadas,
      semTombo: semTombo,
      tombosDuplicados: duplicados,
      contagemPorEd: {for (final e in ordenados) e.key: e.value},
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

    repositorio.inserirLote(inventarioId, novos);

    return ResultadoImportacao(
      inseridos: novos.length,
      preservados: preservados,
      ignoradosPorEd: ignorados,
    );
  }

  static String? _celula(List<String?> linha, int? coluna) {
    if (coluna == null || coluna >= linha.length) return null;
    final valor = linha[coluna]?.trim();
    return (valor == null || valor.isEmpty) ? null : valor;
  }

  /// Reconhece o estado de conservação escrito na planilha.
  ///
  /// Raro: a exportação padrão do SUAP não traz essa coluna. Quando traz, vira
  /// o valor de origem e passa a permitir divergência nesse campo.
  static EstadoConservacao? _conservacao(String? texto) {
    if (texto == null) return null;
    final chave = formaComparavel(texto);

    for (final e in EstadoConservacao.values) {
      if (chave == e.valor || chave == formaComparavel(e.rotulo)) return e;
    }
    if (chave.startsWith('b')) return EstadoConservacao.bom;
    if (chave.startsWith('reg')) return EstadoConservacao.regular;
    if (chave.startsWith('ru')) return EstadoConservacao.ruim;
    return null;
  }

  static SituacaoUso? _situacao(String? texto) {
    if (texto == null) return null;
    final chave = formaComparavel(texto);

    for (final s in SituacaoUso.values) {
      if (chave == s.valor || chave == formaComparavel(s.rotulo)) return s;
    }
    if (chave.startsWith('at') || chave.startsWith('emuso')) return SituacaoUso.ativo;
    if (chave.startsWith('oci')) return SituacaoUso.ocioso;
    if (chave.startsWith('ins')) return SituacaoUso.inservivel;
    return null;
  }
}
