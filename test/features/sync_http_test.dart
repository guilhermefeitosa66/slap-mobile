import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/hlc.dart';
import 'package:slap_mobile/core/version_vector.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/sync/cifra.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/protocolo.dart';
import 'package:slap_mobile/features/sync/servidor.dart';

import '../apoio/rede_simulada.dart';

/// Sincronização sobre HTTP real, com sockets de verdade em localhost.
///
/// Os testes de `sincronizacao_test.dart` exercitam a convergência isolada do
/// transporte; estes exercitam o transporte: assinatura, rotas, serialização e
/// a transferência do pacote inicial.
void main() {
  late Aparelho a;
  late Aparelho b;
  late ServidorSync servidorA;
  late ServidorSync servidorB;
  late ClienteSync clienteA;
  late ClienteSync clienteB;
  late Inventario inventario;
  late Par paraA;
  late Par paraB;

  setUp(() async {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');

    // Validade curta: o pedido de entrada vale um minuto em campo, e o teste
    // de expiração não pode esperar um minuto.
    const validade = Duration(seconds: 2);
    servidorA = ServidorSync(
      banco: a.banco,
      ops: a.ops,
      inventarios: a.inventarios,
      patrimonios: a.patrimonios,
      validadePedido: validade,
    );
    servidorB = ServidorSync(
      banco: b.banco,
      ops: b.ops,
      inventarios: b.inventarios,
      patrimonios: b.patrimonios,
      validadePedido: validade,
    );

    final portaA = await servidorA.iniciar();
    final portaB = await servidorB.iniciar();

    paraA = Par(
      dispositivoId: a.dispositivoId,
      host: '127.0.0.1',
      porta: portaA,
    );
    paraB = Par(
      dispositivoId: b.dispositivoId,
      host: '127.0.0.1',
      porta: portaB,
    );

    clienteA = ClienteSync(a.ops);
    clienteB = ClienteSync(b.ops);

    inventario = a.inventarios.criar(
      nome: 'Campus Picos — Biblioteca',
      ano: 2026,
    );
    a.patrimonios.inserirRecebidos([
      patrimonioDeTeste(
        id: 'item-1',
        inventarioId: inventario.id,
        tombo: '12345',
        sala: 'Coordenação de TI',
        responsavel: 'João',
      ),
      patrimonioDeTeste(
        id: 'item-2',
        inventarioId: inventario.id,
        tombo: '12346',
        sala: 'Biblioteca',
        responsavel: 'Maria',
      ),
    ]);
  });

  StreamSubscription<PedidoEntrada>? inscricao;

  /// Quem está com o aparelho A responde a todo pedido do mesmo jeito.
  void aAtende({required bool aceitar}) {
    inscricao = servidorA.pedidos.listen(
      (p) => servidorA.responderPedido(p.token, aceitar: aceitar),
    );
  }

  /// Um pedido montado à mão, para exercitar o que o `ClienteSync` não deixa
  /// fazer — repetir um token, por exemplo.
  Future<Map<String, dynamic>> pedirBruto(
    Par par,
    Map<String, dynamic> corpo, {
    String? inventarioId,
  }) async {
    final cliente = HttpClient();
    try {
      final req = await cliente.postUrl(
        Uri(
          scheme: 'http',
          host: par.host,
          port: par.porta,
          path: Rotas.pedido,
          queryParameters: {'inventario': inventarioId ?? inventario.id},
        ),
      );
      req.headers.set(cabecalhoVersao, '$versaoProtocolo');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(corpo));
      final resposta = await req.close();
      final texto = await utf8.decoder.bind(resposta).join();
      return {
        'status': resposta.statusCode,
        if (texto.isNotEmpty) ...jsonDecode(texto) as Map<String, dynamic>,
      };
    } finally {
      cliente.close(force: true);
    }
  }

  /// Uma requisição autenticada montada à mão: é o que um aparelho hostil
  /// faria com a chave de um inventário para falar de outro.
  Future<({int status, Map<String, dynamic> corpo})> requisitarBruto({
    required String caminho,
    required String inventarioNaQuery,
    required String chaveSync,
    required Map<String, dynamic> corpo,
  }) async {
    final cifra = CifraSync(chaveSync);
    final texto = cifra.cifrar(
      corpo,
      contexto: CifraSync.contextoPedido('POST', caminho),
    );
    final cliente = HttpClient();
    try {
      final req = await cliente.postUrl(
        Uri(
          scheme: 'http',
          host: paraA.host,
          port: paraA.porta,
          path: caminho,
          queryParameters: {'inventario': inventarioNaQuery},
        ),
      );
      req.headers.set(cabecalhoVersao, '$versaoProtocolo');
      req.headers.set(
        HttpHeaders.authorizationHeader,
        Assinatura.gerar(
          chaveSync: chaveSync,
          dispositivoId: b.dispositivoId,
          metodo: 'POST',
          caminho: caminho,
          corpo: texto,
        ),
      );
      req.headers.contentType = ContentType.text;
      req.write(texto);

      final resposta = await req.close();
      final retorno = await utf8.decoder.bind(resposta).join();
      if (resposta.statusCode != HttpStatus.ok) {
        return (
          status: resposta.statusCode,
          corpo: jsonDecode(retorno) as Map<String, dynamic>,
        );
      }
      return (
        status: resposta.statusCode,
        corpo: cifra.decifrar(
          retorno,
          contexto: CifraSync.contextoResposta('POST', caminho),
        ),
      );
    } finally {
      cliente.close(force: true);
    }
  }

  tearDown(() async {
    await inscricao?.cancel();
    await servidorA.dispose();
    await servidorB.dispose();
    a.fechar();
    b.fechar();
  });

  /// Entrar no inventário: é o que acontece depois de ler o QR code.
  Future<void> entrarNoInventario(
    Aparelho aparelho,
    ClienteSync cliente,
    Par anfitriao,
  ) async {
    final pacote = await cliente.baixarPacote(
      par: anfitriao,
      inventarioId: inventario.id,
      chaveSync: inventario.chaveSync,
    );
    aparelho.inventarios.registrarRecebido(pacote.inventario);
    aparelho.patrimonios.inserirRecebidos(pacote.patrimonios);
  }

  test('um aparelho se apresenta sem precisar de chave', () async {
    final apresentacao = await clienteB.apresentar('127.0.0.1', paraA.porta);

    expect(apresentacao.dispositivoId, a.dispositivoId);
    expect(apresentacao.usuarioNome, 'Ana');
    expect(apresentacao.versao, versaoProtocolo);
  });

  test('o pacote inicial leva o inventário e os dados do SUAP', () async {
    await entrarNoInventario(b, clienteB, paraA);

    final noB = b.inventarios.porId(inventario.id);
    expect(noB, isNotNull);
    expect(noB!.nome, 'Campus Picos — Biblioteca');
    expect(noB.chaveSync, inventario.chaveSync);

    final itens = b.patrimonios.todos(inventario.id);
    expect(itens.length, 2);
    expect(itens.first.salaOriginal, 'Coordenação de TI');
    expect(
      itens.first.verificado,
      isFalse,
      reason: 'o levantamento chega pelo log de operações, não pelo pacote',
    );
  });

  test('sem a chave correta o aparelho recusa a conexão', () async {
    expect(
      () => clienteB.baixarPacote(
        par: paraA,
        inventarioId: inventario.id,
        chaveSync: RepositorioInventarios(
          b.banco,
          b.ops,
        ).criar(nome: 'Outro', ano: 2026).chaveSync,
      ),
      throwsA(isA<FalhaSync>()),
    );
  });

  test('um inventário desconhecido responde igual a chave inválida', () async {
    // Distinguir os dois casos confirmaria a existência do inventário a quem
    // não tem a chave.
    expect(
      () => clienteB.baixarPacote(
        par: paraA,
        inventarioId: 'inventario-que-nao-existe',
        chaveSync: inventario.chaveSync,
      ),
      throwsA(isA<FalhaSync>()),
    );
  });

  test('o levantamento atravessa a rede nos dois sentidos', () async {
    await entrarNoInventario(b, clienteB, paraA);

    a.patrimonios.registrarVerificacao(
      patrimonio: a.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Auditório'),
      usuarioNome: 'Ana',
    );
    b.patrimonios.registrarVerificacao(
      patrimonio: b.patrimonios.porId('item-2')!,
      config: const ConfiguracaoLevantamento(sala: 'Laboratório'),
      usuarioNome: 'Bruno',
    );

    final resultado = await clienteB.sincronizar(
      par: paraA,
      inventarioId: inventario.id,
      chaveSync: inventario.chaveSync,
    );

    expect(resultado.recebidas, greaterThan(0));
    expect(resultado.enviadas, greaterThan(0));

    expect(b.patrimonios.porId('item-1')!.salaAtual, 'Auditório');
    expect(a.patrimonios.porId('item-2')!.salaAtual, 'Laboratório');
    expect(a.patrimonios.progresso(inventario.id).verificados, 2);
    expect(b.patrimonios.progresso(inventario.id).verificados, 2);
  });

  test('sincronizar de novo sem novidade não transfere nada', () async {
    await entrarNoInventario(b, clienteB, paraA);

    a.patrimonios.registrarVerificacao(
      patrimonio: a.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Auditório'),
      usuarioNome: 'Ana',
    );

    await clienteB.sincronizar(
      par: paraA,
      inventarioId: inventario.id,
      chaveSync: inventario.chaveSync,
    );
    final segunda = await clienteB.sincronizar(
      par: paraA,
      inventarioId: inventario.id,
      chaveSync: inventario.chaveSync,
    );

    expect(
      segunda.houveTroca,
      isFalse,
      reason: 'o inventário inteiro não é retransmitido a cada encontro',
    );
  });

  test('o conflito é detectado através da rede', () async {
    await entrarNoInventario(b, clienteB, paraA);

    a.patrimonios.registrarVerificacao(
      patrimonio: a.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Biblioteca'),
      usuarioNome: 'Ana',
    );
    b.patrimonios.registrarVerificacao(
      patrimonio: b.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Auditório'),
      usuarioNome: 'Bruno',
    );

    final resultado = await clienteB.sincronizar(
      par: paraA,
      inventarioId: inventario.id,
      chaveSync: inventario.chaveSync,
    );

    expect(resultado.conflitos, greaterThan(0));
    // As duas réplicas acabam com o mesmo valor, ainda que haja conflito
    // pendente de conferência.
    await clienteA.sincronizar(
      par: paraB,
      inventarioId: inventario.id,
      chaveSync: inventario.chaveSync,
    );
    expect(impressaoDe(b, 'item-1'), impressaoDe(a, 'item-1'));
  });

  group('assinatura', () {
    const chave = 'bXVpdG8tc2VjcmV0by1jaGF2ZS1kZS0zMi1ieXRlcy0hIQ==';

    test('confere quando nada foi alterado', () {
      final cabecalho = Assinatura.gerar(
        chaveSync: chave,
        dispositivoId: 'disp-a',
        metodo: 'POST',
        caminho: '/sync/pull',
        corpo: '{"inventario":"x"}',
      );

      final remoto = Assinatura.verificar(
        cabecalho: cabecalho,
        chaveSync: chave,
        metodo: 'POST',
        caminho: '/sync/pull',
        corpo: '{"inventario":"x"}',
      );

      expect(remoto, 'disp-a');
    });

    test('recusa corpo alterado em trânsito', () {
      final cabecalho = Assinatura.gerar(
        chaveSync: chave,
        dispositivoId: 'disp-a',
        metodo: 'POST',
        caminho: '/sync/push',
        corpo: '{"ops":[]}',
      );

      expect(
        Assinatura.verificar(
          cabecalho: cabecalho,
          chaveSync: chave,
          metodo: 'POST',
          caminho: '/sync/push',
          corpo: '{"ops":[{"adulterada":true}]}',
        ),
        isNull,
      );
    });

    test('recusa requisição repetida fora da janela de tempo', () {
      final cabecalho = Assinatura.gerar(
        chaveSync: chave,
        dispositivoId: 'disp-a',
        metodo: 'GET',
        caminho: '/inventario/pacote',
        corpo: '',
        agora: DateTime(2026, 1, 1, 10),
      );

      expect(
        Assinatura.verificar(
          cabecalho: cabecalho,
          chaveSync: chave,
          metodo: 'GET',
          caminho: '/inventario/pacote',
          corpo: '',
          agora: DateTime(2026, 1, 1, 11),
        ),
        isNull,
      );
    });

    test('recusa cabeçalho malformado sem explodir', () {
      for (final lixo in [
        '',
        'Bearer abc',
        'SLAP',
        'SLAP a:b',
        'SLAP a:xyz:c',
      ]) {
        expect(
          Assinatura.verificar(
            cabecalho: lixo,
            chaveSync: chave,
            metodo: 'GET',
            caminho: '/hello',
            corpo: '',
          ),
          isNull,
          reason: 'cabeçalho "$lixo"',
        );
      }
    });
  });

  group('pedido de entrada', () {
    test(
      'o aceite entrega a chave, e com ela o pacote inicial chega',
      () async {
        // O fluxo inteiro da entrada por link: o link não trouxe chave nenhuma,
        // e ela só existe do lado de quem entra depois do "Aceitar".
        aAtende(aceitar: true);

        final chave = await clienteB.pedirEntrada(
          par: paraA,
          inventarioId: inventario.id,
          usuarioNome: 'Bruno',
          matricula: '2024001',
        );

        expect(chave, inventario.chaveSync);

        final pacote = await clienteB.baixarPacote(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: chave,
        );
        b.inventarios.registrarRecebido(pacote.inventario);
        b.patrimonios.inserirRecebidos(pacote.patrimonios);

        expect(b.patrimonios.todos(inventario.id).length, 2);
      },
    );

    test('o pedido diz quem está pedindo, para a pessoa decidir', () async {
      final recebidos = <PedidoEntrada>[];
      inscricao = servidorA.pedidos.listen((p) {
        recebidos.add(p);
        servidorA.responderPedido(p.token, aceitar: true);
      });

      await clienteB.pedirEntrada(
        par: paraA,
        inventarioId: inventario.id,
        usuarioNome: 'Bruno',
        matricula: '2024001',
      );

      expect(recebidos, hasLength(1));
      expect(recebidos.single.dispositivo, b.dispositivoId);
      expect(recebidos.single.usuarioNome, 'Bruno');
      expect(recebidos.single.matricula, '2024001');
      expect(recebidos.single.rotulo, startsWith('Bruno (aparelho '));
    });

    test('a recusa não entrega a chave', () async {
      aAtende(aceitar: false);

      await expectLater(
        clienteB.pedirEntrada(par: paraA, inventarioId: inventario.id),
        throwsA(
          isA<EntradaRecusada>().having(
            (e) => e.motivo,
            'motivo',
            MotivoRecusa.recusado,
          ),
        ),
      );
      expect(b.inventarios.porId(inventario.id), isNull);
    });

    test('sem resposta o pedido caduca, e nada é entregue', () async {
      // Ninguém escuta: o aparelho de Ana está no bolso.
      await expectLater(
        clienteB.pedirEntrada(par: paraA, inventarioId: inventario.id),
        throwsA(
          isA<EntradaRecusada>().having(
            (e) => e.motivo,
            'motivo',
            MotivoRecusa.expirou,
          ),
        ),
      );
    });

    test('o mesmo token não vale duas vezes', () async {
      aAtende(aceitar: true);

      final corpo = PedidoEntrada(
        inventarioId: inventario.id,
        token: gerarTokenEntrada(),
        dispositivo: b.dispositivoId,
        chavePublica: AcordoEfemero.gerar().publica,
        usuarioNome: 'Bruno',
      ).toJson();

      final primeira = await pedirBruto(paraA, corpo);
      expect(primeira['aceito'], isTrue);

      // Quem gravou a rede não reaproveita o pedido de outro para receber a
      // chave uma segunda vez.
      final segunda = await pedirBruto(paraA, corpo);
      expect(segunda['aceito'], isFalse);
      expect(segunda['motivo'], MotivoRecusa.tokenRepetido.name);
      expect(segunda['entrega'], isNull);
    });

    test(
      'pedido sem os campos obrigatórios é recusado sem derrubar nada',
      () async {
        for (final corpo in [
          <String, dynamic>{},
          {'inventario': inventario.id},
          {
            'inventario': inventario.id,
            'token': '',
            'dispositivo': 'x',
            'pub': 'y',
          },
        ]) {
          final resposta = await pedirBruto(paraA, corpo);
          expect(resposta['aceito'], isFalse, reason: '$corpo');
          expect(
            resposta['motivo'],
            MotivoRecusa.invalido.name,
            reason: '$corpo',
          );
        }

        // O servidor continua de pé depois do lixo.
        final apresentacao = await clienteB.apresentar(
          '127.0.0.1',
          paraA.porta,
        );
        expect(apresentacao.dispositivoId, a.dispositivoId);
      },
    );

    test(
      'inventário que o aparelho não tem responde como chave inválida',
      () async {
        await expectLater(
          clienteB.pedirEntrada(
            par: paraA,
            inventarioId: 'inventario-que-nao-existe',
          ),
          throwsA(isA<FalhaSync>()),
        );
      },
    );

    test('chave pública inválida no pedido não entrega nada', () async {
      aAtende(aceitar: true);

      final resposta = await pedirBruto(paraA, {
        'inventario': inventario.id,
        'token': gerarTokenEntrada(),
        'dispositivo': b.dispositivoId,
        'pub': 'isto-nao-e-um-ponto',
      });

      expect(resposta['aceito'], isFalse);
      expect(resposta['motivo'], MotivoRecusa.invalido.name);
    });
  });

  test('a lacuna declarada atravessa a rede e é preenchida', () async {
    // O que falta no meio da sequência de um terceiro só volta se o pedido
    // souber dizer qual intervalo é.
    await entrarNoInventario(b, clienteB, paraA);
    const carla = 'aparelho-da-carla';

    plantarOperacoes(
      a,
      inventarioId: inventario.id,
      dispositivo: carla,
      patrimonioId: 'item-1',
      de: 1,
      ate: 5,
    );
    for (final aparelho in [a, b]) {
      plantarOperacoes(
        aparelho,
        inventarioId: inventario.id,
        dispositivo: carla,
        patrimonioId: 'item-1',
        de: 6,
        ate: 10,
      );
    }

    expect(b.ops.lacunasDe(inventario.id)[carla], isNotEmpty);

    await clienteB.sincronizar(
      par: paraA,
      inventarioId: inventario.id,
      chaveSync: inventario.chaveSync,
    );

    expect(b.ops.lacunasDe(inventario.id)[carla], isEmpty);
    expect(b.ops.vetorDe(inventario.id)[carla], 10);
  });

  group('isolamento entre inventários', () {
    /// Um segundo inventário no aparelho da Ana, de cuja chave o Bruno não
    /// sabe nada. É o alvo da invasão.
    late Inventario segredo;

    setUp(() {
      segredo = a.inventarios.criar(nome: 'Campus Teresina', ano: 2026);
      a.patrimonios.inserirRecebidos([
        patrimonioDeTeste(
          id: 'item-secreto',
          inventarioId: segredo.id,
          tombo: '99999',
          sala: 'Reitoria',
        ),
      ]);
      a.patrimonios.registrarVerificacao(
        patrimonio: a.patrimonios.porId('item-secreto')!,
        config: const ConfiguracaoLevantamento(sala: 'Almoxarifado'),
        usuarioNome: 'Ana',
      );
    });

    test('a chave de um inventário não puxa o log de outro', () async {
      final resposta = await requisitarBruto(
        caminho: Rotas.pull,
        inventarioNaQuery: inventario.id,
        chaveSync: inventario.chaveSync,
        corpo: PedidoPull(
          inventarioId: segredo.id,
          vetor: VersionVector.vazia,
        ).toJson(),
      );

      expect(resposta.status, HttpStatus.badRequest);
      expect(
        jsonEncode(resposta.corpo),
        isNot(contains('Almoxarifado')),
        reason: 'nada do inventário alheio volta na resposta',
      );
    });

    test('a chave de um inventário não escreve noutro', () async {
      final resposta = await requisitarBruto(
        caminho: Rotas.push,
        inventarioNaQuery: inventario.id,
        chaveSync: inventario.chaveSync,
        corpo: LoteOperacoes(
          inventarioId: segredo.id,
          ops: [
            Operacao(
              opId: 'forjada-1',
              inventarioId: segredo.id,
              entidade: 'inventario',
              entidadeId: segredo.id,
              campo: 'nome',
              valor: 'Tomado',
              hlc: Hlc(
                DateTime.now()
                    .add(const Duration(minutes: 1))
                    .millisecondsSinceEpoch,
                0,
                b.dispositivoId,
              ),
              dispositivo: b.dispositivoId,
              seq: 1,
              ctxId: null,
              usuarioNome: 'Bruno',
              usuarioMatricula: null,
              criadoEm: DateTime.now().millisecondsSinceEpoch,
            ),
          ],
        ).toJson(),
      );

      expect(resposta.status, HttpStatus.badRequest);
      expect(a.inventarios.porId(segredo.id)!.nome, 'Campus Teresina');
    });

    test(
      'operação de outro inventário dentro do lote certo é recusada',
      () async {
        // Aqui o corpo declara o inventário da query, e são as operações que
        // apontam para outro lugar.
        final resposta = await requisitarBruto(
          caminho: Rotas.push,
          inventarioNaQuery: inventario.id,
          chaveSync: inventario.chaveSync,
          corpo: LoteOperacoes(
            inventarioId: inventario.id,
            ops: [
              Operacao(
                opId: 'forjada-2',
                inventarioId: segredo.id,
                entidade: 'patrimonio',
                entidadeId: 'item-secreto',
                campo: CampoPatrimonio.salaAtual,
                valor: 'Invadida',
                hlc: Hlc(
                  DateTime.now()
                      .add(const Duration(minutes: 1))
                      .millisecondsSinceEpoch,
                  0,
                  b.dispositivoId,
                ),
                dispositivo: b.dispositivoId,
                seq: 1,
                ctxId: null,
                usuarioNome: 'Bruno',
                usuarioMatricula: null,
                criadoEm: DateTime.now().millisecondsSinceEpoch,
              ),
            ],
          ).toJson(),
        );

        expect(resposta.status, HttpStatus.badRequest);
        expect(a.patrimonios.porId('item-secreto')!.salaAtual, 'Almoxarifado');
      },
    );

    test('o cliente recusa uma resposta de outro inventário', () async {
      // O mesmo buraco do lado de quem pede: sem conferir, um par responderia
      // com o log de outro inventário a quem tem a chave deste.
      await entrarNoInventario(b, clienteB, paraA);
      final hostil = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => hostil.close(force: true));

      final cifra = CifraSync(inventario.chaveSync);
      unawaited(
        hostil.forEach((req) async {
          if (req.uri.path == Rotas.hello) {
            req.response
              ..headers.contentType = ContentType.json
              ..write(
                jsonEncode(
                  Apresentacao(
                    dispositivoId: 'aparelho-hostil',
                    agora: DateTime.now().millisecondsSinceEpoch,
                  ).toJson(),
                ),
              );
            await req.response.close();
            return;
          }
          await utf8.decoder.bind(req).join();
          req.response
            ..headers.contentType = ContentType.text
            ..write(
              cifra.cifrar(
                LoteOperacoes(
                  inventarioId: 'outro-inventario-qualquer',
                  ops: const [],
                ).toJson(),
                contexto: CifraSync.contextoResposta('POST', req.uri.path),
              ),
            );
          await req.response.close();
        }),
      );

      await expectLater(
        clienteB.sincronizar(
          par: Par(
            dispositivoId: 'aparelho-hostil',
            host: '127.0.0.1',
            porta: hostil.port,
          ),
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<FalhaSync>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('outro inventário'),
          ),
        ),
      );
    });
  });

  group('identidade duplicada', () {
    /// Faz o aparelho da Ana e o do Bruno discordarem sobre qual operação
    /// ocupa uma posição da sequência de [dono] — que é o que acontece quando
    /// os dados do aplicativo são copiados de um celular para outro.
    Future<void> duasHistoriasPara(Aparelho dono) async {
      await entrarNoInventario(b, clienteB, paraA);
      dono.patrimonios.registrarVerificacao(
        patrimonio: dono.patrimonios.porId('item-1')!,
        config: const ConfiguracaoLevantamento(sala: 'Auditório'),
        usuarioNome: dono.apelido,
      );
      // O outro aparelho tem, nas mesmas posições, operações diferentes.
      plantarOperacoes(
        dono == a ? b : a,
        inventarioId: inventario.id,
        dispositivo: dono.dispositivoId,
        patrimonioId: 'item-2',
        de: 1,
        ate: dono.ops.vetorDe(inventario.id)[dono.dispositivoId],
      );
    }

    test('a identidade do par não vira ordem para este se apagar', () async {
      // O caso do defeito: a identidade duplicada é a da Ana, e ela recusa
      // dizendo "outro aparelho está usando a identidade deste" — dela. O
      // Bruno, que não tem nada a ver com isso, era levado a "Gerar nova
      // identidade" e a perder o trabalho ainda não entregue.
      await duasHistoriasPara(a);

      await expectLater(
        clienteB.sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<IdentidadeEmConflito>()
              .having((e) => e.dispositivo, 'aparelho', a.dispositivoId)
              .having((e) => e.esteAparelho, 'é o deste aparelho', isFalse)
              .having((e) => e.mensagem, 'mensagem', contains('Dois aparelhos'))
              .having(
                (e) => e.mensagem,
                'mensagem',
                isNot(contains('identidade deste')),
              ),
        ),
      );
    });

    test('quando a identidade é a deste, a mensagem diz isso', () async {
      await duasHistoriasPara(b);

      await expectLater(
        clienteB.sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<IdentidadeEmConflito>()
              .having((e) => e.esteAparelho, 'é o deste aparelho', isTrue)
              .having(
                (e) => e.mensagem,
                'mensagem',
                startsWith('Outro aparelho está usando a identidade deste'),
              ),
        ),
      );
    });

    test('a recusa vai estruturada, com um texto neutro em erro', () async {
      await duasHistoriasPara(a);

      final resposta = await requisitarBruto(
        caminho: Rotas.pull,
        inventarioNaQuery: inventario.id,
        chaveSync: inventario.chaveSync,
        corpo: PedidoPull(
          inventarioId: inventario.id,
          vetor: b.ops.vetorDe(inventario.id),
          cabecas: b.ops.cabecas(inventario.id),
        ).toJson(),
      );

      expect(resposta.status, HttpStatus.conflict);
      expect(resposta.corpo['tipo'], ErroIdentidade.codigo);
      expect(resposta.corpo['dispositivo'], a.dispositivoId);
      expect(
        resposta.corpo['erro'],
        allOf(
          isA<String>(),
          contains('Dois aparelhos'),
          isNot(contains('identidade deste')),
        ),
        reason: 'uma versão anterior mostra este texto, e ele serve aos dois',
      );
    });
  });

  group('convite por QR', () {
    test('ida e volta preserva a chave', () {
      final convite = ConviteInventario.de(inventario);
      final lido = ConviteInventario.decodificar(convite.codificar());

      expect(lido, isNotNull);
      expect(lido!.inventarioId, inventario.id);
      expect(lido.chaveSync, inventario.chaveSync);
      expect(lido.nome, inventario.nome);
      expect(lido.ano, 2026);
    });

    test('QR de outro aplicativo é ignorado em silêncio', () {
      // Apontar a câmera para qualquer código é o caso comum.
      expect(ConviteInventario.decodificar('https://ifpi.edu.br'), isNull);
      expect(ConviteInventario.decodificar('{"algo":"outro"}'), isNull);
      expect(ConviteInventario.decodificar(''), isNull);
    });
  });
}
