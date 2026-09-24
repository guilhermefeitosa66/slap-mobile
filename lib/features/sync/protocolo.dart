import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../../core/version_vector.dart';
import '../../data/repos/inventarios.dart';
import '../../data/repos/operacoes.dart';
import '../../domain/patrimonio.dart';
import 'cifra.dart';

/// Tipo de serviço anunciado por mDNS. O primeiro rótulo precisa ter no
/// máximo 15 caracteres, por especificação (RFC 6335).
const String tipoServico = '_slap-sync._tcp';

/// Endereço e porta do beacon UDP, usado quando o mDNS falha.
const String enderecoMulticast = '239.7.7.7';
const int portaMulticast = 47771;

/// Versão do protocolo. Aparelhos com versões diferentes se recusam a
/// sincronizar, em vez de trocarem dados que um dos lados interpreta errado.
///
/// 2: corpo cifrado (AES-GCM), chaves derivadas por HKDF, inventário na query
/// e cabeças nos pedidos.
const int versaoProtocolo = 2;

/// Cabeçalho com a versão do protocolo de quem pede.
const String cabecalhoVersao = 'x-slap-versao';

/// Explicação para quando as versões do protocolo não batem.
String mensagemVersaoDiferente({required String quem, required int versao}) =>
    '$quem usa uma versão '
    '${versao < versaoProtocolo ? 'anterior' : 'mais nova'} do aplicativo '
    '(protocolo $versao; este usa $versaoProtocolo). Atualize os dois '
    'aparelhos para a mesma versão e sincronize de novo.';

/// Janela de tolerância da assinatura. Limita a repetição de uma requisição
/// capturada na rede.
const Duration janelaAssinatura = Duration(minutes: 5);

class Rotas {
  static const hello = '/hello';
  static const pull = '/sync/pull';
  static const push = '/sync/push';
  static const pacote = '/inventario/pacote';

  /// Pedido de entrada num inventário. É a única rota que **não** é assinada:
  /// quem pede ainda não tem a chave — é justamente o que está pedindo.
  static const pedido = '/inventario/pedido';
}

/// Assinatura das requisições de sincronização.
///
/// Toda requisição autenticada carrega um HMAC-SHA256 da chave do inventário
/// sobre método, caminho, horário e conteúdo. Quem não tem a chave não lê nem
/// escreve, e uma requisição capturada não pode ser alterada nem repetida fora
/// da janela de tempo.
///
/// A assinatura cobre o corpo como ele trafega — cifrado (ver [CifraSync]) —,
/// e usa uma chave derivada da `chave_sync`, e não ela mesma. Ver
/// `docs/02-arquitetura.md`, seção 5.9.
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
    final chave = hkdfSha256(
      base64Url.decode(chaveSync),
      info: utf8.encode(CifraSync.infoAssinatura),
    );
    final hmac = Hmac(sha256, chave);
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

/// Resposta de erro para dois aparelhos escrevendo com a mesma identidade.
///
/// Vai estruturada, e não como frase pronta, porque **a frase depende de quem
/// lê**. Quem recusa diz "outro aparelho está usando a identidade deste"
/// pensando na identidade *dele*; repetido tal e qual no outro lado, isso
/// manda o aparelho honesto tocar em "Gerar nova identidade" e apagar o
/// trabalho que ainda não entregou. Com o identificador do aparelho duplicado
/// na resposta, cada lado monta a frase do ponto de vista dele.
///
/// O campo `erro` continua existindo, com um texto neutro que serve aos dois
/// casos: é o que uma versão anterior do aplicativo mostra, e ela não tem como
/// saber deste formato.
class ErroIdentidade {
  static const codigo = 'identidade';

  /// Aparelho cuja identidade está duplicada.
  final String dispositivo;

  const ErroIdentidade(this.dispositivo);

  Map<String, dynamic> toJson() => {
    'erro': IdentidadeDuplicada(dispositivo, esteAparelho: false).toString(),
    'tipo': codigo,
    'dispositivo': dispositivo,
  };

  static ErroIdentidade? fromJson(Map<String, dynamic> j) {
    final dispositivo = j['dispositivo'];
    if (j['tipo'] != codigo || dispositivo is! String || dispositivo.isEmpty) {
      return null;
    }
    return ErroIdentidade(dispositivo);
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

/// Última operação conhecida de cada aparelho: `{aparelho: (seq, op_id)}`.
///
/// Permite ao outro lado conferir que a mesma posição tem a mesma operação —
/// é como se percebe dois aparelhos escrevendo com a mesma identidade.
typedef Cabecas = Map<String, ({int seq, String opId})>;

Map<String, dynamic> _cabecasParaJson(Cabecas cabecas) => {
  for (final e in cabecas.entries) e.key: '${e.value.seq}:${e.value.opId}',
};

Cabecas _cabecasDeJson(Object? j) {
  if (j is! Map) return const {};
  final cabecas = <String, ({int seq, String opId})>{};
  for (final e in j.entries) {
    final texto = e.value;
    if (texto is! String) continue;
    final corte = texto.indexOf(':');
    final seq = corte < 0 ? null : int.tryParse(texto.substring(0, corte));
    if (seq == null) continue;
    cabecas[e.key as String] = (seq: seq, opId: texto.substring(corte + 1));
  }
  return cabecas;
}

/// Pedido de operações que faltam.
class PedidoPull {
  final String inventarioId;
  final VersionVector vetor;

  /// O que falta abaixo do máximo de cada aparelho (ver [Lacunas]).
  ///
  /// Vai junto com o vetor porque ele sozinho não distingue "tenho as cem
  /// primeiras de B" de "tenho da 51 à 100" — e é essa diferença que decide se
  /// um intervalo perdido volta ou fica faltando para sempre. Ausente em
  /// aparelho com versão anterior do aplicativo, que não as declarava.
  final Lacunas lacunas;

  final Cabecas cabecas;

  const PedidoPull({
    required this.inventarioId,
    required this.vetor,
    this.lacunas = Lacunas.vazia,
    this.cabecas = const {},
  });

  Map<String, dynamic> toJson() => {
    'inventario': inventarioId,
    'vetor': vetor.codificar(),
    'lacunas': lacunas.codificar(),
    'cabecas': _cabecasParaJson(cabecas),
  };

  factory PedidoPull.fromJson(Map<String, dynamic> j) => PedidoPull(
    inventarioId: j['inventario'] as String,
    vetor: VersionVector.decodificar(j['vetor'] as String?),
    lacunas: Lacunas.decodificar(j['lacunas']),
    cabecas: _cabecasDeJson(j['cabecas']),
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

  /// O que falta a quem envia, abaixo do máximo de cada aparelho.
  ///
  /// Acompanha [vetor] pelo mesmo motivo: com ela, quem recebe o lote de um
  /// `pull` já sabe, no `push` seguinte, não só o que está acima do que o
  /// outro conhece mas também o que ficou faltando no meio.
  final Lacunas lacunas;

  /// Última operação que quem envia tem de cada aparelho (ver [Cabecas]).
  final Cabecas cabecas;

  const LoteOperacoes({
    required this.inventarioId,
    required this.ops,
    this.contextos = const {},
    this.vetor = VersionVector.vazia,
    this.lacunas = Lacunas.vazia,
    this.cabecas = const {},
  });

  Map<String, dynamic> toJson() => {
    'inventario': inventarioId,
    'ops': [for (final o in ops) o.toJson()],
    'contextos': {
      for (final e in contextos.entries) e.key: e.value.codificar(),
    },
    'vetor': vetor.codificar(),
    'lacunas': lacunas.codificar(),
    'cabecas': _cabecasParaJson(cabecas),
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
    lacunas: Lacunas.decodificar(j['lacunas']),
    cabecas: _cabecasDeJson(j['cabecas']),
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

// ------------------------------------------------- entrada por link (#55) ---

/// Endereço do site do projeto, onde mora a página de reserva do link.
const String hostSite = 'guilhermefeitosa66.github.io';

/// Caminho do convite no site. É o `pathPrefix` do App Link no manifesto.
const String caminhoEntrar = '/slap-mobile/entrar';

/// Esquema próprio, reserva de quando o Android não verificou o App Link.
const String esquemaProprio = 'slapmobile';

/// Rota interna que recebe o convite, para os dois formatos de link.
const String rotaEntrar = '/entrar';

/// Convite que viaja por link, sem a chave do inventário.
///
/// **O link não dá acesso a nada.** Ele diz qual é o inventário, como se
/// chama e em qual aparelho está; a chave de sincronização só é entregue
/// depois que quem compartilha aceita o pedido de entrada. Um link
/// encaminhado por engano, ou reencaminhado a quem não devia, não abre o
/// inventário de ninguém.
///
/// O endereço é o do site do projeto (App Link), e não um esquema próprio,
/// porque assim quem recebe o link sem o aplicativo instalado cai numa página
/// que explica o que é e oferece o APK — um `slapmobile://` daria erro no
/// navegador.
///
/// Os dados vão no **fragmento** (`#`), e não na query: o fragmento nunca é
/// enviado ao servidor. Mesmo que o link seja aberto no navegador, o GitHub
/// Pages não vê o identificador do inventário nem o nome do campus nos
/// registros dele. A leitura também aceita os mesmos parâmetros na query, para
/// o caso de um aplicativo de mensagens reescrever o endereço pelo caminho.
class ConviteLink {
  final String inventarioId;
  final String nome;
  final int ano;

  /// Aparelho que compartilhou — é a ele que o pedido de entrada é enviado.
  final String? dispositivoOrigem;

  const ConviteLink({
    required this.inventarioId,
    required this.nome,
    required this.ano,
    this.dispositivoOrigem,
  });

  factory ConviteLink.de(Inventario inv, {required String dispositivo}) =>
      ConviteLink(
        inventarioId: inv.id,
        nome: inv.nome,
        ano: inv.ano,
        dispositivoOrigem: dispositivo,
      );

  String get titulo => '$nome — $ano';

  /// O link que vai na folha de compartilhamento do sistema.
  String codificar() => 'https://$hostSite$caminhoEntrar#${_parametros()}';

  /// A mesma informação no esquema próprio, reserva do App Link.
  String codificarEsquemaProprio() =>
      '$esquemaProprio://entrar#${_parametros()}';

  String _parametros() {
    final partes = <String, String>{
      'v': '$versaoProtocolo',
      'id': inventarioId,
      'n': nome,
      'a': '$ano',
      'd': ?dispositivoOrigem,
    };
    return [
      for (final e in partes.entries)
        '${e.key}=${Uri.encodeQueryComponent(e.value)}',
    ].join('&');
  }

  /// Lê um convite de qualquer um dos endereços possíveis.
  ///
  /// Aceita o endereço completo do site, o esquema próprio e a rota que o
  /// go_router entrega ao aplicativo (`/slap-mobile/entrar#…` com o
  /// aplicativo fechado, `/entrar#…` pelo esquema próprio). Devolve `null`
  /// quando o endereço não é um convite — abrir um link qualquer no aplicativo
  /// é o caso comum, e não é erro.
  static ConviteLink? decodificar(String endereco) {
    try {
      return deUri(Uri.parse(endereco.trim()));
    } on FormatException {
      return null;
    }
  }

  /// Como [decodificar], a partir de um [Uri] já montado — é o que o
  /// go_router entrega em `GoRouterState.uri`.
  static ConviteLink? deUri(Uri uri) {
    if (!_ehEntrada(uri)) return null;

    // Fragmento primeiro, query depois: o fragmento é o lugar certo, a query
    // é tolerância a quem reescreve o endereço no caminho.
    final fragmento = _fragmentoBruto(uri);
    final campos = <String, String>{
      ...uri.queryParameters,
      ...fragmento.isEmpty
          ? const <String, String>{}
          : Uri.splitQueryString(fragmento),
    };

    final id = campos['id'];
    if (campos['v'] == null || id == null || id.isEmpty) return null;

    return ConviteLink(
      inventarioId: id,
      nome: campos['n']?.trim().isNotEmpty == true
          ? campos['n']!.trim()
          : 'Inventário',
      ano: int.tryParse(campos['a'] ?? '') ?? DateTime.now().year,
      dispositivoOrigem: campos['d']?.isNotEmpty == true ? campos['d'] : null,
    );
  }

  /// O fragmento como ele veio, ainda codificado.
  ///
  /// `Uri.fragment` devolve o fragmento **decodificado**, e aí um nome de
  /// inventário com `&` já teria virado separador antes de a divisão em
  /// campos acontecer — "Reitoria & Anexo" viraria dois campos. O texto
  /// original está no próprio endereço, depois do `#`.
  static String _fragmentoBruto(Uri uri) {
    final texto = uri.toString();
    final corte = texto.indexOf('#');
    return corte < 0 ? '' : texto.substring(corte + 1);
  }

  /// O endereço aponta para a entrada em inventário?
  static bool _ehEntrada(Uri uri) {
    final caminho = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;

    if (uri.scheme == esquemaProprio) {
      // `slapmobile://entrar` põe "entrar" no host, e não no caminho.
      return uri.host == 'entrar' || caminho == rotaEntrar;
    }
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      return uri.host == hostSite && caminho == caminhoEntrar;
    }
    // Rota interna, sem esquema nem host.
    return caminho == caminhoEntrar || caminho == rotaEntrar;
  }
}

/// Quanto tempo um pedido de entrada espera resposta.
///
/// Curto de propósito: o diálogo aparece por cima de qualquer tela, e um
/// pedido que ficasse pendurado atrapalharia o levantamento de quem está com
/// o celular na mão. Um minuto é o bastante para olhar o nome e decidir.
const Duration validadePedidoPadrao = Duration(minutes: 1);

/// Token de uso único de um pedido de entrada.
///
/// `Random.secure()`, 32 bytes: é o que impede alguém na mesma rede de
/// aproveitar um pedido alheio que acabou de ser aceito.
String gerarTokenEntrada() {
  final aleatorio = Random.secure();
  return base64Url.encode(List.generate(32, (_) => aleatorio.nextInt(256)));
}

/// Rótulo que amarra a chave derivada àquele pedido.
///
/// Entram o inventário, o token e as duas chaves públicas, sempre na mesma
/// ordem nos dois lados. Assim a chave combinada não serve para outro pedido,
/// nem uma resposta de um pedido pode ser devolvida em outro.
String rotuloEntrega({
  required String inventarioId,
  required String token,
  required String publicaPedinte,
  required String publicaOrigem,
}) => 'slap/entrada/$inventarioId/$token|$publicaPedinte|$publicaOrigem';

/// Pedido de entrada num inventário, enviado a quem compartilhou.
///
/// Vai em claro: é a única requisição do protocolo que não pode ser assinada,
/// porque quem pede ainda não tem a chave. Por isso ele não leva nada além do
/// necessário para a pessoa do outro lado decidir — nome, matrícula e o
/// aparelho —, e a chave pública efêmera com que a resposta será cifrada.
class PedidoEntrada {
  final String inventarioId;
  final String token;
  final String dispositivo;
  final String? usuarioNome;
  final String? matricula;

  /// Parte pública do acordo efêmero de quem pede (ver `AcordoEfemero`).
  final String chavePublica;

  const PedidoEntrada({
    required this.inventarioId,
    required this.token,
    required this.dispositivo,
    required this.chavePublica,
    this.usuarioNome,
    this.matricula,
  });

  /// Como o pedido aparece no diálogo de aceite.
  String get rotulo {
    final nome = usuarioNome?.trim();
    final aparelho = dispositivo.length > 6
        ? dispositivo.substring(0, 6)
        : dispositivo;
    return nome == null || nome.isEmpty
        ? 'Alguém (aparelho $aparelho)'
        : '$nome (aparelho $aparelho)';
  }

  Map<String, dynamic> toJson() => {
    'v': versaoProtocolo,
    'inventario': inventarioId,
    'token': token,
    'dispositivo': dispositivo,
    'usuario': ?usuarioNome,
    'matricula': ?matricula,
    'pub': chavePublica,
  };

  /// Lê um pedido. Devolve `null` quando o corpo não tem o formato esperado —
  /// a rota é aberta, e qualquer um na rede pode bater nela.
  static PedidoEntrada? fromJson(Map<String, dynamic> j) {
    final inventarioId = j['inventario'];
    final token = j['token'];
    final dispositivo = j['dispositivo'];
    final publica = j['pub'];
    if (inventarioId is! String ||
        token is! String ||
        dispositivo is! String ||
        publica is! String ||
        token.isEmpty ||
        dispositivo.isEmpty ||
        publica.isEmpty) {
      return null;
    }
    return PedidoEntrada(
      inventarioId: inventarioId,
      token: token,
      dispositivo: dispositivo,
      chavePublica: publica,
      usuarioNome: j['usuario'] as String?,
      matricula: j['matricula'] as String?,
    );
  }
}

/// Por que um pedido de entrada não foi atendido.
enum MotivoRecusa {
  /// Quem compartilha tocou em "Recusar".
  recusado,

  /// Um minuto sem resposta: ninguém olhou o aparelho a tempo.
  expirou,

  /// O token já tinha sido usado. Cada pedido vale uma vez só.
  tokenRepetido,

  /// Pedido malformado, ou inventário que este aparelho não tem.
  invalido;

  String get explicacao => switch (this) {
    MotivoRecusa.recusado =>
      'O pedido foi recusado no aparelho que compartilhou o inventário.',
    MotivoRecusa.expirou =>
      'Ninguém respondeu ao pedido a tempo. Peça para a pessoa ficar com o '
          'aplicativo aberto e tente de novo.',
    MotivoRecusa.tokenRepetido =>
      'Este pedido já tinha sido enviado. Tente entrar de novo.',
    MotivoRecusa.invalido => 'O aparelho não reconheceu o pedido de entrada.',
  };

  static MotivoRecusa de(String? nome) {
    for (final m in values) {
      if (m.name == nome) return m;
    }
    return MotivoRecusa.invalido;
  }
}

/// Resposta ao pedido de entrada.
///
/// No aceite leva a chave do inventário **cifrada** com a chave combinada do
/// acordo efêmero; na recusa, só o motivo.
class RespostaPedido {
  final bool aceito;
  final MotivoRecusa? motivo;

  /// Parte pública do acordo efêmero de quem compartilha.
  final String? chavePublica;

  /// `{'chave': <chave_sync>}` cifrado com a chave combinada.
  final String? entrega;

  const RespostaPedido.aceito({
    required String this.chavePublica,
    required String this.entrega,
  }) : aceito = true,
       motivo = null;

  const RespostaPedido.recusado(MotivoRecusa this.motivo)
    : aceito = false,
      chavePublica = null,
      entrega = null;

  Map<String, dynamic> toJson() => {
    'aceito': aceito,
    'motivo': ?motivo?.name,
    'pub': ?chavePublica,
    'entrega': ?entrega,
  };

  factory RespostaPedido.fromJson(Map<String, dynamic> j) {
    final publica = j['pub'];
    final entrega = j['entrega'];
    if (j['aceito'] == true && publica is String && entrega is String) {
      return RespostaPedido.aceito(chavePublica: publica, entrega: entrega);
    }
    return RespostaPedido.recusado(MotivoRecusa.de(j['motivo'] as String?));
  }

  /// Nome do campo que leva a chave dentro do envelope cifrado.
  static const campoChave = 'chave';
}
