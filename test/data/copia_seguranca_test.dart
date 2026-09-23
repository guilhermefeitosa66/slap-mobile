import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/copia_seguranca.dart';
import 'package:slap_mobile/data/repos/conflitos.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';

import '../apoio/rede_simulada.dart';

/// Cópia de segurança: perder o celular não pode perder o trabalho.
void main() {
  late Directory pasta;
  late Aparelho a;
  late Aparelho b;
  late Inventario inventario;

  setUp(() async {
    pasta = await Directory.systemTemp.createTemp('slap_copia_');
    a = Aparelho('Ana');
    b = Aparelho('Bruno');
    inventario = a.inventarios.criar(nome: 'Campus Picos', ano: 2026);
    a.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 6; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: '$i',
          sala: 'Sala $i',
          ed: i == 6 ? '44905218' : '44905242',
        ),
    ]);
    a.inventarios.definirEdsExcluidos(inventario.id, ['44905218']);
    RedeSimulada.distribuir(a, [b], inventario);
  });

  tearDown(() async {
    a.fechar();
    b.fechar();
    await pasta.delete(recursive: true);
  });

  void verificar(Aparelho x, String item, String sala) =>
      x.patrimonios.registrarVerificacao(
        patrimonio: x.patrimonios.porId(item)!,
        config: ConfiguracaoLevantamento(sala: sala),
        usuarioNome: x.apelido,
      );

  String arquivo(String nome) =>
      '${pasta.path}/$nome.${CopiaDeSeguranca.extensao}';

  List<String> estado(Aparelho x) => [
    for (var i = 1; i <= 6; i++) impressaoDe(x, 'item-$i'),
    'encerrado=${x.inventarios.porId(inventario.id)?.encerrado}',
    'eds=${x.inventarios.porId(inventario.id)?.edsExcluidos}',
    'progresso=${x.patrimonios.progresso(inventario.id).verificados}',
  ];

  test(
    'exportar, restaurar num aparelho novo e sincronizar dá o mesmo estado',
    () {
      // Ana e Bruno trabalham; sincronizam uma vez; Ana continua sozinha.
      verificar(a, 'item-1', 'Auditório');
      verificar(b, 'item-2', 'Biblioteca');
      RedeSimulada.sincronizar(a, b, inventario.id);
      verificar(a, 'item-3', 'Auditório');
      verificar(a, 'item-4', 'Laboratório');
      // Conflito resolvido na Ana: tem de continuar resolvido na restauração.
      verificar(b, 'item-5', 'Secretaria');
      verificar(a, 'item-5', 'Protocolo');
      RedeSimulada.sincronizar(a, b, inventario.id);
      final conflitosA = RepositorioConflitos(a.banco, a.ops);
      final pendente = conflitosA.listar(inventario.id).single;
      conflitosA.resolver(
        conflito: pendente,
        valorEscolhido: 'Protocolo',
        usuarioNome: 'Ana',
      );
      verificar(a, 'item-1', 'Sala dos Professores');

      CopiaDeSeguranca.exportar(a.banco, arquivo('ana'));

      // O celular da Ana se perde. Aparelho novo, identidade nova.
      final novo = Aparelho('Ana (celular novo)');
      addTearDown(novo.fechar);
      expect(novo.dispositivoId, isNot(a.dispositivoId));

      final resultado = CopiaDeSeguranca.restaurar(novo.banco, arquivo('ana'));
      expect(resultado.inventariosNovos, 1);
      expect(
        estado(novo),
        estado(a),
        reason: 'a cópia traz tudo o que a Ana tinha',
      );
      expect(
        RepositorioConflitos(
          novo.banco,
          novo.ops,
        ).contarPendentes(inventario.id),
        0,
        reason: 'o conflito resolvido continua resolvido',
      );

      // Sincronizar com o Bruno leva a ele o que só a Ana tinha.
      RedeSimulada.sincronizar(novo, b, inventario.id);
      expect(estado(b), estado(novo));
      expect(estado(b), estado(a));

      // E o aparelho novo continua trabalhando, com a identidade dele.
      verificar(novo, 'item-6', 'Almoxarifado');
      RedeSimulada.sincronizar(novo, b, inventario.id);
      expect(estado(b), estado(novo));
      expect(
        b.ops.vetorDe(inventario.id)[novo.dispositivoId],
        greaterThan(0),
        reason: 'o trabalho novo sai com a identidade nova',
      );
      expect(
        RepositorioConflitos(b.banco, b.ops).contarPendentes(inventario.id),
        0,
        reason: 'o que o aparelho novo escreve já conhece o que a cópia trouxe',
      );
    },
  );

  test('a identidade e as preferências do aparelho não vão na cópia', () {
    a.banco.gravarConfig(Config.sons, '0');
    CopiaDeSeguranca.exportar(a.banco, arquivo('ana'));

    final novo = Aparelho('Novo');
    addTearDown(novo.fechar);
    final idAntes = novo.dispositivoId;
    CopiaDeSeguranca.restaurar(novo.banco, arquivo('ana'));

    expect(novo.dispositivoId, idAntes);
    expect(novo.banco.lerConfig(Config.sons), isNull);
    expect(novo.banco.lerConfig(Config.usuarioNome), 'Novo');

    final resumo = CopiaDeSeguranca.ler(
      arquivo('ana'),
      comparadoCom: novo.banco,
    );
    expect(resumo.autor, 'Ana');
    expect(resumo.criadaEm, isNotNull);
    expect(resumo.inventarios.single.jaExiste, isTrue);
    expect(resumo.inventarios.single.itens, 6);
  });

  test('exportar um inventário leva só ele', () {
    final outro = a.inventarios.criar(nome: 'Biblioteca', ano: 2026);
    a.patrimonios.inserirRecebidos([
      patrimonioDeTeste(id: 'livro', inventarioId: outro.id, tombo: '99'),
    ]);
    verificar(a, 'item-1', 'Auditório');

    CopiaDeSeguranca.exportar(
      a.banco,
      arquivo('so'),
      inventarioId: inventario.id,
    );
    final resumo = CopiaDeSeguranca.ler(arquivo('so'));
    expect(resumo.inventarios.map((i) => i.nome), ['Campus Picos']);

    final novo = Aparelho('Novo');
    addTearDown(novo.fechar);
    CopiaDeSeguranca.restaurar(novo.banco, arquivo('so'));
    expect(novo.inventarios.listar().map((i) => i.id), [inventario.id]);
    expect(novo.patrimonios.porId('item-1')!.verificado, isTrue);
  });

  test('restaurar duas vezes não duplica nada', () {
    verificar(a, 'item-1', 'Auditório');
    CopiaDeSeguranca.exportar(a.banco, arquivo('ana'));

    final novo = Aparelho('Novo');
    addTearDown(novo.fechar);
    CopiaDeSeguranca.restaurar(novo.banco, arquivo('ana'));
    final segunda = CopiaDeSeguranca.restaurar(novo.banco, arquivo('ana'));
    expect(segunda.inventariosNovos, 0);
    expect(segunda.operacoes, 0);
    expect(
      novo.patrimonios.todos(inventario.id, incluirIgnorados: true),
      hasLength(6),
    );
  });

  test('restaurar no próprio aparelho devolve o que foi apagado', () {
    verificar(a, 'item-1', 'Auditório');
    CopiaDeSeguranca.exportar(a.banco, arquivo('ana'));
    final antes = estado(a);

    a.inventarios.removerLocalmente(inventario.id);
    CopiaDeSeguranca.restaurar(a.banco, arquivo('ana'));
    expect(estado(a), antes);

    // A numeração segue sem repetir a antiga.
    verificar(a, 'item-2', 'Auditório');
    RedeSimulada.sincronizar(a, b, inventario.id);
    expect(estado(b), estado(a));
  });

  group('arquivos que não servem', () {
    test('qualquer outro arquivo é recusado com explicação', () {
      final lixo = File(arquivo('lixo'))..writeAsStringSync('não sou um banco');
      expect(
        () => CopiaDeSeguranca.restaurar(a.banco, lixo.path),
        throwsA(
          isA<CopiaInvalida>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('não é uma cópia'),
          ),
        ),
      );
    });

    test('cópia de versão mais nova do aplicativo é recusada', () {
      CopiaDeSeguranca.exportar(a.banco, arquivo('futuro'));
      final banco = Banco.emMemoria();
      addTearDown(banco.fechar);
      // Simula o arquivo de uma versão futura do esquema.
      final futuro = arquivo('futuro');
      final db = RepositorioOperacoes(a.banco).banco.db;
      db.execute("ATTACH DATABASE ? AS f", [futuro]);
      db.execute('PRAGMA f.user_version = ${versaoEsquema + 1}');
      db.execute('DETACH DATABASE f');

      expect(
        () => CopiaDeSeguranca.restaurar(banco, futuro),
        throwsA(
          isA<CopiaInvalida>().having(
            (e) => e.mensagem,
            'mensagem',
            contains('versão mais nova'),
          ),
        ),
      );
    });
  });

  group('identidade', () {
    test(
      'apagar a réplica e voltar pelos pares recupera o próprio trabalho',
      () {
        verificar(b, 'item-1', 'Auditório');
        verificar(b, 'item-2', 'Biblioteca');
        RedeSimulada.sincronizar(a, b, inventario.id);

        b.inventarios.removerLocalmente(inventario.id);
        RedeSimulada.distribuir(a, [b], a.inventarios.porId(inventario.id)!);

        // Bruno volta a ler antes de sincronizar: a numeração não pode
        // reaproveitar a antiga, que a Ana ainda guarda.
        verificar(b, 'item-3', 'Laboratório');
        RedeSimulada.sincronizar(a, b, inventario.id);

        expect(estado(b), estado(a));
        expect(
          b.patrimonios.porId('item-1')!.verificado,
          isTrue,
          reason: 'o trabalho antigo do próprio Bruno voltou',
        );
        expect(
          a.patrimonios.porId('item-3')!.verificado,
          isTrue,
          reason: 'e o novo chegou à Ana',
        );
      },
    );

    test('dois aparelhos com a mesma identidade são recusados', () {
      verificar(b, 'item-1', 'Auditório');
      RedeSimulada.sincronizar(a, b, inventario.id);

      // Um clone do Bruno, como faria o backup do sistema: mesmo banco,
      // mesma identidade. Cada um escreve a sua operação seguinte.
      CopiaSimulada.clonar(b, arquivo('clone'));
      final clone = Aparelho.deArquivo('Bruno (clone)', arquivo('clone'));
      addTearDown(clone.fechar);
      expect(clone.dispositivoId, b.dispositivoId);

      verificar(b, 'item-2', 'Biblioteca');
      verificar(clone, 'item-2', 'Secretaria');
      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(
        () => RedeSimulada.sincronizar(a, clone, inventario.id),
        throwsA(isA<IdentidadeDuplicada>()),
      );
      expect(
        impressaoDe(a, 'item-2'),
        contains('Biblioteca'),
        reason: 'nada do clone entrou na Ana',
      );
    });

    test('o clone recomeça com identidade nova e volta a sincronizar', () {
      verificar(b, 'item-1', 'Auditório');
      RedeSimulada.sincronizar(a, b, inventario.id);
      CopiaSimulada.clonar(b, arquivo('clone'));
      final clone = Aparelho.deArquivo('Bruno (clone)', arquivo('clone'));
      addTearDown(clone.fechar);
      verificar(b, 'item-2', 'Biblioteca');
      verificar(clone, 'item-2', 'Secretaria');
      RedeSimulada.sincronizar(a, b, inventario.id);

      clone.inventarios.renovarIdentidade();
      expect(clone.dispositivoId, isNot(b.dispositivoId));
      expect(clone.inventarios.listar(), isEmpty);
      expect(clone.banco.lerConfig(Config.usuarioNome), 'Bruno (clone)');

      // Entra de novo pelo QR code e segue trabalhando.
      RedeSimulada.distribuir(a, [clone], a.inventarios.porId(inventario.id)!);
      RedeSimulada.sincronizar(a, clone, inventario.id);
      verificar(clone, 'item-3', 'Laboratório');
      RedeSimulada.sincronizar(a, clone, inventario.id);
      RedeSimulada.sincronizar(a, b, inventario.id);

      expect(estado(clone), estado(a));
      expect(estado(b), estado(a));
      expect(impressaoDe(a, 'item-2'), contains('Biblioteca'));
      expect(a.patrimonios.porId('item-3')!.verificado, isTrue);
    });
  });
}

/// Cópia do arquivo inteiro do banco, identidade incluída — o que o
/// aplicativo evita, e o backup do sistema faria.
class CopiaSimulada {
  static void clonar(Aparelho aparelho, String destino) {
    aparelho.banco.db.execute('VACUUM INTO ?', [destino]);
  }
}
