import 'package:sqlite3/sqlite3.dart';

import '../../core/hlc.dart';
import '../../domain/valores.dart';
import '../banco.dart';
import '../schema.dart';
import 'operacoes.dart';

/// Uma alteração concorrente pendente de decisão.
///
/// O LWW já escolheu um vencedor e o banco está consistente — o conflito não
/// bloqueia ninguém. Ele existe para que a pessoa certa confira o caso em vez
/// de o sistema decidir em silêncio.
class Conflito {
  final String id;
  final String inventarioId;
  final String patrimonioId;
  final String campo;

  /// A operação que prevaleceu e a que foi preterida.
  final Operacao vencedora;
  final Operacao perdedora;

  final DateTime criadoEm;
  final DateTime? resolvidoEm;

  /// Dados do patrimônio, para a tela não precisar consultar outra tabela.
  final String tombo;
  final String? descricao;

  const Conflito({
    required this.id,
    required this.inventarioId,
    required this.patrimonioId,
    required this.campo,
    required this.vencedora,
    required this.perdedora,
    required this.criadoEm,
    required this.tombo,
    this.descricao,
    this.resolvidoEm,
  });

  bool get resolvido => resolvidoEm != null;

  /// Nome do campo como aparece para o usuário.
  String get rotuloCampo => switch (campo) {
        CampoPatrimonio.salaAtual => 'Sala',
        CampoPatrimonio.responsavelAtual => 'Responsável',
        CampoPatrimonio.conservacao => 'Estado de conservação',
        CampoPatrimonio.situacao => 'Situação de uso',
        CampoPatrimonio.verificado => 'Verificação',
        _ => campo,
      };

  String rotuloValor(String? valor) {
    if (valor == null || valor.isEmpty) return '(vazio)';
    return switch (campo) {
      CampoPatrimonio.conservacao => EstadoConservacao.de(valor)?.rotulo ?? valor,
      CampoPatrimonio.situacao => SituacaoUso.de(valor)?.rotulo ?? valor,
      CampoPatrimonio.verificado => valor == '1' ? 'Verificado' : 'Não verificado',
      _ => valor,
    };
  }

  String get valorMantido => rotuloValor(vencedora.valor);
  String get valorPreterido => rotuloValor(perdedora.valor);
}

class RepositorioConflitos {
  final Banco banco;
  final RepositorioOperacoes ops;

  RepositorioConflitos(this.banco, this.ops);

  Database get _db => banco.db;

  int contarPendentes(String inventarioId) {
    final r = _db.select(
      'SELECT COUNT(*) AS n FROM conflitos '
      'WHERE inventario_id = ? AND resolvido_em IS NULL',
      [inventarioId],
    );
    return r.first['n'] as int;
  }

  List<Conflito> listar(String inventarioId, {bool apenasPendentes = true}) {
    final linhas = _db.select(
      'SELECT c.*, p.tombo, p.descricao, '
      '  ov.valor AS v_valor, ov.hlc AS v_hlc, ov.dispositivo AS v_disp, '
      '  ov.seq AS v_seq, ov.ctx_id AS v_ctx, ov.usuario_nome AS v_nome, '
      '  ov.usuario_matricula AS v_mat, ov.criado_em AS v_em, '
      '  ov.entidade AS v_ent, ov.entidade_id AS v_ent_id, ov.campo AS v_campo, '
      '  op.valor AS p_valor, op.hlc AS p_hlc, op.dispositivo AS p_disp, '
      '  op.seq AS p_seq, op.ctx_id AS p_ctx, op.usuario_nome AS p_nome, '
      '  op.usuario_matricula AS p_mat, op.criado_em AS p_em, '
      '  op.entidade AS p_ent, op.entidade_id AS p_ent_id, op.campo AS p_campo '
      'FROM conflitos c '
      'JOIN patrimonios p ON p.id = c.patrimonio_id '
      'JOIN ops ov ON ov.op_id = c.op_vencedora '
      'JOIN ops op ON op.op_id = c.op_perdedora '
      'WHERE c.inventario_id = ? '
      '${apenasPendentes ? 'AND c.resolvido_em IS NULL' : ''} '
      'ORDER BY c.criado_em DESC',
      [inventarioId],
    );

    return [for (final l in linhas) _daLinha(l)];
  }

  /// Registra a decisão do usuário.
  ///
  /// Grava uma operação nova em vez de alterar as antigas. Por construção ela
  /// domina causalmente as duas em disputa, então o conflito se encerra
  /// sozinho em todas as réplicas na próxima sincronização — sem ninguém
  /// precisar resolver o mesmo caso duas vezes.
  void resolver({
    required Conflito conflito,
    required String? valorEscolhido,
    String? usuarioNome,
    String? usuarioMatricula,
  }) {
    banco.transacao(() {
      final geradas = ops.registrarLocal(
        inventarioId: conflito.inventarioId,
        entidade: 'patrimonio',
        entidadeId: conflito.patrimonioId,
        campos: {conflito.campo: valorEscolhido},
        usuarioNome: usuarioNome,
        usuarioMatricula: usuarioMatricula,
      );

      _db.execute(
        'UPDATE conflitos SET resolvido_em = ?, resolvido_por_op = ? WHERE id = ?',
        [
          DateTime.now().millisecondsSinceEpoch,
          geradas.isEmpty ? null : geradas.first.opId,
          conflito.id,
        ],
      );
    });
  }

  /// Marca como resolvidos todos os conflitos de um inventário, mantendo o
  /// valor que já prevaleceu.
  ///
  /// É a saída para quem conferiu a lista e concluiu que as escolhas
  /// automáticas estavam certas. Não gera operação: nada muda de valor.
  void aceitarTodos(String inventarioId) {
    _db.execute(
      'UPDATE conflitos SET resolvido_em = ? '
      'WHERE inventario_id = ? AND resolvido_em IS NULL',
      [DateTime.now().millisecondsSinceEpoch, inventarioId],
    );
  }

  static Conflito _daLinha(Row r) {
    Operacao op(String prefixo) => Operacao(
          opId: r[prefixo == 'v' ? 'op_vencedora' : 'op_perdedora'] as String,
          inventarioId: r['inventario_id'] as String,
          entidade: r['${prefixo}_ent'] as String,
          entidadeId: r['${prefixo}_ent_id'] as String,
          campo: r['${prefixo}_campo'] as String,
          valor: r['${prefixo}_valor'] as String?,
          hlc: Hlc.decodificar(r['${prefixo}_hlc'] as String),
          dispositivo: r['${prefixo}_disp'] as String,
          seq: r['${prefixo}_seq'] as int,
          ctxId: r['${prefixo}_ctx'] as String?,
          usuarioNome: r['${prefixo}_nome'] as String?,
          usuarioMatricula: r['${prefixo}_mat'] as String?,
          criadoEm: r['${prefixo}_em'] as int,
        );

    return Conflito(
      id: r['id'] as String,
      inventarioId: r['inventario_id'] as String,
      patrimonioId: r['patrimonio_id'] as String,
      campo: r['campo'] as String,
      vencedora: op('v'),
      perdedora: op('p'),
      criadoEm: DateTime.fromMillisecondsSinceEpoch(r['criado_em'] as int),
      resolvidoEm: r['resolvido_em'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(r['resolvido_em'] as int),
      tombo: r['tombo'] as String,
      descricao: r['descricao'] as String?,
    );
  }
}
