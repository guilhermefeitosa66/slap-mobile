import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

/// Formatos aceitos na importação.
enum FormatoPlanilha { xlsx, csv }

class PlanilhaInvalida implements Exception {
  final String mensagem;
  PlanilhaInvalida(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Conteúdo bruto de uma planilha, já como texto.
class PlanilhaLida {
  final String nomeArquivo;
  final FormatoPlanilha formato;

  /// Nome da aba, quando houver.
  final String? aba;

  /// Abas disponíveis, para o caso de a planilha ter mais de uma.
  final List<String> abas;

  final List<List<String?>> linhas;

  const PlanilhaLida({
    required this.nomeArquivo,
    required this.formato,
    required this.linhas,
    this.aba,
    this.abas = const [],
  });

  int get totalLinhas => linhas.length;
}

/// Lê planilhas XLSX e CSV.
///
/// O `.xls` antigo — único formato que o SLAP aceita, através da gem
/// `spreadsheet` — ficou de fora: a especificação pede XLSX e CSV, e manter um
/// leitor do formato binário do Excel 97 custaria mais do que orientar a
/// conversão. Arquivos `.xls` são rejeitados com mensagem explícita, em vez de
/// falharem de um jeito obscuro.
class LeitorPlanilha {
  static PlanilhaLida ler({
    required String nomeArquivo,
    required Uint8List bytes,
    String? aba,
  }) {
    final nome = nomeArquivo.toLowerCase();

    if (nome.endsWith('.xls') && !nome.endsWith('.xlsx')) {
      throw PlanilhaInvalida(
        'Arquivos .xls (Excel 97-2003) não são aceitos. '
        'Abra a planilha e salve como .xlsx ou .csv.',
      );
    }

    if (nome.endsWith('.csv') || nome.endsWith('.txt')) {
      return _lerCsv(nomeArquivo, bytes);
    }

    return _lerXlsx(nomeArquivo, bytes, aba);
  }

  // ------------------------------------------------------------------ XLSX ---

  static PlanilhaLida _lerXlsx(
    String nomeArquivo,
    Uint8List bytes,
    String? aba,
  ) {
    final Excel planilha;
    try {
      planilha = Excel.decodeBytes(bytes);
    } catch (e) {
      throw PlanilhaInvalida('Não foi possível abrir a planilha: $e');
    }

    final abas = planilha.tables.keys.toList();
    if (abas.isEmpty) throw PlanilhaInvalida('A planilha não tem nenhuma aba.');

    final escolhida = aba != null && planilha.tables.containsKey(aba)
        ? aba
        : abas.first;
    final tabela = planilha.tables[escolhida]!;

    final linhas = <List<String?>>[];
    for (final linha in tabela.rows) {
      linhas.add([for (final celula in linha) _textoDaCelula(celula?.value)]);
    }

    return PlanilhaLida(
      nomeArquivo: nomeArquivo,
      formato: FormatoPlanilha.xlsx,
      linhas: _semLinhasVazias(linhas),
      aba: escolhida,
      abas: abas,
    );
  }

  /// Converte uma célula em texto sem deformar códigos.
  ///
  /// O cuidado principal é com número inteiro guardado como ponto flutuante:
  /// o `toString()` de um `double` produz "19281.0", e um tombo com essa
  /// sujeira não casa com a leitura do código de barras.
  static String? _textoDaCelula(CellValue? valor) {
    if (valor == null) return null;

    return switch (valor) {
      TextCellValue() => valor.value.toString(),
      IntCellValue() => valor.value.toString(),
      DoubleCellValue() => _textoDoDecimal(valor.value),
      BoolCellValue() => valor.value ? 'sim' : 'não',
      DateCellValue() =>
        valor.asDateTimeLocal().toIso8601String().split('T').first,
      DateTimeCellValue() => valor.asDateTimeLocal().toIso8601String(),
      TimeCellValue() => valor.toString(),
      FormulaCellValue() => valor.formula,
    };
  }

  static String _textoDoDecimal(double valor) {
    if (valor.isNaN || valor.isInfinite) return '';
    // Inteiro disfarçado de decimal, que é como o Excel guarda tombos.
    if (valor == valor.roundToDouble() && valor.abs() < 1e15) {
      return valor.toStringAsFixed(0);
    }
    return valor.toString();
  }

  // ------------------------------------------------------------------- CSV ---

  static PlanilhaLida _lerCsv(String nomeArquivo, Uint8List bytes) {
    // `fieldDelimiter: null` deixa o separador ser detectado pela biblioteca,
    // o que importa aqui: o Excel em português grava com ponto e vírgula,
    // porque a vírgula já é o separador decimal.
    //
    // `dynamicTyping: false` é essencial — converter campos para número
    // transformaria o tombo "000123" em 123 e perderia os zeros à esquerda,
    // que é justamente um dos defeitos do SLAP.
    const decodificador = CsvDecoder(dynamicTyping: false);

    final linhas = decodificador
        .convert(_decodificar(bytes))
        .map((l) => [for (final c in l) c?.toString()])
        .toList();

    return PlanilhaLida(
      nomeArquivo: nomeArquivo,
      formato: FormatoPlanilha.csv,
      linhas: _semLinhasVazias(linhas),
    );
  }

  /// Decodifica o texto tentando UTF-8 e caindo para Latin-1.
  ///
  /// Exportações de sistemas públicos brasileiros frequentemente vêm em
  /// Windows-1252. Decodificar como UTF-8 à força transformaria "Coordenação"
  /// em lixo — ou lançaria exceção, dependendo do byte.
  ///
  /// O marcador de ordem de bytes que o Excel grava é removido pelo próprio
  /// decodificador de CSV.
  static String _decodificar(Uint8List bytes) {
    try {
      return const Utf8Decoder(allowMalformed: false).convert(bytes);
    } on FormatException {
      return const Latin1Decoder(allowInvalid: true).convert(bytes);
    }
  }

  // ----------------------------------------------------------------- comum ---

  /// Remove linhas totalmente vazias do fim.
  ///
  /// Planilhas costumam trazer centenas delas, e contá-las como patrimônios
  /// daria um inventário com milhares de itens em branco.
  static List<List<String?>> _semLinhasVazias(List<List<String?>> linhas) {
    var fim = linhas.length;
    while (fim > 0 && _vazia(linhas[fim - 1])) {
      fim--;
    }
    return linhas.sublist(0, fim);
  }

  static bool _vazia(List<String?> linha) =>
      linha.every((c) => c == null || c.trim().isEmpty);
}
