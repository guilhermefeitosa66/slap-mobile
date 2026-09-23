import 'dart:convert';
import 'dart:io';

import '../../core/version_vector.dart';
import '../../data/repos/operacoes.dart';
import 'protocolo.dart';

class FalhaSync implements Exception {
  final String mensagem;
  FalhaSync(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Um aparelho encontrado na rede local.
class Par {
  final String dispositivoId;
  final String? usuarioNome;
  final String host;
  final int porta;

  /// Como foi encontrado — útil para diagnosticar rede em que o mDNS não passa.
  final String origem;

  const Par({
    required this.dispositivoId,
    required this.host,
    required this.porta,
    this.usuarioNome,
    this.origem = 'mdns',
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

  ClienteSync(this.ops, {this.tempoLimite = const Duration(seconds: 15)});

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
        : ops.aplicarRemotas(lote.ops, contextos: lote.contextos);

    final enviadas = await _enviar(par, inventarioId, chaveSync, lote.vetor);

    return ResultadoSync(
      par: par,
      recebidas: recebidas.aplicadas,
      enviadas: enviadas,
      conflitos: recebidas.conflitos,
    );
  }

  Future<LoteOperacoes> _puxar(
    Par par,
    String inventarioId,
    String chaveSync,
  ) async {
    final resposta = await _requisitar(
      host: par.host,
      porta: par.porta,
      metodo: 'POST',
      caminho: Rotas.pull,
      corpo: PedidoPull(
        inventarioId: inventarioId,
        vetor: ops.vetorDe(inventarioId),
      ).toJson(),
      chaveSync: chaveSync,
    );

    return LoteOperacoes.fromJson(resposta);
  }

  Future<int> _enviar(
    Par par,
    String inventarioId,
    String chaveSync,
    VersionVector vetorDoPar,
  ) async {
    final faltantes = ops.opsFaltantes(inventarioId, vetorDoPar);
    if (faltantes.isEmpty) return 0;

    await _requisitar(
      host: par.host,
      porta: par.porta,
      metodo: 'POST',
      caminho: Rotas.push,
      corpo: LoteOperacoes(
        inventarioId: inventarioId,
        ops: faltantes,
        contextos: ops.contextosDe(faltantes),
        vetor: ops.vetorDe(inventarioId),
      ).toJson(),
      chaveSync: chaveSync,
    );

    return faltantes.length;
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
      metodo: 'GET',
      caminho: Rotas.pacote,
      query: {'inventario': inventarioId},
      chaveSync: chaveSync,
    );
    return PacoteInventario.fromJson(resposta);
  }

  Future<Map<String, dynamic>> _requisitar({
    required String host,
    required int porta,
    required String metodo,
    required String caminho,
    Map<String, dynamic>? corpo,
    Map<String, String>? query,
    String? chaveSync,
  }) async {
    final cliente = HttpClient()..connectionTimeout = tempoLimite;

    try {
      final uri = Uri(
        scheme: 'http',
        host: host,
        port: porta,
        path: caminho,
        queryParameters: query,
      );

      final req = metodo == 'GET'
          ? await cliente.getUrl(uri)
          : await cliente.postUrl(uri);

      final textoCorpo = corpo == null ? '' : jsonEncode(corpo);

      if (chaveSync != null) {
        req.headers.set(
          HttpHeaders.authorizationHeader,
          Assinatura.gerar(
            chaveSync: chaveSync,
            dispositivoId: ops.dispositivoId,
            metodo: metodo,
            // A assinatura cobre o caminho sem a query, que é o que o
            // servidor também usa ao conferir.
            caminho: caminho,
            corpo: textoCorpo,
          ),
        );
      }

      if (corpo != null) {
        req.headers.contentType = ContentType.json;
        req.write(textoCorpo);
      }

      final resposta = await req.close().timeout(tempoLimite);
      final texto = await utf8.decoder.bind(resposta).join();

      if (resposta.statusCode == HttpStatus.unauthorized) {
        throw FalhaSync(
          'O aparelho recusou a conexão. Ele participa deste inventário?',
        );
      }
      if (resposta.statusCode != HttpStatus.ok) {
        throw FalhaSync('Resposta inesperada (${resposta.statusCode}).');
      }

      return jsonDecode(texto) as Map<String, dynamic>;
    } on SocketException catch (e) {
      throw FalhaSync('Não foi possível falar com $host: ${e.message}');
    } finally {
      cliente.close(force: true);
    }
  }
}
