import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/divergencia.dart';
import 'package:slap_mobile/domain/valores.dart';
import 'package:slap_mobile/features/divergence/tela_itens.dart';

import '../apoio/app_de_teste.dart';

/// Lista de itens paginada, com a classificação feita no banco.
void main() {
  late Banco banco;
  late RepositorioPatrimonios repo;
  late Inventario inventario;

  setUp(() {
    banco = Banco.emMemoria();
    final ops = RepositorioOperacoes(banco);
    repo = RepositorioPatrimonios(banco, ops);
    inventario = RepositorioInventarios(
      banco,
      ops,
    ).criar(nome: 'Campus', ano: 2026);
  });

  tearDown(() => banco.fechar());

  void importar(int quantidade, {String descricao = 'CADEIRA'}) {
    repo.inserirLote(inventario.id, [
      for (var i = 1; i <= quantidade; i++)
        PatrimonioImportado(
          ordem: '$i',
          tombo: i.toString().padLeft(6, '0'),
          descricao: '$descricao $i',
          sala: 'Sala ${i % 7}',
        ),
    ]);
  }

  group('classificação no banco', () {
    test('o SQL separa OK e divergente exatamente como o domínio', () {
      // Variações que o domínio considera iguais ou diferentes: acento,
      // caixa, espaço sobrando, vazio e ausente.
      const salas = [
        'Coordenação de TI',
        'COORDENACAO DE TI',
        ' coordenação  de ti ',
        'Auditório',
        'auditorio',
        '',
        null,
      ];
      const responsaveis = ['Maria José', 'MARIA JOSE', 'João', null];
      final aleatorio = Random(42);
      T sorteio<T>(List<T> lista) => lista[aleatorio.nextInt(lista.length)];

      repo.inserirLote(inventario.id, [
        for (var i = 0; i < 400; i++)
          PatrimonioImportado(
            tombo: '$i',
            sala: sorteio(salas),
            responsavel: sorteio(responsaveis),
          ),
      ]);

      for (final p in repo.todos(inventario.id)) {
        if (aleatorio.nextInt(4) == 0) continue; // parte não é encontrada
        repo.registrarVerificacao(
          patrimonio: p,
          config: ConfiguracaoLevantamento(
            sala: sorteio(salas.whereType<String>().toList()..remove('')),
            conservacao: sorteio(EstadoConservacao.values),
            situacao: sorteio(SituacaoUso.values),
            responsavel: sorteio(responsaveis),
          ),
        );
      }

      final todos = repo.todos(inventario.id);
      for (final c in Classificacao.values.where(
        (c) => c != Classificacao.ignorado,
      )) {
        final peloDominio = {
          for (final p in todos)
            if (classificar(p) == c) p.id,
        };
        final peloBanco = {
          for (final p in repo.listar(
            inventarioId: inventario.id,
            classificacao: c,
            limite: 10000,
          ))
            p.id,
        };
        expect(peloBanco, peloDominio, reason: c.rotulo);
        expect(
          repo.contar(inventarioId: inventario.id, classificacao: c),
          peloDominio.length,
        );
      }

      final progresso = repo.progresso(inventario.id);
      expect(
        progresso.divergentes,
        todos.where((p) => classificar(p) == Classificacao.divergente).length,
      );
      expect(
        progresso.ok,
        todos.where((p) => classificar(p) == Classificacao.ok).length,
      );
      expect(progresso.divergentes, greaterThan(0));
      expect(progresso.ok, greaterThan(0));
    });
  });

  group('paginação', () {
    test('as páginas cobrem tudo, sem repetir e sem pular', () {
      importar(1234);
      final vistos = <String>[];
      for (var desde = 0; ; desde += 100) {
        final pagina = repo.listar(
          inventarioId: inventario.id,
          limite: 100,
          deslocamento: desde,
        );
        if (pagina.isEmpty) break;
        vistos.addAll(pagina.map((p) => p.id));
      }
      expect(vistos.length, 1234);
      expect(vistos.toSet().length, 1234);
      expect(repo.contar(inventarioId: inventario.id), 1234);
    });

    test('página de divergentes vem cheia, e não filtrada depois', () {
      importar(600);
      for (final p in repo.todos(inventario.id)) {
        repo.registrarVerificacao(
          patrimonio: p,
          config: ConfiguracaoLevantamento(
            // Metade muda de sala.
            sala: int.parse(p.tombo).isEven ? 'Auditório' : p.salaOriginal!,
          ),
        );
      }
      final pagina = repo.listar(
        inventarioId: inventario.id,
        classificacao: Classificacao.divergente,
        limite: 100,
      );
      expect(pagina.length, 100);
      expect(
        repo.contar(
          inventarioId: inventario.id,
          classificacao: Classificacao.divergente,
        ),
        300,
      );
    });
  });

  group('busca', () {
    test('sem caixa nem acento na descrição', () {
      repo.inserirLote(inventario.id, const [
        PatrimonioImportado(tombo: '1', descricao: 'CADEIRA GIRATÓRIA'),
        PatrimonioImportado(tombo: '2', descricao: 'MESA'),
      ]);
      final achados = repo.listar(
        inventarioId: inventario.id,
        busca: 'giratoria',
      );
      expect(achados.map((p) => p.tombo), ['1']);
    });

    test('pelo começo do tombo, com zeros à esquerda ou não', () {
      importar(30);
      expect(
        repo.contar(inventarioId: inventario.id, busca: '00002'),
        11, // 2 e 20 a 29
      );
    });

    test('% e _ digitados não viram curinga', () {
      importar(20);
      expect(repo.contar(inventarioId: inventario.id, busca: '%'), 0);
      expect(repo.contar(inventarioId: inventario.id, busca: '_'), 0);
    });
  });

  group('consultas de apoio', () {
    // Aspas duplas em SQL são identificador, não texto: a build do SQLite que
    // o app embarca recusa "" e a folha de configuração quebrava ao abrir.
    test('salas, responsáveis e EDs, sem vazios', () {
      repo.inserirLote(inventario.id, const [
        PatrimonioImportado(
          tombo: '1',
          sala: 'Biblioteca',
          responsavel: 'Ana',
          ed: '42',
        ),
        PatrimonioImportado(tombo: '2', sala: '  ', responsavel: '', ed: null),
        PatrimonioImportado(
          tombo: '3',
          sala: 'Auditório',
          responsavel: 'Bruno',
          ed: '42',
        ),
      ]);
      expect(repo.salas(inventario.id), ['Auditório', 'Biblioteca']);
      expect(repo.responsaveis(inventario.id), ['Ana', 'Bruno']);
      expect(repo.contagemPorEd(inventario.id), {'42': 2, '': 1});
    });
  });

  group('tela', () {
    testWidgets('mostra o total e carrega além de 500 conforme rola', (
      tester,
    ) async {
      importar(1234);
      await montar(
        tester,
        TelaItens(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pump();

      expect(find.text('1.234 patrimônios'), findsOneWidget);

      // Rola até encontrar o último item: só aparece se as páginas vierem.
      await tester.scrollUntilVisible(
        find.text('CADEIRA 1234'),
        2000,
        scrollable: find.byType(Scrollable).last,
        maxScrolls: 400,
      );
      expect(find.text('CADEIRA 1234'), findsOneWidget);
    });

    testWidgets('a busca responde depois de uma pausa na digitação', (
      tester,
    ) async {
      importar(50);
      await montar(
        tester,
        TelaItens(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'cadeira 4');
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('50 patrimônios'),
        findsOneWidget,
        reason: 'ainda digitando: nenhuma consulta',
      );

      await tester.pump(const Duration(milliseconds: 300));
      // "CADEIRA 4" e "CADEIRA 40" a "CADEIRA 49".
      expect(find.text('11 patrimônios'), findsOneWidget);
    });
  });
}
