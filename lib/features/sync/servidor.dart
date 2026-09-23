import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/hlc.dart';
import '../../data/banco.dart';
import '../../data/repos/inventarios.dart';
import '../../data/repos/operacoes.dart';
import '../../data/repos/patrimonios.dart';
import '../../data/schema.dart';
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

  ServidorSync({
    required this.banco,
    required this.ops,
    required this.inventarios,
    required this.patrimonios,
    DateTime Function()? relogio,
  }) : relogio = relogio ?? DateTime.now;

  Stream<EventoSync> get eventos => _eventos.stream;

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
    await _servidor?.close(force: true);
    _servidor = null;
  }

  Future<void> dispose() async {
    await parar();
    await _eventos.close();
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

      // O resto exige a chave do inventário. O identificador vem no corpo ou
      // na query, porque é preciso saber qual chave usar para conferir a
      // assinatura antes de confiar em qualquer coisa.
      final inventarioId = _inventarioDaRequisicao(req, corpo);
      if (inventarioId == null) {
        return _erro(req, HttpStatus.badRequest, 'Inventário não informado.');
      }

      final inventario = inventarios.porId(inventarioId);
      if (inventario == null) {
        // Mesma resposta de assinatura inválida: dizer "não tenho esse
        // inventário" confirmaria a existência dele a quem não tem a chave.
        return _erro(req, HttpStatus.unauthorized, 'Não autorizado.');
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

      switch (caminho) {
        case Rotas.pull:
          return _atenderPull(req, corpo, remoto);
        case Rotas.push:
          return _atenderPush(req, corpo, remoto);
        case Rotas.pacote:
          return _atenderPacote(req, inventario, remoto);
        default:
          return _erro(req, HttpStatus.notFound, 'Rota desconhecida.');
      }
    } catch (e) {
      await _erro(req, HttpStatus.internalServerError, 'Erro interno: $e');
    }
  }

  String? _inventarioDaRequisicao(HttpRequest req, String corpo) {
    final daQuery = req.uri.queryParameters['inventario'];
    if (daQuery != null && daQuery.isNotEmpty) return daQuery;

    if (corpo.isEmpty) return null;
    try {
      return (jsonDecode(corpo) as Map<String, dynamic>)['inventario']
          as String?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _atenderPull(
    HttpRequest req,
    String corpo,
    String remoto,
  ) async {
    final pedido = PedidoPull.fromJson(
      jsonDecode(corpo) as Map<String, dynamic>,
    );
    try {
      ops.conferirCabecas(pedido.inventarioId, pedido.cabecas);
    } on IdentidadeDuplicada catch (e) {
      return _erro(req, HttpStatus.conflict, '$e');
    }
    final faltantes = ops.opsFaltantes(pedido.inventarioId, pedido.vetor);

    // O que o par declara ter de nós é o que está comprovadamente com ele.
    _registrarPar(
      remoto,
      pedido.inventarioId,
      nossoSeq: pedido.vetor[banco.dispositivoId],
    );

    await _responder(
      req,
      LoteOperacoes(
        inventarioId: pedido.inventarioId,
        ops: faltantes,
        contextos: ops.contextosDe(faltantes),
        // A nossa vector vai junto: com ela o solicitante já sabe o que nos
        // enviar em seguida, sem precisar de outra viagem para perguntar.
        vetor: ops.vetorDe(pedido.inventarioId),
        cabecas: ops.cabecas(pedido.inventarioId),
      ).toJson(),
    );
  }

  Future<void> _atenderPush(
    HttpRequest req,
    String corpo,
    String remoto,
  ) async {
    final lote = LoteOperacoes.fromJson(
      jsonDecode(corpo) as Map<String, dynamic>,
    );

    final ResultadoAplicacao resultado;
    try {
      ops.conferirCabecas(lote.inventarioId, lote.cabecas);
      resultado = ops.aplicarRemotas(lote.ops, contextos: lote.contextos);
    } on IdentidadeDuplicada catch (e) {
      // Nada do lote entrou. O outro lado recebe a explicação.
      return _erro(req, HttpStatus.conflict, '$e');
    } on RelogioForaDeSincronia catch (e) {
      // Operações com horário no futuro. A transação já foi desfeita: nada
      // do lote entrou. Aceitar arrastaria o relógio deste aparelho, e depois
      // o de todos, para o futuro.
      final diferenca = e.recebido.millis - e.agoraLocal;
      _avisarRelogio(
        inventarioId: lote.inventarioId,
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
      lote.inventarioId,
      nossoSeq: lote.vetor[banco.dispositivoId],
    );
    _eventos.add(
      EventoSync(
        inventarioId: lote.inventarioId,
        dispositivoRemoto: remoto,
        recebidas: resultado.aplicadas,
        conflitos: resultado.conflitos,
      ),
    );

    await _responder(req, {
      'aplicadas': resultado.aplicadas,
      'ignoradas': resultado.ignoradas,
      'conflitos': resultado.conflitos,
    });
  }

  Future<void> _atenderPacote(
    HttpRequest req,
    Inventario inventario,
    String remoto,
  ) async {
    _registrarPar(remoto, inventario.id);

    await _responder(
      req,
      PacoteInventario(
        inventario: inventario,
        patrimonios: patrimonios.todos(inventario.id, incluirIgnorados: true),
      ).toJson(),
    );
  }

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
