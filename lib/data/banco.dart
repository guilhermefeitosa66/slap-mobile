import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../domain/valores.dart';
import 'schema.dart';

/// Abertura e configuração do banco local.
///
/// O acesso é síncrono (`package:sqlite3` sobre FFI). Isso é intencional: as
/// consultas do caminho quente são acessos por índice, medidos em
/// microssegundos, e ir para um isolate custaria mais em serialização do que a
/// própria consulta. Só a importação de planilha — que percorre milhares de
/// linhas — roda fora da thread de interface.
class Banco {
  final Database db;

  /// Arquivo do banco, ou `null` quando em memória.
  ///
  /// É o que permite abrir uma segunda conexão num isolate — a importação de
  /// planilha grava lá, sem travar a interface.
  final String? caminho;

  Banco._(this.db, {this.caminho});

  static Banco? _instancia;
  static Banco get instancia {
    final b = _instancia;
    if (b == null) {
      throw StateError('Banco não foi aberto. Chame Banco.abrir() antes.');
    }
    return b;
  }

  static Future<Banco> abrir({String? caminho}) async {
    final arquivo =
        caminho ?? '${(await getApplicationDocumentsDirectory()).path}/slap.db';

    if (caminho == null) {
      await Directory(File(arquivo).parent.path).create(recursive: true);
    }

    final db = sqlite3.open(arquivo);
    _configurar(db);
    _migrar(db);

    final banco = Banco._(db, caminho: arquivo);
    banco._garantirIdentidade();
    _instancia = banco;
    return banco;
  }

  /// Banco em memória, para testes.
  static Banco emMemoria() {
    final db = sqlite3.openInMemory();
    _configurar(db);
    _migrar(db);
    final banco = Banco._(db);
    banco._garantirIdentidade();
    return banco;
  }

  static void _configurar(Database db) {
    // WAL permite ler durante a sincronização sem bloquear: o usuário continua
    // lendo patrimônios enquanto operações de outro aparelho são aplicadas.
    db.execute('PRAGMA journal_mode = WAL');
    // NORMAL em vez de FULL: sacrifica durabilidade contra queda de energia,
    // não contra queda do app. Numa importação de 10 mil linhas a diferença é
    // de segundos, e o dado perdido no pior caso é recuperável por sincronia.
    db.execute('PRAGMA synchronous = NORMAL');
    db.execute('PRAGMA foreign_keys = ON');
    // Com a importação gravando por uma segunda conexão, a primeira pode
    // encontrar o banco ocupado. Esperar alguns segundos é melhor que falhar
    // uma leitura no meio do levantamento.
    db.execute('PRAGMA busy_timeout = 10000');
    db.execute('PRAGMA temp_store = MEMORY');

    // A comparação de texto do domínio (caixa, acento e espaço ignorados),
    // disponível no SQL. É o que permite separar OK de divergente numa
    // consulta — e, com isso, paginar e contar sem trazer as linhas todas
    // para o Dart.
    db.createFunction(
      functionName: 'forma_comparavel',
      argumentCount: const AllowedArgumentCount(1),
      deterministic: true,
      function: (argumentos) => formaComparavel(argumentos[0]?.toString()),
    );
  }

  static void _migrar(Database db) {
    final atual = db.select('PRAGMA user_version').first['user_version'] as int;
    if (atual >= versaoEsquema) return;

    db.execute('BEGIN');
    try {
      if (atual == 0) {
        for (final ddl in ddlEsquema) {
          db.execute(ddl);
        }
      }
      // Migrações futuras entram aqui, comparando `atual`.

      db.execute('PRAGMA user_version = $versaoEsquema');
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Gera o identificador do aparelho na primeira execução.
  ///
  /// Nunca muda depois disso: é o que dá autoria às operações e desempata os
  /// conflitos de forma idêntica em todas as réplicas.
  void _garantirIdentidade() {
    final existente = lerConfig(Config.dispositivoId);
    if (existente == null) {
      gravarConfig(Config.dispositivoId, const Uuid().v4());
    }
  }

  String get dispositivoId => lerConfig(Config.dispositivoId)!;

  String? lerConfig(String chave) {
    final r = db.select('SELECT valor FROM config WHERE chave = ?', [chave]);
    return r.isEmpty ? null : r.first['valor'] as String;
  }

  void gravarConfig(String chave, String valor) {
    db.execute(
      'INSERT INTO config (chave, valor) VALUES (?, ?) '
      'ON CONFLICT(chave) DO UPDATE SET valor = excluded.valor',
      [chave, valor],
    );
  }

  void apagarConfig(String chave) {
    db.execute('DELETE FROM config WHERE chave = ?', [chave]);
  }

  /// Roda [acao] numa transação, desfazendo tudo se ela lançar.
  ///
  /// Sem isto, uma falha no meio da importação deixaria o inventário pela
  /// metade — exatamente o que acontece no SLAP, que insere linha a linha sem
  /// transação depois de já ter apagado as anteriores.
  T transacao<T>(T Function() acao) {
    db.execute('BEGIN');
    try {
      final resultado = acao();
      db.execute('COMMIT');
      return resultado;
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    }
  }

  void fechar() {
    db.close();
    if (identical(_instancia, this)) _instancia = null;
  }
}
