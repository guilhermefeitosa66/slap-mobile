import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../../data/repos/inventarios.dart';
import '../../domain/divergencia.dart';
import '../../domain/patrimonio.dart';

/// Os relatórios que o inventário produz.
///
/// Os três primeiros são o resultado final do processo: o que está certo, o
/// que precisa ser alterado no SUAP e o que não foi encontrado. O SLAP só
/// produz uma planilha com tudo misturado e um HTML de transferências, de modo
/// que separar os três grupos fica a cargo de quem recebe o arquivo.
enum TipoRelatorio {
  ok(
    'Itens OK',
    'Encontrados e sem nenhuma alteração. Não precisam de atualização no SUAP.',
  ),
  divergencias(
    'Divergências',
    'Uma linha por campo alterado, com o valor do SUAP ao lado do encontrado.',
  ),
  naoLocalizados(
    'Não localizados',
    'Estavam na planilha e não foram encontrados durante o inventário.',
  ),
  completo(
    'Inventário completo',
    'Todos os itens, com a situação e a classificação de cada um.',
  );

  final String titulo;
  final String descricao;

  const TipoRelatorio(this.titulo, this.descricao);
}

/// Uma tabela pronta para exportar.
class Relatorio {
  final TipoRelatorio tipo;
  final String tituloInventario;
  final List<String> cabecalho;
  final List<List<String>> linhas;

  const Relatorio({
    required this.tipo,
    required this.tituloInventario,
    required this.cabecalho,
    required this.linhas,
  });

  bool get vazio => linhas.isEmpty;
  int get total => linhas.length;

  /// Nome de arquivo sugerido, sem extensão.
  String get nomeArquivo {
    final base = '${tituloInventario}_${tipo.name}'
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .toLowerCase();
    final agora = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    return '$base-$agora';
  }
}

class GeradorRelatorios {
  static final _data = DateFormat('dd/MM/yyyy HH:mm');

  static Relatorio gerar({
    required TipoRelatorio tipo,
    required Inventario inventario,
    required List<Patrimonio> patrimonios,
  }) {
    return switch (tipo) {
      TipoRelatorio.ok => _ok(inventario, patrimonios),
      TipoRelatorio.divergencias => _divergencias(inventario, patrimonios),
      TipoRelatorio.naoLocalizados => _naoLocalizados(inventario, patrimonios),
      TipoRelatorio.completo => _completo(inventario, patrimonios),
    };
  }

  static Relatorio _ok(Inventario inv, List<Patrimonio> itens) {
    final selecionados = itens
        .where((p) => classificar(p) == Classificacao.ok)
        .toList();

    return Relatorio(
      tipo: TipoRelatorio.ok,
      tituloInventario: inv.titulo,
      cabecalho: const [
        'Ordem',
        'Tombo',
        'Código de barras',
        'ED',
        'Descrição',
        'Sala',
        'Responsável',
        'Estado',
        'Situação',
        'Verificado por',
        'Verificado em',
      ],
      linhas: [
        for (final p in selecionados)
          [
            p.ordem ?? '',
            p.tombo,
            p.codigoBarras ?? '',
            p.ed ?? '',
            p.descricao ?? '',
            p.salaEfetiva ?? '',
            p.responsavelEfetivo ?? '',
            p.conservacao?.rotulo ?? '',
            p.situacao?.rotulo ?? '',
            p.verificadoPor ?? '',
            p.verificadoEm == null ? '' : _data.format(p.verificadoEm!),
          ],
      ],
    );
  }

  /// Formato longo: uma linha por campo divergente.
  ///
  /// É o que a comissão precisa para conferir item a item no SUAP — um
  /// formato largo, com todos os campos lado a lado, obrigaria a comparar
  /// coluna por coluna para descobrir o que mudou.
  static Relatorio _divergencias(Inventario inv, List<Patrimonio> itens) {
    final linhas = <List<String>>[];

    for (final p in itens) {
      for (final d in divergenciasDe(p)) {
        linhas.add([
          p.tombo,
          p.codigoBarras ?? '',
          p.descricao ?? '',
          d.campo.rotulo,
          d.valorSuap ?? '(vazio)',
          d.valorEncontrado ?? '(vazio)',
          p.exigeAtencao ? 'Sim' : '',
          p.verificadoPor ?? '',
          p.verificadoPorMatricula ?? '',
          p.verificadoEm == null ? '' : _data.format(p.verificadoEm!),
        ]);
      }
    }

    return Relatorio(
      tipo: TipoRelatorio.divergencias,
      tituloInventario: inv.titulo,
      cabecalho: const [
        'Tombo',
        'Código de barras',
        'Descrição',
        'Campo',
        'Valor no SUAP',
        'Valor encontrado',
        'Requer atenção',
        'Verificado por',
        'Matrícula',
        'Verificado em',
      ],
      linhas: linhas,
    );
  }

  static Relatorio _naoLocalizados(Inventario inv, List<Patrimonio> itens) {
    final selecionados = itens
        .where((p) => classificar(p) == Classificacao.naoLocalizado)
        .toList();

    return Relatorio(
      tipo: TipoRelatorio.naoLocalizados,
      tituloInventario: inv.titulo,
      cabecalho: const [
        'Ordem',
        'Tombo',
        'Código de barras',
        'ED',
        'Descrição',
        'Sala original',
        'Responsável original',
        'Valor',
      ],
      linhas: [
        for (final p in selecionados)
          [
            p.ordem ?? '',
            p.tombo,
            p.codigoBarras ?? '',
            p.ed ?? '',
            p.descricao ?? '',
            p.salaOriginal ?? '',
            p.responsavelOriginal ?? '',
            p.valor ?? '',
          ],
      ],
    );
  }

  static Relatorio _completo(Inventario inv, List<Patrimonio> itens) {
    return Relatorio(
      tipo: TipoRelatorio.completo,
      tituloInventario: inv.titulo,
      cabecalho: const [
        'Ordem',
        'Tombo',
        'Código de barras',
        'ED',
        'Descrição',
        'Valor',
        'Sala (SUAP)',
        'Sala encontrada',
        'Responsável (SUAP)',
        'Responsável encontrado',
        'Estado',
        'Situação',
        'Classificação',
        'Requer atenção',
        'Verificado por',
        'Matrícula',
        'Verificado em',
      ],
      linhas: [
        for (final p in itens)
          [
            p.ordem ?? '',
            p.tombo,
            p.codigoBarras ?? '',
            p.ed ?? '',
            p.descricao ?? '',
            p.valor ?? '',
            p.salaOriginal ?? '',
            // Coluna vazia quando não mudou, para que a diferença salte aos
            // olhos. O export do SLAP funde os dois valores numa coluna só,
            // e o que mudou deixa de ser visível.
            p.salaAtual ?? '',
            p.responsavelOriginal ?? '',
            p.responsavelAtual ?? '',
            p.conservacao?.rotulo ?? '',
            p.situacao?.rotulo ?? '',
            classificar(p).rotulo,
            p.exigeAtencao ? 'Sim' : '',
            p.verificadoPor ?? '',
            p.verificadoPorMatricula ?? '',
            p.verificadoEm == null ? '' : _data.format(p.verificadoEm!),
          ],
      ],
    );
  }

  // ------------------------------------------------------------- formatos ---

  static Uint8List paraXlsx(Relatorio relatorio) {
    final planilha = Excel.createExcel();
    final nomeAba = _nomeDeAba(relatorio.tipo.titulo);

    planilha.rename(planilha.getDefaultSheet()!, nomeAba);
    final aba = planilha.sheets[nomeAba]!;

    aba.appendRow([for (final c in relatorio.cabecalho) TextCellValue(c)]);
    for (final linha in relatorio.linhas) {
      aba.appendRow([for (final c in linha) TextCellValue(c)]);
    }

    final bytes = planilha.encode();
    if (bytes == null) {
      throw StateError('Não foi possível gerar a planilha.');
    }
    return Uint8List.fromList(bytes);
  }

  static Uint8List paraCsv(Relatorio relatorio) {
    // Ponto e vírgula e marcador de ordem de bytes: é o que faz o arquivo
    // abrir já com as colunas separadas no Excel em português, sem passar
    // pelo assistente de importação.
    const codificador = CsvEncoder(fieldDelimiter: ';', addBom: true);

    final texto = codificador.convert([
      relatorio.cabecalho,
      ...relatorio.linhas,
    ]);

    return Uint8List.fromList(utf8.encode(texto));
  }

  /// O Excel limita o nome da aba a 31 caracteres e proíbe `: \ / ? * [ ]`.
  static String _nomeDeAba(String titulo) {
    final limpo = titulo.replaceAll(RegExp(r'[:\\/?*\[\]]'), '-');
    return limpo.length <= 31 ? limpo : limpo.substring(0, 31);
  }
}
