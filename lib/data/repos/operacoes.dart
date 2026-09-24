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

/// Dois aparelhos escrevendo com o mesmo `dispositivo_id`.
///
/// Acontece quando os dados do aplicativo são copiados de um celular para
/// outro por fora dele — backup do sistema, cópia de pastas. A numeração das
/// operações deixa de identificar quem escreveu o quê, e a sincronização é
/// recusada para não misturar as duas histórias. Ver
/// `docs/copia-de-seguranca.md`.
class IdentidadeDuplicada implements Exception {
  final String dispositivo;

  /// A identidade duplicada é a deste aparelho.
  final bool esteAparelho;

  IdentidadeDuplicada(this.dispositivo, {required this.esteAparelho});

  @override
  String toString() => esteAparelho
      ? 'Outro aparelho está usando a identidade deste. Isso acontece quando '
            'os dados do aplicativo são copiados de um celular para outro. A '
            'sincronização foi recusada para não misturar o trabalho dos dois.'
      : 'Dois aparelhos estão usando a mesma identidade '
            '(${dispositivo.substring(0, 6)}). Isso acontece quando os dados '
            'do aplicativo são copiados de um celular para outro. A '
            'sincronização foi recusada para não misturar o trabalho dos dois.';
}

/// Trabalho deste aparelho que ainda não está em nenhum outro.
class TrabalhoNaoEntregue {
  /// Algum outro aparelho já sincronizou este inventário com este.
  final bool jaSincronizou;

  /// Operações deste aparelho que nenhum par confirmou ter.
  final int operacoes;

  /// Itens verificados por este aparelho cuja verificação nenhum par tem.
  final int verificacoes;

  const TrabalhoNaoEntregue({
    required this.jaSincronizou,
    required this.operacoes,
    required this.verificacoes,
  });

  bool get nada => operacoes == 0;
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
    final noLog = r.first['s'] as int;
    // Se a réplica foi apagada, a numeração continua de onde parou: os pares
    // ainda guardam as operações antigas, e reusar um número faria a nova
    // ser tomada pela velha.
    final piso =
        int.tryParse(banco.lerConfig(Config.seqMinimo(inventarioId)) ?? '') ??
        0;
    return (noLog > piso ? noLog : piso) + 1;
  }

  /// A última operação que este aparelho tem de cada aparelho do inventário.
  ///
  /// Vai junto nos pedidos de sincronização para o par conferir que, na mesma
  /// posição da sequência de um aparelho, os dois têm a mesma operação. Se não
  /// têm, dois aparelhos escreveram com a mesma identidade — e o vetor, que só
  /// conta posições, não perceberia.
  Map<String, ({int seq, String opId})> cabecas(String inventarioId) {
    final linhas = _db.select(
      'SELECT o.dispositivo, o.seq, o.op_id FROM ops o '
      'JOIN (SELECT dispositivo, MAX(seq) AS s FROM ops '
      '      WHERE inventario_id = ?1 GROUP BY dispositivo) m '
      'ON m.dispositivo = o.dispositivo AND m.s = o.seq '
      'WHERE o.inventario_id = ?1',
      [inventarioId],
    );
    return {
      for (final l in linhas)
        l['dispositivo'] as String: (
          seq: l['seq'] as int,
          opId: l['op_id'] as String,
        ),
    };
  }

  /// Lança [IdentidadeDuplicada] se o par tem, em alguma posição que também
  /// temos, uma operação diferente da nossa.
  void conferirCabecas(
    String inventarioId,
    Map<String, ({int seq, String opId})> doPar,
  ) {
    for (final MapEntry(key: dispositivo, value: cabeca) in doPar.entries) {
      final nossa = _db.select(
        'SELECT op_id FROM ops WHERE inventario_id = ? AND dispositivo = ? '
        'AND seq = ?',
        [inventarioId, dispositivo, cabeca.seq],
      );
      if (nossa.isNotEmpty && nossa.first['op_id'] != cabeca.opId) {
        throw IdentidadeDuplicada(
          dispositivo,
          esteAparelho: dispositivo == dispositivoId,
        );
      }
    }
  }

  /// O que este aparelho tem do inventário, para pedir a um par o que falta.
  ///
  /// Igual a [vetorDe], exceto pela entrada deste aparelho, que só conta a
  /// parte contígua da sequência. Depois de apagar a réplica e voltar a
  /// escrever, as operações antigas deste aparelho faltam no começo; pedir
  /// pelo máximo faria o par achar que já temos tudo, e elas nunca voltariam.
  VersionVector vetorParaPedido(String inventarioId) {
    final vetor = vetorDe(inventarioId);
    final maximo = vetor[dispositivoId];
    if (maximo == 0) return vetor;

    final quantas =
        _db.select(
              'SELECT COUNT(*) AS n FROM ops '
              'WHERE inventario_id = ? AND dispositivo = ?',
              [inventarioId, dispositivoId],
            ).first['n']
            as int;
    if (quantas == maximo) return vetor;

    var contiguo = 0;
    for (final l in _db.select(
      'SELECT seq FROM ops WHERE inventario_id = ? AND dispositivo = ? '
      'ORDER BY seq',
      [inventarioId, dispositivoId],
    )) {
      if (l['seq'] != contiguo + 1) break;
      contiguo++;
    }
    return VersionVector({
      for (final d in vetor.dispositivos) d: vetor[d],
      dispositivoId: contiguo,
    });
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
        final jaTemos = _db.select(
          'SELECT op_id FROM ops WHERE inventario_id = ? AND dispositivo = ? AND seq = ?',
          [op.inventarioId, op.dispositivo, op.seq],
        );
        if (jaTemos.isNotEmpty) {
          // A mesma posição na sequência de um aparelho com outra operação:
          // dois aparelhos estão escrevendo com a mesma identidade. Aceitar
          // misturaria as duas histórias sem ninguém perceber.
          if (jaTemos.first['op_id'] != op.opId) {
            throw IdentidadeDuplicada(
              op.dispositivo,
              esteAparelho: op.dispositivo == dispositivoId,
            );
          }
          ignoradas++;
          continue;
        }

        // Operação deste próprio aparelho que não está aqui: a réplica foi
        // apagada e o histórico está voltando pelos pares, ou por uma cópia
        // de segurança. Entra como qualquer outra.

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
        _encerrarConflitosSuperados(op);
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

  /// Encerra os conflitos do campo que [op] superou.
  ///
  /// Quem escreveu conhecendo as duas escritas concorrentes já decidiu — seja
  /// pela tela de conflitos, seja relendo o item. É o que faz uma resolução
  /// valer em todas as réplicas: sem isto, o conflito seguiria pendente em
  /// todo aparelho que não fosse o de quem resolveu.
  void _encerrarConflitosSuperados(Operacao op) {
    final pendentes = _db.select(
      'SELECT c.id, v.dispositivo AS vd, v.seq AS vs, '
      'p.dispositivo AS pd, p.seq AS ps FROM conflitos c '
      'JOIN ops v ON v.op_id = c.op_vencedora '
      'JOIN ops p ON p.op_id = c.op_perdedora '
      'WHERE c.patrimonio_id = ? AND c.campo = ? AND c.resolvido_em IS NULL',
      [op.entidadeId, op.campo],
    );
    if (pendentes.isEmpty) return;

    final conhecia = contexto(op.ctxId).com(op.dispositivo, op.seq);
    for (final c in pendentes) {
      if (conhecia.conhece(c['vd'] as String, c['vs'] as int) &&
          conhecia.conhece(c['pd'] as String, c['ps'] as int)) {
        _db.execute(
          'UPDATE conflitos SET resolvido_em = ?, resolvido_por_op = ? '
          'WHERE id = ?',
          [DateTime.now().millisecondsSinceEpoch, op.opId, c['id']],
        );
      }
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

  /// Aplica um campo do inventário, se a operação for a mais nova dele.
  ///
  /// Last-writer-wins pelo HLC, igual em todas as réplicas. Operação antiga
  /// chegando depois fica no log e não altera nada — é o que impede, por
  /// exemplo, um aparelho que sincronizou tarde de reabrir um inventário
  /// encerrado.
  void _aplicarCampoInventario(Operacao op) {
    const permitidos = {'nome', 'ano', 'eds_excluidos', 'encerrado_em'};
    if (!permitidos.contains(op.campo)) return;

    final vigente = _db.select(
      'SELECT hlc FROM campos_inventario WHERE inventario_id = ? AND campo = ?',
      [op.entidadeId, op.campo],
    );
    if (vigente.isNotEmpty &&
        Hlc.decodificar(vigente.first['hlc'] as String) >= op.hlc) {
      return;
    }

    _db.execute(
      'INSERT INTO campos_inventario (inventario_id, campo, valor, hlc, op_id) '
      'VALUES (?,?,?,?,?) ON CONFLICT(inventario_id, campo) DO UPDATE SET '
      'valor = excluded.valor, hlc = excluded.hlc, op_id = excluded.op_id',
      [op.entidadeId, op.campo, op.valor, op.hlc.codificar(), op.opId],
    );
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

  // ------------------------------------------------------------------ pares ---

  /// Registra um encontro com outro aparelho neste inventário.
  ///
  /// [nossoSeq] é até onde as operações *deste* aparelho estão comprovadamente
  /// no par — o que ele declarou ter, ou o que aceitou num envio. Só cresce:
  /// um encontro não desfaz o que o anterior entregou.
  void registrarPar(
    String dispositivo,
    String inventarioId, {
    int nossoSeq = 0,
    String? usuarioNome,
  }) {
    _db.execute(
      'INSERT INTO pares (dispositivo, inventario_id, usuario_nome, '
      'ultima_sync, nosso_seq) VALUES (?,?,?,?,?) '
      'ON CONFLICT(dispositivo, inventario_id) DO UPDATE SET '
      'ultima_sync = excluded.ultima_sync, '
      'usuario_nome = COALESCE(excluded.usuario_nome, pares.usuario_nome), '
      'nosso_seq = MAX(pares.nosso_seq, excluded.nosso_seq)',
      [
        dispositivo,
        inventarioId,
        usuarioNome,
        DateTime.now().millisecondsSinceEpoch,
        nossoSeq,
      ],
    );
  }

  /// O que se perde apagando a réplica local: o trabalho deste aparelho que
  /// nenhum outro recebeu.
  ///
  /// Conservador de propósito — conta como não entregue o que o par ainda
  /// não confirmou ter. Avisar a mais custa uma pergunta; avisar a menos
  /// custa o levantamento de um dia.
  TrabalhoNaoEntregue trabalhoNaoEntregue(String inventarioId) {
    final par = _db.select(
      'SELECT COUNT(*) AS n, COALESCE(MAX(nosso_seq), 0) AS s FROM pares '
      'WHERE inventario_id = ?',
      [inventarioId],
    ).first;
    final entregue = par['s'] as int;

    final operacoes =
        _db.select(
              'SELECT COUNT(*) AS n FROM ops '
              'WHERE inventario_id = ? AND dispositivo = ? AND seq > ?',
              [inventarioId, dispositivoId, entregue],
            ).first['n']
            as int;

    final verificacoes =
        _db.select(
              'SELECT COUNT(*) AS n FROM campos_patrimonio c '
              'JOIN patrimonios p ON p.id = c.patrimonio_id '
              'WHERE p.inventario_id = ? AND c.campo = ? AND c.valor = ? '
              'AND c.dispositivo = ? AND c.seq > ?',
              [
                inventarioId,
                CampoPatrimonio.verificado,
                '1',
                dispositivoId,
                entregue,
              ],
            ).first['n']
            as int;

    return TrabalhoNaoEntregue(
      jaSincronizou: (par['n'] as int) > 0,
      operacoes: operacoes,
      verificacoes: verificacoes,
    );
  }

  /// Quando este aparelho leu um patrimônio pela última vez neste inventário.
  ///
  /// Serve para perceber que a pessoa voltou depois de horas — no dia
  /// seguinte, talvez em outra sala. Vem da marca gravada a cada leitura, e
  /// não do log: reabrir o inventário ou resolver um conflito de manhã também
  /// gravam operações, e esconderiam a volta.
  ///
  /// Bancos gravados antes da marca não a têm. Na primeira consulta ela vem
  /// do log, das operações de patrimônio deste aparelho — leituras, mas
  /// também edições e desfazer, só desta vez. Vazia fica gravada como '', para
  /// não voltar ao log.
  DateTime? ultimaLeituraLocal(String inventarioId) {
    final chave = Config.ultimaLeitura(inventarioId);
    var texto = banco.lerConfig(chave);
    if (texto == null) {
      final m =
          _db.select(
                'SELECT MAX(criado_em) AS m FROM ops '
                'WHERE inventario_id = ? AND dispositivo = ? '
                "AND entidade = 'patrimonio'",
                [inventarioId, dispositivoId],
              ).first['m']
              as int?;
      texto = m?.toString() ?? '';
      banco.gravarConfig(chave, texto);
    }
    final m = int.tryParse(texto);
    return m == null ? null : DateTime.fromMillisecondsSinceEpoch(m);
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
