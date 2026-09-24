/// Esquema do banco local.
///
/// Princípio: o **log de operações é a fonte da verdade**. A tabela
/// `patrimonios` é cache materializado, reconstruível a partir de `ops`.
/// Isso faz sincronização incremental, registro de alterações e auditoria
/// serem a mesma estrutura, em vez de três mecanismos concorrentes.
library;

const int versaoEsquema = 4;

/// Campos de patrimônio que o levantamento altera.
///
/// Cada um converge de forma independente na sincronização: duas pessoas
/// podem alterar campos diferentes do mesmo item sem que isso seja conflito.
class CampoPatrimonio {
  static const verificado = 'verificado';
  static const salaAtual = 'sala_atual';
  static const responsavelAtual = 'responsavel_atual';
  static const conservacao = 'conservacao';
  static const situacao = 'situacao';

  static const todos = [
    verificado,
    salaAtual,
    responsavelAtual,
    conservacao,
    situacao,
  ];
}

/// Versão 1: o esquema inicial.
const List<String> ddlEsquema = [
  '''
  CREATE TABLE inventarios (
    id                 TEXT    PRIMARY KEY,
    nome               TEXT    NOT NULL,
    ano                INTEGER NOT NULL,
    criado_em          INTEGER NOT NULL,
    dispositivo_origem TEXT    NOT NULL,
    -- Segredo compartilhado por QR code. Autentica a sincronização: quem não
    -- tem a chave não lê nem escreve neste inventário.
    chave_sync         TEXT    NOT NULL,
    -- JSON com os EDs que o usuário escolheu ignorar na importação.
    eds_excluidos      TEXT    NOT NULL DEFAULT '[]',
    encerrado_em       INTEGER
  )
  ''',

  '''
  CREATE TABLE patrimonios (
    id            TEXT PRIMARY KEY,
    inventario_id TEXT NOT NULL REFERENCES inventarios(id) ON DELETE CASCADE,

    -- ---- Original do SUAP: imutável depois da importação ----
    ordem                TEXT,
    tombo                TEXT NOT NULL,
    codigo_barras        TEXT,
    ed                   TEXT,
    descricao            TEXT,
    responsavel_original TEXT,
    sala_original        TEXT,
    valor                TEXT,
    -- Removidas na versão 4: esses campos nunca vêm da planilha.
    conservacao_original TEXT,
    situacao_original    TEXT,

    -- Formas normalizadas, usadas só na busca. Fazem -19281, 19281 e 019281
    -- casarem entre si sem que o valor exibido deixe de ser o do cadastro.
    tombo_chave         TEXT NOT NULL,
    codigo_barras_chave TEXT,

    ignorado INTEGER NOT NULL DEFAULT 0,

    -- ---- Cache do levantamento: derivado de campos_patrimonio ----
    verificado                 INTEGER NOT NULL DEFAULT 0,
    sala_atual                 TEXT,
    responsavel_atual          TEXT,
    conservacao                TEXT,
    situacao                   TEXT,
    verificado_em              INTEGER,
    verificado_por             TEXT,
    verificado_por_matricula   TEXT,
    verificado_por_dispositivo TEXT
  )
  ''',

  // O caminho quente: toda leitura de patrimônio é um acesso por estes dois
  // índices. É o que mantém a busca imperceptível com dezenas de milhares de
  // itens, sem rede no caminho.
  'CREATE INDEX idx_patr_tombo   ON patrimonios(inventario_id, tombo_chave)',
  'CREATE INDEX idx_patr_barras  ON patrimonios(inventario_id, codigo_barras_chave)',
  'CREATE INDEX idx_patr_estado  ON patrimonios(inventario_id, ignorado, verificado)',
  'CREATE INDEX idx_patr_sala    ON patrimonios(inventario_id, sala_original)',

  '''
  -- Valor vencedor de cada campo, com a procedência que permite decidir o
  -- próximo confronto sem reprocessar o log inteiro.
  CREATE TABLE campos_patrimonio (
    patrimonio_id TEXT NOT NULL,
    campo         TEXT NOT NULL,
    valor         TEXT,
    hlc           TEXT NOT NULL,
    op_id         TEXT NOT NULL,
    dispositivo   TEXT NOT NULL,
    seq           INTEGER NOT NULL,
    ctx_id        TEXT,
    PRIMARY KEY (patrimonio_id, campo)
  ) WITHOUT ROWID
  ''',

  '''
  -- O log. Imutável: nada aqui é alterado ou apagado, só acrescentado.
  CREATE TABLE ops (
    op_id            TEXT    PRIMARY KEY,
    inventario_id    TEXT    NOT NULL,
    entidade         TEXT    NOT NULL,
    entidade_id      TEXT    NOT NULL,
    campo            TEXT    NOT NULL,
    valor            TEXT,
    hlc              TEXT    NOT NULL,
    dispositivo      TEXT    NOT NULL,
    -- Numeração monotônica por (dispositivo, inventário). É o que a version
    -- vector conta, e o que torna a sincronização incremental.
    seq              INTEGER NOT NULL,
    ctx_id           TEXT,
    usuario_nome     TEXT,
    usuario_matricula TEXT,
    criado_em        INTEGER NOT NULL
  )
  ''',

  // Garante idempotência: receber a mesma operação duas vezes não a duplica.
  'CREATE UNIQUE INDEX idx_ops_origem ON ops(inventario_id, dispositivo, seq)',
  'CREATE INDEX idx_ops_entidade ON ops(entidade_id, campo, hlc)',
  'CREATE INDEX idx_ops_inventario ON ops(inventario_id, criado_em)',

  '''
  -- Contextos causais deduplicados.
  --
  -- Cada operação precisa saber o que o autor já conhecia ao escrever. Guardar
  -- a version vector inteira em cada operação seria caro, mas só a parte
  -- remota importa (a local é o próprio seq) e ela só muda quando ocorre uma
  -- sincronização. Resultado: uma linha por sincronização, não por operação.
  CREATE TABLE contextos (
    ctx_id TEXT PRIMARY KEY,
    vetor  TEXT NOT NULL
  ) WITHOUT ROWID
  ''',

  '''
  CREATE TABLE pares (
    dispositivo   TEXT NOT NULL,
    inventario_id TEXT NOT NULL,
    usuario_nome  TEXT,
    ultima_sync   INTEGER,
    PRIMARY KEY (dispositivo, inventario_id)
  ) WITHOUT ROWID
  ''',

  '''
  -- Alterações genuinamente concorrentes: duas pessoas mudaram o mesmo campo
  -- do mesmo patrimônio sem que nenhuma conhecesse a escrita da outra.
  --
  -- O LWW já deixou o banco consistente, então o conflito não bloqueia
  -- ninguém: fica pendente para o usuário decidir.
  CREATE TABLE conflitos (
    id               TEXT PRIMARY KEY,
    inventario_id    TEXT NOT NULL,
    patrimonio_id    TEXT NOT NULL,
    campo            TEXT NOT NULL,
    op_vencedora     TEXT NOT NULL,
    op_perdedora     TEXT NOT NULL,
    resolvido_por_op TEXT,
    resolvido_em     INTEGER,
    criado_em        INTEGER NOT NULL
  )
  ''',

  'CREATE INDEX idx_conflitos_pendentes ON conflitos(inventario_id, resolvido_em)',
  // Um mesmo par de operações concorrentes só gera um conflito, mesmo que a
  // sincronização se repita.
  'CREATE UNIQUE INDEX idx_conflitos_par ON conflitos(patrimonio_id, campo, op_vencedora, op_perdedora)',

  '''
  -- Parte remota da version vector corrente de cada inventário: o que este
  -- aparelho já recebeu dos outros.
  CREATE TABLE estado_sync (
    inventario_id TEXT PRIMARY KEY,
    ctx_id        TEXT NOT NULL
  ) WITHOUT ROWID
  ''',

  '''
  -- Identidade local e relógio. Chave/valor porque é meia dúzia de campos
  -- que mudam raramente.
  CREATE TABLE config (
    chave TEXT PRIMARY KEY,
    valor TEXT NOT NULL
  ) WITHOUT ROWID
  ''',
];

/// Versão 2: valor vencedor de cada campo do inventário.
///
/// Até a v1, operação sobre o inventário era aplicada sem comparar com o
/// valor em vigor: uma operação antiga chegando depois — de um aparelho que
/// sincronizou tarde — desfazia uma mais nova. Com o encerramento, isso
/// reabriria um inventário encerrado. Aqui fica o HLC do vencedor, e só
/// operação mais nova altera o campo (last-writer-wins, como nos patrimônios,
/// mas sem registro de conflito: não há o que a pessoa decidir).
const List<String> migracaoV2 = [
  '''
  CREATE TABLE campos_inventario (
    inventario_id TEXT NOT NULL,
    campo         TEXT NOT NULL,
    valor         TEXT,
    hlc           TEXT NOT NULL,
    op_id         TEXT NOT NULL,
    PRIMARY KEY (inventario_id, campo)
  ) WITHOUT ROWID
  ''',
  // O vencedor de cada campo já está no log: é a operação de maior HLC.
  '''
  INSERT INTO campos_inventario (inventario_id, campo, valor, hlc, op_id)
  SELECT o.entidade_id, o.campo, o.valor, o.hlc, o.op_id
  FROM ops o
  WHERE o.entidade = 'inventario'
    AND o.hlc = (
      SELECT MAX(o2.hlc) FROM ops o2
      WHERE o2.entidade = 'inventario'
        AND o2.entidade_id = o.entidade_id
        AND o2.campo = o.campo
    )
  ''',
];

/// Versão 3: até onde as operações deste aparelho chegaram a cada par.
///
/// Apagar a réplica local só é seguro se o trabalho feito aqui já estiver em
/// outro aparelho. Com isto dá para dizer, na confirmação, quanto se perde.
const List<String> migracaoV3 = [
  'ALTER TABLE pares ADD COLUMN nosso_seq INTEGER NOT NULL DEFAULT 0',
];

/// Versão 4: fora as colunas de origem de estado de conservação e situação
/// de uso.
///
/// Elas recebiam o que a planilha trouxesse com esse nome. Mas os dois campos
/// são levantados em campo, nunca importados: a exportação do SUAP tem uma
/// coluna `ESTADO DE CONSERVAÇÃO` com outro vocabulário, e lida como origem
/// ela inventava divergência. Sem origem, o levantado é informação nova. As
/// colunas somem para que nada volte a lê-las ou escrevê-las por engano; o
/// resto da linha fica intacto. (`DROP COLUMN` existe desde o SQLite 3.35; o
/// `package:sqlite3` embute uma versão bem mais nova.)
const List<String> migracaoV4 = [
  'ALTER TABLE patrimonios DROP COLUMN conservacao_original',
  'ALTER TABLE patrimonios DROP COLUMN situacao_original',
];

/// Migrações por versão de destino. Um banco novo passa por todas, em ordem:
/// é o mesmo caminho de quem atualiza, e por isso é o caminho testado.
const Map<int, List<String>> migracoes = {
  1: ddlEsquema,
  2: migracaoV2,
  3: migracaoV3,
  4: migracaoV4,
};

/// Chaves da tabela `config`.
class Config {
  /// UUID gerado na primeira execução. Imutável: é a identidade do aparelho
  /// no sistema distribuído e o desempate final dos conflitos.
  static const dispositivoId = 'dispositivo_id';

  static const usuarioNome = 'usuario_nome';
  static const usuarioMatricula = 'usuario_matricula';

  /// Último HLC emitido. Global ao aparelho, e não por inventário, para que o
  /// relógio nunca ande para trás.
  static const hlcLocal = 'hlc_local';

  /// Configuração corrente do levantamento de um inventário, em JSON.
  ///
  /// Sobrevive ao Android encerrar o aplicativo — o que acontece com a
  /// câmera aberta em aparelho com pouca memória. É preferência do aparelho,
  /// não dado do inventário: não sincroniza.
  static String configuracaoLevantamento(String inventarioId) =>
      'levantamento.$inventarioId';

  /// Maior número de operação deste aparelho num inventário cuja réplica foi
  /// apagada. A numeração continua daí se o inventário voltar.
  static String seqMinimo(String inventarioId) => 'seq_minimo.$inventarioId';

  /// Maior número de operação deste aparelho que já saiu daqui num inventário
  /// — entregue a um par ou gravado numa cópia de segurança.
  ///
  /// É o limite do que ainda pode ser re-estampado quando o relógio estava
  /// errado (ver `RepositorioOperacoes.reestamparOperacoesDoFuturo`). Conta
  /// o que saiu, e não o que o par confirmou ter: a confirmação vem uma
  /// sincronização atrasada, e reescrever uma operação que já está na mão de
  /// outro aparelho criaria duas versões da mesma operação.
  static String seqEnviado(String inventarioId) => 'seq_enviado.$inventarioId';

  /// Momento da última leitura gravada por este aparelho num inventário, em
  /// milissegundos. Só leitura conta: reabrir o inventário, resolver conflito
  /// ou desfazer uma verificação não mostram que a pessoa está na sala.
  /// Vazia: nenhuma leitura, já conferido no log.
  static String ultimaLeitura(String inventarioId) =>
      'ultima_leitura.$inventarioId';

  /// Inventário cujo levantamento estava aberto. O aplicativo reabre nele.
  static const levantamentoAberto = 'levantamento_aberto';

  // Preferências do aparelho, gravadas como '1' ou '0'. Ausente vale o padrão.

  /// Manter a tela ligada no levantamento e na câmera. Padrão: sim.
  static const manterTelaLigada = 'pref_tela_ligada';

  /// Som de retorno das leituras. Padrão: sim.
  static const sons = 'pref_sons';

  /// Vibração de retorno das leituras. Padrão: sim.
  static const vibracao = 'pref_vibracao';
}
