import 'dart:convert';
import 'dart:io';

import '../../core/formato.dart';
import '../../core/hlc.dart';
import '../../core/version_vector.dart';
import '../../data/repos/operacoes.dart';
import 'cifra.dart';
import 'protocolo.dart';

class FalhaSync implements Exception {
  final String mensagem;
  FalhaSync(this.mensagem);

  @override
  String toString() => mensagem;
}

/// A sincronização foi recusada porque os relógios estão longe demais.
///
/// Nenhuma operação daquele par é aplicada enquanto a diferença durar:
/// aceitar operação do futuro arrastaria o relógio deste aparelho e, depois,
/// o de todos os outros. Celular com data errada é comum, e sem esta
/// explicação o usuário não teria como adivinhar que o problema é esse.
class RelogioDivergente extends FalhaSync {
  /// Como mostrar o aparelho de relógio diferente.
  final String aparelho;

  /// Quanto o relógio de [aparelho] está à frente deste. Negativo quando
  /// está atrás.
  final Duration diferenca;

  RelogioDivergente({required this.aparelho, required this.diferenca})
    : super(_mensagem(aparelho, diferenca));

  bool get adiantado => !diferenca.isNegative;

  /// Hora que o outro aparelho marca agora, segundo a diferença medida.
  DateTime horaDoOutro(DateTime agora) => agora.add(diferenca);

  static String _mensagem(String aparelho, Duration diferenca) =>
      'O relógio de $aparelho está ${descreverDuracao(diferenca.abs())} '
      '${diferenca.isNegative ? 'atrasado' : 'adiantado'} em relação a este '
      'aparelho. Nada foi trocado. Ative a data e a hora automáticas nos dois '
      'aparelhos e sincronize de novo.';
}

/// Um aparelho encontrado na rede local.
class Par {
  final String dispositivoId;
  final String? usuarioNome;
  final String host;
  final int porta;

  /// Todas as vias que o encontraram (`mdns`, `beacon`), não só a última: é o
  /// que diz, no teste em campo, se cada uma funciona naquela rede.
  final Set<String> origens;

  const Par({
    required this.dispositivoId,
    required this.host,
    required this.porta,
    this.usuarioNome,
    this.origens = const {'mdns'},
  });

  String get endereco => '$host:$porta';
  String get rotulo => usuarioNome?.trim().isNotEmpty == true
      ? usuarioNome!
      : 'Aparelho ${dispositivoId.substring(0, 6)}';

  @override
  bool operator ==(Object outro) =>
      outro is Par && outro.dispositivoId == dispositivoId;

  @override
  int get hashCode => dispositivoId.hashCode;
}

/// Resultado de uma sincronização com um par.
class ResultadoSync {
  final Par par;
  final int recebidas;
  final int enviadas;
  final int conflitos;

  const ResultadoSync({
    required this.par,
    required this.recebidas,
    required this.enviadas,
    required this.conflitos,
  });

  bool get houveTroca => recebidas > 0 || enviadas > 0;
}

/// O lado cliente: conversa com os outros aparelhos.
class ClienteSync {
  final RepositorioOperacoes ops;

  /// Curto de propósito: o par está na mesma rede local, e uma espera longa
  /// travaria a tela de sincronização por causa de um aparelho que saiu do
  /// alcance.
  final Duration tempoLimite;

  /// Relógio deste aparelho. Substituível nos testes, para simular aparelho
  /// com data errada.
  final DateTime Function() relogio;

  ClienteSync(
    this.ops, {
    this.tempoLimite = const Duration(seconds: 15),
    DateTime Function()? relogio,
  }) : relogio = relogio ?? DateTime.now;

  /// Identifica um aparelho. Não exige chave: serve para listá-lo antes de
  /// saber se ele participa de algum inventário em comum.
  Future<Apresentacao> apresentar(String host, int porta) async {
    final resposta = await _requisitar(
      host: host,
      porta: porta,
      metodo: 'GET',
      caminho: Rotas.hello,
    );
    return Apresentacao.fromJson(resposta);
  }

  /// Sincronização completa com um par: puxa o que falta e envia o que o
  /// outro não tem.
  ///
  /// Puxar primeiro é proposital. Assim as operações remotas entram no
  /// contexto causal antes de enviarmos as nossas, e o par recebe um lote já
  /// ciente do que ele mesmo escreveu — o que evita marcar como concorrente
  /// algo que acabou de chegar.
  Future<ResultadoSync> sincronizar({
    required Par par,
    required String inventarioId,
    required String chaveSync,
  }) async {
    // Os relógios são conferidos antes de qualquer troca: com diferença
    // grande, nenhum dos dois lados deve aplicar nada do outro.
    await _conferirRelogio(par);

    // Uma viagem para puxar: a resposta traz as operações que nos faltam e a
    // version vector do par. Outra para enviar exatamente o que falta a ele.
    final lote = await _puxar(par, inventarioId, chaveSync);

    final recebidas = lote.ops.isEmpty
        ? const ResultadoAplicacao(
            aplicadas: 0,
            ignoradas: 0,
            conflitos: 0,
            patrimoniosAfetados: {},
          )
        : _aplicar(par, lote);

    final enviadas = await _enviar(par, inventarioId, chaveSync, lote.vetor);

    // Até onde o nosso trabalho está com o par: o que ele declarou ter, ou o
    // que ele acabou de aceitar do nosso envio.
    ops.registrarPar(
      par.dispositivoId,
      inventarioId,
      usuarioNome: par.usuarioNome,
      nossoSeq: [
        lote.vetor[ops.dispositivoId],
        enviadas.nossoSeq,
      ].reduce((a, b) => a > b ? a : b),
    );

    return ResultadoSync(
      par: par,
      recebidas: recebidas.aplicadas,
      enviadas: enviadas.quantidade,
      conflitos: recebidas.conflitos,
    );
  }

  /// Compara o relógio do par com o nosso, pela apresentação dele.
  ///
  /// O horário remoto é comparado com o meio da viagem de ida e volta, o que
  /// desconta a latência da rede — irrelevante perto do limite de minutos,
  /// mas de graça.
  Future<void> _conferirRelogio(Par par) async {
    final antes = relogio();
    final apresentacao = await apresentar(par.host, par.porta);
    final depois = relogio();

    // Versão diferente não troca nada: um dos lados interpretaria errado.
    if (apresentacao.versao != versaoProtocolo) {
      throw FalhaSync(
        mensagemVersaoDiferente(
          quem: 'O aparelho de ${par.rotulo}',
          versao: apresentacao.versao,
        ),
      );
    }

    final remoto = apresentacao.agora;
    if (remoto == null) return;

    final meio =
        antes.millisecondsSinceEpoch +
        depois.difference(antes).inMilliseconds ~/ 2;
    final diferenca = Duration(milliseconds: remoto - meio);
    if (diferenca.abs() > deslocamentoMaximoRelogio) {
      throw RelogioDivergente(aparelho: par.rotulo, diferenca: diferenca);
    }
  }

  /// Aplica o lote puxado, traduzindo relógio adiantado em explicação.
  ///
  /// A operação do futuro pode ser de um terceiro, que chegou ao par por
  /// sincronização anterior: o aviso nomeia quem a escreveu, não o par.
  ResultadoAplicacao _aplicar(Par par, LoteOperacoes lote) {
    try {
      ops.conferirCabecas(lote.inventarioId, lote.cabecas);
      return ops.aplicarRemotas(lote.ops, contextos: lote.contextos);
    } on IdentidadeDuplicada catch (e) {
      throw FalhaSync('$e');
    } on RelogioForaDeSincronia catch (e) {
      final autor = e.recebido.nodeId;
      throw RelogioDivergente(
        aparelho: _rotuloDe(autor, par, lote.ops),
        diferenca: Duration(milliseconds: e.recebido.millis - e.agoraLocal),
      );
    }
  }

  String _rotuloDe(String dispositivo, Par par, List<Operacao> lote) {
    if (dispositivo == par.dispositivoId) return par.rotulo;
    for (final op in lote) {
      final nome = op.usuarioNome?.trim();
      if (op.dispositivo == dispositivo && nome != null && nome.isNotEmpty) {
        return 'um aparelho de $nome';
      }
    }
    return 'aparelho ${dispositivo.substring(0, 6)}';
  }

  Future<LoteOperacoes> _puxar(
    Par par,
    String inventarioId,
    String chaveSync,
  ) async {
    final resposta = await _requisitar(
      host: par.host,
      porta: par.porta,
      rotulo: par.rotulo,
      metodo: 'POST',
      caminho: Rotas.pull,
      inventarioId: inventarioId,
      corpo: PedidoPull(
        inventarioId: inventarioId,
        vetor: ops.vetorParaPedido(inventarioId),
        cabecas: ops.cabecas(inventarioId),
      ).toJson(),
      chaveSync: chaveSync,
    );

    return LoteOperacoes.fromJson(resposta);
  }

  /// Envia o que falta ao par. Devolve quantas foram e o maior `seq` deste
  /// aparelho entre elas, que o par agora tem.
  Future<({int quantidade, int nossoSeq})> _enviar(
    Par par,
    String inventarioId,
    String chaveSync,
    VersionVector vetorDoPar,
  ) async {
    // Vai mesmo sem nada a enviar: o lote leva o nosso vetor, e é assim que
    // o par fica sabendo que já recebemos o trabalho dele. Sem isso, quem só
    // forneceu dados nunca saberia se eles chegaram — e a confirmação de
    // apagar o inventário lá avisaria de uma perda que não existe.
    final faltantes = ops.opsFaltantes(inventarioId, vetorDoPar);

    await _requisitar(
      host: par.host,
      porta: par.porta,
      rotulo: par.rotulo,
      metodo: 'POST',
      caminho: Rotas.push,
      inventarioId: inventarioId,
      corpo: LoteOperacoes(
        inventarioId: inventarioId,
        ops: faltantes,
        contextos: ops.contextosDe(faltantes),
        vetor: ops.vetorDe(inventarioId),
        cabecas: ops.cabecas(inventarioId),
      ).toJson(),
      chaveSync: chaveSync,
    );

    var nossoSeq = 0;
    for (final op in faltantes) {
      if (op.dispositivo == ops.dispositivoId && op.seq > nossoSeq) {
        nossoSeq = op.seq;
      }
    }
    return (quantidade: faltantes.length, nossoSeq: nossoSeq);
  }

  /// Baixa a réplica inicial de um inventário.
  Future<PacoteInventario> baixarPacote({
    required Par par,
    required String inventarioId,
    required String chaveSync,
  }) async {
    final resposta = await _requisitar(
      host: par.host,
      porta: par.porta,
      rotulo: par.rotulo,
      metodo: 'GET',
      caminho: Rotas.pacote,
      inventarioId: inventarioId,
      chaveSync: chaveSync,
    );
    return PacoteInventario.fromJson(resposta);
  }

  /// Uma requisição ao par.
  ///
  /// Com [chaveSync] — tudo menos a apresentação —, o corpo vai cifrado e
  /// assinado, o inventário vai na query, e a resposta volta cifrada.
  Future<Map<String, dynamic>> _requisitar({
    required String host,
    required int porta,
    required String metodo,
    required String caminho,
    String? rotulo,
    Map<String, dynamic>? corpo,
    String? inventarioId,
    String? chaveSync,
  }) async {
    final cliente = HttpClient()..connectionTimeout = tempoLimite;
    final cifra = chaveSync == null ? null : CifraSync(chaveSync);

    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: porta,
        path: caminho,
        queryParameters: inventarioId == null
            ? null
            : {'inventario': inventarioId},
      );

      final req = metodo == 'GET'
          ? await cliente.getUrl(uri)
          : await cliente.postUrl(uri);

      final textoCorpo = corpo == null
          ? ''
          : cifra == null
          ? jsonEncode(corpo)
          : cifra.cifrar(
              corpo,
              contexto: CifraSync.contextoPedido(metodo, caminho),
            );

      if (chaveSync != null) {
        req.headers
          ..set(cabecalhoVersao, '$versaoProtocolo')
          ..set(
            HttpHeaders.authorizationHeader,
            Assinatura.gerar(
              chaveSync: chaveSync,
              dispositivoId: ops.dispositivoId,
              metodo: metodo,
              // A assinatura cobre o caminho sem a query, que é o que o
              // servidor também usa ao conferir, e o corpo como ele
              // trafega: cifrado.
              caminho: caminho,
              corpo: textoCorpo,
              agora: relogio(),
            ),
          );
      }

      if (corpo != null) {
        req.headers.contentType = cifra == null
            ? ContentType.json
            : ContentType.text;
        req.write(textoCorpo);
      }

      final resposta = await req.close().timeout(tempoLimite);
      final texto = await utf8.decoder.bind(resposta).join();

      if (resposta.statusCode == HttpStatus.upgradeRequired) {
        throw _versaoRecusada(texto, rotulo ?? host);
      }
      if (resposta.statusCode == HttpStatus.conflict) {
        throw _relogioRecusado(texto, rotulo ?? host);
      }
      if (resposta.statusCode == HttpStatus.unauthorized) {
        throw FalhaSync(
          'O aparelho recusou a conexão. Ele participa deste inventário?',
        );
      }
      if (resposta.statusCode != HttpStatus.ok) {
        throw FalhaSync('Resposta inesperada (${resposta.statusCode}).');
      }

      if (cifra == null) return jsonDecode(texto) as Map<String, dynamic>;
      try {
        return cifra.decifrar(
          texto,
          contexto: CifraSync.contextoResposta(metodo, caminho),
        );
      } on CorpoIlegivel {
        throw FalhaSync(
          'A resposta de ${rotulo ?? host} não pôde ser decifrada. Os dois '
          'aparelhos têm a mesma versão do aplicativo?',
        );
      }
    } on SocketException catch (e) {
      throw FalhaSync('Não foi possível falar com $host: ${e.message}');
    } finally {
      cliente.close(force: true);
    }
  }

  FalhaSync _versaoRecusada(String texto, String rotulo) {
    try {
      final j = jsonDecode(texto) as Map<String, dynamic>;
      final versao = (j['versao'] as num?)?.toInt();
      if (versao != null) {
        return FalhaSync(
          mensagemVersaoDiferente(
            quem: 'O aparelho de $rotulo',
            versao: versao,
          ),
        );
      }
    } catch (_) {
      // Resposta sem o formato esperado: a mensagem genérica serve.
    }
    return FalhaSync(
      '$rotulo usa outra versão do aplicativo. Atualize os dois aparelhos '
      'para a mesma versão e sincronize de novo.',
    );
  }

  /// Traduz a recusa por relógio do outro lado.
  ///
  /// Quando o par aponta o autor das operações do futuro, o aviso é sobre
  /// ele; senão, a diferença é entre o relógio do par e o nosso.
  FalhaSync _relogioRecusado(String texto, String rotulo) {
    final Map<String, dynamic> corpo;
    try {
      corpo = jsonDecode(texto) as Map<String, dynamic>;
    } catch (_) {
      return FalhaSync('Resposta inesperada (409).');
    }
    final erro = ErroRelogio.fromJson(corpo);
    if (erro == null) {
      // Outra recusa explicada pelo par — identidade duplicada, por exemplo.
      final motivo = corpo['erro'];
      return FalhaSync(
        motivo is String ? motivo : 'Resposta inesperada (409).',
      );
    }

    if (erro.dispositivo != null && erro.diferencaMs != null) {
      final ehEste = erro.dispositivo == ops.dispositivoId;
      return RelogioDivergente(
        aparelho: ehEste
            ? 'este aparelho'
            : 'aparelho ${erro.dispositivo!.substring(0, 6)}',
        diferenca: Duration(milliseconds: erro.diferencaMs!),
      );
    }

    return RelogioDivergente(
      aparelho: rotulo,
      diferenca: Duration(
        milliseconds: erro.agora - relogio().millisecondsSinceEpoch,
      ),
    );
  }
}
