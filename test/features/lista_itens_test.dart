import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/divergencia.dart';
import 'package:slap_mobile/domain/filtro_itens.dart';
import 'package:slap_mobile/domain/patrimonio.dart';
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

  group('filtros', () {
    /// Quatro itens em duas salas. O 1 muda de sala e de responsável, o 2 é
    /// verificado onde estava, o 3 só troca de responsável e o 4 nunca é
    /// encontrado.
    void cenario() {
      repo.inserirLote(inventario.id, const [
        PatrimonioImportado(
          ordem: '1',
          tombo: '1',
          descricao: 'CADEIRA',
          sala: 'Sala 1',
          responsavel: 'Ana',
        ),
        PatrimonioImportado(
          ordem: '2',
          tombo: '2',
          descricao: 'MESA',
          sala: 'Sala 1',
          responsavel: 'Ana',
        ),
        PatrimonioImportado(
          ordem: '3',
          tombo: '3',
          descricao: 'ARMÁRIO',
          sala: 'Sala 2',
          responsavel: 'Bruno',
        ),
        PatrimonioImportado(
          ordem: '4',
          tombo: '4',
          descricao: 'CADEIRA',
          sala: 'Sala 2',
          responsavel: 'Bruno',
        ),
      ]);

      Patrimonio item(String tombo) =>
          repo.todos(inventario.id).firstWhere((p) => p.tombo == tombo);

      repo.registrarVerificacao(
        patrimonio: item('1'),
        // Em caixa alta e sem acento de propósito: é a mesma sala que alguém
        // digitaria "Auditório".
        config: const ConfiguracaoLevantamento(
          sala: 'AUDITORIO',
          conservacao: EstadoConservacao.ruim,
          situacao: SituacaoUso.inservivel,
          responsavel: 'Carla',
        ),
        usuarioNome: 'Ana Souza',
      );
      repo.registrarVerificacao(
        patrimonio: item('2'),
        config: const ConfiguracaoLevantamento(sala: 'Sala 1'),
        usuarioNome: 'Bruno Lima',
      );
      repo.registrarVerificacao(
        patrimonio: item('3'),
        config: const ConfiguracaoLevantamento(
          sala: 'Sala 2',
          responsavel: 'Carla',
        ),
        usuarioNome: 'Bruno Lima',
      );
    }

    /// Toca no que pode estar fora da parte visível da folha: a lista de
    /// filtros é mais alta que a tela de um celular.
    Future<void> tocar(WidgetTester tester, Finder alvo) async {
      await tester.ensureVisible(alvo);
      await tester.pumpAndSettle();
      await tester.tap(alvo);
      await tester.pumpAndSettle();
    }

    List<String> tombos({
      Classificacao? classificacao,
      FiltroItens filtro = FiltroItens.nenhum,
      String? busca,
    }) {
      final achados = repo.listar(
        inventarioId: inventario.id,
        classificacao: classificacao,
        filtro: filtro,
        busca: busca,
      );
      // A contagem do topo da tela e a página têm de contar a mesma coisa.
      expect(
        repo.contar(
          inventarioId: inventario.id,
          classificacao: classificacao,
          filtro: filtro,
          busca: busca,
        ),
        achados.length,
      );
      return achados.map((p) => p.tombo).toList();
    }

    test('sala da planilha não se move com o levantamento', () {
      cenario();
      expect(tombos(filtro: const FiltroItens(sala: 'Sala 1')), ['1', '2']);
    });

    test('sala atual é o valor efetivo: inclui quem não saiu do lugar', () {
      cenario();
      // O 4 nunca foi verificado, então `sala_atual` é nulo: pela coluna crua
      // ele sumiria da sala em que está.
      expect(tombos(filtro: const FiltroItens(salaAtual: 'Sala 2')), [
        '3',
        '4',
      ]);
      // E o 1, que saiu da Sala 1, não aparece mais nela.
      expect(tombos(filtro: const FiltroItens(salaAtual: 'Sala 1')), ['2']);
    });

    test('caixa e acento não separam a mesma sala', () {
      cenario();
      expect(tombos(filtro: const FiltroItens(salaAtual: ' auditório ')), [
        '1',
      ]);
    });

    test('responsável em branco mantém o da planilha', () {
      cenario();
      expect(tombos(filtro: const FiltroItens(responsavel: 'Ana')), ['1', '2']);
      // O 2 foi verificado sem responsável: o original continua valendo.
      expect(tombos(filtro: const FiltroItens(responsavelAtual: 'Ana')), ['2']);
      expect(tombos(filtro: const FiltroItens(responsavelAtual: 'Carla')), [
        '1',
        '3',
      ]);
    });

    test('estado e situação só existem em item verificado', () {
      cenario();
      expect(
        tombos(filtro: const FiltroItens(conservacao: EstadoConservacao.ruim)),
        ['1'],
      );
      expect(
        tombos(filtro: const FiltroItens(situacao: SituacaoUso.inservivel)),
        ['1'],
      );
      // Bom é o padrão das leituras: os outros dois verificados.
      expect(
        tombos(filtro: const FiltroItens(conservacao: EstadoConservacao.bom)),
        ['2', '3'],
      );
      // Combinado com "Não localizado" nada pode casar — e a tela avisa.
      expect(
        tombos(
          classificacao: Classificacao.naoLocalizado,
          filtro: const FiltroItens(conservacao: EstadoConservacao.bom),
        ),
        isEmpty,
      );
    });

    test('verificado por separa o trabalho de cada pessoa', () {
      cenario();
      expect(tombos(filtro: const FiltroItens(verificadoPor: 'Bruno Lima')), [
        '2',
        '3',
      ]);
    });

    test('os filtros se somam entre si, à busca e à classificação', () {
      cenario();
      expect(
        tombos(
          filtro: const FiltroItens(sala: 'Sala 2'),
          busca: 'cadeira',
        ),
        ['4'],
      );
      expect(
        tombos(
          classificacao: Classificacao.divergente,
          filtro: const FiltroItens(responsavelAtual: 'Carla'),
        ),
        ['1', '3'],
      );
      // Dois filtros que não se encontram em item nenhum.
      expect(
        tombos(
          filtro: const FiltroItens(sala: 'Sala 1', salaAtual: 'Sala 2'),
        ),
        isEmpty,
      );
    });

    test('a paginação repassa o filtro em cada página', () {
      repo.inserirLote(inventario.id, [
        for (var i = 1; i <= 300; i++)
          PatrimonioImportado(
            ordem: '$i',
            tombo: '$i',
            sala: i.isEven ? 'Par' : 'Ímpar',
          ),
      ]);
      const filtro = FiltroItens(sala: 'Par');
      final vistos = <String>[];
      for (var desde = 0; ; desde += 100) {
        final pagina = repo.listar(
          inventarioId: inventario.id,
          filtro: filtro,
          limite: 100,
          deslocamento: desde,
        );
        if (pagina.isEmpty) break;
        vistos.addAll(pagina.map((p) => p.id));
      }
      expect(vistos.length, 150);
      expect(vistos.toSet().length, 150, reason: 'nada repetido');
      expect(repo.contar(inventarioId: inventario.id, filtro: filtro), 150);
    });

    test('os seletores só oferecem valor que existe', () {
      cenario();
      expect(repo.salasOriginais(inventario.id), ['Sala 1', 'Sala 2']);
      expect(repo.salasAtuais(inventario.id), [
        'AUDITORIO',
        'Sala 1',
        'Sala 2',
      ]);
      expect(repo.responsaveisOriginais(inventario.id), ['Ana', 'Bruno']);
      expect(repo.responsaveisAtuais(inventario.id), ['Ana', 'Bruno', 'Carla']);
      expect(repo.verificadores(inventario.id), ['Ana Souza', 'Bruno Lima']);
    });

    testWidgets('a folha filtra a lista, e a ficha desfaz o filtro', (
      tester,
    ) async {
      cenario();
      await montar(
        tester,
        TelaItens(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pumpAndSettle();
      expect(find.text('4 patrimônios'), findsOneWidget);

      await tocar(tester, find.byIcon(Icons.filter_list));
      await tocar(tester, find.text(CampoFiltro.salaAtual.rotulo));
      await tocar(tester, find.text('Sala 2'));
      await tocar(tester, find.text('Aplicar'));

      // O 3 e o 4 estão na Sala 2; o 4 nunca foi verificado.
      expect(find.text('2 patrimônios'), findsOneWidget);
      expect(find.text('Tombo 4 · Sala 2'), findsOneWidget);

      // A ficha diz o que está valendo, e tocá-la desfaz.
      expect(find.text('Sala atual: Sala 2'), findsOneWidget);
      await tocar(tester, find.text('Sala atual: Sala 2'));
      expect(find.text('4 patrimônios'), findsOneWidget);
    });

    testWidgets('a busca continua valendo junto com o filtro', (tester) async {
      cenario();
      await montar(
        tester,
        TelaItens(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pumpAndSettle();

      await tocar(tester, find.byIcon(Icons.filter_list));
      await tocar(tester, find.text(CampoFiltro.sala.rotulo));
      await tocar(tester, find.text('Sala 2'));
      await tocar(tester, find.text('Aplicar'));
      expect(find.text('2 patrimônios'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'cadeira');
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('2 patrimônios'),
        findsOneWidget,
        reason: 'ainda digitando',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('1 patrimônio'), findsOneWidget);
    });

    testWidgets('lista vazia com filtro diz que nada combina', (tester) async {
      cenario();
      await montar(
        tester,
        TelaItens(
          inventarioId: inventario.id,
          classificacao: Classificacao.naoLocalizado,
        ),
        banco: banco,
      );
      await tester.pumpAndSettle();

      await tocar(tester, find.byIcon(Icons.filter_list));
      await tocar(tester, find.text(EstadoConservacao.bom.rotulo));
      await tocar(tester, find.text('Aplicar'));

      expect(find.text('0 patrimônios'), findsOneWidget);
      expect(
        find.textContaining('só existem em item encontrado'),
        findsOneWidget,
      );
      // Só um filtro ativo: o "limpar" da lista vazia é o único na tela.
      expect(find.text('Limpar filtros'), findsOneWidget);
      await tocar(tester, find.text('Limpar filtros'));
      expect(find.text('1 patrimônio'), findsOneWidget);
    });

    testWidgets('a folha de filtros passa na auditoria de acessibilidade', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      cenario();
      await montar(
        tester,
        TelaItens(inventarioId: inventario.id),
        banco: banco,
      );
      await tester.pumpAndSettle();

      await tocar(tester, find.byIcon(Icons.filter_list));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      // A lista de valores, com a busca.
      await tocar(tester, find.text(CampoFiltro.salaAtual.rotulo));
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar na lista'),
        'audi',
      );
      await tester.pumpAndSettle();
      expect(find.text('AUDITORIO'), findsOneWidget);
      expect(find.text('Sala 1'), findsNothing);
      await tocar(tester, find.text('AUDITORIO'));
      await tocar(tester, find.text('Aplicar'));

      // De volta à lista, com a ficha do filtro à vista.
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(find.text('1 patrimônio'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('a folha de filtros com a fonte em 200%', (tester) async {
      cenario();
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await montar(
        tester,
        MediaQuery.withClampedTextScaling(
          minScaleFactor: 2,
          maxScaleFactor: 2,
          child: TelaItens(inventarioId: inventario.id),
        ),
        banco: banco,
      );
      await tester.pumpAndSettle();

      await tocar(tester, find.byIcon(Icons.filter_list));
      await tocar(tester, find.text(CampoFiltro.salaAtual.rotulo));
      await tocar(tester, find.text('Sala 2'));
      await tocar(tester, find.text('Aplicar'));
      expect(find.text('2 patrimônios'), findsOneWidget);
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
