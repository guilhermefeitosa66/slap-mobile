import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/resumo_troca.dart';

/// O aviso que fecha uma troca de dados.
///
/// Com poucos itens a trocar, a barra de andamento aparece e some antes de
/// alguém ler: o aviso é a única confirmação de que deu certo, e por isso o
/// que ele diz precisa estar certo em número e em português.
void main() {
  const ana = Par(dispositivoId: 'aaaaaa11', host: '10.0.0.2', porta: 8080);
  const bruno = Par(
    dispositivoId: 'bbbbbb22',
    host: '10.0.0.3',
    porta: 8080,
    usuarioNome: 'Bruno',
  );

  ResultadoSync troca({
    Par par = bruno,
    int recebidas = 0,
    int enviadas = 0,
    int conflitos = 0,
    int itens = 0,
  }) => ResultadoSync(
    par: par,
    recebidas: recebidas,
    enviadas: enviadas,
    conflitos: conflitos,
    itensAtualizados: itens,
  );

  String tudo(ResumoTroca r) => '${r.titulo}\n${r.linhas.join('\n')}';

  group('uma troca', () {
    test('conta itens atualizados, não operações', () {
      // Várias alterações caem no mesmo patrimônio: "18 alterações" não diz
      // nada a quem conduz o inventário; "12 itens atualizados" diz.
      final r = resumirTroca(troca(recebidas: 18, enviadas: 3, itens: 12));

      expect(r.titulo, 'Dados trocados com Bruno');
      expect(tudo(r), contains('12 itens atualizados vieram de Bruno'));
      expect(tudo(r), contains('3 alterações suas foram para Bruno'));
      expect(r.houveTroca, isTrue);
    });

    test('sem novidade de nenhum lado, diz isso e não inventa número', () {
      final r = resumirTroca(troca());

      expect(r.titulo, 'Já estava tudo sincronizado');
      expect(r.houveTroca, isFalse);
      expect(tudo(r), isNot(contains('0 ')));
    });

    test('só enviou: o outro lado não tinha novidade', () {
      final r = resumirTroca(troca(enviadas: 5));

      expect(tudo(r), contains('Nada novo veio de Bruno'));
      expect(tudo(r), contains('5 alterações suas foram para Bruno'));
    });

    test('só recebeu: o par já tinha o nosso trabalho', () {
      final r = resumirTroca(troca(recebidas: 4, itens: 4));

      expect(tudo(r), contains('4 itens atualizados vieram de Bruno'));
      expect(tudo(r), contains('Bruno já tinha tudo o que você levantou'));
    });

    test('alteração que não mexe em patrimônio conta como alteração', () {
      // Encerrar o inventário, por exemplo: chega uma operação e nenhum
      // patrimônio muda. Dizer "0 itens atualizados" soaria como nada feito.
      final r = resumirTroca(troca(recebidas: 1));

      expect(tudo(r), contains('1 alteração veio de Bruno'));
    });

    test('singular em tudo o que pode vir sozinho', () {
      final r = resumirTroca(
        troca(recebidas: 1, enviadas: 1, itens: 1, conflitos: 1),
      );

      expect(tudo(r), contains('1 item atualizado veio de Bruno'));
      expect(tudo(r), contains('1 alteração sua foi para Bruno'));
      expect(tudo(r), contains('1 conflito ficou para conferir'));
    });

    test('conflitos aparecem, e o resumo os carrega para o botão', () {
      final r = resumirTroca(troca(recebidas: 9, itens: 9, conflitos: 2));

      expect(tudo(r), contains('2 conflitos ficaram para conferir'));
      expect(r.conflitos, 2);
    });

    test('aparelho sem nome é identificado assim mesmo', () {
      final r = resumirTroca(troca(par: ana, recebidas: 2, itens: 2));

      expect(r.titulo, 'Dados trocados com ${ana.rotulo}');
    });
  });

  group('trocar com todos', () {
    test('uma linha por aparelho, na ordem percorrida', () {
      final r = resumirTrocas([
        troca(par: bruno, recebidas: 7, enviadas: 2, itens: 5),
        troca(par: ana),
      ], const []);

      expect(r.titulo, 'Troca concluída com 2 aparelhos');
      expect(r.linhas.first, 'Bruno: 5 itens recebidos, 2 alterações enviadas');
      expect(r.linhas[1], '${ana.rotulo}: já estava sincronizado');
    });

    test('falha de um aparelho não some no total dos outros', () {
      final r = resumirTrocas(
        [troca(par: bruno, recebidas: 3, itens: 3)],
        const [FalhaNaTroca('Carlos', 'relógios diferentes, nada foi trocado')],
      );

      expect(r.titulo, 'Troca concluída com ressalvas');
      expect(
        r.linhas,
        contains('Carlos: relógios diferentes, nada foi trocado'),
      );
    });

    test('conflitos somam entre os aparelhos', () {
      final r = resumirTrocas([
        troca(par: bruno, recebidas: 4, itens: 4, conflitos: 1),
        troca(par: ana, recebidas: 2, itens: 2, conflitos: 2),
      ], const []);

      expect(r.conflitos, 3);
      expect(r.linhas.last, '3 conflitos ficaram para conferir.');
    });
  });

  test('a falha explica o caso inteiro, sem reescrever a mensagem', () {
    const mensagem =
        'O relógio de Bruno está 2 h adiantado em relação a este aparelho.';
    final r = resumirFalha('Bruno', mensagem);

    expect(r.titulo, 'Não foi possível trocar com Bruno');
    expect(r.linhas, [mensagem]);
    expect(r.houveTroca, isFalse);
  });
}
