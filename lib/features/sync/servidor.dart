import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/hlc.dart';
import '../../data/banco.dart';
import '../../data/repos/inventarios.dart';
import '../../data/repos/operacoes.dart';
import '../../data/repos/patrimonios.dart';
import '../../data/schema.dart';
import 'cifra.dart';
import 'protocolo.dart';

/// O lado servidor de cada aparelho.
///
/// Todo aparelho é simultaneamente cliente e servidor: não existe um
/// designado como principal, e qualquer um pode sair da rede sem interromper
/// os demais.
class ServidorSync {
  final Banco banco;
  final RepositorioOperacoes ops;
  final RepositorioInventarios inventarios;
  final RepositorioPatrimonios patrimonios;

  HttpServer? _servidor;

  /// Relógio deste aparelho. Substituível nos testes, para simular aparelho
  /// com data errada.
  final DateTime Function() relogio;

  /// Última sincronização recebida, para a interface reagir sem consultar o
  /// banco em laço.
  final _eventos = StreamController<EventoSync>.broadcast();

  /// Pedidos de entrada esperando o aceite de quem está com o aparelho.
  final _pedidos = StreamController<PedidoEntrada>.broadcast();

  /// Pedidos pendentes, por token.
  final _emEspera = <String, _EsperaPedido>{};

  /// Tokens já apresentados, com o momento em que chegaram. Cada pedido vale
  /// uma vez só, tenha sido aceito, recusado ou esquecido.
  final _tokensUsados = <String, DateTime>{};

  /// Quanto um pedido de entrada espera pela resposta. Substituível nos
  /// testes, que não podem esperar um minuto de verdade.
  final Duration validadePedido;

  ServidorSync({
    required this.banco,
    required this.ops,
    required this.inventarios,
    required this.patrimonios,
    DateTime Function()? relogio,
    Duration? validadePedido,
  }) : relogio = relogio ?? DateTime.now,
       validadePedido = validadePedido ?? validadePedidoPadrao;

  Stream<EventoSync> get eventos => _eventos.stream;

  /// Pedidos de entrada chegando. É o canal que o diálogo de aceite escuta.
  Stream<PedidoEntrada> get pedidos => _pedidos.stream;

  /// Pedidos que ainda esperam resposta. Serve a quem abre o aplicativo já
  /// com um pedido em andamento.
  List<PedidoEntrada> get pedidosPendentes => [
    for (final espera in _emEspera.values) espera.pedido,
  ];

  int? get porta => _servidor?.port;
  bool get ativo => _servidor != null;

  /// Sobe o servidor numa porta efêmera, anunciada depois pela descoberta.
  ///
  /// Porta fixa causaria colisão quando dois processos do app rodassem no
  /// mesmo aparelho, e não traz vantagem: ninguém digita o endereço.
  Future<int> iniciar() async {
    if (_servidor != null) return _servidor!.port;

    final servidor = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: true,
    );
    _servidor = servidor;

    unawaited(servidor.forEach(_atender));
    return servidor.port;
  }

  Future<void> parar() async {
    // Pedido pendente não fica pendurado: fechar o servidor derruba a
    // requisição, e a espera ficaria esperando para sempre.
    for (final espera in _emEspera.values.toList()) {
      espera.decidir(null);
    }
    _emEspera.clear();

    await _servidor?.close(force: true);
    _servidor = null;
  }

  Future<void> dispose() async {
    await parar();
    await _eventos.close();
    await _pedidos.close();
  }

  Future<void> _atender(HttpRequest req) async {
    try {
      final caminho = req.uri.path;
      final corpo = req.method == 'POST'
          ? await utf8.decoder.bind(req).join()
          : '';

      if (caminho == Rotas.hello) {
        return _responder(req, {
          ...Apresentacao(
            dispositivoId: banco.dispositivoId,
            usuarioNome: banco.lerConfig(Config.usuarioNome),
            agora: relogio().millisecondsSinceEpoch,
          ).toJson(),
        });
      }

      // Versão diferente é recusada antes de qualquer coisa, com a nossa
      // versão na resposta para o outro lado explicar a quem está com ele.
      final versao = int.tryParse(req.headers.value(cabecalhoVersao) ?? '');
      if (versao != versaoProtocolo) {
        return _responderJson(req, HttpStatus.upgradeRequired, {
          'erro': 'versao',
          'versao': versaoProtocolo,
          'mensagem': mensagemVersaoDiferente(
            quem: 'O aparelho que pediu',
            versao: versao ?? 1,
          ),
        });
      }

      // O resto exige a chave do inventário. O identificador vem na query,
      // em claro — o corpo está cifrado, e é preciso saber qual chave usar
      // para conferir a assinatura antes de confiar em qualquer coisa.
      final inventarioId = req.uri.queryParameters['inventario'];
      if (inventarioId == null || inventarioId.isEmpty) {
        return _erro(req, HttpStatus.badRequest, 'Inventário não informado.');
      }

      final inventario = inventarios.porId(inventarioId);
      if (inventario == null) {
        // Mesma resposta de assinatura inválida: dizer "não tenho esse
        // inventário" confirmaria a existência dele a quem não tem a chave.
        return _erro(req, HttpStatus.unauthorized, 'Não autorizado.');
      }

      // O pedido de entrada vem antes da assinatura, e é o único que vem:
      // quem pede ainda não tem a chave com que assinaria — é ela que está
      // sendo pedida. O que autoriza aqui é uma pessoa tocando em "Aceitar".
      if (caminho == Rotas.pedido) {
        return _atenderPedido(req, inventario, corpo);
      }

      final conferencia = Assinatura.conferir(
        cabecalho: req.headers.value(HttpHeaders.authorizationHeader),
        chaveSync: inventario.chaveSync,
        metodo: req.method,
        caminho: caminho,
        corpo: corpo,
        agora: relogio(),
      );
      if (conferencia.situacao == SituacaoAssinatura.foraDaJanela) {
        // Chave certa, horário errado: é o relógio de um dos dois aparelhos.
        // Nada é aplicado, e o outro lado recebe o nosso horário para dizer
        // ao usuário de quanto é a diferença.
        _avisarRelogio(
          inventarioId: inventario.id,
          remoto: conferencia.dispositivoId!,
          diferenca: Duration(
            milliseconds:
                conferencia.momento! - relogio().millisecondsSinceEpoch,
          ),
        );
        return _responderJson(
          req,
          HttpStatus.conflict,
          ErroRelogio(agora: relogio().millisecondsSinceEpoch).toJson(),
        );
      }
      final remoto = conferencia.dispositivoId;
      if (!conferencia.valida || remoto == null) {
        return _erro(req, HttpStatus.unauthorized, 'Não autorizado.');
      }

      final cifra = CifraSync(inventario.chaveSync);
      final Map<String, dynamic> conteudo;
      try {
        conteudo = corpo.isEmpty
            ? const {}
            : cifra.decifrar(
                corpo,
                contexto: CifraSync.contextoPedido(req.method, caminho),
              );
      } on CorpoIlegivel {
        return _erro(req, HttpStatus.badRequest, 'Corpo ilegível.');
      }
      final canal = _Canal(req, cifra, caminho);

      switch (caminho) {
        case Rotas.pull:
          return _atenderPull(canal, conteudo, remoto, inventario.id);
        case Rotas.push:
          return _atenderPush(canal, conteudo, remoto, inventario.id);
        case Rotas.pacote:
          return _atenderPacote(canal, inventario, remoto);
        default:
          return _erro(req, HttpStatus.notFound, 'Rota desconhecida.');
      }
    } catch (e) {
      try {
        await _erro(req, HttpStatus.internalServerError, 'Erro interno: $e');
      } catch (_) {
        // Conexão já fechada do outro lado: não há a quem explicar.
      }
    }
  }

  Future<void> _atenderPull(
    _Canal canal,
    Map<String, dynamic> conteudo,
    String remoto,
    String inventarioId,
  ) async {
    final req = canal.req;
    final pedido = PedidoPull.fromJson(conteudo);
    if (pedido.inventarioId != inventarioId) {
      return _erroDeInventario(req);
    }
    try {
      ops.conferirCabecas(inventarioId, pedido.cabecas);
    } on IdentidadeDuplicada catch (e) {
      return _erro(req, HttpStatus.conflict, '$e');
    }
    final faltantes = ops.opsFaltantes(
      inventarioId,
      pedido.vetor,
      lacunas: pedido.lacunas,
    );

    // O que o par declara ter de nós é o que está comprovadamente com ele —
    // até o começo da primeira lacuna que ele declarou na nossa sequência.
    _registrarPar(
      remoto,
      inventarioId,
      nossoSeq: ops.seqEntregueA(
        inventarioId,
        maximoDoPar: pedido.vetor[banco.dispositivoId],
        lacunasDoPar: pedido.lacunas[banco.dispositivoId],
      ),
    );

    await canal.responder(
      LoteOperacoes(
        inventarioId: inventarioId,
        ops: faltantes,
        contextos: ops.contextosDe(faltantes),
        // A nossa vector vai junto: com ela o solicitante já sabe o que nos
        // enviar em seguida, sem precisar de outra viagem para perguntar. As
        // lacunas completam o quadro: o que falta a nós no meio da sequência.
        vetor: ops.vetorDe(inventarioId),
        lacunas: ops.lacunasDe(inventarioId),
        cabecas: ops.cabecas(inventarioId),
      ).toJson(),
    );
  }

  Future<void> _atenderPush(
    _Canal canal,
    Map<String, dynamic> conteudo,
    String remoto,
    String inventarioId,
  ) async {
    final req = canal.req;
    final lote = LoteOperacoes.fromJson(conteudo);
    if (lote.inventarioId != inventarioId) {
      return _erroDeInventario(req);
    }

    final ResultadoAplicacao resultado;
    try {
      ops.conferirCabecas(inventarioId, lote.cabecas);
      resultado = ops.aplicarRemotas(
        lote.ops,
        inventarioId: inventarioId,
        contextos: lote.contextos,
      );
    } on LoteDeOutroInventario {
      // Assinado com a chave deste inventário, mas escrevendo em outro.
      return _erroDeInventario(req);
    } on IdentidadeDuplicada catch (e) {
      // Nada do lote entrou. O outro lado recebe a explicação.
      return _erro(req, HttpStatus.conflict, '$e');
    } on RelogioForaDeSincronia catch (e) {
      // Operações com horário no futuro. A transação já foi desfeita: nada
      // do lote entrou. Aceitar arrastaria o relógio deste aparelho, e depois
      // o de todos, para o futuro.
      final diferenca = e.recebido.millis - e.agoraLocal;
      _avisarRelogio(
        inventarioId: inventarioId,
        remoto: e.recebido.nodeId,
        diferenca: Duration(milliseconds: diferenca),
      );
      return _responderJson(
        req,
        HttpStatus.conflict,
        ErroRelogio(
          agora: relogio().millisecondsSinceEpoch,
          dispositivo: e.recebido.nodeId,
          diferencaMs: diferenca,
        ).toJson(),
      );
    }

    _registrarPar(
      remoto,
      inventarioId,
      nossoSeq: ops.seqEntregueA(
        inventarioId,
        maximoDoPar: lote.vetor[banco.dispositivoId],
        lacunasDoPar: lote.lacunas[banco.dispositivoId],
      ),
    );
    _eventos.add(
      EventoSync(
        inventarioId: inventarioId,
        dispositivoRemoto: remoto,
        recebidas: resultado.aplicadas,
        conflitos: resultado.conflitos,
      ),
    );

    await canal.responder({
      'aplicadas': resultado.aplicadas,
      'ignoradas': resultado.ignoradas,
      'conflitos': resultado.conflitos,
    });
  }

  Future<void> _atenderPacote(
    _Canal canal,
    Inventario inventario,
    String remoto,
  ) async {
    _registrarPar(remoto, inventario.id);

    await canal.responder(
      PacoteInventario(
        inventario: inventario,
        patrimonios: patrimonios.todos(inventario.id, incluirIgnorados: true),
      ).toJson(),
    );
  }

  // ------------------------------------------------ pedido de entrada ---

  /// Recebe um pedido de entrada e segura a resposta até alguém decidir.
  ///
  /// A requisição fica aberta enquanto o diálogo está na tela do outro lado:
  /// é uma conversa entre dois celulares na mesma sala, e devolver "pedido
  /// registrado, pergunte de novo depois" só acrescentaria um laço de
  /// tentativas a um caso que dura segundos.
  Future<void> _atenderPedido(
    HttpRequest req,
    Inventario inventario,
    String corpo,
  ) async {
    const invalido = RespostaPedido.recusado(MotivoRecusa.invalido);

    PedidoEntrada? pedido;
    try {
      pedido = PedidoEntrada.fromJson(
        jsonDecode(corpo) as Map<String, dynamic>,
      );
    } catch (_) {
      // Rota aberta: qualquer coisa pode bater nela, inclusive um varredor.
      pedido = null;
    }
    if (req.method != 'POST' ||
        pedido == null ||
        pedido.inventarioId != inventario.id) {
      return _responderPedido(req, invalido);
    }

    // Um aparelho hostil na mesma rede não pode encher a tela de diálogos
    // nem prender conexões: passado o limite, o pedido é recusado na hora.
    if (_emEspera.length >= _limitePendentes) {
      return _responderPedido(req, invalido);
    }

    _limparTokens();
    // Uso único: um pedido aceito não pode ser reapresentado por quem estava
    // ouvindo a rede para receber a chave uma segunda vez.
    if (_tokensUsados.containsKey(pedido.token)) {
      return _responderPedido(
        req,
        const RespostaPedido.recusado(MotivoRecusa.tokenRepetido),
      );
    }
    _tokensUsados[pedido.token] = relogio();

    final espera = _EsperaPedido(pedido);
    _emEspera[pedido.token] = espera;
    if (!_pedidos.isClosed) _pedidos.add(pedido);

    // Sem resposta, o pedido caduca sozinho: ninguém fica esperando um
    // aparelho que foi para o bolso.
    final cronometro = Timer(validadePedido, () => espera.decidir(null));

    final RespostaPedido resposta;
    try {
      final decisao = await espera.decisao;
      resposta = switch (decisao) {
        true => _entregarChave(inventario, pedido),
        false => const RespostaPedido.recusado(MotivoRecusa.recusado),
        null => const RespostaPedido.recusado(MotivoRecusa.expirou),
      };
    } finally {
      cronometro.cancel();
      _emEspera.remove(pedido.token);
    }

    await _responderPedido(req, resposta);
  }

  /// Resposta de quem está com o aparelho. Devolve `false` quando o pedido já
  /// tinha caducado — o diálogo então some sem prometer nada.
  bool responderPedido(String token, {required bool aceitar}) {
    final espera = _emEspera[token];
    if (espera == null) return false;
    espera.decidir(aceitar);
    return true;
  }

  /// Entrega a chave do inventário cifrada com a chave combinada do acordo
  /// efêmero. Nem a chave nem o segredo combinado trafegam.
  RespostaPedido _entregarChave(Inventario inventario, PedidoEntrada pedido) {
    try {
      final acordo = AcordoEfemero.gerar();
      final cifra = acordo.combinar(
        pedido.chavePublica,
        rotulo: rotuloEntrega(
          inventarioId: inventario.id,
          token: pedido.token,
          publicaPedinte: pedido.chavePublica,
          publicaOrigem: acordo.publica,
        ),
      );
      return RespostaPedido.aceito(
        chavePublica: acordo.publica,
        entrega: cifra.cifrar({
          RespostaPedido.campoChave: inventario.chaveSync,
        }, contexto: CifraSync.contextoResposta('POST', Rotas.pedido)),
      );
    } on CorpoIlegivel {
      // Chave pública que não é um ponto desta curva.
      return const RespostaPedido.recusado(MotivoRecusa.invalido);
    }
  }

  /// Esquece tokens antigos. Sem isto a lista cresceria pelo dia inteiro; com
  /// meia hora, a reapresentação de um token continua barrada muito além da
  /// validade de um minuto do pedido.
  void _limparTokens() {
    final limite = relogio().subtract(const Duration(minutes: 30));
    _tokensUsados.removeWhere((_, quando) => quando.isBefore(limite));
  }

  Future<void> _responderPedido(
    HttpRequest req,
    RespostaPedido resposta,
  ) async {
    try {
      // Em claro, e não cifrada: é a resposta que carrega a chave combinada
      // com que o resto vai ser decifrado. O conteúdo sensível dela — a chave
      // do inventário — vai cifrado por dentro.
      await _responder(req, resposta.toJson());
    } catch (_) {
      // A requisição ficou aberta enquanto o diálogo estava na tela: quem
      // pediu pode ter desistido e fechado a conexão. Não é erro.
    }
  }

  /// Quantos pedidos de entrada podem esperar resposta ao mesmo tempo.
  static const _limitePendentes = 5;

  void _registrarPar(
    String dispositivo,
    String inventarioId, {
    int nossoSeq = 0,
  }) {
    ops.registrarPar(dispositivo, inventarioId, nossoSeq: nossoSeq);
  }

  Future<void> _responder(HttpRequest req, Map<String, dynamic> corpo) =>
      _responderJson(req, HttpStatus.ok, corpo);

  Future<void> _responderJson(
    HttpRequest req,
    int status,
    Map<String, dynamic> corpo,
  ) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(corpo));
    await req.response.close();
  }

  void _avisarRelogio({
    required String inventarioId,
    required String remoto,
    required Duration diferenca,
  }) {
    if (_eventos.isClosed) return;
    _eventos.add(
      EventoSync(
        inventarioId: inventarioId,
        dispositivoRemoto: remoto,
        recebidas: 0,
        conflitos: 0,
        diferencaRelogio: diferenca,
      ),
    );
  }

  /// O corpo fala de um inventário e a requisição foi autenticada com a chave
  /// de outro.
  ///
  /// Nenhum cliente honesto faz isso: quem monta o pedido põe o mesmo
  /// identificador nos dois lugares. A resposta não distingue os casos e não
  /// diz nada sobre o outro inventário — quem tentou não fica sabendo sequer
  /// se ele existe aqui.
  Future<void> _erroDeInventario(HttpRequest req) =>
      _erro(req, HttpStatus.badRequest, 'O corpo não é deste inventário.');

  Future<void> _erro(HttpRequest req, int status, String mensagem) async {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'erro': mensagem}));
    await req.response.close();
  }
}

/// Uma sincronização recebida de outro aparelho.
class EventoSync {
  final String inventarioId;
  final String dispositivoRemoto;
  final int recebidas;
  final int conflitos;

  /// Preenchido quando a sincronização foi recusada por relógio: quanto o
  /// relógio do outro aparelho está à frente deste (negativo se atrás).
  final Duration? diferencaRelogio;

  const EventoSync({
    required this.inventarioId,
    required this.dispositivoRemoto,
    required this.recebidas,
    required this.conflitos,
    this.diferencaRelogio,
  });

  bool get recusadoPorRelogio => diferencaRelogio != null;
}

/// Um pedido de entrada esperando a decisão de quem está com o aparelho.
class _EsperaPedido {
  final PedidoEntrada pedido;
  final _decisao = Completer<bool?>();

  _EsperaPedido(this.pedido);

  /// `true` aceito, `false` recusado, `null` caducou.
  Future<bool?> get decisao => _decisao.future;

  void decidir(bool? aceito) {
    if (!_decisao.isCompleted) _decisao.complete(aceito);
  }
}

/// A resposta a um pedido autenticado, cifrada com a chave do inventário.
class _Canal {
  final HttpRequest req;
  final CifraSync cifra;
  final String caminho;

  _Canal(this.req, this.cifra, this.caminho);

  Future<void> responder(Map<String, dynamic> corpo) async {
    req.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.text
      ..write(
        cifra.cifrar(
          corpo,
          contexto: CifraSync.contextoResposta(req.method, caminho),
        ),
      );
    await req.response.close();
  }
}
