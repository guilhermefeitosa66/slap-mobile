import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
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

    servidorA = ServidorSync(
      banco: a.banco,
      ops: a.ops,
      inventarios: a.inventarios,
      patrimonios: a.patrimonios,
    );
    servidorB = ServidorSync(
      banco: b.banco,
      ops: b.ops,
      inventarios: b.inventarios,
      patrimonios: b.patrimonios,
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

  tearDown(() async {
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
