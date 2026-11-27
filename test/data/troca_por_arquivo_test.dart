import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/copia_seguranca.dart';
import 'package:slap_mobile/data/repos/conflitos.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';

import '../apoio/rede_simulada.dart';

/// Troca de dados por arquivo: uma equipe que nunca está na mesma rede.
///
/// Ninguém se encontra. A Marta importa a planilha e manda o arquivo do
/// inventário pelo WhatsApp; o Davi e a Rosa recebem, levantam cada um a sua
/// parte e devolvem o arquivo deles; a Marta vai juntando. O arquivo é o
/// mesmo `.slapcopia` da cópia de segurança, e receber é restaurar: as
/// operações entram pelo mesmo caminho da troca pela rede.
void main() {
  late Directory pasta;
  late Aparelho marta;
  late Aparelho davi;
  late Aparelho rosa;
  late Inventario inventario;

  setUp(() async {
    pasta = await Directory.systemTemp.createTemp('slap_arquivo_');
    marta = Aparelho('Marta');
    davi = Aparelho('Davi');
    rosa = Aparelho('Rosa');
    inventario = marta.inventarios.criar(nome: 'Campus Modelo', ano: 2026);
    marta.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 8; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: '$i',
          sala: 'Sala $i',
        ),
    ]);
  });

  tearDown(() async {
    marta.fechar();
    davi.fechar();
    rosa.fechar();
    await pasta.delete(recursive: true);
  });

  void verificar(Aparelho x, String item, String sala) =>
      x.patrimonios.registrarVerificacao(
        patrimonio: x.patrimonios.porId(item)!,
        config: ConfiguracaoLevantamento(sala: sala),
        usuarioNome: x.apelido,
      );

  /// Exporta o inventário de [de] e recebe em [para], como um arquivo que
  /// passou pelo WhatsApp.
  ResultadoRestauracao mandar(Aparelho de, Aparelho para) {
    final arquivo =
        '${pasta.path}/${de.apelido}-${DateTime.now().microsecondsSinceEpoch}'
        '.${CopiaDeSeguranca.extensao}';
    CopiaDeSeguranca.exportar(de.banco, arquivo, inventarioId: inventario.id);
    return CopiaDeSeguranca.restaurar(para.banco, arquivo);
  }

  List<String> estado(Aparelho x) => [
    for (var i = 1; i <= 8; i++) impressaoDe(x, 'item-$i'),
    'progresso=${x.patrimonios.progresso(inventario.id).verificados}',
  ];

  int conflitos(Aparelho x) =>
      RepositorioConflitos(x.banco, x.ops).contarPendentes(inventario.id);

  test('o arquivo leva o inventário inteiro a quem não tem', () {
    final r = mandar(marta, davi);

    expect(r.inventariosNovos, 1);
    final recebido = davi.inventarios.porId(inventario.id)!;
    expect(recebido.titulo, inventario.titulo);
    expect(
      recebido.chaveSync,
      inventario.chaveSync,
      reason: 'a mesma chave: depois os dois podem trocar também pela rede',
    );
    expect(estado(davi), estado(marta));
  });

  test(
    'cada um levanta a sua parte e a Marta junta tudo, sem se encontrarem',
    () {
      mandar(marta, davi);
      mandar(marta, rosa);

      verificar(marta, 'item-1', 'Diretoria');
      verificar(davi, 'item-2', 'Biblioteca');
      verificar(davi, 'item-3', 'Biblioteca');
      verificar(rosa, 'item-4', 'Laboratório');

      final doDavi = mandar(davi, marta);
      expect(doDavi.inventariosNovos, 0);
      expect(doDavi.operacoes, greaterThan(0));
      mandar(rosa, marta);

      expect(marta.patrimonios.progresso(inventario.id).verificados, 4);

      // O consolidado volta para os dois.
      mandar(marta, davi);
      mandar(marta, rosa);
      expect(estado(davi), estado(marta));
      expect(estado(rosa), estado(marta));
    },
  );

  test('a ordem dos arquivos não importa, e receber de novo não duplica', () {
    mandar(marta, davi);
    mandar(marta, rosa);
    verificar(davi, 'item-2', 'Biblioteca');
    verificar(rosa, 'item-4', 'Laboratório');

    // A Rosa recebe do Davi direto, e a Marta recebe só da Rosa: o arquivo
    // leva tudo o que o aparelho sabia, inclusive o que veio de outro.
    mandar(davi, rosa);
    mandar(rosa, marta);
    expect(marta.patrimonios.progresso(inventario.id).verificados, 2);

    final antes = estado(marta);
    final repetido = mandar(rosa, marta);
    expect(repetido.operacoes, 0, reason: 'nada novo no mesmo arquivo');
    expect(estado(marta), antes);
  });

  test('duas pessoas no mesmo item, sem saber da outra, viram conflito', () {
    mandar(marta, davi);
    mandar(marta, rosa);
    verificar(davi, 'item-5', 'Secretaria');
    verificar(rosa, 'item-5', 'Protocolo');

    mandar(davi, marta);
    final daRosa = mandar(rosa, marta);
    expect(daRosa.conflitos, 1);
    expect(conflitos(marta), 1);

    // A Marta decide, e a decisão viaja no arquivo seguinte.
    final repo = RepositorioConflitos(marta.banco, marta.ops);
    repo.resolver(
      conflito: repo.listar(inventario.id).single,
      valorEscolhido: 'Protocolo',
      usuarioNome: 'Marta',
    );
    mandar(marta, davi);
    mandar(marta, rosa);
    expect(conflitos(davi), 0);
    expect(conflitos(rosa), 0);
    expect(estado(davi), estado(marta));
    expect(estado(rosa), estado(marta));
  });

  test(
    'arquivo e rede se misturam: quem recebeu por arquivo troca pela rede',
    () {
      mandar(marta, davi);
      mandar(marta, rosa);
      verificar(davi, 'item-6', 'Auditório');
      verificar(rosa, 'item-7', 'Cantina');

      // Davi e Rosa se encontram um dia; a Marta segue só por arquivo.
      RedeSimulada.sincronizar(davi, rosa, inventario.id);
      mandar(rosa, marta);
      expect(estado(marta), estado(rosa));
      expect(estado(davi), estado(rosa));
    },
  );
}
