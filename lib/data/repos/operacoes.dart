import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../core/hlc.dart';
import '../../core/version_vector.dart';
import '../banco.dart';
import '../schema.dart';

const _uuid = Uuid();

/// Uma alteração, registrada de forma imutável.
///
/// É simultaneamente a unidade de sincronização, o registro de auditoria e a
/// fonte da verdade do estado. As três coisas são a mesma estrutura porque
/// responder "o que mudou desde a última vez que nos falamos?" e "quem mexeu
/// nisso?" é a mesma pergunta feita de dois jeitos.
class Operacao {
  final String opId;
  final String inventarioId;

  /// `patrimonio` ou `inventario`.
  final String entidade;
  final String entidadeId;
  final String campo;

  /// Valor novo, serializado como texto. `null` apaga o campo.
  final String? valor;

  final Hlc hlc;
  final String dispositivo;

  /// Posição na sequência deste dispositivo **neste inventário**. É o que a
  /// version vector conta.
  final int seq;

  /// Contexto causal: o que o autor já conhecia dos outros aparelhos quando
  /// escreveu. `null` quando ele ainda não conhecia nada de ninguém.
  final String? ctxId;

  final String? usuarioNome;
  final String? usuarioMatricula;
  final int criadoEm;

  const Operacao({
    required this.opId,
    required this.inventarioId,
    required this.entidade,
    required this.entidadeId,
    required this.campo,
    required this.valor,
    required this.hlc,
    required this.dispositivo,
    required this.seq,
    required this.ctxId,
    required this.usuarioNome,
    required this.usuarioMatricula,
    required this.criadoEm,
  });

  factory Operacao.doBanco(Row r) => Operacao(
    opId: r['op_id'] as String,
    inventarioId: r['inventario_id'] as String,
    entidade: r['entidade'] as String,
    entidadeId: r['entidade_id'] as String,
    campo: r['campo'] as String,
    valor: r['valor'] as String?,
    hlc: Hlc.decodificar(r['hlc'] as String),
    dispositivo: r['dispositivo'] as String,
    seq: r['seq'] as int,
    ctxId: r['ctx_id'] as String?,
    usuarioNome: r['usuario_nome'] as String?,
    usuarioMatricula: r['usuario_matricula'] as String?,
    criadoEm: r['criado_em'] as int,
  );

  Map<String, dynamic> toJson() => {
    'op_id': opId,
    'inv': inventarioId,
    'ent': entidade,
    'ent_id': entidadeId,
    'campo': campo,
    'valor': valor,
    'hlc': hlc.codificar(),
    'disp': dispositivo,
    'seq': seq,
    'ctx': ctxId,
    'nome': usuarioNome,
    'mat': usuarioMatricula,
    'em': criadoEm,
  };

  factory Operacao.fromJson(Map<String, dynamic> j) => Operacao(
    opId: j['op_id'] as String,
    inventarioId: j['inv'] as String,
    entidade: j['ent'] as String,
    entidadeId: j['ent_id'] as String,
    campo: j['campo'] as String,
    valor: j['valor'] as String?,
    hlc: Hlc.decodificar(j['hlc'] as String),
    dispositivo: j['disp'] as String,
    seq: (j['seq'] as num).toInt(),
    ctxId: j['ctx'] as String?,
    usuarioNome: j['nome'] as String?,
    usuarioMatricula: j['mat'] as String?,
    criadoEm: (j['em'] as num).toInt(),
  );
}

/// Resultado de aplicar um lote de operações recebidas de outro aparelho.
class ResultadoAplicacao {
  final int aplicadas;
  final int ignoradas;
  final int conflitos;
  final Set<String> patrimoniosAfetados;

  const ResultadoAplicacao({
    required this.aplicadas,
    required this.ignoradas,
    required this.conflitos,
    required this.patrimoniosAfetados,
  });
}

class RepositorioOperacoes {
  final Banco banco;

  RepositorioOperacoes(this.banco);

  Database get _db => banco.db;

  String get dispositivoId => banco.dispositivoId;

  // --------------------------------------------------------------- relógio ---

  /// Avança o relógio local e devolve o HLC da próxima operação.
  ///
  /// O relógio é global ao aparelho, e não por inventário, para que nunca ande
  /// para trás ao alternar entre inventários.
  Hlc _proximoHlc() {
    final guardado = banco.lerConfig(Config.hlcLocal);
    final ultimo = guardado == null
        ? Hlc.zero(dispositivoId)
        : Hlc.decodificar(guardado);
    final novo = Hlc.enviar(ultimo);
    banco.gravarConfig(Config.hlcLocal, novo.codificar());
    return novo;
  }

  /// Puxa o relógio local para frente ao receber operações de outro aparelho.
  void _absorverHlc(Hlc remoto) {
    final guardado = banco.lerConfig(Config.hlcLocal);
    final local = guardado == null
        ? Hlc.zero(dispositivoId)
        : Hlc.decodificar(guardado);
    final novo = Hlc.receber(local, remoto);
    banco.gravarConfig(Config.hlcLocal, novo.codificar());
  }

  // ------------------------------------------------------ version vectors ---

  /// Tudo que este aparelho conhece sobre este inventário.
  VersionVector vetorDe(String inventarioId) {
    final linhas = _db.select(
      'SELECT dispositivo, MAX(seq) AS s FROM ops '
      'WHERE inventario_id = ? GROUP BY dispositivo',
      [inventarioId],
    );
    return VersionVector({
      for (final l in linhas) l['dispositivo'] as String: l['s'] as int,
    });
  }

  int _proximoSeq(String inventarioId) {
    final r = _db.select(
      'SELECT COALESCE(MAX(seq), 0) AS s FROM ops '
      'WHERE inventario_id = ? AND dispositivo = ?',
      [inventarioId, dispositivoId],
    );
    return (r.first['s'] as int) + 1;
  }

  /// Contexto causal corrente: o que sabemos dos **outros** aparelhos.
  ///
  /// Guardado em `estado_sync` e atualizado só quando operações remotas são
  /// aplicadas, para que gravar localmente continue sendo O(1) — é o caminho
  /// quente do levantamento.
  String? _ctxCorrente(String inventarioId) {
    final r = _db.select(
      'SELECT ctx_id FROM estado_sync WHERE inventario_id = ?',
      [inventarioId],
    );
    return r.isEmpty ? null : r.first['ctx_id'] as String;
  }

  void _recalcularContexto(String inventarioId) {
    final linhas = _db.select(
      'SELECT dispositivo, MAX(seq) AS s FROM ops '
      'WHERE inventario_id = ? AND dispositivo <> ? GROUP BY dispositivo',
      [inventarioId, dispositivoId],
    );
    final remoto = VersionVector({
      for (final l in linhas) l['dispositivo'] as String: l['s'] as int,
    });
    if (remoto.isEmpty) return;

    final ctxId = registrarContexto(remoto);
    _db.execute(
      'INSERT INTO estado_sync (inventario_id, ctx_id) VALUES (?, ?) '
      'ON CONFLICT(inventario_id) DO UPDATE SET ctx_id = excluded.ctx_id',
      [inventarioId, ctxId],
    );
  }

  /// Guarda um contexto causal, deduplicado pelo conteúdo.
  ///
  /// O identificador é o hash do próprio vetor, e não um UUID: assim dois
  /// aparelhos que sabem a mesma coisa geram o mesmo `ctx_id`, e o contexto só
  /// precisa ser transferido uma vez.
  String registrarContexto(VersionVector vetor) {
    final texto = vetor.codificar();
    final ctxId = sha256
        .convert(utf8.encode(texto))
        .toString()
        .substring(0, 16);
    _db.execute(
      'INSERT OR IGNORE INTO contextos (ctx_id, vetor) VALUES (?, ?)',
      [ctxId, texto],
    );
    return ctxId;
  }

  VersionVector contexto(String? ctxId) {
    if (ctxId == null) return VersionVector.vazia;
    final r = _db.select('SELECT vetor FROM contextos WHERE ctx_id = ?', [
      ctxId,
    ]);
    return r.isEmpty
        ? VersionVector.vazia
        : VersionVector.decodificar(r.first['vetor'] as String);
  }

  // --------------------------------------------------------- escrita local ---

  /// Registra alterações locais e as aplica ao estado.
  ///
  /// Recebe vários campos de uma vez porque uma leitura de patrimônio altera
  /// cinco campos ao mesmo tempo: todos compartilham HLC e contexto, e vão
  /// numa transação só.
  List<Operacao> registrarLocal({
    required String inventarioId,
    required String entidade,
    required String entidadeId,
    required Map<String, String?> campos,
    String? usuarioNome,
    String? usuarioMatricula,
  }) {
    if (campos.isEmpty) return const [];

    return banco.transacao(() {
      final ctxId = _ctxCorrente(inventarioId);
      var seq = _proximoSeq(inventarioId);
      final agora = DateTime.now().millisecondsSinceEpoch;
      final geradas = <Operacao>[];

      for (final entrada in campos.entries) {
        final op = Operacao(
          opId: _uuid.v4(),
          inventarioId: inventarioId,
          entidade: entidade,
          entidadeId: entidadeId,
          campo: entrada.key,
          valor: entrada.value,
          hlc: _proximoHlc(),
          dispositivo: dispositivoId,
          seq: seq++,
          ctxId: ctxId,
          usuarioNome: usuarioNome,
          usuarioMatricula: usuarioMatricula,
          criadoEm: agora,
        );
        _gravarOp(op);
        _aplicarAoEstado(op, detectarConflito: false);
        geradas.add(op);
      }

      if (entidade == 'patrimonio') _materializar(entidadeId);
      return geradas;
    });
  }

  void _gravarOp(Operacao op) {
    _db.execute(
      'INSERT OR IGNORE INTO ops (op_id, inventario_id, entidade, entidade_id, '
      'campo, valor, hlc, dispositivo, seq, ctx_id, usuario_nome, '
      'usuario_matricula, criado_em) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        op.opId,
        op.inventarioId,
        op.entidade,
        op.entidadeId,
        op.campo,
        op.valor,
        op.hlc.codificar(),
        op.dispositivo,
        op.seq,
        op.ctxId,
        op.usuarioNome,
        op.usuarioMatricula,
        op.criadoEm,
      ],
    );
  }

  // -------------------------------------------------------- escrita remota ---

  /// Aplica operações recebidas de outro aparelho.
  ///
  /// Detecta concorrência real, registra conflito quando há, e mesmo assim
  /// aplica o vencedor: o banco nunca fica num estado indefinido esperando
  /// alguém decidir.
  ResultadoAplicacao aplicarRemotas(
    List<Operacao> ops, {
    Map<String, VersionVector> contextos = const {},
  }) {
    if (ops.isEmpty) {
      return const ResultadoAplicacao(
        aplicadas: 0,
        ignoradas: 0,
        conflitos: 0,
        patrimoniosAfetados: {},
      );
    }

    return banco.transacao(() {
      for (final entrada in contextos.entries) {
        _db.execute(
          'INSERT OR IGNORE INTO contextos (ctx_id, vetor) VALUES (?, ?)',
          [entrada.key, entrada.value.codificar()],
        );
      }

      var aplicadas = 0;
      var ignoradas = 0;
      var conflitos = 0;
      final afetados = <String>{};
      final inventarios = <String>{};

      // Em ordem de HLC: aplicar fora de ordem faria uma operação antiga
      // parecer vencedora de uma recente que ainda não chegou.
      final ordenadas = [...ops]..sort((a, b) => a.hlc.compareTo(b.hlc));

      for (final op in ordenadas) {
        if (op.dispositivo == dispositivoId) {
          // Nossa própria operação, voltando por um terceiro. Já a temos.
          ignoradas++;
          continue;
        }

        final jaTemos = _db.select(
          'SELECT 1 FROM ops WHERE inventario_id = ? AND dispositivo = ? AND seq = ?',
          [op.inventarioId, op.dispositivo, op.seq],
        );
        if (jaTemos.isNotEmpty) {
          ignoradas++;
          continue;
        }

        _absorverHlc(op.hlc);
        _gravarOp(op);
        if (_aplicarAoEstado(op, detectarConflito: true)) conflitos++;

        aplicadas++;
        inventarios.add(op.inventarioId);
        if (op.entidade == 'patrimonio') afetados.add(op.entidadeId);
      }

      for (final id in afetados) {
        _materializar(id);
      }
      for (final inv in inventarios) {
        _recalcularContexto(inv);
      }

      return ResultadoAplicacao(
        aplicadas: aplicadas,
        ignoradas: ignoradas,
        conflitos: conflitos,
        patrimoniosAfetados: afetados,
      );
    });
  }

  /// Decide o vencedor de um campo. Devolve `true` se registrou conflito.
  bool _aplicarAoEstado(Operacao op, {required bool detectarConflito}) {
    if (op.entidade == 'inventario') {
      _aplicarCampoInventario(op);
      return false;
    }

    final atual = _db.select(
      'SELECT * FROM campos_patrimonio WHERE patrimonio_id = ? AND campo = ?',
      [op.entidadeId, op.campo],
    );

    if (atual.isEmpty) {
      _gravarCampo(op);
      return false;
    }

    final r = atual.first;
    final relacao = compararCausalidade(
      deviceA: r['dispositivo'] as String,
      seqA: r['seq'] as int,
      contextoA: contexto(r['ctx_id'] as String?),
      deviceB: op.dispositivo,
      seqB: op.seq,
      contextoB: contexto(op.ctxId),
    );

    switch (relacao) {
      case RelacaoCausal.identica:
        return false;

      case RelacaoCausal.anterior:
        // Quem escreveu já conhecia o valor que está aqui: é atualização.
        _gravarCampo(op);
        return false;

      case RelacaoCausal.posterior:
        // Operação antiga chegando atrasada. Fica no log, não altera o estado.
        return false;

      case RelacaoCausal.concorrente:
        final vencedorAtual = Hlc.decodificar(r['hlc'] as String);
        final novaVence = op.hlc > vencedorAtual;
        final valorAtual = r['valor'] as String?;

        // Concorrentes com o mesmo valor não são conflito: as duas pessoas
        // viram a mesma coisa. Só se escolhe um vencedor determinístico.
        final mesmoValor = valorAtual == op.valor;

        if (detectarConflito && !mesmoValor) {
          _registrarConflito(
            op: op,
            opVencedora: novaVence ? op.opId : r['op_id'] as String,
            opPerdedora: novaVence ? r['op_id'] as String : op.opId,
          );
        }

        if (novaVence) _gravarCampo(op);
        return detectarConflito && !mesmoValor;
    }
  }

  void _gravarCampo(Operacao op) {
    _db.execute(
      'INSERT INTO campos_patrimonio '
      '(patrimonio_id, campo, valor, hlc, op_id, dispositivo, seq, ctx_id) '
      'VALUES (?,?,?,?,?,?,?,?) '
      'ON CONFLICT(patrimonio_id, campo) DO UPDATE SET '
      'valor = excluded.valor, hlc = excluded.hlc, op_id = excluded.op_id, '
      'dispositivo = excluded.dispositivo, seq = excluded.seq, '
      'ctx_id = excluded.ctx_id',
      [
        op.entidadeId,
        op.campo,
        op.valor,
        op.hlc.codificar(),
        op.opId,
        op.dispositivo,
        op.seq,
        op.ctxId,
      ],
    );
  }

  void _aplicarCampoInventario(Operacao op) {
    const permitidos = {'nome', 'ano', 'eds_excluidos', 'encerrado_em'};
    if (!permitidos.contains(op.campo)) return;

    _db.execute('UPDATE inventarios SET ${op.campo} = ? WHERE id = ?', [
      op.valor,
      op.entidadeId,
    ]);

    if (op.campo == 'eds_excluidos') {
      reaplicarEdsExcluidos(op.entidadeId);
    }
  }

  void _registrarConflito({
    required Operacao op,
    required String opVencedora,
    required String opPerdedora,
  }) {
    _db.execute(
      'INSERT OR IGNORE INTO conflitos (id, inventario_id, patrimonio_id, campo, '
      'op_vencedora, op_perdedora, criado_em) VALUES (?,?,?,?,?,?,?)',
      [
        _uuid.v4(),
        op.inventarioId,
        op.entidadeId,
        op.campo,
        opVencedora,
        opPerdedora,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  // --------------------------------------------------------- materialização ---

  /// Reescreve o cache em `patrimonios` a partir dos campos vencedores.
  ///
  /// Os metadados da verificação — quem, quando, em que aparelho — vêm da
  /// operação que venceu o campo `verificado`. Assim o crédito vai para quem
  /// de fato registrou o item, e não para quem mexeu por último em qualquer
  /// outro campo, que é o que o SLAP faz ao guardar só um `user_id`.
  void _materializar(String patrimonioId) {
    final campos = _db.select(
      'SELECT * FROM campos_patrimonio WHERE patrimonio_id = ?',
      [patrimonioId],
    );
    if (campos.isEmpty) return;

    final valores = <String, String?>{};
    Row? opVerificado;
    for (final c in campos) {
      valores[c['campo'] as String] = c['valor'] as String?;
      if (c['campo'] == CampoPatrimonio.verificado) opVerificado = c;
    }

    final verificado = valores[CampoPatrimonio.verificado] == '1';

    String? nome;
    String? matricula;
    String? dispositivo;
    int? quando;

    if (verificado && opVerificado != null) {
      final autor = _db.select(
        'SELECT usuario_nome, usuario_matricula, dispositivo, hlc FROM ops WHERE op_id = ?',
        [opVerificado['op_id'] as String],
      );
      if (autor.isNotEmpty) {
        nome = autor.first['usuario_nome'] as String?;
        matricula = autor.first['usuario_matricula'] as String?;
        dispositivo = autor.first['dispositivo'] as String?;
        quando = Hlc.decodificar(autor.first['hlc'] as String).millis;
      }
    }

    _db.execute(
      'UPDATE patrimonios SET verificado = ?, sala_atual = ?, '
      'responsavel_atual = ?, conservacao = ?, situacao = ?, verificado_em = ?, '
      'verificado_por = ?, verificado_por_matricula = ?, '
      'verificado_por_dispositivo = ? WHERE id = ?',
      [
        verificado ? 1 : 0,
        valores[CampoPatrimonio.salaAtual],
        valores[CampoPatrimonio.responsavelAtual],
        valores[CampoPatrimonio.conservacao],
        valores[CampoPatrimonio.situacao],
        verificado ? quando : null,
        verificado ? nome : null,
        verificado ? matricula : null,
        verificado ? dispositivo : null,
        patrimonioId,
      ],
    );
  }

  /// Recalcula quais itens estão fora do inventário por ED excluído.
  void reaplicarEdsExcluidos(String inventarioId) {
    final r = _db.select('SELECT eds_excluidos FROM inventarios WHERE id = ?', [
      inventarioId,
    ]);
    if (r.isEmpty) return;

    final lista =
        (jsonDecode(r.first['eds_excluidos'] as String? ?? '[]') as List)
            .map((e) => e.toString())
            .toList();

    _db.execute('UPDATE patrimonios SET ignorado = 0 WHERE inventario_id = ?', [
      inventarioId,
    ]);
    if (lista.isEmpty) return;

    final marcadores = List.filled(lista.length, '?').join(',');
    _db.execute(
      'UPDATE patrimonios SET ignorado = 1 '
      'WHERE inventario_id = ? AND ed IN ($marcadores)',
      [inventarioId, ...lista],
    );
  }

  // ------------------------------------------------------------ leitura ---

  /// Operações que um par ainda não tem, dado o que ele declara conhecer.
  ///
  /// Inclui operações originadas em terceiros: é isso que faz o trabalho de C
  /// chegar a A através de B, sem que A e C se encontrem.
  List<Operacao> opsFaltantes(
    String inventarioId,
    VersionVector vetorDoPar, {
    int limite = 5000,
  }) {
    final nosso = vetorDe(inventarioId);
    final resultado = <Operacao>[];

    for (final dispositivo in nosso.dispositivos) {
      final desde = vetorDoPar[dispositivo];
      if (nosso[dispositivo] <= desde) continue;

      final linhas = _db.select(
        'SELECT * FROM ops WHERE inventario_id = ? AND dispositivo = ? '
        'AND seq > ? ORDER BY seq LIMIT ?',
        [inventarioId, dispositivo, desde, limite - resultado.length],
      );
      resultado.addAll(linhas.map(Operacao.doBanco));
      if (resultado.length >= limite) break;
    }

    return resultado;
  }

  /// Contextos referenciados por um lote, para acompanhar as operações.
  ///
  /// Sem eles o par não consegue avaliar causalidade e trataria tudo como
  /// concorrente, gerando conflito falso a cada sincronização.
  Map<String, VersionVector> contextosDe(List<Operacao> ops) {
    final ids = ops.map((o) => o.ctxId).whereType<String>().toSet();
    if (ids.isEmpty) return const {};

    final marcadores = List.filled(ids.length, '?').join(',');
    final linhas = _db.select(
      'SELECT ctx_id, vetor FROM contextos WHERE ctx_id IN ($marcadores)',
      ids.toList(),
    );
    return {
      for (final l in linhas)
        l['ctx_id'] as String: VersionVector.decodificar(l['vetor'] as String),
    };
  }

  /// Histórico de alterações de um patrimônio, do mais recente ao mais antigo.
  List<Operacao> historicoDe(String patrimonioId) {
    final linhas = _db.select(
      'SELECT * FROM ops WHERE entidade_id = ? ORDER BY hlc DESC',
      [patrimonioId],
    );
    return linhas.map(Operacao.doBanco).toList();
  }

  /// Últimas alterações do inventário inteiro.
  List<Operacao> historicoDoInventario(
    String inventarioId, {
    int limite = 200,
  }) {
    final linhas = _db.select(
      'SELECT * FROM ops WHERE inventario_id = ? AND entidade = ? '
      'AND campo = ? ORDER BY hlc DESC LIMIT ?',
      [inventarioId, 'patrimonio', CampoPatrimonio.verificado, limite],
    );
    return linhas.map(Operacao.doBanco).toList();
  }
}
