import 'dart:convert';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../banco.dart';
import 'operacoes.dart';

const _uuid = Uuid();

/// Um processo de inventário.
///
/// Nome é texto livre e **nome + ano não são chave única**: a mesma unidade
/// pode ter vários processos no mesmo ano ("Campus Picos — Biblioteca" e
/// "Campus Picos — Patrimônio Geral"). A identidade é o UUID, que também é o
/// que permite a mesma réplica existir em vários aparelhos.
class Inventario {
  final String id;
  final String nome;
  final int ano;
  final DateTime criadoEm;
  final String dispositivoOrigem;

  /// Segredo compartilhado por QR code. Define quem participa e autentica a
  /// sincronização.
  final String chaveSync;

  final List<String> edsExcluidos;
  final DateTime? encerradoEm;

  const Inventario({
    required this.id,
    required this.nome,
    required this.ano,
    required this.criadoEm,
    required this.dispositivoOrigem,
    required this.chaveSync,
    this.edsExcluidos = const [],
    this.encerradoEm,
  });

  bool get encerrado => encerradoEm != null;

  String get titulo => '$nome — $ano';
}

class RepositorioInventarios {
  final Banco banco;
  final RepositorioOperacoes ops;

  RepositorioInventarios(this.banco, this.ops);

  Database get _db => banco.db;

  /// Gera a chave de sincronização do inventário.
  ///
  /// `Random.secure()` e não `Random()`: a chave é a única coisa que impede um
  /// aparelho qualquer na mesma rede de ler e escrever no inventário.
  static String _novaChave() {
    final aleatorio = Random.secure();
    final bytes = List<int>.generate(32, (_) => aleatorio.nextInt(256));
    return base64Url.encode(bytes);
  }

  Inventario criar({required String nome, required int ano}) {
    final inv = Inventario(
      id: _uuid.v4(),
      nome: nome.trim(),
      ano: ano,
      criadoEm: DateTime.now(),
      dispositivoOrigem: banco.dispositivoId,
      chaveSync: _novaChave(),
    );
    _inserir(inv);
    return inv;
  }

  void _inserir(Inventario inv) {
    _db.execute(
      'INSERT OR IGNORE INTO inventarios (id, nome, ano, criado_em, '
      'dispositivo_origem, chave_sync, eds_excluidos, encerrado_em) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        inv.id,
        inv.nome,
        inv.ano,
        inv.criadoEm.millisecondsSinceEpoch,
        inv.dispositivoOrigem,
        inv.chaveSync,
        jsonEncode(inv.edsExcluidos),
        inv.encerradoEm?.millisecondsSinceEpoch,
      ],
    );
  }

  /// Registra um inventário recebido de outro aparelho.
  void registrarRecebido(Inventario inv) => _inserir(inv);

  List<Inventario> listar() {
    final linhas = _db.select(
      'SELECT * FROM inventarios ORDER BY ano DESC, nome',
    );
    return linhas.map(_daLinha).toList();
  }

  Inventario? porId(String id) {
    final r = _db.select('SELECT * FROM inventarios WHERE id = ?', [id]);
    return r.isEmpty ? null : _daLinha(r.first);
  }

  /// Define quais elementos de despesa ficam fora do inventário.
  ///
  /// Vai pelo log de operações porque é decisão do processo, e não do
  /// aparelho: quem sincronizar depois precisa aplicar a mesma exclusão, ou os
  /// relatórios de cada réplica divergiriam.
  void definirEdsExcluidos(String inventarioId, List<String> eds) {
    ops.registrarLocal(
      inventarioId: inventarioId,
      entidade: 'inventario',
      entidadeId: inventarioId,
      campos: {'eds_excluidos': jsonEncode(eds)},
      usuarioNome: banco.lerConfig('usuario_nome'),
      usuarioMatricula: banco.lerConfig('usuario_matricula'),
    );
    ops.reaplicarEdsExcluidos(inventarioId);
  }

  void renomear(String inventarioId, String nome) {
    ops.registrarLocal(
      inventarioId: inventarioId,
      entidade: 'inventario',
      entidadeId: inventarioId,
      campos: {'nome': nome.trim()},
      usuarioNome: banco.lerConfig('usuario_nome'),
    );
  }

  /// Apaga a réplica local do inventário.
  ///
  /// Não afeta os outros aparelhos: cada um tem a sua própria cópia, e a
  /// próxima sincronização traria tudo de volta. É remoção local, não
  /// encerramento do processo.
  void removerLocalmente(String inventarioId) {
    banco.transacao(() {
      _db.execute('DELETE FROM patrimonios WHERE inventario_id = ?', [
        inventarioId,
      ]);
      _db.execute('DELETE FROM ops WHERE inventario_id = ?', [inventarioId]);
      _db.execute('DELETE FROM conflitos WHERE inventario_id = ?', [
        inventarioId,
      ]);
      _db.execute('DELETE FROM pares WHERE inventario_id = ?', [inventarioId]);
      _db.execute('DELETE FROM estado_sync WHERE inventario_id = ?', [
        inventarioId,
      ]);
      _db.execute('DELETE FROM inventarios WHERE id = ?', [inventarioId]);
      _db.execute(
        'DELETE FROM campos_patrimonio WHERE patrimonio_id NOT IN '
        '(SELECT id FROM patrimonios)',
      );
    });
  }

  static Inventario _daLinha(Row r) => Inventario(
    id: r['id'] as String,
    nome: r['nome'] as String,
    ano: r['ano'] as int,
    criadoEm: DateTime.fromMillisecondsSinceEpoch(r['criado_em'] as int),
    dispositivoOrigem: r['dispositivo_origem'] as String,
    chaveSync: r['chave_sync'] as String,
    edsExcluidos: (jsonDecode(r['eds_excluidos'] as String? ?? '[]') as List)
        .map((e) => e.toString())
        .toList(),
    encerradoEm: r['encerrado_em'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['encerrado_em'] as int),
  );
}
