import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/servidor.dart';

import '../apoio/rede_simulada.dart';

/// O que cada par já recebeu deste aparelho, pela rede de verdade.
///
/// Em arquivo próprio, sem testes de widget: com eles o flutter_test troca o
/// HttpClient por um que responde 400 a tudo.
void main() {
  late Aparelho a;
  late Aparelho b;
  late Inventario inventario;

  setUp(() {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    a.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 3; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: '$i',
        ),
    ]);
    RedeSimulada.distribuir(a, [b], inventario);
  });

  tearDown(() {
    a.fechar();
    b.fechar();
  });

  void verificar(Aparelho x, String item) => x.patrimonios.registrarVerificacao(
    patrimonio: x.patrimonios.porId(item)!,
    config: const ConfiguracaoLevantamento(sala: 'Auditório'),
    usuarioNome: x.apelido,
  );

  test(
    'depois de sincronizar pela rede, nada se perde; o que vier depois, sim',
    () async {
      final servidorA = ServidorSync(
        banco: a.banco,
        ops: a.ops,
        inventarios: a.inventarios,
        patrimonios: a.patrimonios,
      );
      addTearDown(servidorA.dispose);
      final porta = await servidorA.iniciar();
      final paraA = Par(
        dispositivoId: a.dispositivoId,
        usuarioNome: 'Ana',
        host: '127.0.0.1',
        porta: porta,
      );

      verificar(a, 'item-1');
      verificar(a, 'item-2');
      expect(a.ops.trabalhoNaoEntregue(inventario.id).verificacoes, 2);

      // Bruno só puxa: é o envio vazio que conta a Ana que ele recebeu.
      await ClienteSync(b.ops).sincronizar(
        par: paraA,
        inventarioId: inventario.id,
        chaveSync: inventario.chaveSync,
      );
      expect(a.ops.trabalhoNaoEntregue(inventario.id).nada, isTrue);
      expect(b.ops.trabalhoNaoEntregue(inventario.id).nada, isTrue);

      verificar(a, 'item-3');
      final perda = a.ops.trabalhoNaoEntregue(inventario.id);
      expect(perda.jaSincronizou, isTrue);
      expect(perda.verificacoes, 1);
    },
  );

  test(
    'clone de um aparelho é recusado pela rede, sem misturar nada',
    () async {
      final servidorA = ServidorSync(
        banco: a.banco,
        ops: a.ops,
        inventarios: a.inventarios,
        patrimonios: a.patrimonios,
      );
      addTearDown(servidorA.dispose);
      final paraA = Par(
        dispositivoId: a.dispositivoId,
        host: '127.0.0.1',
        porta: await servidorA.iniciar(),
      );
      Future<void> sincronizar(Aparelho x) => ClienteSync(x.ops).sincronizar(
        par: paraA,
        inventarioId: inventario.id,
        chaveSync: inventario.chaveSync,
      );

      verificar(b, 'item-1');
      await sincronizar(b);

      // Os dados do Bruno copiados para outro celular, identidade junto.
      final pasta = await Directory.systemTemp.createTemp('slap_clone_');
      addTearDown(() => pasta.delete(recursive: true));
      b.banco.db.execute('VACUUM INTO ?', ['${pasta.path}/clone.db']);
      final clone = Aparelho.deArquivo(
        'Bruno (clone)',
        '${pasta.path}/clone.db',
      );
      addTearDown(clone.fechar);

      verificar(b, 'item-2');
      verificar(clone, 'item-3');
      await sincronizar(b);

      // Aqui a identidade duplicada é mesmo a de quem está pedindo: o clone
      // é um dos dois, e a ele a orientação de gerar identidade nova serve.
      await expectLater(
        sincronizar(clone),
        throwsA(
          isA<IdentidadeEmConflito>()
              .having((e) => e.dispositivo, 'aparelho', b.dispositivoId)
              .having((e) => e.esteAparelho, 'é o deste aparelho', isTrue)
              .having(
                (e) => e.mensagem,
                'mensagem',
                contains('identidade deste'),
              ),
        ),
      );
      expect(a.patrimonios.porId('item-3')!.verificado, isFalse);
    },
  );
}
