import 'package:slap_mobile/core/hlc.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/patrimonio.dart';

/// Um aparelho participante, com banco próprio em memória.
///
/// Cada instância tem o seu `dispositivo_id`, gerado na abertura do banco,
/// exatamente como aconteceria em celulares diferentes.
class Aparelho {
  final String apelido;
  final Banco banco;
  late final RepositorioOperacoes ops;
  late final RepositorioPatrimonios patrimonios;
  late final RepositorioInventarios inventarios;

  Aparelho(this.apelido) : banco = Banco.emMemoria() {
    _ligar();
  }

  /// Aparelho que abre um banco já existente, identidade incluída.
  Aparelho.deArquivo(this.apelido, String caminho)
    : banco = Banco.abrirSincrono(caminho) {
    _ligar();
  }

  void _ligar() {
    ops = RepositorioOperacoes(banco);
    patrimonios = RepositorioPatrimonios(banco, ops);
    inventarios = RepositorioInventarios(banco, ops);
    banco.gravarConfig('usuario_nome', apelido);
  }

  String get dispositivoId => banco.dispositivoId;

  void fechar() => banco.fechar();
}

/// Rede local simulada: troca as operações direto entre os repositórios,
/// sem HTTP.
///
/// Testa a convergência e a detecção de conflito isoladamente do transporte —
/// que é onde a lógica difícil mora.
class RedeSimulada {
  /// Uma sincronização completa entre dois aparelhos: cada lado puxa do outro.
  static void sincronizar(Aparelho a, Aparelho b, String inventarioId) {
    _puxar(de: a, para: b, inventarioId: inventarioId);
    _puxar(de: b, para: a, inventarioId: inventarioId);
  }

  static int _puxar({
    required Aparelho de,
    required Aparelho para,
    required String inventarioId,
  }) {
    // Cada lado confere as cabeças do outro, como na rede de verdade.
    de.ops.conferirCabecas(inventarioId, para.ops.cabecas(inventarioId));
    para.ops.conferirCabecas(inventarioId, de.ops.cabecas(inventarioId));

    // O pedido leva o vetor e as lacunas, como na rede de verdade.
    final faltantes = de.ops.opsFaltantes(
      inventarioId,
      para.ops.vetorDe(inventarioId),
      lacunas: para.ops.lacunasDe(inventarioId),
    );
    if (faltantes.isNotEmpty) {
      para.ops.aplicarRemotas(
        faltantes,
        inventarioId: inventarioId,
        contextos: de.ops.contextosDe(faltantes),
      );
    }

    // Como o cliente e o servidor de verdade: cada lado anota até onde o
    // trabalho dele está inteiro no outro — sem passar da primeira lacuna.
    de.ops.registrarPar(
      para.dispositivoId,
      inventarioId,
      nossoSeq: _entregueA(para, de, inventarioId),
    );
    para.ops.registrarPar(
      de.dispositivoId,
      inventarioId,
      nossoSeq: _entregueA(de, para, inventarioId),
    );
    return faltantes.length;
  }

  /// Até onde a sequência de [autor] está inteira em [quem].
  static int _entregueA(Aparelho quem, Aparelho autor, String inventarioId) =>
      autor.ops.seqEntregueA(
        inventarioId,
        maximoDoPar: quem.ops.vetorDe(inventarioId)[autor.dispositivoId],
        lacunasDoPar: quem.ops.lacunasDe(inventarioId)[autor.dispositivoId],
      );

  /// Quantas operações seriam transferidas, sem transferir nada. Usado para
  /// verificar que a sincronização é mesmo incremental.
  static int pendentesEntre(Aparelho de, Aparelho para, String inventarioId) {
    return de.ops
        .opsFaltantes(
          inventarioId,
          para.ops.vetorDe(inventarioId),
          lacunas: para.ops.lacunasDe(inventarioId),
        )
        .length;
  }

  /// Distribui o inventário e os patrimônios do criador para os demais,
  /// como faria o pacote inicial transferido pela rede.
  static void distribuir(
    Aparelho origem,
    List<Aparelho> destinos,
    Inventario inventario,
  ) {
    final itens = origem.patrimonios.todos(
      inventario.id,
      incluirIgnorados: true,
    );
    for (final destino in destinos) {
      destino.inventarios.registrarRecebido(inventario);
      destino.patrimonios.inserirRecebidos(itens);
    }
  }
}

/// Escreve no log de [aparelho] uma faixa de operações atribuídas a
/// [dispositivo], como se elas tivessem chegado dele.
///
/// Serve aos casos de volume — milhares de operações acima de um buraco na
/// numeração —, em que simular leitura a leitura só tornaria o teste lento
/// sem tornar o cenário mais fiel. O identificador e o relógio saem do par
/// (aparelho, número), então a mesma operação plantada em dois aparelhos é
/// idêntica nos dois, como seria se tivesse viajado pela rede.
void plantarOperacoes(
  Aparelho aparelho, {
  required String inventarioId,
  required String dispositivo,
  required String patrimonioId,
  required int de,
  required int ate,
  String campo = 'sala_atual',
  String valor = 'Almoxarifado',
  String usuario = 'Plantada',
  int baseMillis = 1700000000000,
}) {
  final comando = aparelho.banco.db.prepare(
    'INSERT OR IGNORE INTO ops (op_id, inventario_id, entidade, entidade_id, '
    'campo, valor, hlc, dispositivo, seq, ctx_id, usuario_nome, '
    'usuario_matricula, criado_em) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
  );
  try {
    aparelho.banco.transacao(() {
      for (var seq = de; seq <= ate; seq++) {
        comando.execute([
          '$dispositivo-$seq',
          inventarioId,
          'patrimonio',
          patrimonioId,
          campo,
          valor,
          Hlc(baseMillis + seq, 0, dispositivo).codificar(),
          dispositivo,
          seq,
          null,
          usuario,
          null,
          baseMillis + seq,
        ]);
      }
    });
  } finally {
    comando.close();
  }
}

/// Estado observável de um patrimônio, para comparar réplicas entre si.
String impressaoDe(Aparelho aparelho, String patrimonioId) {
  final p = aparelho.patrimonios.porId(patrimonioId);
  if (p == null) return 'ausente';
  return [
    'verificado=${p.verificado}',
    'sala=${p.salaAtual}',
    'responsavel=${p.responsavelAtual}',
    'conservacao=${p.conservacao?.valor}',
    'situacao=${p.situacao?.valor}',
  ].join(' ');
}

/// Patrimônio de teste, com apenas os campos que importam ao caso.
Patrimonio patrimonioDeTeste({
  required String id,
  required String inventarioId,
  required String tombo,
  String? codigoBarras,
  String? sala,
  String? responsavel,
  String? ed,
}) {
  return Patrimonio(
    id: id,
    inventarioId: inventarioId,
    tombo: tombo,
    codigoBarras: codigoBarras ?? tombo,
    ed: ed,
    descricao: 'Item $tombo',
    salaOriginal: sala,
    responsavelOriginal: responsavel,
  );
}
