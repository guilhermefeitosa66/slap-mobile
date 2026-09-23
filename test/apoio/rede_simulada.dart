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
    final faltantes = de.ops.opsFaltantes(
      inventarioId,
      para.ops.vetorDe(inventarioId),
    );
    if (faltantes.isNotEmpty) {
      para.ops.aplicarRemotas(
        faltantes,
        contextos: de.ops.contextosDe(faltantes),
      );
    }

    // Como o cliente e o servidor de verdade: cada lado anota até onde o
    // trabalho dele está no outro.
    final deEmPara = para.ops.vetorDe(inventarioId)[de.dispositivoId];
    final paraEmDe = de.ops.vetorDe(inventarioId)[para.dispositivoId];
    de.ops.registrarPar(para.dispositivoId, inventarioId, nossoSeq: deEmPara);
    para.ops.registrarPar(de.dispositivoId, inventarioId, nossoSeq: paraEmDe);
    return faltantes.length;
  }

  /// Quantas operações seriam transferidas, sem transferir nada. Usado para
  /// verificar que a sincronização é mesmo incremental.
  static int pendentesEntre(Aparelho de, Aparelho para, String inventarioId) {
    return de.ops
        .opsFaltantes(inventarioId, para.ops.vetorDe(inventarioId))
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
