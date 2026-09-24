import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/domain/patrimonio.dart';

/// O contador da sala: o que a planilha aponta para ela, quanto já foi
/// verificado e o que chegou de outro lugar.
void main() {
  late Banco banco;
  late RepositorioPatrimonios repo;
  late RepositorioInventarios inventarios;
  late Inventario inventario;

  setUp(() {
    banco = Banco.emMemoria();
    final ops = RepositorioOperacoes(banco);
    repo = RepositorioPatrimonios(banco, ops);
    inventarios = RepositorioInventarios(banco, ops);
    inventario = inventarios.criar(nome: 'Campus', ano: 2026);
  });

  tearDown(() => banco.fechar());

  /// Um patrimônio da planilha, pelo tombo.
  Patrimonio item(String tombo) => repo
      .todos(inventario.id, incluirIgnorados: true)
      .firstWhere((p) => p.tombo == tombo);

  void verificar(String tombo, String sala) => repo.registrarVerificacao(
    patrimonio: item(tombo),
    config: ConfiguracaoLevantamento(sala: sala),
  );

  void importar() {
    repo.inserirLote(inventario.id, const [
      PatrimonioImportado(tombo: '000001', sala: 'Coordenação de TI'),
      PatrimonioImportado(tombo: '000002', sala: 'COORDENACAO DE TI'),
      PatrimonioImportado(tombo: '000003', sala: ' coordenação  de ti '),
      PatrimonioImportado(tombo: '000004', sala: 'Auditório'),
      PatrimonioImportado(tombo: '000005', sala: null),
      PatrimonioImportado(
        tombo: '000006',
        sala: 'Coordenação de TI',
        ed: '4490.52.18',
      ),
    ]);
  }

  test('a sala é comparada como o domínio compara, não por igualdade crua', () {
    importar();

    // As três grafias da planilha são a mesma sala, e a sala digitada na
    // configuração também: quem digita não repete o acento do SUAP.
    for (final digitada in [
      'Coordenação de TI',
      'coordenacao de ti',
      '  COORDENAÇÃO   DE   TI ',
    ]) {
      final p = repo.progressoDaSala(inventario.id, digitada);
      expect(p.total, 4, reason: digitada);
      expect(p.verificados, 0);
      expect(p.semBase, isFalse);
    }

    expect(repo.progressoDaSala(inventario.id, 'Auditório').total, 1);
  });

  test('conta os verificados da sala e ignora os de ED excluído', () {
    importar();
    inventarios.definirEdsExcluidos(inventario.id, ['4490.52.18']);

    var p = repo.progressoDaSala(inventario.id, 'Coordenação de TI');
    expect(p.total, 3, reason: 'o item de ED excluído sai do denominador');
    expect(p.verificados, 0);

    verificar('000001', 'Coordenação de TI');
    p = repo.progressoDaSala(inventario.id, 'Coordenação de TI');
    expect(p.verificados, 1);
    expect(p.pendentes, 2);

    // Ler o item de ED excluído não mexe no contador da sala.
    verificar('000006', 'Coordenação de TI');
    p = repo.progressoDaSala(inventario.id, 'Coordenação de TI');
    expect(p.total, 3);
    expect(p.verificados, 1);
    expect(p.deOutrasSalas, 0);
  });

  test('item da sala encontrado em outro lugar continua verificado aqui', () {
    importar();

    // O item 1 é da Coordenação e foi achado no Auditório: não precisa mais
    // ser procurado na Coordenação, então conta como verificado lá.
    verificar('000001', 'Auditório');

    final origem = repo.progressoDaSala(inventario.id, 'Coordenação de TI');
    expect(origem.total, 4);
    expect(origem.verificados, 1);
    expect(origem.deOutrasSalas, 0);

    // E, no Auditório, entra como item de outra sala — fora do denominador,
    // que continua sendo o que a planilha manda procurar ali.
    final destino = repo.progressoDaSala(inventario.id, 'Auditório');
    expect(destino.total, 1);
    expect(destino.verificados, 0);
    expect(destino.deOutrasSalas, 1);
  });

  test('sala fora da planilha não tem denominador, só o que foi lido ali', () {
    importar();

    var p = repo.progressoDaSala(inventario.id, 'Sala 205');
    expect(p.semBase, isTrue);
    expect(p.total, 0);
    expect(p.verificados, 0);
    expect(p.deOutrasSalas, 0);

    verificar('000001', 'Sala 205');
    verificar('000004', 'SALA 205');

    p = repo.progressoDaSala(inventario.id, 'Sala 205');
    expect(p.semBase, isTrue);
    expect(p.deOutrasSalas, 2, reason: 'tudo que foi lido ali veio de fora');
  });

  test('sem sala configurada não há o que contar', () {
    importar();

    for (final vazia in [null, '', '   ']) {
      final p = repo.progressoDaSala(inventario.id, vazia);
      expect(p.total, 0, reason: 'sala $vazia');
      expect(p.verificados, 0);
      expect(p.deOutrasSalas, 0);
    }

    // Item sem sala na planilha não vira uma sala de nome vazio.
    verificar('000005', 'Coordenação de TI');
    expect(repo.progressoDaSala(inventario.id, '').total, 0);
  });

  test('inventário sem itens devolve zero, não erro', () {
    final p = repo.progressoDaSala(inventario.id, 'Coordenação de TI');
    expect(p.total, 0);
    expect(p.semBase, isTrue);
  });
}
