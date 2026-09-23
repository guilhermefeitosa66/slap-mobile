import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/valores.dart';

import '../apoio/rede_simulada.dart';

/// Testes da sincronização distribuída.
///
/// Verificam a afirmação central da arquitetura: as réplicas convergem
/// sozinhas, sem perder dado, e o sistema ainda distingue uma atualização
/// comum de duas pessoas mexendo no mesmo campo sem saber uma da outra.
void main() {
  late Aparelho a;
  late Aparelho b;
  late Aparelho c;
  late Inventario inventario;

  const idItem1 = 'item-0001';
  const idItem2 = 'item-0002';

  setUp(() {
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    c = Aparelho('Carla');

    inventario = a.inventarios.criar(nome: 'Campus Picos — Geral', ano: 2026);

    a.patrimonios.inserirRecebidos([
      patrimonioDeTeste(
        id: idItem1,
        inventarioId: inventario.id,
        tombo: '12345',
        sala: 'Coordenação de TI',
        responsavel: 'João',
      ),
      patrimonioDeTeste(
        id: idItem2,
        inventarioId: inventario.id,
        tombo: '12346',
        sala: 'Biblioteca',
        responsavel: 'Maria',
      ),
    ]);

    RedeSimulada.distribuir(a, [b, c], inventario);
  });

  tearDown(() {
    a.fechar();
    b.fechar();
    c.fechar();
  });

  ConfiguracaoLevantamento config(String sala, {String? responsavel}) =>
      ConfiguracaoLevantamento(sala: sala, responsavel: responsavel);

  void verificar(
    Aparelho aparelho,
    String itemId,
    ConfiguracaoLevantamento cfg,
  ) {
    final p = aparelho.patrimonios.porId(itemId)!;
    aparelho.patrimonios.registrarVerificacao(
      patrimonio: p,
      config: cfg,
      usuarioNome: aparelho.apelido,
    );
  }

  group('convergência', () {
    test('o que um aparelho levanta chega ao outro', () {
      verificar(a, idItem1, config('Auditório'));

      expect(b.patrimonios.porId(idItem1)!.verificado, isFalse);

      RedeSimulada.sincronizar(a, b, inventario.id);

      final noB = b.patrimonios.porId(idItem1)!;
      expect(noB.verificado, isTrue);
      expect(noB.salaAtual, 'Auditório');
      expect(
        noB.verificadoPor,
        'Ana',
        reason: 'o crédito acompanha a operação entre aparelhos',
      );
    });

    test(
      'o trabalho de C chega a A através de B, sem A e C se encontrarem',
      () {
        // É a topologia em malha: não existe aparelho central obrigatório.
        verificar(c, idItem1, config('Laboratório'));

        RedeSimulada.sincronizar(c, b, inventario.id);
        RedeSimulada.sincronizar(b, a, inventario.id);

        final noA = a.patrimonios.porId(idItem1)!;
        expect(noA.verificado, isTrue);
        expect(noA.salaAtual, 'Laboratório');
        expect(noA.verificadoPor, 'Carla');
      },
    );

    test(
      'trabalho independente de três aparelhos converge para o mesmo estado',
      () {
        verificar(a, idItem1, config('Auditório'));
        verificar(b, idItem2, config('Biblioteca'));

        RedeSimulada.sincronizar(a, b, inventario.id);
        RedeSimulada.sincronizar(b, c, inventario.id);
        RedeSimulada.sincronizar(a, c, inventario.id);

        for (final item in [idItem1, idItem2]) {
          expect(impressaoDe(b, item), impressaoDe(a, item));
          expect(impressaoDe(c, item), impressaoDe(a, item));
        }

        expect(a.patrimonios.progresso(inventario.id).verificados, 2);
        expect(c.patrimonios.progresso(inventario.id).verificados, 2);
      },
    );
  });

  group('sincronização incremental', () {
    test('depois de sincronizar não sobra nada a transferir', () {
      verificar(a, idItem1, config('Auditório'));
      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(RedeSimulada.pendentesEntre(a, b, inventario.id), 0);
      expect(RedeSimulada.pendentesEntre(b, a, inventario.id), 0);
    });

    test('só o que mudou depois da última sincronização é transferido', () {
      // O inventário inteiro não é retransmitido a cada encontro.
      verificar(a, idItem1, config('Auditório'));
      RedeSimulada.sincronizar(a, b, inventario.id);

      verificar(a, idItem2, config('Auditório'));

      final pendentes = RedeSimulada.pendentesEntre(a, b, inventario.id);
      expect(
        pendentes,
        lessThanOrEqualTo(5),
        reason: 'apenas os campos do item novo, não os dois itens',
      );
      expect(pendentes, greaterThan(0));
    });

    test('aplicar o mesmo lote duas vezes não muda nada', () {
      verificar(a, idItem1, config('Auditório'));

      final faltantes = a.ops.opsFaltantes(
        inventario.id,
        b.ops.vetorDe(inventario.id),
      );
      final contextos = a.ops.contextosDe(faltantes);

      final primeira = b.ops.aplicarRemotas(faltantes, contextos: contextos);
      final segunda = b.ops.aplicarRemotas(faltantes, contextos: contextos);

      expect(primeira.aplicadas, greaterThan(0));
      expect(segunda.aplicadas, 0, reason: 'idempotente');
      expect(segunda.conflitos, 0);
    });
  });

  group('conflitos', () {
    test(
      'duas pessoas conferindo o mesmo item sem se falar geram conflito',
      () {
        // O caso da especificação: A diz Biblioteca, B diz Auditório, nenhum
        // dos dois sabia do outro.
        verificar(a, idItem1, config('Biblioteca'));
        verificar(b, idItem1, config('Auditório'));

        RedeSimulada.sincronizar(a, b, inventario.id);

        expect(_conflitosPendentes(a, inventario.id), greaterThan(0));
        expect(_conflitosPendentes(b, inventario.id), greaterThan(0));
      },
    );

    test('as réplicas escolhem o mesmo vencedor, sem se consultar', () {
      verificar(a, idItem1, config('Biblioteca'));
      verificar(b, idItem1, config('Auditório'));

      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(impressaoDe(b, idItem1), impressaoDe(a, idItem1));
      expect(
        a.patrimonios.porId(idItem1)!.salaAtual,
        anyOf('Biblioteca', 'Auditório'),
      );
    });

    test('conflito não deixa o banco indefinido: o item fica verificado', () {
      verificar(a, idItem1, config('Biblioteca'));
      verificar(b, idItem1, config('Auditório'));

      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(a.patrimonios.porId(idItem1)!.verificado, isTrue);
      expect(b.patrimonios.porId(idItem1)!.verificado, isTrue);
    });

    test('atualizar depois de sincronizar não é conflito', () {
      // B já conhecia o que A escreveu: é atualização, não concorrência.
      // Sem esta distinção, todo encontro entre aparelhos viraria alarme.
      verificar(a, idItem1, config('Biblioteca'));
      RedeSimulada.sincronizar(a, b, inventario.id);

      verificar(b, idItem1, config('Auditório'));
      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(_conflitosPendentes(a, inventario.id), 0);
      expect(_conflitosPendentes(b, inventario.id), 0);
      expect(
        a.patrimonios.porId(idItem1)!.salaAtual,
        'Auditório',
        reason: 'a escrita mais recente prevalece',
      );
    });

    test('concorrência com o mesmo valor não é conflito', () {
      // As duas pessoas viram a mesma coisa. Não há o que perguntar.
      verificar(a, idItem1, config('Auditório'));
      verificar(b, idItem1, config('Auditório'));

      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(_conflitosPendentes(a, inventario.id), 0);
      expect(a.patrimonios.porId(idItem1)!.salaAtual, 'Auditório');
    });

    test('campos diferentes do mesmo item não conflitam entre si', () {
      verificar(a, idItem1, config('Auditório'));
      RedeSimulada.sincronizar(a, b, inventario.id);

      // Agora cada um altera um campo distinto, sem saber do outro.
      verificar(a, idItem1, config('Auditório', responsavel: 'Pedro'));
      final noB = b.patrimonios.porId(idItem1)!;
      b.patrimonios.registrarVerificacao(
        patrimonio: noB,
        config: const ConfiguracaoLevantamento(
          sala: 'Auditório',
          conservacao: EstadoConservacao.ruim,
        ),
        usuarioNome: 'Bruno',
      );

      RedeSimulada.sincronizar(a, b, inventario.id);

      final resultado = a.patrimonios.porId(idItem1)!;
      expect(_conflitosPendentes(a, inventario.id), 0);
      expect(resultado.responsavelAtual, 'Pedro');
      expect(
        resultado.conservacao,
        EstadoConservacao.ruim,
        reason: 'as duas alterações sobrevivem',
      );
    });

    test(
      'três aparelhos alterando o mesmo campo convergem para um só valor',
      () {
        verificar(a, idItem1, config('Biblioteca'));
        verificar(b, idItem1, config('Auditório'));
        verificar(c, idItem1, config('Laboratório'));

        RedeSimulada.sincronizar(a, b, inventario.id);
        RedeSimulada.sincronizar(b, c, inventario.id);
        RedeSimulada.sincronizar(a, c, inventario.id);
        RedeSimulada.sincronizar(a, b, inventario.id);

        expect(impressaoDe(b, idItem1), impressaoDe(a, idItem1));
        expect(impressaoDe(c, idItem1), impressaoDe(a, idItem1));
      },
    );
  });

  group('auditoria', () {
    test('o histórico diz quem alterou, o quê e para qual valor', () {
      verificar(a, idItem1, config('Auditório'));
      RedeSimulada.sincronizar(a, b, inventario.id);
      verificar(b, idItem1, config('Biblioteca'));
      RedeSimulada.sincronizar(a, b, inventario.id);

      final historico = a.ops.historicoDe(idItem1);
      final autores = historico.map((o) => o.usuarioNome).toSet();

      expect(autores, containsAll(['Ana', 'Bruno']));

      final mudancasDeSala = historico
          .where((o) => o.campo == 'sala_atual')
          .toList();
      expect(mudancasDeSala.length, 2);
      expect(
        mudancasDeSala.first.valor,
        'Biblioteca',
        reason: 'histórico vem do mais recente para o mais antigo',
      );
    });

    test('o dado original do SUAP sobrevive a toda alteração', () {
      verificar(a, idItem1, config('Auditório', responsavel: 'Pedro'));
      RedeSimulada.sincronizar(a, b, inventario.id);

      final p = b.patrimonios.porId(idItem1)!;
      expect(p.salaOriginal, 'Coordenação de TI');
      expect(p.responsavelOriginal, 'João');
      expect(p.salaAtual, 'Auditório');
      expect(p.responsavelAtual, 'Pedro');
    });
  });
}

int _conflitosPendentes(Aparelho aparelho, String inventarioId) {
  final r = aparelho.banco.db.select(
    'SELECT COUNT(*) AS n FROM conflitos '
    'WHERE inventario_id = ? AND resolvido_em IS NULL',
    [inventarioId],
  );
  return r.first['n'] as int;
}
