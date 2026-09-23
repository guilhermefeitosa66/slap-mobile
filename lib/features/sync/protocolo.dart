import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../core/version_vector.dart';
import '../../data/repos/inventarios.dart';
import '../../data/repos/operacoes.dart';
import '../../domain/patrimonio.dart';
import '../../domain/valores.dart';

/// Tipo de serviço anunciado por mDNS. O primeiro rótulo precisa ter no
/// máximo 15 caracteres, por especificação (RFC 6335).
const String tipoServico = '_slap-sync._tcp';

/// Endereço e porta do beacon UDP, usado quando o mDNS falha.
const String enderecoMulticast = '239.7.7.7';
const int portaMulticast = 47771;

/// Versão do protocolo. Aparelhos com versões diferentes se recusam a
/// sincronizar, em vez de trocarem dados que um dos lados interpreta errado.
const int versaoProtocolo = 1;

/// Janela de tolerância da assinatura. Limita a repetição de uma requisição
/// capturada na rede.
const Duration janelaAssinatura = Duration(minutes: 5);

class Rotas {
  static const hello = '/hello';
  static const pull = '/sync/pull';
  static const push = '/sync/push';
  static const pacote = '/inventario/pacote';
}

/// Assinatura das requisições de sincronização.
///
/// Toda requisição autenticada carrega um HMAC-SHA256 da chave do inventário
/// sobre método, caminho, horário e conteúdo. Quem não tem a chave não lê nem
/// escreve, e uma requisição capturada não pode ser alterada nem repetida fora
/// da janela de tempo.
///
/// **Limite assumido:** o corpo trafega em claro. Na rede local, quem estiver
/// autenticado nela e capturando pacotes consegue ler dados patrimoniais.
/// Não há credencial no tráfego, e o alcance é o segmento local. Cifrar o
/// corpo está no roteiro; ver `docs/02-arquitetura.md`, seção 5.9.
class Assinatura {
  static const _prefixo = 'SLAP';

  static String gerar({
    required String chaveSync,
    required String dispositivoId,
    required String metodo,
    required String caminho,
    required String corpo,
    DateTime? agora,
  }) {
    final momento = (agora ?? DateTime.now()).millisecondsSinceEpoch;
    final mac = _calcular(chaveSync, metodo, caminho, corpo, momento);
    return '$_prefixo $dispositivoId:$momento:$mac';
  }

  /// Valida o cabeçalho e devolve o id do aparelho remoto, ou `null` quando a
  /// assinatura não confere.
  static String? verificar({
    required String? cabecalho,
    required String chaveSync,
    required String metodo,
    required String caminho,
    required String corpo,
    DateTime? agora,
  }) {
    final conferencia = conferir(
      cabecalho: cabecalho,
      chaveSync: chaveSync,
      metodo: metodo,
      caminho: caminho,
      corpo: corpo,
      agora: agora,
    );
    return conferencia.valida ? conferencia.dispositivoId : null;
  }

  /// Confere o cabeçalho distinguindo assinatura errada de relógio errado.
  ///
  /// A distinção importa porque os dois casos pedem coisas diferentes a quem
  /// está com o celular na mão. Com a chave certa e o horário fora da janela,
  /// o problema é o relógio de um dos aparelhos — e dizer "o aparelho recusou
  /// a conexão" mandaria a pessoa procurar defeito no QR code.
  ///
  /// O HMAC é conferido antes do horário: só quem tem a chave fica sabendo que
  /// o problema é o relógio.
  static ConferenciaAssinatura conferir({
    required String? cabecalho,
    required String chaveSync,
    required String metodo,
    required String caminho,
    required String corpo,
    DateTime? agora,
  }) {
    const invalida = ConferenciaAssinatura._(SituacaoAssinatura.invalida);

    if (cabecalho == null || !cabecalho.startsWith('$_prefixo ')) {
      return invalida;
    }

    final partes = cabecalho.substring(_prefixo.length + 1).split(':');
    if (partes.length != 3) return invalida;

    final dispositivoId = partes[0];
    final momento = int.tryParse(partes[1]);
    final recebido = partes[2];
    if (momento == null) return invalida;

    final esperado = _calcular(chaveSync, metodo, caminho, corpo, momento);

    // Comparação de tempo constante: comparar com `==` vazaria, pelo tempo de
    // resposta, quantos bytes iniciais do HMAC um atacante acertou.
    if (!_iguaisEmTempoConstante(esperado, recebido)) return invalida;

    final diferenca =
        ((agora ?? DateTime.now()).millisecondsSinceEpoch - momento).abs();
    if (diferenca > janelaAssinatura.inMilliseconds) {
      return ConferenciaAssinatura._(
        SituacaoAssinatura.foraDaJanela,
        dispositivoId: dispositivoId,
        momento: momento,
      );
    }

    return ConferenciaAssinatura._(
      SituacaoAssinatura.valida,
      dispositivoId: dispositivoId,
      momento: momento,
    );
  }

  static String _calcular(
    String chaveSync,
    String metodo,
    String caminho,
    String corpo,
    int momento,
  ) {
    final resumoCorpo = sha256.convert(utf8.encode(corpo)).toString();
    final mensagem = '$metodo\n$caminho\n$momento\n$resumoCorpo';
    final hmac = Hmac(sha256, base64Url.decode(chaveSync));
    return base64Url.encode(hmac.convert(utf8.encode(mensagem)).bytes);
  }

  static bool _iguaisEmTempoConstante(String a, String b) {
    if (a.length != b.length) return false;
    var diferenca = 0;
    for (var i = 0; i < a.length; i++) {
      diferenca |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diferenca == 0;
  }
}

enum SituacaoAssinatura {
  valida,
  invalida,

  /// Assinada com a chave certa, mas com horário longe demais do deste
  /// aparelho: um dos relógios está errado (ou é uma requisição repetida).
  foraDaJanela,
}

class ConferenciaAssinatura {
  final SituacaoAssinatura situacao;
  final String? dispositivoId;

  /// Horário que o remetente pôs na assinatura, em milissegundos.
  final int? momento;

  const ConferenciaAssinatura._(
    this.situacao, {
    this.dispositivoId,
    this.momento,
  });

  bool get valida => situacao == SituacaoAssinatura.valida;
}

/// Resposta de erro para relógio fora de sincronia, em qualquer rota.
///
/// Leva o horário de quem responde, para que o outro lado saiba de quanto é a
/// diferença e qual aparelho mostrar como adiantado ou atrasado.
class ErroRelogio {
  static const codigo = 'relogio';

  /// Horário de quem respondeu, em milissegundos.
  final int agora;

  /// Aparelho cujas operações vieram com relógio no futuro, quando o problema
  /// foi detectado no conteúdo, e não na assinatura. Pode ser um terceiro,
  /// cujas operações chegaram por intermédio do par.
  final String? dispositivo;

  /// Quanto o relógio de [dispositivo] está à frente, em milissegundos.
  final int? diferencaMs;

  const ErroRelogio({required this.agora, this.dispositivo, this.diferencaMs});

  Map<String, dynamic> toJson() => {
    'erro': codigo,
    'agora': agora,
    'dispositivo': ?dispositivo,
    'diferenca_ms': ?diferencaMs,
  };

  static ErroRelogio? fromJson(Map<String, dynamic> j) {
    if (j['erro'] != codigo || j['agora'] is! num) return null;
    return ErroRelogio(
      agora: (j['agora'] as num).toInt(),
      dispositivo: j['dispositivo'] as String?,
      diferencaMs: (j['diferenca_ms'] as num?)?.toInt(),
    );
  }
}

/// Identificação devolvida por `/hello`.
///
/// Não é autenticada, porque serve para o aparelho aparecer na lista antes de
/// qualquer chave ser conferida. Por isso não revela quais inventários o
/// aparelho tem: quem quer saber precisa da chave e pergunta por um inventário
/// específico.
class Apresentacao {
  final String dispositivoId;
  final String? usuarioNome;
  final int versao;

  /// Relógio de quem se apresenta, em milissegundos. Permite conferir os
  /// relógios antes de trocar qualquer operação. `null` em aparelho antigo,
  /// que não informava.
  final int? agora;

  const Apresentacao({
    required this.dispositivoId,
    this.usuarioNome,
    this.versao = versaoProtocolo,
    this.agora,
  });

  Map<String, dynamic> toJson() => {
    'dispositivo': dispositivoId,
    'usuario': usuarioNome,
    'versao': versao,
    'agora': ?agora,
  };

  factory Apresentacao.fromJson(Map<String, dynamic> j) => Apresentacao(
    dispositivoId: j['dispositivo'] as String,
    usuarioNome: j['usuario'] as String?,
    versao: (j['versao'] as num?)?.toInt() ?? 0,
    agora: (j['agora'] as num?)?.toInt(),
  );
}

/// Pedido de operações que faltam.
class PedidoPull {
  final String inventarioId;
  final VersionVector vetor;

  const PedidoPull({required this.inventarioId, required this.vetor});

  Map<String, dynamic> toJson() => {
    'inventario': inventarioId,
    'vetor': vetor.codificar(),
  };

  factory PedidoPull.fromJson(Map<String, dynamic> j) => PedidoPull(
    inventarioId: j['inventario'] as String,
    vetor: VersionVector.decodificar(j['vetor'] as String?),
  );
}

/// Lote de operações, com os contextos causais que elas referenciam.
///
/// Os contextos precisam viajar junto: sem eles o outro lado não consegue
/// avaliar causalidade e trataria tudo como concorrente, gerando conflito
/// falso a cada sincronização.
class LoteOperacoes {
  final String inventarioId;
  final List<Operacao> ops;
  final Map<String, VersionVector> contextos;

  /// Version vector de quem está respondendo.
  ///
  /// Vai junto para que uma única viagem resolva os dois sentidos: quem pediu
  /// recebe o que lhe falta e, de quebra, fica sabendo exatamente o que o
  /// outro lado já tem, podendo enviar só a diferença em seguida.
  final VersionVector vetor;

  const LoteOperacoes({
    required this.inventarioId,
    required this.ops,
    this.contextos = const {},
    this.vetor = VersionVector.vazia,
  });

  Map<String, dynamic> toJson() => {
    'inventario': inventarioId,
    'ops': [for (final o in ops) o.toJson()],
    'contextos': {
      for (final e in contextos.entries) e.key: e.value.codificar(),
    },
    'vetor': vetor.codificar(),
  };

  factory LoteOperacoes.fromJson(Map<String, dynamic> j) => LoteOperacoes(
    inventarioId: j['inventario'] as String,
    ops: [
      for (final o in (j['ops'] as List))
        Operacao.fromJson(o as Map<String, dynamic>),
    ],
    contextos: {
      for (final e in (j['contextos'] as Map? ?? {}).entries)
        e.key as String: VersionVector.decodificar(e.value as String),
    },
    vetor: VersionVector.decodificar(j['vetor'] as String?),
  );
}

/// Réplica inicial de um inventário.
///
/// Leva o inventário e os dados do SUAP. O levantamento **não** vem aqui: ele
/// chega pelo log de operações, que é o que carrega a informação de ordem
/// causal necessária para detectar conflito depois.
class PacoteInventario {
  final Inventario inventario;
  final List<Patrimonio> patrimonios;

  const PacoteInventario({required this.inventario, required this.patrimonios});

  Map<String, dynamic> toJson() => {
    'inventario': {
      'id': inventario.id,
      'nome': inventario.nome,
      'ano': inventario.ano,
      'criado_em': inventario.criadoEm.millisecondsSinceEpoch,
      'dispositivo_origem': inventario.dispositivoOrigem,
      'chave_sync': inventario.chaveSync,
      'eds_excluidos': inventario.edsExcluidos,
    },
    'patrimonios': [
      for (final p in patrimonios)
        {
          'id': p.id,
          'ordem': p.ordem,
          'tombo': p.tombo,
          'codigo_barras': p.codigoBarras,
          'ed': p.ed,
          'descricao': p.descricao,
          'responsavel': p.responsavelOriginal,
          'sala': p.salaOriginal,
          'valor': p.valor,
          'conservacao': p.conservacaoOriginal?.valor,
          'situacao': p.situacaoOriginal?.valor,
          'ignorado': p.ignorado,
        },
    ],
  };

  factory PacoteInventario.fromJson(Map<String, dynamic> j) {
    final inv = j['inventario'] as Map<String, dynamic>;
    final inventario = Inventario(
      id: inv['id'] as String,
      nome: inv['nome'] as String,
      ano: (inv['ano'] as num).toInt(),
      criadoEm: DateTime.fromMillisecondsSinceEpoch(
        (inv['criado_em'] as num).toInt(),
      ),
      dispositivoOrigem: inv['dispositivo_origem'] as String,
      chaveSync: inv['chave_sync'] as String,
      edsExcluidos: [
        for (final e in (inv['eds_excluidos'] as List? ?? [])) e.toString(),
      ],
    );

    return PacoteInventario(
      inventario: inventario,
      patrimonios: [
        for (final p in (j['patrimonios'] as List))
          Patrimonio(
            id: p['id'] as String,
            inventarioId: inventario.id,
            ordem: p['ordem'] as String?,
            tombo: p['tombo'] as String,
            codigoBarras: p['codigo_barras'] as String?,
            ed: p['ed'] as String?,
            descricao: p['descricao'] as String?,
            responsavelOriginal: p['responsavel'] as String?,
            salaOriginal: p['sala'] as String?,
            valor: p['valor'] as String?,
            conservacaoOriginal: EstadoConservacao.de(
              p['conservacao'] as String?,
            ),
            situacaoOriginal: SituacaoUso.de(p['situacao'] as String?),
            ignorado: p['ignorado'] as bool? ?? false,
          ),
      ],
    );
  }
}

/// Conteúdo do QR code que dá entrada num inventário.
///
/// A câmera já é permissão do projeto, então ela também resolve o pareamento:
/// quem escaneia recebe a chave, encontra o par na rede e puxa o pacote
/// inicial. Responde de uma vez quem participa, como a réplica chega ao
/// aparelho e como autorizar a sincronização.
class ConviteInventario {
  final String inventarioId;
  final String nome;
  final int ano;
  final String chaveSync;

  const ConviteInventario({
    required this.inventarioId,
    required this.nome,
    required this.ano,
    required this.chaveSync,
  });

  factory ConviteInventario.de(Inventario inv) => ConviteInventario(
    inventarioId: inv.id,
    nome: inv.nome,
    ano: inv.ano,
    chaveSync: inv.chaveSync,
  );

  String codificar() => jsonEncode({
    'v': versaoProtocolo,
    'id': inventarioId,
    'n': nome,
    'a': ano,
    'k': chaveSync,
  });

  /// Lê um convite. Devolve `null` quando o QR não é deste aplicativo — é o
  /// caso comum de apontar a câmera para qualquer outro código.
  static ConviteInventario? decodificar(String texto) {
    try {
      final j = jsonDecode(texto) as Map<String, dynamic>;
      if (j['v'] == null || j['id'] == null || j['k'] == null) return null;
      return ConviteInventario(
        inventarioId: j['id'] as String,
        nome: j['n'] as String? ?? 'Inventário',
        ano: (j['a'] as num?)?.toInt() ?? DateTime.now().year,
        chaveSync: j['k'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
