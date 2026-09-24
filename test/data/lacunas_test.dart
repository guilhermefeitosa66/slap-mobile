import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/version_vector.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';

import '../apoio/rede_simulada.dart';

/// Buracos na numeração de um aparelho.
///
/// A version vector guarda um número por aparelho, e `{B: 100}` tanto pode
/// ser "tenho as cem primeiras de B" quanto "tenho da 51 à 100". Sem dizer o
/// que falta no meio, um intervalo perdido nunca é pedido a ninguém — e a
/// divergência entre as réplicas fica permanente.
void main() {
  late Aparelho a;
  late Aparelho b;
  late Aparelho c;
  late Inventario inventario;

  const idItem1 = 'item-0001';
  const idItem2 = 'item-0002';
  const idItem3 = 'item-0003';

  setUp(() {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    c = Aparelho('Carla');

    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    a.patrimonios.inserirRecebidos([
      for (final id in [idItem1, idItem2, idItem3])
        patrimonioDeTeste(
          id: id,
          inventarioId: inventario.id,
          tombo: id,
          sala: 'Almoxarifado',
        ),
    ]);
    RedeSimulada.distribuir(a, [b, c], inventario);
  });

  tearDown(() {
    a.fechar();
    b.fechar();
    c.fechar();
  });

  void verificar(Aparelho aparelho, String item, String sala) {
    aparelho.patrimonios.registrarVerificacao(
      patrimonio: aparelho.patrimonios.porId(item)!,
      config: ConfiguracaoLevantamento(sala: sala),
      usuarioNome: aparelho.apelido,
    );
  }

  int nossoSeqRegistrado(Aparelho em, Aparelho par) =>
      em.banco.db.select(
            'SELECT nosso_seq FROM pares WHERE dispositivo = ? AND '
            'inventario_id = ?',
            [par.dispositivoId, inventario.id],
          ).first['nosso_seq']
          as int;

  group('cálculo das lacunas', () {
    test('sequência inteira não tem lacuna', () {
      verificar(b, idItem1, 'Auditório');
      verificar(b, idItem2, 'Biblioteca');

      expect(b.ops.lacunasDe(inventario.id).isEmpty, isTrue);
    });

    test('o que falta no começo e no meio aparece como faixa', () {
      plantarOperacoes(
        a,
        inventarioId: inventario.id,
        dispositivo: b.dispositivoId,
        patrimonioId: idItem1,
        de: 3,
        ate: 5,
      );
      plantarOperacoes(
        a,
        inventarioId: inventario.id,
        dispositivo: b.dispositivoId,
        patrimonioId: idItem1,
        de: 9,
        ate: 10,
      );

      expect(a.ops.lacunasDe(inventario.id)[b.dispositivoId], [
        const Faixa(1, 2),
        const Faixa(6, 8),
      ]);
    });

    test('ida e volta pelo formato da rede preserva as faixas', () {
      final lacunas = Lacunas({
        'aparelho-b': [const Faixa(1, 50), const Faixa(70, 72)],
      });

      final lidas = Lacunas.decodificar(lacunas.codificar());
      expect(lidas['aparelho-b'], [const Faixa(1, 50), const Faixa(70, 72)]);
      expect(lidas['aparelho-c'], isEmpty);
    });

    test('faixa sem sentido vinda da rede é descartada sem derrubar nada', () {
      final lidas = Lacunas.decodificar(
        '{"b":[[5,1],[0,3],["x",2],[7],[10,12]],"c":"nada"}',
      );

      expect(lidas['b'], [const Faixa(10, 12)]);
      expect(lidas['c'], isEmpty);
      expect(Lacunas.decodificar(null).isEmpty, isTrue);
      expect(Lacunas.decodificar('lixo que não é json').isEmpty, isTrue);
    });
  });

  group('o intervalo que falta é pedido e chega', () {
    test('quem entrou por um par sem o começo recebe o resto depois', () {
      // A história da revisão: o Bruno sincroniza só com a Ana, apaga o
      // inventário do aparelho e entra de novo pela Carla, que nunca viu as
      // operações antigas dele.
      verificar(b, idItem1, 'Auditório');
      RedeSimulada.sincronizar(a, b, inventario.id);

      b.inventarios.removerLocalmente(inventario.id);
      RedeSimulada.distribuir(a, [b], a.inventarios.porId(inventario.id)!);
      verificar(b, idItem2, 'Biblioteca');
      RedeSimulada.sincronizar(b, c, inventario.id);

      // A Carla conhece o Bruno pelo máximo, mas o começo dele falta.
      expect(
        c.ops.vetorDe(inventario.id)[b.dispositivoId],
        greaterThan(0),
        reason: 'ela recebeu o trabalho novo',
      );
      expect(
        c.ops.lacunasDe(inventario.id)[b.dispositivoId],
        isNotEmpty,
        reason: 'e sabe que falta o começo',
      );
      expect(c.patrimonios.porId(idItem1)!.verificado, isFalse);

      // Encontrar quem tem o intervalo basta.
      RedeSimulada.sincronizar(a, c, inventario.id);

      expect(c.ops.lacunasDe(inventario.id)[b.dispositivoId], isEmpty);
      expect(c.patrimonios.porId(idItem1)!.verificado, isTrue);
      expect(impressaoDe(c, idItem1), impressaoDe(a, idItem1));
    });

    test('o buraco fecha antes do que está acima dele', () {
      // Quem tem o intervalo manda primeiro o que falta no meio: assim o
      // buraco fecha já no primeiro encontro, mesmo que o que está acima não
      // caiba num lote só.
      plantarOperacoes(
        a,
        inventarioId: inventario.id,
        dispositivo: b.dispositivoId,
        patrimonioId: idItem1,
        de: 1,
        ate: 4,
      );
      plantarOperacoes(
        c,
        inventarioId: inventario.id,
        dispositivo: b.dispositivoId,
        patrimonioId: idItem1,
        de: 5,
        ate: 30,
      );

      final faltantes = a.ops.opsFaltantes(
        inventario.id,
        c.ops.vetorDe(inventario.id),
        lacunas: c.ops.lacunasDe(inventario.id),
        limite: 2,
      );

      expect(faltantes.map((o) => o.seq), [1, 2]);
    });
  });

  group('lacuna permanente', () {
    /// A Carla com 5.200 operações do Bruno, faltando as cinquenta
    /// primeiras — que ninguém mais tem.
    void montarLacunaGrande() {
      plantarOperacoes(
        c,
        inventarioId: inventario.id,
        dispositivo: b.dispositivoId,
        patrimonioId: idItem3,
        de: 51,
        ate: 5200,
        valor: 'Depósito',
      );
    }

    test('mais de 5.000 operações acima do buraco não travam nada', () {
      montarLacunaGrande();
      verificar(a, idItem1, 'Auditório');

      // Duas voltas: o lote tem limite de 5.000, e as 5.150 operações do
      // Bruno não cabem de uma vez. O que importa é que cada volta avança —
      // era exatamente aqui que anunciar só o prefixo contíguo travava,
      // reenviando as mesmas 5.000 para sempre.
      RedeSimulada.sincronizar(a, c, inventario.id);
      final apos1 = a.ops.vetorDe(inventario.id)[b.dispositivoId];
      RedeSimulada.sincronizar(a, c, inventario.id);
      final apos2 = a.ops.vetorDe(inventario.id)[b.dispositivoId];

      expect(apos1, 5050, reason: 'o primeiro lote encheu no limite');
      expect(apos2, 5200, reason: 'o segundo trouxe o resto');
      expect(RedeSimulada.pendentesEntre(c, a, inventario.id), 0);
    });

    test('o intervalo perdido em todo lugar é pedido e não custa nada', () {
      montarLacunaGrande();
      RedeSimulada.sincronizar(a, c, inventario.id);
      RedeSimulada.sincronizar(a, c, inventario.id);

      // Ninguém tem as cinquenta primeiras do Bruno: as duas réplicas ficam
      // com a mesma lacuna, e é só isso.
      final faixasNaCarla = c.ops.lacunasDe(inventario.id)[b.dispositivoId];
      expect(faixasNaCarla, [const Faixa(1, 50)]);
      expect(a.ops.lacunasDe(inventario.id)[b.dispositivoId], faixasNaCarla);

      expect(
        RedeSimulada.pendentesEntre(a, c, inventario.id),
        0,
        reason: 'sem custo: nada é reenviado por causa do buraco',
      );
      expect(RedeSimulada.pendentesEntre(c, a, inventario.id), 0);

      // E a edição seguinte daquele aparelho não vira conflito falso.
      verificar(a, idItem1, 'Auditório');
      RedeSimulada.sincronizar(a, c, inventario.id);
      expect(
        c.banco.db
            .select(
              'SELECT COUNT(*) AS n FROM conflitos WHERE resolvido_em IS NULL',
            )
            .first['n'],
        0,
      );
      expect(impressaoDe(c, idItem1), impressaoDe(a, idItem1));
    });
  });

  group('o que o par ainda não tem inteiro', () {
    test('lacuna no meio do nosso trabalho não conta como entregue', () {
      // O Bruno tem as próprias operações 1 a 15; a Ana só recebeu até a 5,
      // e alguém lhe entregou da 11 à 15 por outro caminho. O meio ainda está
      // aqui, esperando para sair.
      plantarOperacoes(
        b,
        inventarioId: inventario.id,
        dispositivo: b.dispositivoId,
        patrimonioId: idItem1,
        de: 1,
        ate: 15,
      );
      for (final faixa in [(1, 5), (11, 15)]) {
        plantarOperacoes(
          a,
          inventarioId: inventario.id,
          dispositivo: b.dispositivoId,
          patrimonioId: idItem1,
          de: faixa.$1,
          ate: faixa.$2,
        );
      }

      // Só o registro do encontro, sem o envio que fecharia a lacuna: é o
      // `pull` chegando ao Bruno antes de ele mandar o que falta.
      b.ops.registrarPar(
        a.dispositivoId,
        inventario.id,
        nossoSeq: b.ops.seqEntregueA(
          inventario.id,
          maximoDoPar: a.ops.vetorDe(inventario.id)[b.dispositivoId],
          lacunasDoPar: a.ops.lacunasDe(inventario.id)[b.dispositivoId],
        ),
      );

      expect(
        nossoSeqRegistrado(b, a),
        5,
        reason: 'a Ana só tem inteiro até a operação 5',
      );
      expect(
        b.ops.trabalhoNaoEntregue(inventario.id).operacoes,
        10,
        reason: 'as dez do meio para cima ainda não estão lá inteiras',
      );

      // Depois da sincronização de verdade, a lacuna fecha e a conta fecha
      // junto.
      RedeSimulada.sincronizar(a, b, inventario.id);
      expect(nossoSeqRegistrado(b, a), 15);
      expect(b.ops.trabalhoNaoEntregue(inventario.id).nada, isTrue);
    });

    test('o que se perdeu em todo lugar não é dado como pendente', () {
      // As operações 6 a 10 do Bruno não existem mais em aparelho nenhum:
      // acusá-las de não entregues faria a confirmação de apagar a réplica
      // avisar de uma perda que ninguém consegue evitar.
      for (final aparelho in [a, b]) {
        for (final faixa in [(1, 5), (11, 15)]) {
          plantarOperacoes(
            aparelho,
            inventarioId: inventario.id,
            dispositivo: b.dispositivoId,
            patrimonioId: idItem1,
            de: faixa.$1,
            ate: faixa.$2,
          );
        }
      }

      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(nossoSeqRegistrado(b, a), 15);
      expect(b.ops.trabalhoNaoEntregue(inventario.id).nada, isTrue);
    });

    test('sem lacuna, o que o par declara conta inteiro', () {
      verificar(b, idItem1, 'Auditório');
      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(
        nossoSeqRegistrado(b, a),
        b.ops.vetorDe(inventario.id)[b.dispositivoId],
      );
      expect(b.ops.trabalhoNaoEntregue(inventario.id).nada, isTrue);
    });
  });
}
