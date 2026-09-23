import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/descoberta.dart';
import 'package:slap_mobile/features/sync/multicast.dart';
import 'package:slap_mobile/features/sync/protocolo.dart';

/// Trava que registra o que foi pedido, sem falar com o sistema.
class TravaDeTeste implements TravaMulticast {
  final String? falha;
  bool adquirida = false;
  int aquisicoes = 0;
  int liberacoes = 0;

  TravaDeTeste({this.falha});

  @override
  Future<String?> adquirir() async {
    aquisicoes++;
    if (falha == null) adquirida = true;
    return falha;
  }

  @override
  Future<void> liberar() async {
    liberacoes++;
    adquirida = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Descoberta nova(TravaDeTeste trava, Set<ViaDescoberta> vias) => Descoberta(
    dispositivoId: 'aparelho-de-teste',
    usuarioNome: () => 'Ana',
    porta: 4000,
    vias: vias,
    trava: trava,
  );

  group('trava de multicast', () {
    test('fica segura só enquanto a descoberta está ativa', () async {
      final trava = TravaDeTeste();
      final descoberta = nova(trava, {ViaDescoberta.beacon});

      await descoberta.iniciar();
      expect(trava.aquisicoes, 1);
      // Se o ambiente não deixar abrir o socket, a descoberta não sobe e a
      // trava já tem de ter sido solta; se subir, tem de estar segura.
      expect(trava.adquirida, descoberta.ativa);

      await descoberta.dispose();
      expect(trava.adquirida, isFalse);
      expect(descoberta.travaAdquirida, isFalse);
    });

    test('é liberada quando a descoberta falha ao subir', () async {
      // Ocupa a porta do beacon sem compartilhamento: o bind da descoberta
      // falha, e nenhuma via fica ativa.
      final ocupante = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        portaMulticast,
        reuseAddress: false,
      );
      addTearDown(ocupante.close);

      final trava = TravaDeTeste();
      final descoberta = nova(trava, {ViaDescoberta.beacon});
      await descoberta.iniciar();

      expect(descoberta.ativa, isFalse);
      expect(trava.aquisicoes, 1);
      expect(trava.liberacoes, 1, reason: 'ninguém vai chamar parar()');
      expect(trava.adquirida, isFalse);
      await descoberta.dispose();
      expect(trava.liberacoes, 1, reason: 'liberar duas vezes é desnecessário');
    });

    test('sem o beacon, a trava nem é pedida', () async {
      final trava = TravaDeTeste();
      final descoberta = nova(trava, {});
      await descoberta.iniciar();
      await descoberta.dispose();
      expect(trava.aquisicoes, 0);
    });

    test('trava negada vira aviso, e a busca continua', () async {
      final trava = TravaDeTeste(falha: 'sem a permissão');
      final descoberta = nova(trava, {ViaDescoberta.beacon});

      await descoberta.iniciar();
      expect(
        descoberta.avisos.join('\n'),
        allOf(contains('sem a permissão'), contains('A busca continua')),
      );
      expect(descoberta.travaAdquirida, isFalse);

      await descoberta.dispose();
      expect(trava.liberacoes, 0, reason: 'não há o que liberar');
    });
  });

  group('canal do Android', () {
    final chamadas = <String>[];

    void responder(Object? Function(MethodCall) resposta) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TravaMulticastAndroid.canal, (
            chamada,
          ) async {
            chamadas.add(chamada.method);
            return resposta(chamada);
          });
    }

    setUp(chamadas.clear);
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(TravaMulticastAndroid.canal, null),
    );

    test('adquire e libera pelo canal', () async {
      responder((_) => true);
      final trava = TravaMulticastAndroid();

      expect(await trava.adquirir(), isNull);
      await trava.liberar();
      expect(chamadas, ['adquirirMulticast', 'liberarMulticast']);
    });

    test('a falha do sistema chega com o motivo', () async {
      responder(
        (_) => throw PlatformException(
          code: 'multicast_indisponivel',
          message: 'WifiManager indisponível neste aparelho',
        ),
      );

      expect(
        await TravaMulticastAndroid().adquirir(),
        'WifiManager indisponível neste aparelho',
      );
    });
  });

  test('por padrão as duas vias ficam ligadas', () {
    expect(ViaDescoberta.configuradas(), ViaDescoberta.values.toSet());
  });

  group('vias de cada aparelho', () {
    Par visto(String host, String via) => Par(
      dispositivoId: 'outro-aparelho',
      usuarioNome: 'Bruno',
      host: host,
      porta: 4100,
      origens: {via},
    );

    test('se somam, em vez de ficar só a última', () async {
      final descoberta = nova(TravaDeTeste(), ViaDescoberta.values.toSet());
      addTearDown(descoberta.dispose);
      final avisos = <List<Par>>[];
      final escuta = descoberta.mudancas.listen(avisos.add);
      addTearDown(escuta.cancel);

      descoberta.adicionar(visto('bruno.local', 'mdns'));
      // O beacon traz o IP e se repete a cada poucos segundos.
      descoberta.adicionar(visto('192.168.0.20', 'beacon'));
      descoberta.adicionar(visto('192.168.0.20', 'beacon'));
      descoberta.adicionar(visto('192.168.0.20', 'beacon'));
      await Future<void>.delayed(Duration.zero);

      final par = descoberta.pares.single;
      expect(par.origens, {'mdns', 'beacon'});
      expect(par.host, '192.168.0.20');
      expect(descreverOrigens(par.origens), 'mDNS e anúncio na rede');
      // Um aviso por mudança de verdade: os anúncios repetidos não fazem a
      // lista piscar.
      expect(avisos, hasLength(2));
    });

    test('dizem por extenso por onde o aparelho apareceu', () {
      expect(descreverOrigens({'mdns'}), 'mDNS');
      expect(descreverOrigens({'beacon'}), 'anúncio na rede');
    });
  });
}
