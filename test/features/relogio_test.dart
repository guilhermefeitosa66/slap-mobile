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
      // A operação do futuro é de um terceiro, e a Ana só a repassa: ela não
      // pode consertar o que não escreveu.
      verificar(a, 'item-1');
      plantarOperacoes(
        a,
        inventarioId: inventario.id,
        dispositivo: 'aparelho-da-carla',
        patrimonioId: 'item-2',
        de: 1,
        ate: 2,
        usuario: 'Carla',
        baseMillis: DateTime.now()
            .add(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      );
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
              .having((e) => e.aparelho, 'aparelho', 'um aparelho de Carla')
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
      // Elas já saíram daqui — numa cópia de segurança, por exemplo. Reparar
      // agora criaria duas versões da mesma operação, então o Bruno não
      // repara, e o lote é recusado como antes.
      b.ops.marcarEnviadoAte(
        inventario.id,
        b.ops.vetorDe(inventario.id)[b.dispositivoId],
      );

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

  group('reparo depois de corrigir a data', () {
    /// Os HLC das operações de um aparelho, em ordem.
    List<String> estampasDe(Aparelho aparelho) => [
      for (final l in aparelho.banco.db.select(
        'SELECT hlc FROM ops WHERE dispositivo = ? ORDER BY seq',
        [aparelho.dispositivoId],
      ))
        l['hlc'] as String,
    ];

    test('o trabalho gravado com o ano errado volta a sair', () async {
      // O celular do Bruno estava com o ano adiantado. Antes, cada envio era
      // recusado até o tempo real alcançar a data errada — nunca — e a única
      // saída no aplicativo apagava o trabalho não entregue.
      adiantarRelogioDasOperacoes(b, const Duration(days: 400));
      verificar(b, 'item-1');
      final estampasErradas = estampasDe(b);

      // A data é corrigida e ele encontra a Ana, com o relógio certo.
      final (_, paraA) = await servir(a);
      final resultado = await ClienteSync(b.ops).sincronizar(
        par: paraA,
        inventarioId: inventario.id,
        chaveSync: inventario.chaveSync,
      );

      expect(resultado.enviadas, greaterThan(0));
      expect(opsDe(a, b), greaterThan(0), reason: 'o trabalho chegou à Ana');
      expect(estampasDe(b), isNot(estampasErradas));
      expect(
        DateTime.now()
            .difference(a.patrimonios.porId('item-1')!.verificadoEm!)
            .inMinutes
            .abs(),
        lessThan(5),
        reason: 'a leitura passa a constar com a data de agora',
      );
    });

    test('a ordem entre as operações reparadas é preservada', () {
      adiantarRelogioDasOperacoes(b, const Duration(days: 400));
      verificar(b, 'item-1');
      verificar(b, 'item-2');

      expect(b.ops.reestamparOperacoesDoFuturo(), greaterThan(1));

      final estampas = estampasDe(b);
      expect(estampas, orderedEquals([...estampas]..sort()));
      expect(
        b.banco.lerConfig(Config.hlcLocal),
        estampas.last,
        reason: 'o relógio local desce junto, e não fica no futuro',
      );
      // E o estado continua de pé: o vencedor de cada campo é o mesmo.
      expect(b.patrimonios.porId('item-1')!.salaAtual, 'Auditório');
    });

    test('sem evidência de fora, nada é re-estampado', () async {
      // Um relógio que só voltou para trás faria operações corretas do
      // passado parecerem do futuro. O que autoriza o reparo é o par
      // concordar com a nossa hora — e aqui ele não concorda.
      adiantarRelogioDasOperacoes(b, const Duration(hours: 2));
      verificar(b, 'item-1');
      final antes = estampasDe(b);

      final (_, paraA) = await servir(
        a,
        deslocamento: const Duration(hours: 2),
      );
      await expectLater(
        ClienteSync(b.ops).sincronizar(
          par: paraA,
          inventarioId: inventario.id,
          chaveSync: inventario.chaveSync,
        ),
        throwsA(isA<RelogioDivergente>()),
      );

      expect(estampasDe(b), antes);
    });

    test('escrever local nunca re-estampa o que já está gravado', () {
      adiantarRelogioDasOperacoes(b, const Duration(days: 400));
      verificar(b, 'item-1');
      final antes = estampasDe(b);

      // Mais leituras, sem falar com ninguém: o reparo não mora aqui.
      verificar(b, 'item-2');

      expect(estampasDe(b).take(antes.length), antes);
    });

    test('se uma operação do futuro já saiu, nada é reparado', () {
      // Reparar só uma parte faria as escritas novas perderem para as antigas
      // que ficaram lá fora com a estampa adiantada.
      adiantarRelogioDasOperacoes(b, const Duration(days: 400));
      verificar(b, 'item-1');
      verificar(b, 'item-2');
      final antes = estampasDe(b);

      b.ops.marcarEnviadoAte(inventario.id, 1);

      expect(b.ops.reestamparOperacoesDoFuturo(), 0);
      expect(estampasDe(b), antes);
    });

    test('o servidor repara depois de uma assinatura válida', () async {
      // A porta do servidor: quem tem a chave e assina dentro da janela de
      // tempo está com o relógio certo, e isso basta como evidência.
      adiantarRelogioDasOperacoes(b, const Duration(days: 400));
      verificar(b, 'item-1');
      final (_, paraB) = await servir(b);

      final resultado = await ClienteSync(a.ops).sincronizar(
        par: paraB,
        inventarioId: inventario.id,
        chaveSync: inventario.chaveSync,
      );

      expect(resultado.recebidas, greaterThan(0));
      expect(a.patrimonios.porId('item-1')!.verificado, isTrue);
    });

    test('a mensagem fala "deste aparelho", e não "de este aparelho"', () {
      final falha = RelogioDivergente(
        aparelho: RelogioDivergente.esteAparelho,
        diferenca: const Duration(hours: 2),
      );

      expect(falha.mensagem, startsWith('O relógio deste aparelho está'));
      expect(falha.mensagem, isNot(contains('de este')));
      expect(
        RelogioDivergente(
          aparelho: 'Ana',
          diferenca: const Duration(hours: 2),
        ).mensagem,
        startsWith('O relógio de Ana está'),
      );
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
