import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:sqlite3/sqlite3.dart';

/// Migrações do esquema sobre bancos que aparelhos reais deixaram para trás.
void main() {
  late Directory pasta;

  setUp(() async {
    pasta = await Directory.systemTemp.createTemp('slap_esquema_');
  });

  tearDown(() => pasta.delete(recursive: true));

  test('banco da versão 3 perde as colunas de origem do vocabulário antigo '
      'sem perder o resto', () async {
    final caminho = '${pasta.path}/v3.db';

    // Um banco como a versão 3 deixava: com estado e situação "de origem"
    // preenchidos por uma planilha que os trazia.
    final antigo = sqlite3.open(caminho);
    for (final versao in [1, 2, 3]) {
      for (final ddl in migracoes[versao]!) {
        antigo.execute(ddl);
      }
    }
    antigo.execute('PRAGMA user_version = 3');
    antigo.execute(
      "INSERT INTO inventarios (id, nome, ano, criado_em, dispositivo_origem, "
      "chave_sync) VALUES ('inv', 'Campus', 2026, 0, 'd', 'k')",
    );
    antigo.execute(
      'INSERT INTO patrimonios (id, inventario_id, ordem, tombo, codigo_barras, '
      'ed, descricao, responsavel_original, sala_original, valor, '
      'conservacao_original, situacao_original, tombo_chave, '
      'codigo_barras_chave, verificado, conservacao) '
      "VALUES ('item', 'inv', '1', '000123', '-19281', '44905242', 'CADEIRA', "
      "'Ana', 'Auditório', '289.90', 'bom', 'ativo', '123', '19281', 1, 'ruim')",
    );
    antigo.close();

    final banco = await Banco.abrir(caminho: caminho);
    addTearDown(banco.fechar);

    expect(
      banco.db.select('PRAGMA user_version').first['user_version'],
      versaoEsquema,
    );
    final colunas = {
      for (final r in banco.db.select('PRAGMA table_info(patrimonios)'))
        r['name'] as String,
    };
    expect(colunas, isNot(contains('situacao_original')));
    expect(colunas, containsAll(['conservacao', 'situacao']));
    // A coluna de origem voltou na versão 6, para o estado do SUAP — e volta
    // vazia: o "bom" que havia nela era do vocabulário antigo.
    expect(colunas, contains('conservacao_original'));

    final p = RepositorioPatrimonios(
      banco,
      RepositorioOperacoes(banco),
    ).porId('item')!;
    expect(p.tombo, '000123');
    expect(p.codigoBarras, '-19281');
    expect(p.descricao, 'CADEIRA');
    expect(p.responsavelOriginal, 'Ana');
    expect(p.salaOriginal, 'Auditório');
    expect(p.valor, '289.90');
    expect(p.verificado, isTrue);
    expect(p.conservacao?.valor, 'ruim', reason: 'o levantado fica');
    expect(p.conservacao!.legado, isTrue);
    expect(p.conservacaoOriginal, isNull);
  });

  test('banco da versão 4 perde a coluna de ordem sem perder o resto', () async {
    final caminho = '${pasta.path}/v4.db';

    // Um banco como a versão 4 deixava, com a ordem da planilha preenchida.
    // É o esquema que está nos aparelhos em campo hoje.
    final antigo = sqlite3.open(caminho);
    for (final versao in [1, 2, 3, 4]) {
      for (final ddl in migracoes[versao]!) {
        antigo.execute(ddl);
      }
    }
    antigo.execute('PRAGMA user_version = 4');
    antigo.execute(
      "INSERT INTO inventarios (id, nome, ano, criado_em, dispositivo_origem, "
      "chave_sync) VALUES ('inv', 'Campus', 2026, 0, 'd', 'k')",
    );
    antigo.execute(
      'INSERT INTO patrimonios (id, inventario_id, ordem, tombo, codigo_barras, '
      'ed, descricao, responsavel_original, sala_original, valor, tombo_chave, '
      'codigo_barras_chave, verificado, sala_atual, verificado_por) '
      "VALUES ('item', 'inv', '7', '000123', '-19281', '44905242', 'CADEIRA', "
      "'Ana', 'Auditório', '289.90', '123', '19281', 1, 'Biblioteca', 'Bruno')",
    );
    antigo.close();

    final banco = await Banco.abrir(caminho: caminho);
    addTearDown(banco.fechar);

    expect(
      banco.db.select('PRAGMA user_version').first['user_version'],
      versaoEsquema,
    );
    final colunas = {
      for (final r in banco.db.select('PRAGMA table_info(patrimonios)'))
        r['name'] as String,
    };
    expect(colunas, isNot(contains('ordem')));

    // O levantamento feito em campo é o que não pode se perder na migração.
    final p = RepositorioPatrimonios(
      banco,
      RepositorioOperacoes(banco),
    ).porId('item')!;
    expect(p.tombo, '000123');
    expect(p.codigoBarras, '-19281');
    expect(p.descricao, 'CADEIRA');
    expect(p.salaOriginal, 'Auditório');
    expect(p.salaAtual, 'Biblioteca');
    expect(p.verificado, isTrue);
    expect(p.verificadoPor, 'Bruno');
  });

  test('banco da versão 5 recalcula as chaves de busca com sinal', () async {
    final caminho = '${pasta.path}/v5.db';

    // Até a versão 5, -19281 e 19281 tinham a mesma chave. No SUAP são dois
    // bens (tombos 23254 e 61816), e a leitura de um registrava o outro.
    final antigo = sqlite3.open(caminho);
    for (final versao in [1, 2, 3, 4, 5]) {
      for (final ddl in migracoes[versao]!) {
        antigo.execute(ddl);
      }
    }
    antigo.execute('PRAGMA user_version = 5');
    antigo.execute(
      "INSERT INTO inventarios (id, nome, ano, criado_em, dispositivo_origem, "
      "chave_sync) VALUES ('inv', 'Campus', 2026, 0, 'd', 'k')",
    );
    antigo.execute(
      'INSERT INTO patrimonios (id, inventario_id, tombo, codigo_barras, '
      'descricao, tombo_chave, codigo_barras_chave) VALUES '
      "('antigo', 'inv', '23254', '-019281', 'ESTABILIZADOR', '23254', '19281'), "
      "('novo', 'inv', '61816', '19281', 'MONITOR', '61816', '19281'), "
      "('sem', 'inv', '000777', NULL, 'MESA', '777', NULL)",
    );
    antigo.close();

    final banco = await Banco.abrir(caminho: caminho);
    addTearDown(banco.fechar);

    final chaves = {
      for (final r in banco.db.select(
        'SELECT id, tombo_chave, codigo_barras_chave FROM patrimonios',
      ))
        r['id'] as String: (r['tombo_chave'], r['codigo_barras_chave']),
    };
    expect(chaves['antigo'], ('23254', '-19281'));
    expect(chaves['novo'], ('61816', '19281'));
    expect(chaves['sem'], ('777', null));

    final repo = RepositorioPatrimonios(banco, RepositorioOperacoes(banco));
    final leitura = repo.procurar(
      inventarioId: 'inv',
      codigo: '19281',
      modo: ModoLeitura.codigoBarras,
    );
    expect(leitura.resultado, ResultadoLeitura.sucesso);
    expect(leitura.patrimonio!.descricao, 'MONITOR');
  });
}
