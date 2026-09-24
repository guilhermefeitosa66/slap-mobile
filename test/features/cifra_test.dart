import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/features/sync/cifra.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/protocolo.dart';
import 'package:slap_mobile/features/sync/servidor.dart';

import '../apoio/rede_simulada.dart';

/// O corpo da sincronização cifrado: quem captura a rede não lê patrimônio.
void main() {
  const chave = 'bXVpdG8tc2VjcmV0by1jaGF2ZS1kZS0zMi1ieXRlcy0hIQ==';
  const contexto = 'pedido POST /sync/push';

  test('HKDF-SHA256 confere com o vetor da RFC 5869 (caso 1)', () {
    final okm = hkdfSha256(
      List.filled(22, 0x0b),
      sal: List.generate(13, (i) => i),
      info: List.generate(10, (i) => 0xf0 + i),
    );
    String hex(List<int> b) =>
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    expect(
      hex(okm),
      '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf',
    );
  });

  group('cifra', () {
    final conteudo = {
      'descricao': 'PROJETOR MULTIMÍDIA',
      'sala': 'Coordenação de TI',
      'responsavel': 'Maria José',
    };

    test('ida e volta', () {
      final cifra = CifraSync(chave);
      final texto = cifra.cifrar(conteudo, contexto: contexto);
      expect(cifra.decifrar(texto, contexto: contexto), conteudo);
    });

    test('nada do conteúdo aparece no que trafega', () {
      final texto = CifraSync(chave).cifrar(conteudo, contexto: contexto);
      final bruto = latin1.decode(base64Url.decode(texto));
      for (final palavra in ['PROJETOR', 'Coordena', 'Maria', 'sala']) {
        expect(texto.contains(palavra), isFalse);
        expect(bruto.contains(palavra), isFalse);
      }
    });

    test('nonce novo a cada mensagem: o mesmo conteúdo nunca se repete', () {
      final cifra = CifraSync(chave);
      final vistos = {
        for (var i = 0; i < 200; i++)
          base64Url
              .decode(cifra.cifrar(conteudo, contexto: contexto))
              .sublist(0, 12)
              .join(','),
      };
      expect(vistos, hasLength(200));
      expect(
        cifra.cifrar(conteudo, contexto: contexto),
        isNot(cifra.cifrar(conteudo, contexto: contexto)),
      );
    });

    test('um bit alterado em trânsito é recusado', () {
      final cifra = CifraSync(chave);
      final bytes = base64Url.decode(
        cifra.cifrar(conteudo, contexto: contexto),
      );
      bytes[bytes.length ~/ 2] ^= 0x01;
      expect(
        () => cifra.decifrar(base64Url.encode(bytes), contexto: contexto),
        throwsA(isA<CorpoIlegivel>()),
      );
    });

    test('outra chave não decifra', () {
      final texto = CifraSync(chave).cifrar(conteudo, contexto: contexto);
      final outra = base64Url.encode(List.filled(32, 7));
      expect(
        () => CifraSync(outra).decifrar(texto, contexto: contexto),
        throwsA(isA<CorpoIlegivel>()),
      );
    });

    test(
      'corpo de uma rota não serve em outra, nem a resposta como pedido',
      () {
        final cifra = CifraSync(chave);
        final pedido = cifra.cifrar(
          conteudo,
          contexto: CifraSync.contextoPedido('POST', Rotas.push),
        );
        expect(
          () => cifra.decifrar(
            pedido,
            contexto: CifraSync.contextoPedido('POST', Rotas.pull),
          ),
          throwsA(isA<CorpoIlegivel>()),
        );
        expect(
          () => cifra.decifrar(
            pedido,
            contexto: CifraSync.contextoResposta('POST', Rotas.push),
          ),
          throwsA(isA<CorpoIlegivel>()),
        );
      },
    );

    test('lixo é recusado sem explodir', () {
      final cifra = CifraSync(chave);
      for (final lixo in [
        '',
        'abc',
        '!!!',
        base64Url.encode([1, 2, 3]),
      ]) {
        expect(
          () => cifra.decifrar(lixo, contexto: contexto),
          throwsA(isA<CorpoIlegivel>()),
          reason: lixo,
        );
      }
    });

    test('a assinatura não usa a chave do QR diretamente', () {
      final cabecalho = Assinatura.gerar(
        chaveSync: chave,
        dispositivoId: 'd',
        metodo: 'GET',
        caminho: '/x',
        corpo: '',
        agora: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final comChaveCrua = base64Url.encode(
        Hmac(sha256, base64Url.decode(chave))
            .convert(
              utf8.encode(
                'GET\n/x\n1000\n${sha256.convert(utf8.encode('')).toString()}',
              ),
            )
            .bytes,
      );
      expect(cabecalho.endsWith(comChaveCrua), isFalse);
    });
  });

  group('acordo efêmero', () {
    // A chave do inventário é entregue por este acordo depois do aceite: o
    // canal cifrado de sempre deriva da própria `chave_sync`, que quem está
    // entrando ainda não tem.
    const rotulo = 'slap/entrada/inv-1/token-1|pub-a|pub-b';

    test('os dois lados chegam à mesma chave sem ela trafegar', () {
      final origem = AcordoEfemero.gerar();
      final pedinte = AcordoEfemero.gerar();

      final daOrigem = origem.combinar(pedinte.publica, rotulo: rotulo);
      final doPedinte = pedinte.combinar(origem.publica, rotulo: rotulo);

      final envelope = daOrigem.cifrar({'chave': chave}, contexto: contexto);
      expect(doPedinte.decifrar(envelope, contexto: contexto), {
        'chave': chave,
      });

      // O que atravessa a rede são as duas públicas e o envelope. Nenhum
      // deles contém a chave do inventário.
      for (final trafegado in [origem.publica, pedinte.publica, envelope]) {
        expect(trafegado.contains(chave), isFalse);
      }
    });

    test('um terceiro par de chaves não abre a entrega', () {
      final origem = AcordoEfemero.gerar();
      final pedinte = AcordoEfemero.gerar();
      final bisbilhoteiro = AcordoEfemero.gerar();

      final envelope = origem.combinar(pedinte.publica, rotulo: rotulo).cifrar({
        'chave': chave,
      }, contexto: contexto);

      expect(
        () => bisbilhoteiro
            .combinar(origem.publica, rotulo: rotulo)
            .decifrar(envelope, contexto: contexto),
        throwsA(isA<CorpoIlegivel>()),
      );
    });

    test('rótulo diferente não abre: a chave vale para um pedido só', () {
      final origem = AcordoEfemero.gerar();
      final pedinte = AcordoEfemero.gerar();

      final envelope = origem.combinar(pedinte.publica, rotulo: rotulo).cifrar({
        'chave': chave,
      }, contexto: contexto);

      expect(
        () => pedinte
            .combinar(origem.publica, rotulo: '$rotulo-de-outro-pedido')
            .decifrar(envelope, contexto: contexto),
        throwsA(isA<CorpoIlegivel>()),
      );
    });

    test('cada acordo gera um par novo', () {
      final publicas = {
        for (var i = 0; i < 20; i++) AcordoEfemero.gerar().publica,
      };
      expect(publicas.length, 20);
    });

    test('chave pública inválida é recusada sem explodir', () {
      final acordo = AcordoEfemero.gerar();
      for (final lixo in [
        '',
        'nao-e-base64!!',
        base64Url.encode(List.filled(65, 4)),
        // Ponto fora da curva: o começo do ataque de curva inválida.
        base64Url.encode([4, ...List.filled(64, 1)]),
      ]) {
        expect(
          () => acordo.combinar(lixo, rotulo: rotulo),
          throwsA(isA<CorpoIlegivel>()),
          reason: 'pública "$lixo"',
        );
      }
    });
  });

  group('na rede', () {
    late Aparelho a;
    late ServidorSync servidor;
    late Inventario inventario;
    late int porta;

    setUp(() async {
      a = Aparelho('Ana');
      inventario = a.inventarios.criar(nome: 'Inventário Sigiloso', ano: 2026);
      a.patrimonios.inserirRecebidos([
        patrimonioDeTeste(
          id: 'item-1',
          inventarioId: inventario.id,
          tombo: '424242',
          sala: 'Sala do Reitor',
          responsavel: 'Fulano de Tal',
        ),
      ]);
      servidor = ServidorSync(
        banco: a.banco,
        ops: a.ops,
        inventarios: a.inventarios,
        patrimonios: a.patrimonios,
      );
      porta = await servidor.iniciar();
    });

    tearDown(() async {
      await servidor.dispose();
      a.fechar();
    });

    Future<(int, String)> pedirPacote({String? versao}) async {
      final cliente = HttpClient();
      try {
        final req = await cliente.getUrl(
          Uri.parse(
            'http://127.0.0.1:$porta${Rotas.pacote}?inventario=${inventario.id}',
          ),
        );
        if (versao != null) req.headers.set(cabecalhoVersao, versao);
        req.headers.set(
          HttpHeaders.authorizationHeader,
          Assinatura.gerar(
            chaveSync: inventario.chaveSync,
            dispositivoId: 'quem-escuta',
            metodo: 'GET',
            caminho: Rotas.pacote,
            corpo: '',
          ),
        );
        final resposta = await req.close();
        return (resposta.statusCode, await utf8.decoder.bind(resposta).join());
      } finally {
        cliente.close(force: true);
      }
    }

    test('o que passa pela rede não revela patrimônio', () async {
      final (status, texto) = await pedirPacote(versao: '$versaoProtocolo');
      expect(status, HttpStatus.ok);
      for (final segredo in [
        'Sigiloso',
        '424242',
        'Reitor',
        'Fulano',
        'patrimonios',
      ]) {
        expect(texto.contains(segredo), isFalse, reason: segredo);
      }

      // Com a chave do inventário, o conteúdo está todo lá.
      final pacote = PacoteInventario.fromJson(
        CifraSync(inventario.chaveSync).decifrar(
          texto,
          contexto: CifraSync.contextoResposta('GET', Rotas.pacote),
        ),
      );
      expect(pacote.inventario.nome, 'Inventário Sigiloso');
      expect(pacote.patrimonios.single.salaOriginal, 'Sala do Reitor');
    });

    test('aparelho de outra versão é recusado com explicação', () async {
      for (final versao in [null, '1', '${versaoProtocolo + 1}']) {
        final (status, texto) = await pedirPacote(versao: versao);
        expect(status, HttpStatus.upgradeRequired, reason: '$versao');
        final j = jsonDecode(texto) as Map<String, dynamic>;
        expect(j['versao'], versaoProtocolo);
        expect(j['mensagem'], contains('Atualize os dois aparelhos'));
      }
    });

    test('par de versão anterior aparece com a explicação na tela', () async {
      // Um aparelho que ainda fala o protocolo 1.
      final antigo = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => antigo.close(force: true));
      antigo.listen((req) {
        req.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode(
              const Apresentacao(
                dispositivoId: 'antigo',
                usuarioNome: 'Bruno',
                versao: 1,
              ).toJson(),
            ),
          );
        req.response.close();
      });

      await expectLater(
        ClienteSync(a.ops).sincronizar(
          par: Par(
            dispositivoId: 'antigo',
            usuarioNome: 'Bruno',
            host: '127.0.0.1',
            porta: antigo.port,
          ),
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<FalhaSync>().having(
            (e) => e.mensagem,
            'mensagem',
            allOf(
              contains('Bruno'),
              contains('versão anterior'),
              contains('Atualize os dois aparelhos'),
            ),
          ),
        ),
      );
    });
  });
}
