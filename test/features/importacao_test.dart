import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/import/importador.dart';
import 'package:slap_mobile/features/import/leitor_planilha.dart';
import 'package:slap_mobile/features/import/mapeamento.dart';

/// Monta um XLSX em memória, para exercitar o caminho real de leitura.
Uint8List planilhaXlsx(List<List<String>> linhas) {
  final excel = Excel.createExcel();
  final aba = excel.sheets[excel.getDefaultSheet()!]!;
  for (final linha in linhas) {
    aba.appendRow([for (final c in linha) TextCellValue(c)]);
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  test('os campos seguem a ordem da planilha do SLAP', () {
    // A tela "Confira as colunas" percorre `CampoImportacao.values`. Quem
    // conferia a planilha no SLAP confere aqui na mesma sequência.
    expect(CampoImportacao.values.map((c) => c.rotulo).toList(), [
      'Código de barras',
      'Tombo',
      'Elemento de despesa',
      'Descrição',
      'Responsável',
      'Sala',
      'Valor',
    ]);
  });

  group('detecção de colunas', () {
    test('reconhece o cabeçalho do SLAP na ordem original', () {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'suap.xlsx',
        bytes: planilhaXlsx([
          [
            'ORDEM',
            'COD. BARRAS',
            'TOMBO',
            'ED',
            'DESCRIÇÃO',
            'RESPONSAVEL',
            'SALA',
            'VALOR',
          ],
          [
            '1',
            '-19281',
            '23254',
            '30',
            'ESTABILIZADOR',
            'Dann Luciano',
            'SRN-CTI',
            '58',
          ],
        ]),
      );

      final m = detectarMapeamento(planilha.linhas);

      expect(m.valido, isTrue);
      // `ORDEM` não alimenta campo nenhum: a numeração das linhas do
      // relatório de origem não diz nada sobre o bem.
      expect(m.campoDaColuna(0), isNull);
      expect(m.colunaDe(CampoImportacao.codigoBarras), 1);
      expect(m.colunaDe(CampoImportacao.tombo), 2);
      expect(m.colunaDe(CampoImportacao.ed), 3);
      expect(m.colunaDe(CampoImportacao.descricao), 4);
      expect(m.colunaDe(CampoImportacao.responsavel), 5);
      expect(m.colunaDe(CampoImportacao.sala), 6);
      expect(m.colunaDe(CampoImportacao.valor), 7);
    });

    test('reconhece o cabeçalho real da exportação do SUAP', () {
      // `#` é a numeração das linhas, que não se importa, e `NUMERO` é o
      // código de barras. `NUMERO NOTA FISCAL`
      // e `NÚMERO DE SÉRIE` contêm "numero" e não podem roubar a coluna;
      // `STATUS` e `ESTADO DE CONSERVAÇÃO` têm outro vocabulário e ficam de
      // fora.
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'suap-real.xlsx',
        bytes: planilhaXlsx([
          [
            '#',
            'NUMERO',
            'TOMBO',
            'STATUS',
            'ED',
            'DESCRICAO',
            'RÓTULOS',
            'CARGA ATUAL',
            'SETOR DO RESPONSÁVEL',
            'CAMPUS DA CARGA',
            'VALOR AQUISIÇÃO',
            'VALOR DEPRECIADO',
            'NUMERO NOTA FISCAL',
            'NÚMERO DE SÉRIE',
            'DATA DA ENTRADA',
            'DATA DA CARGA',
            'FORNECEDOR',
            'SALA',
            'ESTADO DE CONSERVAÇÃO',
          ],
          [
            '1',
            '-019281',
            '23254',
            'Ativo',
            '449052',
            'ESTABILIZADOR',
            '',
            'Dann Luciano',
            'CTI',
            'Picos',
            '58,00',
            '0,00',
            '1234',
            'SN-1',
            '01/02/2010',
            '01/02/2010',
            'FORNECEDOR LTDA',
            'SRN-CTI',
            'Bom',
          ],
        ]),
      );

      final m = detectarMapeamento(planilha.linhas);

      final esperado = {
        CampoImportacao.codigoBarras: 1,
        CampoImportacao.tombo: 2,
        CampoImportacao.ed: 4,
        CampoImportacao.descricao: 5,
        CampoImportacao.responsavel: 7,
        CampoImportacao.sala: 17,
        CampoImportacao.valor: 10,
      };
      expect(m.valido, isTrue);
      expect(m.colunas, esperado);
      for (var coluna = 0; coluna < 19; coluna++) {
        if (esperado.containsValue(coluna)) continue;
        expect(
          m.campoDaColuna(coluna),
          isNull,
          reason: 'coluna ${coluna + 1} não alimenta campo nenhum',
        );
      }
      expect(m.disponiveis[0].cabecalho, '#');

      final previa = Importador.preparar(planilha, m);
      expect(previa.itens.single.codigoBarras, '-019281');
      expect(previa.itens.single.tombo, '23254');
    });

    test('reconhece o cabeçalho do inventario.ifpi.edu.br', () {
      // Outro sistema, os mesmos dados, outros nomes. Três armadilhas aqui:
      // `Número` é o código de barras e não a numeração das linhas; há duas
      // colunas de elemento de despesa, e a que vale é a do código; e `Sala`
      // e `Setor` disputam o mesmo campo, com `Sala` sendo o ambiente e
      // `Setor` a unidade administrativa.
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'inventario-ifpi.xlsx',
        bytes: planilhaXlsx([
          [
            'Número',
            'Tombo',
            'Marca',
            'Modelo',
            'Descrição',
            'Status',
            'Código Elemento de Despesa',
            'Elemento de Despesa',
            'Rótulos',
            'Sala',
            'Estado de Conservação',
            'Responsável',
            'Campus',
            'Setor',
            'Registrado em',
            'Registrado por',
          ],
          [
            '-42313',
            '222',
            '',
            '',
            'ARQUIVO DE ACO COM QUATRO GAVETAS',
            'Ativo',
            '44905242',
            'MOBILIÁRIO EM GERAL',
            '',
            'PIC-BL A-08-MANUTENCAO',
            'Bom',
            'Tiago Morais de Almeida',
            'Campus Picos',
            'COORDENACAO DE LOGISTICA E MANUTENCAO',
            '02/09/2025',
            'alguem@ifpi.edu.br',
          ],
        ]),
      );

      final m = detectarMapeamento(planilha.linhas);

      expect(m.valido, isTrue);
      expect(m.colunaDe(CampoImportacao.codigoBarras), 0);
      expect(m.colunaDe(CampoImportacao.tombo), 1);
      expect(m.colunaDe(CampoImportacao.descricao), 4);
      expect(
        m.colunaDe(CampoImportacao.ed),
        6,
        reason: 'o código do elemento de despesa, não o nome dele',
      );
      expect(
        m.colunaDe(CampoImportacao.sala),
        9,
        reason: 'o ambiente, não a unidade administrativa de Setor',
      );
      expect(m.colunaDe(CampoImportacao.responsavel), 11);

      // Levantados em campo, nunca importados: o vocabulário da planilha é
      // outro, e o valor que vale é o que a comissão encontra na sala.
      expect(m.campoDaColuna(5), isNull, reason: 'Status');
      expect(m.campoDaColuna(10), isNull, reason: 'Estado de Conservação');
      // Sem coluna de valor neste formato.
      expect(m.colunaDe(CampoImportacao.valor), isNull);
    });

    test('a ordem das colunas é irrelevante', () {
      // É a correção central sobre o SLAP, que lê por posição e joga dado no
      // campo errado quando a exportação muda.
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'invertida.xlsx',
        bytes: planilhaXlsx([
          ['SALA', 'DESCRIÇÃO', 'TOMBO', 'RESPONSÁVEL', 'COD. BARRAS'],
          ['Biblioteca', 'Cadeira', '999', 'Maria', '888'],
        ]),
      );

      final m = detectarMapeamento(planilha.linhas);

      expect(m.colunaDe(CampoImportacao.sala), 0);
      expect(m.colunaDe(CampoImportacao.descricao), 1);
      expect(m.colunaDe(CampoImportacao.tombo), 2);
      expect(m.colunaDe(CampoImportacao.responsavel), 3);
      expect(m.colunaDe(CampoImportacao.codigoBarras), 4);
    });

    test('reconhece variações de nome entre versões da planilha', () {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'variante.xlsx',
        bytes: planilhaXlsx([
          [
            'Nº Patrimonial',
            'Descrição do Bem',
            'Elemento de Despesa',
            'Localização',
            'Detentor',
          ],
          ['123', 'Mesa', '449052', 'Auditório', 'João'],
        ]),
      );

      final m = detectarMapeamento(planilha.linhas);

      expect(m.colunaDe(CampoImportacao.tombo), 0);
      expect(m.colunaDe(CampoImportacao.descricao), 1);
      expect(m.colunaDe(CampoImportacao.ed), 2);
      expect(m.colunaDe(CampoImportacao.sala), 3);
      expect(m.colunaDe(CampoImportacao.responsavel), 4);
    });

    test('pula linhas de título antes da tabela', () {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'com_titulo.xlsx',
        bytes: planilhaXlsx([
          ['INSTITUTO FEDERAL DO PIAUÍ', '', ''],
          ['Relatório de Bens Patrimoniais', '', ''],
          ['', '', ''],
          ['TOMBO', 'DESCRIÇÃO', 'SALA'],
          ['123', 'Mesa', 'Auditório'],
        ]),
      );

      final m = detectarMapeamento(planilha.linhas);

      expect(m.linhaCabecalho, 3);
      expect(m.valido, isTrue);
    });

    test('sem tombo o mapeamento é inválido e diz o que falta', () {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'sem_tombo.xlsx',
        bytes: planilhaXlsx([
          ['DESCRIÇÃO', 'SALA'],
          ['Mesa', 'Auditório'],
        ]),
      );

      final m = detectarMapeamento(planilha.linhas);

      expect(m.valido, isFalse);
      expect(m.faltando, contains(CampoImportacao.tombo));
    });

    test('uma coluna nunca alimenta dois campos', () {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'ajuste.xlsx',
        bytes: planilhaXlsx([
          ['TOMBO', 'CÓDIGO'],
          ['123', '456'],
        ]),
      );

      var m = detectarMapeamento(planilha.linhas);
      m = m.definir(CampoImportacao.codigoBarras, 0);

      expect(m.colunaDe(CampoImportacao.codigoBarras), 0);
      expect(
        m.colunaDe(CampoImportacao.tombo),
        isNull,
        reason: 'tombo perdeu a coluna que foi reatribuída',
      );
    });
  });

  group('leitura de CSV', () {
    test('aceita ponto e vírgula, que é o padrão do Excel em português', () {
      final csv = 'TOMBO;DESCRIÇÃO;SALA\n123;Mesa;Auditório\n';
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'bens.csv',
        bytes: Uint8List.fromList(utf8.encode(csv)),
      );

      expect(planilha.linhas.length, 2);
      expect(planilha.linhas[1][0], '123');
      expect(planilha.linhas[1][2], 'Auditório');
    });

    test('aceita vírgula como separador', () {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'bens.csv',
        bytes: Uint8List.fromList(utf8.encode('TOMBO,DESCRICAO\n123,Mesa\n')),
      );

      expect(planilha.linhas[1][0], '123');
      expect(planilha.linhas[1][1], 'Mesa');
    });

    test('acentos sobrevivem a arquivo em Latin-1', () {
      // Exportação de sistema público brasileiro frequentemente vem em
      // Windows-1252; decodificar como UTF-8 à força viraria lixo.
      final bytes = Uint8List.fromList(
        latin1.encode('TOMBO;SALA\n123;Coordenação\n'),
      );
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'latin.csv',
        bytes: bytes,
      );

      expect(planilha.linhas[1][1], 'Coordenação');
    });

    test('arquivo .xls é recusado com orientação, não com erro obscuro', () {
      expect(
        () => LeitorPlanilha.ler(
          nomeArquivo: 'antigo.xls',
          bytes: Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0]),
        ),
        throwsA(isA<PlanilhaInvalida>()),
      );
    });
  });

  group('importação', () {
    late Banco banco;
    late RepositorioPatrimonios patrimonios;
    late Inventario inventario;

    setUp(() {
      banco = Banco.emMemoria();
      final ops = RepositorioOperacoes(banco);
      patrimonios = RepositorioPatrimonios(banco, ops);
      inventario = RepositorioInventarios(
        banco,
        ops,
      ).criar(nome: 'Campus Picos', ano: 2026);
    });

    tearDown(() => banco.fechar());

    PreviaImportacao prever(List<List<String>> linhas) {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: 'teste.xlsx',
        bytes: planilhaXlsx(linhas),
      );
      return Importador.preparar(planilha, detectarMapeamento(planilha.linhas));
    }

    test('importa as linhas e conta os elementos de despesa', () {
      final previa = prever([
        ['TOMBO', 'ED', 'DESCRIÇÃO'],
        ['1', '30', 'Mesa'],
        ['2', '30', 'Cadeira'],
        ['3', '18', 'Livro'],
      ]);

      expect(previa.total, 3);
      expect(previa.contagemPorEd['30'], 2);
      expect(previa.contagemPorEd['18'], 1);
    });

    test('linha sem tombo é descartada, não vira item em branco', () {
      final previa = prever([
        ['TOMBO', 'DESCRIÇÃO'],
        ['1', 'Mesa'],
        ['', 'TOTAL GERAL'],
        ['', ''],
      ]);

      expect(previa.total, 1);
      expect(
        previa.semTombo,
        1,
        reason: 'a linha totalmente vazia nem é contada',
      );
    });

    test('tombo repetido no arquivo é sinalizado e entra uma vez só', () {
      final previa = prever([
        ['TOMBO', 'DESCRIÇÃO'],
        ['123', 'Mesa'],
        ['123', 'Mesa duplicada'],
      ]);

      expect(previa.tombosDuplicados, contains('123'));

      Importador.aplicar(
        repositorio: patrimonios,
        inventarioId: inventario.id,
        previa: previa,
      );

      expect(
        patrimonios.todos(inventario.id, incluirIgnorados: true).length,
        1,
      );
    });

    test('o ED escolhido sai do inventário sem sumir do banco', () {
      final previa = prever([
        ['TOMBO', 'ED', 'DESCRIÇÃO'],
        ['1', '30', 'Mesa'],
        ['2', '18', 'Livro'],
      ]);

      Importador.aplicar(
        repositorio: patrimonios,
        inventarioId: inventario.id,
        previa: previa,
        edsExcluidos: {'18'},
      );
      RepositorioInventarios(
        banco,
        RepositorioOperacoes(banco),
      ).definirEdsExcluidos(inventario.id, ['18']);

      final progresso = patrimonios.progresso(inventario.id);
      expect(progresso.total, 1, reason: 'o livro não é pendência de ninguém');
      expect(progresso.ignorados, 1);
      expect(
        patrimonios.todos(inventario.id, incluirIgnorados: true).length,
        2,
      );
    });

    test('reimportar preserva o levantamento já feito', () {
      // O SLAP apaga tudo antes de importar: reimportar para corrigir uma
      // coluna destrói dias de trabalho sem aviso.
      final previa = prever([
        ['TOMBO', 'DESCRIÇÃO'],
        ['123', 'Mesa'],
      ]);
      Importador.aplicar(
        repositorio: patrimonios,
        inventarioId: inventario.id,
        previa: previa,
      );

      final item = patrimonios.todos(inventario.id).first;
      patrimonios.registrarVerificacao(
        patrimonio: item,
        config: const ConfiguracaoLevantamento(sala: 'Auditório'),
        usuarioNome: 'Ana',
      );

      final segunda = Importador.aplicar(
        repositorio: patrimonios,
        inventarioId: inventario.id,
        previa: prever([
          ['TOMBO', 'DESCRIÇÃO'],
          ['123', 'Mesa'],
          ['124', 'Cadeira nova'],
        ]),
      );

      expect(segunda.preservados, 1);
      expect(segunda.inseridos, 1);

      final depois = patrimonios.procurar(
        inventarioId: inventario.id,
        codigo: '123',
        modo: ModoLeitura.tombo,
      );
      expect(depois.patrimonio!.verificado, isTrue);
      expect(depois.patrimonio!.salaAtual, 'Auditório');
    });

    test('o código de barras negativo da base real fica encontrável', () {
      Importador.aplicar(
        repositorio: patrimonios,
        inventarioId: inventario.id,
        previa: prever([
          ['TOMBO', 'COD. BARRAS', 'DESCRIÇÃO'],
          ['23254', '-19281', 'ESTABILIZADOR'],
        ]),
      );

      final leitura = patrimonios.procurar(
        inventarioId: inventario.id,
        codigo: '19281',
        modo: ModoLeitura.codigoBarras,
      );

      expect(leitura.resultado, ResultadoLeitura.sucesso);
      expect(
        leitura.patrimonio!.codigoBarras,
        '-19281',
        reason: 'o valor do cadastro é preservado como veio',
      );
    });
  });
}
