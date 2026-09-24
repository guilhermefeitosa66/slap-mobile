import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/formato.dart';
import 'package:slap_mobile/core/hlc.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/protocolo.dart';
import 'package:slap_mobile/features/sync/servidor.dart';

import '../apoio/rede_simulada.dart';

/// Relógio fora de sincronia: celular com data errada é comum, e a
/// sincronização precisa dizer isso em vez de falhar com erro genérico.
void main() {
  late Aparelho a;
  late Aparelho b;
  late Inventario inventario;
  final servidores = <ServidorSync>[];

  setUp(() {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    a.patrimonios.inserirRecebidos([
      patrimonioDeTeste(id: 'item-1', inventarioId: inventario.id, tombo: '1'),
      patrimonioDeTeste(id: 'item-2', inventarioId: inventario.id, tombo: '2'),
    ]);
    RedeSimulada.distribuir(a, [b], inventario);
  });

  tearDown(() async {
    for (final s in servidores) {
      await s.dispose();
    }
    servidores.clear();
    a.fechar();
    b.fechar();
  });

  /// Sobe o servidor de [aparelho], com o relógio deslocado de [deslocamento].
  Future<(ServidorSync, Par)> servir(
    Aparelho aparelho, {
    Duration deslocamento = Duration.zero,
  }) async {
    final servidor = ServidorSync(
      banco: aparelho.banco,
      ops: aparelho.ops,
      inventarios: aparelho.inventarios,
      patrimonios: aparelho.patrimonios,
      relogio: () => DateTime.now().add(deslocamento),
    );
    servidores.add(servidor);
    final porta = await servidor.iniciar();
    return (
      servidor,
      Par(
        dispositivoId: aparelho.dispositivoId,
        usuarioNome: aparelho.apelido,
        host: '127.0.0.1',
        porta: porta,
      ),
    );
  }

  void verificar(Aparelho aparelho, String item) {
    aparelho.patrimonios.registrarVerificacao(
      patrimonio: aparelho.patrimonios.porId(item)!,
      config: const ConfiguracaoLevantamento(sala: 'Auditório'),
      usuarioNome: aparelho.apelido,
    );
  }

  /// Faz [aparelho] escrever as próximas operações com o relógio adiantado,
  /// como faria um celular que estava com a data errada.
  void adiantarRelogioDasOperacoes(Aparelho aparelho, Duration quanto) {
    final futuro = Hlc(
      DateTime.now().add(quanto).millisecondsSinceEpoch,
      0,
      aparelho.dispositivoId,
    );
    aparelho.banco.gravarConfig(Config.hlcLocal, futuro.codificar());
  }

  int opsDe(Aparelho em, Aparelho autor) =>
      em.ops.vetorDe(inventario.id)[autor.dispositivoId];

  group('relógio do par', () {
    test('par adiantado: recusa antes de trocar qualquer coisa', () async {
      verificar(a, 'item-1');
      verificar(b, 'item-2');
      final (_, paraA) = await servir(
        a,
        deslocamento: const Duration(minutes: 20),
      );

      final cliente = ClienteSync(b.ops);
      await expectLater(
        cliente.sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<RelogioDivergente>()
              .having((e) => e.aparelho, 'aparelho', 'Ana')
              .having((e) => e.adiantado, 'adiantado', isTrue)
              .having(
                (e) => e.diferenca.inMinutes,
                'minutos',
                inInclusiveRange(19, 20),
              )
              .having(
                (e) => e.mensagem,
                'mensagem',
                contains('data e a hora automáticas'),
              ),
        ),
      );

      expect(opsDe(b, a), 0, reason: 'nada do par foi aplicado');
      expect(opsDe(a, b), 0, reason: 'nada foi enviado ao par');
    });

    test('este aparelho adiantado: o par aparece como atrasado', () async {
      final (_, paraA) = await servir(a);
      final cliente = ClienteSync(
        b.ops,
        relogio: () => DateTime.now().add(const Duration(minutes: 30)),
      );

      await expectLater(
        cliente.sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<RelogioDivergente>()
              .having((e) => e.adiantado, 'adiantado', isFalse)
              .having((e) => e.mensagem, 'mensagem', contains('atrasado')),
        ),
      );
    });

    test('diferença pequena, normal entre celulares, não atrapalha', () async {
      verificar(a, 'item-1');
      final (_, paraA) = await servir(
        a,
        deslocamento: const Duration(minutes: 2),
      );

      final resultado = await ClienteSync(b.ops).sincronizar(
        par: paraA,
        inventarioId: inventario.id,
        chaveSync: inventario.chaveSync,
      );
      expect(resultado.recebidas, greaterThan(0));
    });

    test(
      'assinatura fora da janela é explicada como relógio, não como chave errada',
      () async {
        final (servidor, paraA) = await servir(a);
        final eventos = <EventoSync>[];
        servidor.eventos.listen(eventos.add);

        // Sem passar pela apresentação: é o caminho do pacote inicial.
        final cliente = ClienteSync(
          b.ops,
          relogio: () => DateTime.now().subtract(const Duration(hours: 3)),
        );
        await expectLater(
          cliente.baixarPacote(
            par: paraA,
            inventarioId: inventario.id,
            chaveSync: inventario.chaveSync,
          ),
          throwsA(
            isA<RelogioDivergente>()
                .having((e) => e.adiantado, 'par adiantado', isTrue)
                .having(
                  (e) => e.diferenca.inMinutes,
                  'minutos',
                  inInclusiveRange(179, 181),
                ),
          ),
        );

        await pumpEventQueue();
        expect(
          eventos,
          hasLength(1),
          reason: 'o outro lado também fica sabendo',
        );
        expect(eventos.single.recusadoPorRelogio, isTrue);
        expect(eventos.single.dispositivoRemoto, b.dispositivoId);
      },
    );
  });

  group('operações do futuro', () {
    test('no pull: o lote inteiro é recusado e o autor é nomeado', () async {
      verificar(a, 'item-1');
      adiantarRelogioDasOperacoes(a, const Duration(hours: 2));
      verificar(a, 'item-2');
      final (_, paraA) = await servir(a);

      final hlcAntes = b.banco.lerConfig(Config.hlcLocal);
      await expectLater(
        ClienteSync(b.ops).sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<RelogioDivergente>()
              .having((e) => e.aparelho, 'aparelho', 'Ana')
              .having(
                (e) => e.diferenca.inMinutes,
                'minutos',
                greaterThan(100),
              ),
        ),
      );

      expect(opsDe(b, a), 0, reason: 'nem a operação de horário correto entra');
      expect(
        b.banco.lerConfig(Config.hlcLocal),
        hlcAntes,
        reason: 'o relógio local não é arrastado para o futuro',
      );
    });

    test('no push: o par recusa e nada do lote entra nele', () async {
      final (servidor, paraA) = await servir(a);
      final eventos = <EventoSync>[];
      servidor.eventos.listen(eventos.add);

      adiantarRelogioDasOperacoes(b, const Duration(hours: 2));
      verificar(b, 'item-1');

      await expectLater(
        ClienteSync(b.ops).sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(
          isA<RelogioDivergente>().having(
            (e) => e.aparelho,
            'aparelho',
            'este aparelho',
          ),
        ),
      );

      expect(opsDe(a, b), 0);
      await pumpEventQueue();
      expect(eventos.where((e) => e.recusadoPorRelogio), hasLength(1));
    });

    test('corrigido o relógio, a sincronização volta a passar', () async {
      verificar(a, 'item-1');
      final (servidor, paraA) = await servir(a);
      final cliente = ClienteSync(
        b.ops,
        relogio: () => DateTime.now().add(const Duration(minutes: 30)),
      );
      await expectLater(
        cliente.sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(isA<RelogioDivergente>()),
      );

      final resultado = await ClienteSync(b.ops).sincronizar(
        par: paraA,
        inventarioId: inventario.id,
        chaveSync: inventario.chaveSync,
      );
      expect(resultado.recebidas, greaterThan(0));
      expect(servidor.ativo, isTrue);
    });
  });

  group('assinatura', () {
    const chave = 'bXVpdG8tc2VjcmV0by1jaGF2ZS1kZS0zMi1ieXRlcy0hIQ==';

    test('chave certa com horário fora da janela é relógio', () {
      final cabecalho = Assinatura.gerar(
        chaveSync: chave,
        dispositivoId: 'disp-a',
        metodo: 'GET',
        caminho: '/inventario/pacote',
        corpo: '',
        agora: DateTime(2026, 1, 1, 10),
      );

      final conferencia = Assinatura.conferir(
        cabecalho: cabecalho,
        chaveSync: chave,
        metodo: 'GET',
        caminho: '/inventario/pacote',
        corpo: '',
        agora: DateTime(2026, 1, 1, 11),
      );
      expect(conferencia.situacao, SituacaoAssinatura.foraDaJanela);
      expect(conferencia.dispositivoId, 'disp-a');
    });

    test('chave errada fora da janela continua só inválida', () {
      // Quem não tem a chave não fica sabendo nem do relógio.
      final cabecalho = Assinatura.gerar(
        chaveSync: chave,
        dispositivoId: 'disp-a',
        metodo: 'GET',
        caminho: '/inventario/pacote',
        corpo: '',
        agora: DateTime(2026, 1, 1, 10),
      );

      final conferencia = Assinatura.conferir(
        cabecalho: cabecalho,
        chaveSync: 'b3V0cmEtY2hhdmUtZGUtMzItYnl0ZXMtcGFyYS10ZXN0ZQ==',
        metodo: 'GET',
        caminho: '/inventario/pacote',
        corpo: '',
        agora: DateTime(2026, 1, 1, 11),
      );
      expect(conferencia.situacao, SituacaoAssinatura.invalida);
      expect(conferencia.dispositivoId, isNull);
    });
  });

  test('a diferença é dita por extenso', () {
    expect(descreverDuracao(const Duration(seconds: 20)), 'menos de 1 min');
    expect(descreverDuracao(const Duration(minutes: 12)), '12 min');
    expect(descreverDuracao(const Duration(hours: 2)), '2 h');
    expect(descreverDuracao(const Duration(hours: 2, minutes: 5)), '2 h 5 min');
    expect(descreverDuracao(const Duration(days: 3, hours: 4)), '3 dias');
    expect(descreverDuracao(const Duration(minutes: -12)), '12 min');
  });
}
