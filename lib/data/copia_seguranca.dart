import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../core/version_vector.dart';
import 'banco.dart';
import 'repos/operacoes.dart';
import 'schema.dart';

/// Cópia de segurança do banco local, e a restauração dela.
///
/// Se o celular for perdido ou formatado no meio de um inventário, o que ele
/// fez some — a não ser que tenha sido sincronizado. A cópia é um arquivo
/// SQLite com os inventários, os dados do SUAP e o log de operações, que a
/// pessoa guarda onde quiser pelo seletor do sistema.
///
/// **A identidade do aparelho não viaja.** Restaurar não transforma o aparelho
/// novo no antigo: as operações da cópia entram como de um terceiro, do mesmo
/// jeito que chegariam pela sincronização, e o aparelho novo continua
/// escrevendo com a identidade dele. Assim o mesmo `dispositivo_id` nunca passa
/// a existir em dois aparelhos por causa de uma restauração — o que quebraria
/// a numeração das operações. A decisão está em `docs/copia-de-seguranca.md`.
class CopiaDeSeguranca {
  /// Extensão sugerida para o arquivo.
  static const extensao = 'slapcopia';

  /// Grava em [destino] uma cópia consistente do banco.
  ///
  /// Com [inventarioId], só aquele inventário. A identidade e as preferências
  /// deste aparelho ficam de fora; vão só o nome de quem exportou e quando,
  /// para a pessoa reconhecer o arquivo ao restaurar.
  static void exportar(Banco banco, String destino, {String? inventarioId}) {
    final arquivo = File(destino);
    if (arquivo.existsSync()) arquivo.deleteSync();

    // VACUUM INTO copia o estado confirmado, mesmo com o banco em uso.
    banco.db.execute('VACUUM INTO ?', [destino]);

    final copia = sqlite3.open(destino);
    try {
      copia.execute('BEGIN');
      if (inventarioId != null) _manterSo(copia, inventarioId);

      // O que é do aparelho, e não do inventário, não vai junto.
      copia.execute('DELETE FROM config');
      copia.execute('DELETE FROM pares');
      copia.execute('DELETE FROM estado_sync');
      final origem = {
        _chaveOrigem: banco.dispositivoId,
        _chaveAutor: banco.lerConfig(Config.usuarioNome) ?? '',
        _chaveCriadaEm: '${DateTime.now().millisecondsSinceEpoch}',
      };
      for (final e in origem.entries) {
        copia.execute('INSERT INTO config (chave, valor) VALUES (?, ?)', [
          e.key,
          e.value,
        ]);
      }
      copia.execute('COMMIT');

      // Um arquivo só, sem -wal ao lado, e sem o espaço do que foi apagado.
      copia.execute('PRAGMA journal_mode = DELETE');
      copia.execute('VACUUM');
    } finally {
      copia.close();
    }

    _marcarLogComoSaido(banco, inventarioId);
  }

  /// O log saiu deste aparelho, e o que saiu não pode mais ser re-estampado.
  ///
  /// Restaurada noutro celular, a cópia leva estas operações com a estampa que
  /// têm agora. Reescrever aqui uma delas criaria duas versões da mesma
  /// operação — ver `RepositorioOperacoes.reestamparOperacoesDoFuturo`.
  static void _marcarLogComoSaido(Banco banco, String? inventarioId) {
    final ops = RepositorioOperacoes(banco);
    final linhas = banco.db.select(
      'SELECT inventario_id, MAX(seq) AS s FROM ops WHERE dispositivo = ?'
      '${inventarioId == null ? '' : ' AND inventario_id = ?'} '
      'GROUP BY inventario_id',
      [banco.dispositivoId, ?inventarioId],
    );
    for (final l in linhas) {
      ops.marcarEnviadoAte(l['inventario_id'] as String, l['s'] as int);
    }
  }

  static void _manterSo(Database copia, String inventarioId) {
    for (final tabela in [
      'patrimonios',
      'ops',
      'conflitos',
      'campos_inventario',
    ]) {
      copia.execute('DELETE FROM $tabela WHERE inventario_id <> ?', [
        inventarioId,
      ]);
    }
    copia.execute('DELETE FROM inventarios WHERE id <> ?', [inventarioId]);
    copia.execute(
      'DELETE FROM campos_patrimonio WHERE patrimonio_id NOT IN '
      '(SELECT id FROM patrimonios)',
    );
    copia.execute(
      'DELETE FROM contextos WHERE ctx_id NOT IN '
      '(SELECT ctx_id FROM ops WHERE ctx_id IS NOT NULL)',
    );
  }

  /// O que há na cópia, para a pessoa confirmar antes de restaurar.
  static ResumoCopia ler(String arquivo, {Banco? comparadoCom}) {
    final copia = _abrir(arquivo);
    try {
      String? config(String chave) {
        final r = copia.select('SELECT valor FROM config WHERE chave = ?', [
          chave,
        ]);
        return r.isEmpty ? null : r.first['valor'] as String;
      }

      final criadaEm = int.tryParse(config(_chaveCriadaEm) ?? '');
      return ResumoCopia(
        autor: config(_chaveAutor),
        criadaEm: criadaEm == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(criadaEm),
        inventarios: [
          for (final r in copia.select(
            'SELECT i.id, i.nome, i.ano, '
            '(SELECT COUNT(*) FROM patrimonios p WHERE p.inventario_id = i.id) '
            'AS itens FROM inventarios i ORDER BY i.ano DESC, i.nome',
          ))
            (
              id: r['id'] as String,
              nome: r['nome'] as String,
              ano: r['ano'] as int,
              itens: r['itens'] as int,
              jaExiste:
                  comparadoCom != null &&
                  comparadoCom.db.select(
                    'SELECT 1 FROM inventarios WHERE id = ?',
                    [r['id']],
                  ).isNotEmpty,
            ),
        ],
      );
    } finally {
      copia.close();
    }
  }

  /// Traz o conteúdo da cópia para este banco, sem apagar nada.
  ///
  /// Inventário que não existe aqui é criado; o que já existe recebe o que
  /// falta. As operações entram pelo mesmo caminho da sincronização — com a
  /// detecção de conflito e a numeração de cada aparelho preservadas —, e os
  /// conflitos já resolvidos na cópia continuam resolvidos. Tudo numa
  /// transação: ou a cópia entra inteira, ou nada muda.
  static ResultadoRestauracao restaurar(Banco banco, String arquivo) {
    final copia = _abrir(arquivo);
    try {
      final ops = RepositorioOperacoes(banco);
      return banco.transacao(() {
        var novos = 0;
        var operacoes = 0;
        var conflitos = 0;

        final inventarios = copia.select('SELECT * FROM inventarios');
        for (final inv in inventarios) {
          final id = inv['id'] as String;
          final existia = banco.db.select(
            'SELECT 1 FROM inventarios WHERE id = ?',
            [id],
          ).isNotEmpty;
          if (!existia) novos++;

          banco.db.execute(
            'INSERT OR IGNORE INTO inventarios (id, nome, ano, criado_em, '
            'dispositivo_origem, chave_sync, eds_excluidos, encerrado_em) '
            'VALUES (?,?,?,?,?,?,?,?)',
            [
              id,
              inv['nome'],
              inv['ano'],
              inv['criado_em'],
              inv['dispositivo_origem'],
              inv['chave_sync'],
              inv['eds_excluidos'],
              inv['encerrado_em'],
            ],
          );

          _copiarPatrimonios(copia, banco.db, id);

          // Antes das operações: aplicá-las recria os conflitos, e a versão
          // da cópia — talvez já resolvida — tem de estar lá primeiro.
          _copiarLinhas(copia, banco.db, 'conflitos', id);

          final lote = [
            for (final r in copia.select(
              'SELECT * FROM ops WHERE inventario_id = ? ORDER BY hlc',
              [id],
            ))
              Operacao.doBanco(r),
          ];
          final contextos = {
            for (final r in copia.select(
              'SELECT ctx_id, vetor FROM contextos WHERE ctx_id IN '
              '(SELECT DISTINCT ctx_id FROM ops WHERE inventario_id = ?)',
              [id],
            ))
              r['ctx_id'] as String: VersionVector.decodificar(
                r['vetor'] as String,
              ),
          };
          final resultado = ops.aplicarRemotas(
            lote,
            inventarioId: id,
            contextos: contextos,
          );
          operacoes += resultado.aplicadas;
          conflitos += resultado.conflitos;
          ops.reaplicarEdsExcluidos(id);
        }

        return ResultadoRestauracao(
          inventarios: inventarios.length,
          inventariosNovos: novos,
          operacoes: operacoes,
          conflitos: conflitos,
        );
      });
    } finally {
      copia.close();
    }
  }

  static void _copiarPatrimonios(Database de, Database para, String id) {
    // A lista é fechada, e não `SELECT *`, para que uma cópia feita por uma
    // versão anterior do esquema continue restaurável: as colunas que ela
    // tinha a mais — `conservacao_original` e `situacao_original`, até a
    // versão 3 — simplesmente não são lidas.
    const colunas =
        'id, inventario_id, ordem, tombo, codigo_barras, ed, descricao, '
        'responsavel_original, sala_original, valor, tombo_chave, '
        'codigo_barras_chave, ignorado';
    final stmt = para.prepare(
      'INSERT OR IGNORE INTO patrimonios ($colunas) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
    );

    try {
      for (final r in de.select(
        'SELECT $colunas FROM patrimonios WHERE inventario_id = ?',
        [id],
      )) {
        stmt.execute([...r.values]);
      }
    } finally {
      stmt.close();
    }
  }

  static void _copiarLinhas(
    Database de,
    Database para,
    String tabela,
    String inventarioId,
  ) {
    final linhas = de.select('SELECT * FROM $tabela WHERE inventario_id = ?', [
      inventarioId,
    ]);
    if (linhas.isEmpty) return;
    final colunas = linhas.columnNames;
    final stmt = para.prepare(
      'INSERT OR IGNORE INTO $tabela (${colunas.join(', ')}) '
      'VALUES (${List.filled(colunas.length, '?').join(', ')})',
    );
    try {
      for (final r in linhas) {
        stmt.execute([...r.values]);
      }
    } finally {
      stmt.close();
    }
  }

  /// Abre a cópia só para leitura, conferindo que é uma cópia deste
  /// aplicativo e de uma versão que ele entende.
  static Database _abrir(String arquivo) {
    const naoE = 'Este arquivo não é uma cópia de segurança do SLAP.';

    final Database copia;
    try {
      copia = sqlite3.open(arquivo, mode: OpenMode.readOnly);
    } on SqliteException {
      throw CopiaInvalida(naoE);
    }

    try {
      final versao =
          copia.select('PRAGMA user_version').first['user_version'] as int;
      if (versao > versaoEsquema) {
        throw CopiaInvalida(
          'Esta cópia foi feita por uma versão mais nova do aplicativo. '
          'Atualize o aplicativo e tente de novo.',
        );
      }
      final tabelas = {
        for (final r in copia.select(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ))
          r['name'] as String,
      };
      const exigidas = {
        'inventarios',
        'patrimonios',
        'ops',
        'contextos',
        'conflitos',
      };
      if (versao == 0 || !tabelas.containsAll(exigidas)) {
        throw CopiaInvalida(naoE);
      }
      return copia;
    } on SqliteException {
      copia.close();
      throw CopiaInvalida(naoE);
    } on CopiaInvalida {
      copia.close();
      rethrow;
    }
  }

  static const _chaveOrigem = 'copia.dispositivo';
  static const _chaveAutor = 'copia.usuario';
  static const _chaveCriadaEm = 'copia.criada_em';
}

class CopiaInvalida implements Exception {
  final String mensagem;
  CopiaInvalida(this.mensagem);

  @override
  String toString() => mensagem;
}

/// O que uma cópia contém.
class ResumoCopia {
  /// Quem exportou, pelo nome configurado no aparelho de origem.
  final String? autor;
  final DateTime? criadaEm;
  final List<({String id, String nome, int ano, int itens, bool jaExiste})>
  inventarios;

  const ResumoCopia({
    required this.autor,
    required this.criadaEm,
    required this.inventarios,
  });
}

/// O que a restauração fez.
class ResultadoRestauracao {
  final int inventarios;
  final int inventariosNovos;
  final int operacoes;
  final int conflitos;

  const ResultadoRestauracao({
    required this.inventarios,
    required this.inventariosNovos,
    required this.operacoes,
    required this.conflitos,
  });
}
