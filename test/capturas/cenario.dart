import 'dart:io';

import 'package:flutter/services.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';

export '../apoio/app_de_teste.dart' show SonsMudos;

/// Um inventário de demonstração, com levantamento em andamento.
///
/// Os nomes são fictícios: as capturas vão para a loja e para a documentação,
/// e planilha real do SUAP traz nome de servidor.
class Cenario {
  final Banco banco;
  late final RepositorioOperacoes ops;
  late final RepositorioPatrimonios patrimonios;
  late final RepositorioInventarios inventarios;
  late final Inventario geral;

  Cenario() : banco = Banco.emMemoria() {
    ops = RepositorioOperacoes(banco);
    patrimonios = RepositorioPatrimonios(banco, ops);
    inventarios = RepositorioInventarios(banco, ops);
    banco.gravarConfig(Config.usuarioNome, 'Ana Souza');
    banco.gravarConfig(Config.usuarioMatricula, '2091234');
    _montar();
  }

  static const _descricoes = [
    'CADEIRA FIXA ESTOFADA PRETA',
    'MESA DE REUNIÃO OVAL 8 LUGARES',
    'PROJETOR MULTIMÍDIA 3500 LUMENS',
    'ARMÁRIO DE AÇO 2 PORTAS',
    'ESTABILIZADOR ELETRÔNICO 1000VA',
    'CADEIRA GIRATÓRIA COM BRAÇOS',
    'MICROCOMPUTADOR DESKTOP',
    'MONITOR LED 24 POLEGADAS',
    'QUADRO BRANCO 120 X 90',
    'ESTANTE DE AÇO 6 PRATELEIRAS',
    'NOBREAK 1500VA',
    'IMPRESSORA LASER MONOCROMÁTICA',
  ];

  static const _salas = [
    'Auditório',
    'Biblioteca',
    'Coordenação de TI',
    'Laboratório 2',
    'Sala dos Professores',
    'Secretaria',
  ];

  static const _responsaveis = [
    'Bruno Carvalho',
    'Carla Menezes',
    'Davi Nogueira',
    'Elisa Prado',
  ];

  void _montar() {
    geral = inventarios.criar(
      nome: 'Campus Picos — Patrimônio Geral',
      ano: 2026,
    );
    final biblioteca = inventarios.criar(
      nome: 'Campus Picos — Biblioteca',
      ano: 2026,
    );
    inventarios.criar(nome: 'Laboratório de Informática', ano: 2025);

    patrimonios.inserirLote(geral.id, [
      for (var i = 0; i < 412; i++)
        PatrimonioImportado(
          ordem: '${i + 1}',
          tombo: (23100 + i).toString().padLeft(6, '0'),
          codigoBarras: (887000 + i).toString(),
          ed: '44905242',
          descricao: _descricoes[i % _descricoes.length],
          sala: _salas[i % _salas.length],
          responsavel: _responsaveis[i % _responsaveis.length],
        ),
    ]);
    patrimonios.inserirLote(biblioteca.id, [
      for (var i = 0; i < 64; i++)
        PatrimonioImportado(
          ordem: '${i + 1}',
          tombo: (31000 + i).toString().padLeft(6, '0'),
          descricao: _descricoes[i % _descricoes.length],
          sala: 'Biblioteca',
        ),
    ]);

    // Levantamento em andamento: a maior parte confere, parte mudou de sala.
    final itens = patrimonios.todos(geral.id);
    for (var i = 0; i < 248; i++) {
      final p = itens[i];
      final mudou = i % 5 == 0;
      patrimonios.registrarVerificacao(
        patrimonio: p,
        config: ConfiguracaoLevantamento(
          sala: mudou ? 'Auditório' : p.salaOriginal!,
          responsavel: i % 11 == 0 ? 'Elisa Prado' : null,
        ),
        usuarioNome: i.isEven ? 'Ana Souza' : 'Bruno Carvalho',
      );
    }
    for (final p in patrimonios.todos(biblioteca.id)) {
      patrimonios.registrarVerificacao(
        patrimonio: p,
        config: const ConfiguracaoLevantamento(sala: 'Biblioteca'),
        usuarioNome: 'Carla Menezes',
      );
    }
  }

  void fechar() => banco.fechar();
}

/// Carrega as fontes de verdade, para a captura sair como no aparelho.
///
/// Sem isto o `flutter_test` desenha tudo numa fonte de blocos.
Future<void> carregarFontes() async {
  Future<void> carregar(String familia, List<String> arquivos) async {
    final carregador = FontLoader(familia);
    for (final arquivo in arquivos) {
      carregador.addFont(rootBundle.load(arquivo));
    }
    await carregador.load();
  }

  await carregar('Archivo', [
    for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fontes/Archivo-$peso.ttf',
  ]);
  await carregar('Public Sans', [
    for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold'])
      'assets/fontes/PublicSans-$peso.ttf',
  ]);

  // Os ícones do Material vêm do SDK, não do pacote.
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk != null) {
    final icones = File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icones.existsSync()) {
      final carregador = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icones.readAsBytesSync())));
      await carregador.load();
    }
  }
}
