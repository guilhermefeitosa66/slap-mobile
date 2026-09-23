// Gera docs/loja/planilha-demonstracao.xlsx: uma planilha no formato do SUAP,
// com dados fictícios, para quem revisa o aplicativo na loja (ou quer
// experimentar) ter o que importar.
//
//     dart run tool/gerar_planilha_demonstracao.dart
//
// test/features/planilha_demonstracao_test.dart confere que o arquivo
// publicado continua sendo importado inteiro.

import 'dart:io';

import 'package:excel/excel.dart';

const _salas = [
  'BIBLIOTECA',
  'LAB. INFORMÁTICA 1',
  'AUDITÓRIO',
  'COORDENAÇÃO DE CURSO',
  'SALA DOS PROFESSORES',
];

const _responsaveis = [
  'ANA SOUZA',
  'BRUNO CARVALHO',
  'CARLA MENDES',
  'DIEGO LIMA',
  'ELISA ROCHA',
];

// (ED, descrição, valor)
const _bens = [
  ('42', 'MESA DE REUNIÃO OVAL 8 LUGARES', 1890.00),
  ('42', 'CADEIRA FIXA ESTOFADA PRETA', 289.90),
  ('42', 'CADEIRA GIRATÓRIA COM BRAÇOS', 649.00),
  ('42', 'ARMÁRIO DE AÇO 2 PORTAS', 980.50),
  ('42', 'ESTANTE DE AÇO 6 PRATELEIRAS', 415.00),
  ('42', 'QUADRO BRANCO 120 X 90', 238.00),
  ('52', 'NOBREAK 1500VA', 1320.00),
  ('52', 'PROJETOR MULTIMÍDIA 3500 LUMENS', 2750.00),
  ('52', 'MICROCOMPUTADOR DESKTOP', 4180.00),
  ('52', 'MONITOR LED 24 POLEGADAS', 899.00),
  ('52', 'IMPRESSORA LASER MONOCROMÁTICA', 1540.00),
  ('52', 'ESTABILIZADOR ELETRÔNICO 1000VA', 310.00),
];

const _conservacao = ['bom', 'bom', 'bom', 'regular', 'ruim'];
const _situacao = ['ativo', 'ativo', 'ativo', 'ocioso', 'inserv.'];

void main() {
  final excel = Excel.createExcel();
  final aba = excel.sheets[excel.getDefaultSheet()!]!;

  aba.appendRow([
    for (final titulo in [
      'ORDEM',
      'COD. BARRAS',
      'TOMBO',
      'ED',
      'DESCRIÇÃO',
      'RESPONSAVEL ATUAL',
      'SALA ATUAL',
      'VALOR',
      'ESTADO DE CONSERVAÇÃO',
      'SITUAÇÃO DE USO',
    ])
      TextCellValue(titulo),
  ]);

  // Cinco salas, doze bens cada uma, com variação determinística: o conteúdo
  // sai igual a cada execução (os bytes não: o XLSX guarda a data de criação).
  var ordem = 0;
  for (var s = 0; s < _salas.length; s++) {
    for (var b = 0; b < _bens.length; b++) {
      ordem++;
      final (ed, descricao, valor) = _bens[b];
      final tombo = (23100 + ordem).toString().padLeft(6, '0');
      aba.appendRow([
        IntCellValue(ordem),
        TextCellValue(tombo),
        TextCellValue(tombo),
        TextCellValue(ed),
        TextCellValue(descricao),
        TextCellValue(_responsaveis[(s + b) % _responsaveis.length]),
        TextCellValue(_salas[s]),
        DoubleCellValue(valor),
        TextCellValue(_conservacao[(s * 3 + b) % _conservacao.length]),
        TextCellValue(_situacao[(s * 7 + b * 2) % _situacao.length]),
      ]);
    }
  }

  final destino = File('docs/loja/planilha-demonstracao.xlsx');
  destino.writeAsBytesSync(excel.encode()!);
  stdout.writeln('${destino.path}: $ordem patrimônios');
}
