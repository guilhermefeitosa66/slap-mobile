import 'package:sqlite3/sqlite3.dart';
import 'package:uuid/uuid.dart';

import '../../core/codigo.dart';
import '../../domain/divergencia.dart';
import '../../domain/patrimonio.dart';
import '../../domain/valores.dart';
import '../banco.dart';
import '../schema.dart';
import 'operacoes.dart';

const _uuid = Uuid();

/// Como o código lido foi encontrado — ou por que não foi.
enum ResultadoLeitura {
  /// Encontrado, ainda não verificado, e a verificação foi gravada.
  sucesso,

  /// Encontrado, mas já havia sido inventariado. Não é sobrescrito em
  /// silêncio: o SLAP exige confirmação explícita, e isso se preserva.
  jaVerificado,

  /// Nenhum patrimônio do inventário corresponde ao código.
  naoLocalizado,
}

/// O que aconteceu com uma leitura.
class Leitura {
  final ResultadoLeitura resultado;
  final Patrimonio? patrimonio;

  /// O número foi achado no *outro* campo: lido como tombo e encontrado no
  /// código de barras, ou o contrário.
  ///
  /// O item é registrado normalmente, mas o usuário fica sabendo que há
  /// inconsistência no cadastro. O SLAP nunca faz essa segunda tentativa, e é
  /// uma das causas mais comuns de falso "não localizado".
  final bool achadoNoOutroCampo;

  /// Mais de um patrimônio com o mesmo código no inventário. O SLAP escolhe um
  /// com `.first` e não avisa ninguém.
  final int duplicados;

  const Leitura({
    required this.resultado,
    this.patrimonio,
    this.achadoNoOutroCampo = false,
    this.duplicados = 0,
  });

  bool get temDuplicados => duplicados > 1;
}

/// Campo em que procurar primeiro.
enum ModoLeitura {
  tombo('Tombo'),
  codigoBarras('Código de barras');

  final String rotulo;
  const ModoLeitura(this.rotulo);
}

/// Valores aplicados automaticamente às próximas leituras.
///
/// É o mecanismo que dá a velocidade do SLAP: configura-se uma vez ao entrar
/// na sala e cada leitura seguinte não exige nenhum toque na tela.
class ConfiguracaoLevantamento {
  final String sala;
  final EstadoConservacao conservacao;
  final SituacaoUso situacao;

  /// Responsável novo. `null` mantém o do SUAP, reproduzindo a regra do
  /// `before_save` do SLAP.
  final String? responsavel;

  const ConfiguracaoLevantamento({
    required this.sala,
    this.conservacao = EstadoConservacao.bom,
    this.situacao = SituacaoUso.ativo,
    this.responsavel,
  });

  ConfiguracaoLevantamento copyWith({
    String? sala,
    EstadoConservacao? conservacao,
    SituacaoUso? situacao,
    String? responsavel,
    bool limparResponsavel = false,
  }) {
    return ConfiguracaoLevantamento(
      sala: sala ?? this.sala,
      conservacao: conservacao ?? this.conservacao,
      situacao: situacao ?? this.situacao,
      responsavel: limparResponsavel ? null : (responsavel ?? this.responsavel),
    );
  }
}

/// Linha de patrimônio pronta para importar.
class PatrimonioImportado {
  final String? ordem;
  final String tombo;
  final String? codigoBarras;
  final String? ed;
  final String? descricao;
  final String? responsavel;
  final String? sala;
  final String? valor;
  final EstadoConservacao? conservacao;
  final SituacaoUso? situacao;

  const PatrimonioImportado({
    required this.tombo,
    this.ordem,
    this.codigoBarras,
    this.ed,
    this.descricao,
    this.responsavel,
    this.sala,
    this.valor,
    this.conservacao,
    this.situacao,
  });
}

class RepositorioPatrimonios {
  final Banco banco;
  final RepositorioOperacoes ops;

  RepositorioPatrimonios(this.banco, this.ops);

  Database get _db => banco.db;

  // ------------------------------------------------------------- leitura ---

  /// Procura um patrimônio pelo código lido.
  ///
  /// Tenta primeiro o campo do modo selecionado e, se não achar, tenta o
  /// outro. Nenhuma chamada de rede participa disso: é acesso por índice no
  /// banco local, que é o que mantém o ritmo do levantamento.
  Leitura procurar({
    required String inventarioId,
    required String codigo,
    required ModoLeitura modo,
  }) {
    final chave = chaveBusca(codigo);
    if (chave.isEmpty) {
      return const Leitura(resultado: ResultadoLeitura.naoLocalizado);
    }

    final primeiro = modo == ModoLeitura.tombo
        ? 'tombo_chave'
        : 'codigo_barras_chave';
    final segundo = modo == ModoLeitura.tombo
        ? 'codigo_barras_chave'
        : 'tombo_chave';

    var linhas = _buscarPor(inventarioId, primeiro, chave);
    var cruzado = false;

    if (linhas.isEmpty) {
      linhas = _buscarPor(inventarioId, segundo, chave);
      cruzado = linhas.isNotEmpty;
    }

    if (linhas.isEmpty) {
      return const Leitura(resultado: ResultadoLeitura.naoLocalizado);
    }

    final p = _daLinha(linhas.first);
    return Leitura(
      resultado: p.verificado
          ? ResultadoLeitura.jaVerificado
          : ResultadoLeitura.sucesso,
      patrimonio: p,
      achadoNoOutroCampo: cruzado,
      duplicados: linhas.length,
    );
  }

  List<Row> _buscarPor(String inventarioId, String coluna, String chave) {
    return _db.select(
      'SELECT * FROM patrimonios WHERE inventario_id = ? AND $coluna = ? '
      // Itens fora do inventário por ED não devem "não ser localizados":
      // eles aparecem, mas o usuário é avisado de que estão excluídos.
      'ORDER BY ignorado, verificado DESC',
      [inventarioId, chave],
    ).toList();
  }

  Patrimonio? porId(String id) {
    final r = _db.select('SELECT * FROM patrimonios WHERE id = ?', [id]);
    return r.isEmpty ? null : _daLinha(r.first);
  }

  // ------------------------------------------------------------ gravação ---

  /// Grava a verificação de um patrimônio, aplicando a configuração corrente.
  ///
  /// Só registra os campos que de fato mudam. Gravar operação para valor
  /// idêntico incharia o log e faria a sincronização transferir ruído.
  Patrimonio registrarVerificacao({
    required Patrimonio patrimonio,
    required ConfiguracaoLevantamento config,
    String? usuarioNome,
    String? usuarioMatricula,
  }) {
    final campos = <String, String?>{};

    if (!patrimonio.verificado) campos[CampoPatrimonio.verificado] = '1';

    if (!mesmoTexto(patrimonio.salaAtual, config.sala)) {
      campos[CampoPatrimonio.salaAtual] = config.sala;
    }
    if (patrimonio.conservacao != config.conservacao) {
      campos[CampoPatrimonio.conservacao] = config.conservacao.valor;
    }
    if (patrimonio.situacao != config.situacao) {
      campos[CampoPatrimonio.situacao] = config.situacao.valor;
    }
    // Responsável em branco significa "não alterar": o original permanece.
    if (config.responsavel != null &&
        !mesmoTexto(patrimonio.responsavelAtual, config.responsavel)) {
      campos[CampoPatrimonio.responsavelAtual] = config.responsavel;
    }

    // Reverificar um item idêntico ainda precisa registrar a passagem, ou o
    // usuário não teria como saber que a leitura foi aceita.
    if (campos.isEmpty) campos[CampoPatrimonio.verificado] = '1';

    ops.registrarLocal(
      inventarioId: patrimonio.inventarioId,
      entidade: 'patrimonio',
      entidadeId: patrimonio.id,
      campos: campos,
      usuarioNome: usuarioNome,
      usuarioMatricula: usuarioMatricula,
    );

    return porId(patrimonio.id)!;
  }

  /// Desfaz a verificação de um item.
  ///
  /// Ao contrário do `undo` do SLAP, que apaga os campos sem deixar rastro, a
  /// reversão é ela mesma uma operação registrada e sincronizada.
  void desfazerVerificacao({
    required Patrimonio patrimonio,
    String? usuarioNome,
    String? usuarioMatricula,
  }) {
    ops.registrarLocal(
      inventarioId: patrimonio.inventarioId,
      entidade: 'patrimonio',
      entidadeId: patrimonio.id,
      campos: {
        CampoPatrimonio.verificado: '0',
        CampoPatrimonio.salaAtual: null,
        CampoPatrimonio.responsavelAtual: null,
        CampoPatrimonio.conservacao: null,
        CampoPatrimonio.situacao: null,
      },
      usuarioNome: usuarioNome,
      usuarioMatricula: usuarioMatricula,
    );
  }

  // ----------------------------------------------------------- importação ---

  /// Insere os patrimônios de uma planilha.
  ///
  /// Statement preparado dentro de uma transação única: dez mil linhas entram
  /// numa operação de disco, não em dez mil. O SLAP faz um `INSERT` por linha
  /// sem transação, depois de já ter apagado os itens anteriores — falha no
  /// meio deixa o inventário destruído pela metade.
  int inserirLote(String inventarioId, List<PatrimonioImportado> itens) {
    if (itens.isEmpty) return 0;

    return banco.transacao(() {
      final stmt = _db.prepare(
        'INSERT INTO patrimonios (id, inventario_id, ordem, tombo, codigo_barras, '
        'ed, descricao, responsavel_original, sala_original, valor, '
        'conservacao_original, situacao_original, tombo_chave, codigo_barras_chave) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      );

      try {
        for (final i in itens) {
          stmt.execute([
            _uuid.v4(),
            inventarioId,
            i.ordem,
            i.tombo,
            i.codigoBarras,
            i.ed,
            i.descricao,
            i.responsavel,
            i.sala,
            i.valor,
            i.conservacao?.valor,
            i.situacao?.valor,
            chaveBusca(i.tombo),
            i.codigoBarras == null ? null : chaveBusca(i.codigoBarras),
          ]);
        }
      } finally {
        stmt.close();
      }

      return itens.length;
    });
  }

  /// Insere patrimônios vindos de outro aparelho, preservando os
  /// identificadores de origem.
  ///
  /// O id precisa ser o mesmo em todas as réplicas: é ele que faz uma operação
  /// de outro aparelho encontrar o patrimônio certo aqui. Só os dados do SUAP
  /// vêm no pacote inicial — o levantamento chega depois, pelo log de
  /// operações, que é o que carrega a informação de ordem causal.
  int inserirRecebidos(List<Patrimonio> itens) {
    if (itens.isEmpty) return 0;

    return banco.transacao(() {
      final stmt = _db.prepare(
        'INSERT OR IGNORE INTO patrimonios (id, inventario_id, ordem, tombo, '
        'codigo_barras, ed, descricao, responsavel_original, sala_original, '
        'valor, conservacao_original, situacao_original, tombo_chave, '
        'codigo_barras_chave, ignorado) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      );

      try {
        for (final p in itens) {
          stmt.execute([
            p.id,
            p.inventarioId,
            p.ordem,
            p.tombo,
            p.codigoBarras,
            p.ed,
            p.descricao,
            p.responsavelOriginal,
            p.salaOriginal,
            p.valor,
            p.conservacaoOriginal?.valor,
            p.situacaoOriginal?.valor,
            chaveBusca(p.tombo),
            p.codigoBarras == null ? null : chaveBusca(p.codigoBarras),
            p.ignorado ? 1 : 0,
          ]);
        }
      } finally {
        stmt.close();
      }

      return itens.length;
    });
  }

  /// Tombos já presentes no inventário, para que a reimportação reconcilie em
  /// vez de duplicar ou apagar.
  Set<String> chavesExistentes(String inventarioId) {
    final linhas = _db.select(
      'SELECT tombo_chave FROM patrimonios WHERE inventario_id = ?',
      [inventarioId],
    );
    return {for (final l in linhas) l['tombo_chave'] as String};
  }

  // --------------------------------------------------------------- listas ---

  List<Patrimonio> listar({
    required String inventarioId,
    Classificacao? classificacao,
    String? sala,
    String? busca,
    int limite = 200,
    int deslocamento = 0,
  }) {
    final condicoes = <String>['inventario_id = ?'];
    final params = <Object?>[inventarioId];

    if (classificacao == Classificacao.ignorado) {
      condicoes.add('ignorado = 1');
    } else {
      condicoes.add('ignorado = 0');
      if (classificacao == Classificacao.naoLocalizado) {
        condicoes.add('verificado = 0');
      } else if (classificacao != null) {
        condicoes.add('verificado = 1');
      }
    }

    if (sala != null) {
      condicoes.add('sala_original = ?');
      params.add(sala);
    }

    if (busca != null && busca.trim().isNotEmpty) {
      final chave = chaveBusca(busca);
      condicoes.add(
        '(descricao LIKE ? OR tombo_chave LIKE ? OR codigo_barras_chave LIKE ?)',
      );
      params
        ..add('%${busca.trim()}%')
        ..add('$chave%')
        ..add('$chave%');
    }

    final linhas = _db.select(
      'SELECT * FROM patrimonios WHERE ${condicoes.join(' AND ')} '
      'ORDER BY CAST(ordem AS INTEGER), tombo_chave LIMIT ? OFFSET ?',
      [...params, limite, deslocamento],
    );

    var itens = linhas.map(_daLinha).toList();

    // OK e divergente não se distinguem em SQL: dependem da comparação com
    // acento e caixa normalizados, que é regra de domínio.
    if (classificacao == Classificacao.ok) {
      itens = itens.where((p) => divergenciasDe(p).isEmpty).toList();
    } else if (classificacao == Classificacao.divergente) {
      itens = itens.where((p) => divergenciasDe(p).isNotEmpty).toList();
    }

    return itens;
  }

  /// Todos os itens do inventário. Usado na geração de relatórios.
  List<Patrimonio> todos(String inventarioId, {bool incluirIgnorados = false}) {
    final linhas = _db.select(
      'SELECT * FROM patrimonios WHERE inventario_id = ? '
      '${incluirIgnorados ? '' : 'AND ignorado = 0'} '
      'ORDER BY CAST(ordem AS INTEGER), tombo_chave',
      [inventarioId],
    );
    return linhas.map(_daLinha).toList();
  }

  /// Salas conhecidas do inventário, para sugerir na configuração.
  ///
  /// Inclui as salas do SUAP e as que já foram usadas no levantamento — o
  /// SLAP só oferece as primeiras, o que impede inventariar numa sala nova.
  List<String> salas(String inventarioId) {
    final linhas = _db.select(
      'SELECT DISTINCT sala FROM ('
      '  SELECT sala_original AS sala FROM patrimonios WHERE inventario_id = ?1'
      '  UNION SELECT sala_atual FROM patrimonios WHERE inventario_id = ?1'
      ') WHERE sala IS NOT NULL AND TRIM(sala) <> "" ORDER BY sala',
      [inventarioId],
    );
    return [for (final l in linhas) l['sala'] as String];
  }

  /// Responsáveis conhecidos, escopados ao inventário.
  ///
  /// O SLAP esquece o escopo e mistura responsáveis de todos os inventários
  /// do banco.
  List<String> responsaveis(String inventarioId) {
    final linhas = _db.select(
      'SELECT DISTINCT r FROM ('
      '  SELECT responsavel_original AS r FROM patrimonios WHERE inventario_id = ?1'
      '  UNION SELECT responsavel_atual FROM patrimonios WHERE inventario_id = ?1'
      ') WHERE r IS NOT NULL AND TRIM(r) <> "" ORDER BY r',
      [inventarioId],
    );
    return [for (final l in linhas) l['r'] as String];
  }

  /// Elementos de despesa presentes, com a contagem de itens de cada um.
  ///
  /// É o que alimenta a escolha de EDs a ignorar. A lista vem do arquivo, e
  /// não de códigos fixos no app, para funcionar com qualquer versão da
  /// planilha do SUAP.
  Map<String, int> contagemPorEd(String inventarioId) {
    final linhas = _db.select(
      'SELECT COALESCE(ed, "") AS ed, COUNT(*) AS n FROM patrimonios '
      'WHERE inventario_id = ? GROUP BY ed ORDER BY n DESC',
      [inventarioId],
    );
    return {for (final l in linhas) l['ed'] as String: l['n'] as int};
  }

  /// Progresso do inventário.
  ///
  /// Os totais simples saem do banco; a separação entre OK e divergente
  /// percorre os verificados, porque depende da comparação de domínio.
  ProgressoInventario progresso(String inventarioId) {
    final r = _db.select(
      'SELECT '
      '  SUM(CASE WHEN ignorado = 0 THEN 1 ELSE 0 END) AS total, '
      '  SUM(CASE WHEN ignorado = 0 AND verificado = 1 THEN 1 ELSE 0 END) AS verificados, '
      '  SUM(CASE WHEN ignorado = 1 THEN 1 ELSE 0 END) AS ignorados '
      'FROM patrimonios WHERE inventario_id = ?',
      [inventarioId],
    );
    if (r.isEmpty) return ProgressoInventario.vazio;

    final total = (r.first['total'] as int?) ?? 0;
    final verificados = (r.first['verificados'] as int?) ?? 0;
    final ignorados = (r.first['ignorados'] as int?) ?? 0;

    var ok = 0;
    var divergentes = 0;
    final linhas = _db.select(
      'SELECT * FROM patrimonios WHERE inventario_id = ? AND ignorado = 0 AND verificado = 1',
      [inventarioId],
    );
    for (final l in linhas) {
      if (divergenciasDe(_daLinha(l)).isEmpty) {
        ok++;
      } else {
        divergentes++;
      }
    }

    return ProgressoInventario(
      total: total,
      verificados: verificados,
      naoLocalizados: total - verificados,
      ok: ok,
      divergentes: divergentes,
      ignorados: ignorados,
    );
  }

  // ---------------------------------------------------------------- mapa ---

  static Patrimonio _daLinha(Row r) => Patrimonio(
    id: r['id'] as String,
    inventarioId: r['inventario_id'] as String,
    ordem: r['ordem'] as String?,
    tombo: r['tombo'] as String,
    codigoBarras: r['codigo_barras'] as String?,
    ed: r['ed'] as String?,
    descricao: r['descricao'] as String?,
    responsavelOriginal: r['responsavel_original'] as String?,
    salaOriginal: r['sala_original'] as String?,
    valor: r['valor'] as String?,
    conservacaoOriginal: EstadoConservacao.de(
      r['conservacao_original'] as String?,
    ),
    situacaoOriginal: SituacaoUso.de(r['situacao_original'] as String?),
    ignorado: (r['ignorado'] as int) == 1,
    verificado: (r['verificado'] as int) == 1,
    salaAtual: r['sala_atual'] as String?,
    responsavelAtual: r['responsavel_atual'] as String?,
    conservacao: EstadoConservacao.de(r['conservacao'] as String?),
    situacao: SituacaoUso.de(r['situacao'] as String?),
    verificadoEm: r['verificado_em'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(r['verificado_em'] as int),
    verificadoPor: r['verificado_por'] as String?,
    verificadoPorMatricula: r['verificado_por_matricula'] as String?,
    verificadoPorDispositivo: r['verificado_por_dispositivo'] as String?,
  );
}
