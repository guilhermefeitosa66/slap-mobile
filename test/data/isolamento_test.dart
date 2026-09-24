import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/hlc.dart';
import 'package:slap_mobile/core/version_vector.dart';
import 'package:slap_mobile/data/repos/conflitos.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/domain/valores.dart';

import '../apoio/rede_simulada.dart';

/// Isolamento entre inventários.
///
/// A chave de sincronização vale por inventário: quem tem a de um não lê nem
/// escreve no outro. Quem autentica a conversa é a chave do inventário da
/// query; o que o corpo diz não pode ampliar esse alcance.
void main() {
  late Aparelho vitima;
  late Aparelho outro;
  late Inventario alvo;
  late Inventario alheio;

  setUp(() {
    vitima = Aparelho('Ana');
    outro = Aparelho('Bruno');

    // Os dois inventários vivem no mesmo aparelho, como acontece com quem
    // participa do levantamento de dois campi.
    alvo = vitima.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    alheio = vitima.inventarios.criar(nome: 'Campus Teresina', ano: 2026);

    for (final inv in [alvo, alheio]) {
      vitima.patrimonios.inserirRecebidos([
        patrimonioDeTeste(
          id: 'item-${inv.id}',
          inventarioId: inv.id,
          tombo: '1',
          sala: 'Almoxarifado',
        ),
      ]);
    }
    RedeSimulada.distribuir(vitima, [outro], alvo);
  });

  tearDown(() {
    vitima.fechar();
    outro.fechar();
  });

  /// Uma operação forjada, como a montaria quem tem a chave de um inventário
  /// e quer escrever noutro.
  Operacao forjada({
    required String inventarioId,
    required String entidade,
    required String entidadeId,
    String campo = CampoPatrimonio.salaAtual,
    String? valor = 'Invadida',
    int seq = 1,
  }) => Operacao(
    opId: 'forjada-$entidadeId-$seq',
    inventarioId: inventarioId,
    entidade: entidade,
    entidadeId: entidadeId,
    campo: campo,
    valor: valor,
    hlc: Hlc(DateTime.now().millisecondsSinceEpoch, 0, outro.dispositivoId),
    dispositivo: outro.dispositivoId,
    seq: seq,
    ctxId: null,
    usuarioNome: 'Bruno',
    usuarioMatricula: null,
    criadoEm: DateTime.now().millisecondsSinceEpoch,
  );

  group('lote de outro inventário', () {
    test('operação com outro inventario_id derruba o lote inteiro', () {
      expect(
        () => vitima.ops.aplicarRemotas([
          forjada(
            inventarioId: alheio.id,
            entidade: 'patrimonio',
            entidadeId: 'item-${alheio.id}',
          ),
        ], inventarioId: alvo.id),
        throwsA(isA<LoteDeOutroInventario>()),
      );

      expect(vitima.patrimonios.porId('item-${alheio.id}')!.salaAtual, isNull);
    });

    test('nem uma operação legítima passa junto de uma forjada', () {
      expect(
        () => vitima.ops.aplicarRemotas([
          forjada(
            inventarioId: alvo.id,
            entidade: 'patrimonio',
            entidadeId: 'item-${alvo.id}',
            valor: 'Auditório',
          ),
          forjada(
            inventarioId: alheio.id,
            entidade: 'patrimonio',
            entidadeId: 'item-${alheio.id}',
            seq: 2,
          ),
        ], inventarioId: alvo.id),
        throwsA(isA<LoteDeOutroInventario>()),
      );

      expect(
        vitima.patrimonios.porId('item-${alvo.id}')!.salaAtual,
        isNull,
        reason: 'a transação inteira foi desfeita',
      );
    });

    test('operação de inventário apontando para outro id é recusada', () {
      // O caminho para renomear ou encerrar o inventário alheio.
      expect(
        () => vitima.ops.aplicarRemotas([
          forjada(
            inventarioId: alvo.id,
            entidade: 'inventario',
            entidadeId: alheio.id,
            campo: 'nome',
            valor: 'Tomado',
          ),
        ], inventarioId: alvo.id),
        throwsA(isA<LoteDeOutroInventario>()),
      );

      expect(vitima.inventarios.porId(alheio.id)!.nome, 'Campus Teresina');
    });

    test('operação sobre patrimônio de outro inventário é recusada', () {
      // Aqui o `inventario_id` da operação está certo: o que denuncia é o
      // patrimônio, que este aparelho sabe ser de outro inventário.
      expect(
        () => vitima.ops.aplicarRemotas([
          forjada(
            inventarioId: alvo.id,
            entidade: 'patrimonio',
            entidadeId: 'item-${alheio.id}',
          ),
        ], inventarioId: alvo.id),
        throwsA(isA<LoteDeOutroInventario>()),
      );

      expect(vitima.patrimonios.porId('item-${alheio.id}')!.salaAtual, isNull);
    });

    test('patrimônio desconhecido é aceito', () {
      // Uma importação feita noutro aparelho depois da entrada cria itens que
      // este nunca recebeu. Recusá-los impediria o inventário de crescer.
      final resultado = vitima.ops.aplicarRemotas([
        forjada(
          inventarioId: alvo.id,
          entidade: 'patrimonio',
          entidadeId: 'item-que-ainda-nao-chegou',
        ),
      ], inventarioId: alvo.id);

      expect(resultado.aplicadas, 1);
    });
  });

  group('contexto plantado', () {
    test('contexto que o lote não cita não entra no banco', () {
      final plantado = VersionVector({'aparelho-qualquer': 9999});

      vitima.ops.aplicarRemotas(
        [
          forjada(
            inventarioId: alvo.id,
            entidade: 'patrimonio',
            entidadeId: 'item-${alvo.id}',
          ),
        ],
        inventarioId: alvo.id,
        contextos: {RepositorioOperacoes.idDeContexto(plantado): plantado},
      );

      expect(
        vitima.banco.db.select(
          'SELECT ctx_id FROM contextos WHERE ctx_id = ?',
          [RepositorioOperacoes.idDeContexto(plantado)],
        ).isEmpty,
        isTrue,
        reason: 'nenhuma operação do lote o cita',
      );
    });

    test('vetor entregue sob identificador alheio não é guardado', () {
      // O `ctx_id` é o hash do vetor. Aceitar o identificador como veio
      // deixaria escrever qualquer vetor sob o identificador de um contexto
      // de outro inventário.
      const identificadorAlheio = 'ffffffffffffffff';
      final mentira = VersionVector({'aparelho-qualquer': 9999});

      vitima.ops.aplicarRemotas(
        [
          Operacao(
            opId: 'com-ctx',
            inventarioId: alvo.id,
            entidade: 'patrimonio',
            entidadeId: 'item-${alvo.id}',
            campo: CampoPatrimonio.salaAtual,
            valor: 'Invadida',
            hlc: Hlc(
              DateTime.now().millisecondsSinceEpoch,
              0,
              outro.dispositivoId,
            ),
            dispositivo: outro.dispositivoId,
            seq: 1,
            ctxId: identificadorAlheio,
            usuarioNome: 'Bruno',
            usuarioMatricula: null,
            criadoEm: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
        inventarioId: alvo.id,
        contextos: {identificadorAlheio: mentira},
      );

      expect(
        vitima.ops.contexto(identificadorAlheio),
        VersionVector.vazia,
        reason: 'o identificador não confere com o conteúdo',
      );
    });

    test('contexto plantado não suprime conflito noutro inventário', () {
      // O ataque inteiro: com a chave do inventário alvo, plantar o contexto
      // que uma operação do inventário alheio vai citar, com um vetor que
      // mente dizer que o autor já conhecia a escrita daqui. Sem a
      // conferência, as duas escritas concorrentes viram "atualização" e o
      // conflito some sem ninguém ver.
      final terceiro = Aparelho('Carla');
      addTearDown(terceiro.fechar);
      RedeSimulada.distribuir(vitima, [terceiro], alheio);

      // Carla já sabe de alguma coisa da Ana: é o que dá contexto às
      // operações dela.
      vitima.patrimonios.registrarVerificacao(
        patrimonio: vitima.patrimonios.porId('item-${alheio.id}')!,
        config: const ConfiguracaoLevantamento(sala: 'Almoxarifado'),
        usuarioNome: 'Ana',
      );
      RedeSimulada.sincronizar(vitima, terceiro, alheio.id);

      // Agora as duas leem o mesmo item sem se falar.
      vitima.patrimonios.registrarVerificacao(
        patrimonio: vitima.patrimonios.porId('item-${alheio.id}')!,
        config: const ConfiguracaoLevantamento(sala: 'Biblioteca'),
        usuarioNome: 'Ana',
      );
      terceiro.patrimonios.registrarVerificacao(
        patrimonio: terceiro.patrimonios.porId('item-${alheio.id}')!,
        config: const ConfiguracaoLevantamento(sala: 'Auditório'),
        usuarioNome: 'Carla',
      );

      final faltantes = terceiro.ops.opsFaltantes(
        alheio.id,
        vitima.ops.vetorDe(alheio.id),
      );
      final ctxDaCarla = faltantes
          .map((o) => o.ctxId)
          .whereType<String>()
          .first;

      // O golpe, entregue pela porta do inventário alvo.
      final mentira = VersionVector({
        vitima.dispositivoId: 9999,
        terceiro.dispositivoId: 9999,
      });
      vitima.ops.aplicarRemotas(
        [
          forjada(
            inventarioId: alvo.id,
            entidade: 'patrimonio',
            entidadeId: 'item-${alvo.id}',
          ),
        ],
        inventarioId: alvo.id,
        contextos: {ctxDaCarla: mentira},
      );

      vitima.ops.aplicarRemotas(
        faltantes,
        inventarioId: alheio.id,
        contextos: terceiro.ops.contextosDe(faltantes),
      );

      expect(
        RepositorioConflitos(
          vitima.banco,
          vitima.ops,
        ).contarPendentes(alheio.id),
        greaterThan(0),
        reason: 'o contexto plantado não passou por cima do verdadeiro',
      );
    });
  });
}
