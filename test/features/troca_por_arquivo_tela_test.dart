import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/app/app.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/data/copia_seguranca.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/data/schema.dart';
import 'package:slap_mobile/features/inventory/tela_dashboard.dart';
import 'package:slap_mobile/features/inventory/tela_inventarios.dart';
import 'package:slap_mobile/features/sync/troca_por_arquivo.dart';

import '../apoio/app_de_teste.dart';
import '../apoio/rede_simulada.dart';

/// Arquivos abertos de fora, sem canal nativo: o teste entrega o caminho.
class RecebidosDeTeste implements ArquivosRecebidos {
  final _chegadas = StreamController<String>.broadcast();
  String? inicial;

  void chegar(String caminho) => _chegadas.add(caminho);

  @override
  Stream<String> get chegadas => _chegadas.stream;

  @override
  Future<String?> pendente() async {
    final c = inicial;
    inicial = null;
    return c;
  }
}

/// Receber o arquivo de um inventário: o caminho de quem nunca está na mesma
/// rede que o resto da equipe.
void main() {
  late Directory pasta;
  late Aparelho marta;
  late Aparelho davi;
  late Inventario inventario;
  late RecebidosDeTeste recebidos;

  setUp(() async {
    pasta = await Directory.systemTemp.createTemp('slap_receber_');
    marta = Aparelho('Marta');
    marta.banco.gravarConfig(Config.usuarioNome, 'Marta Lima');
    inventario = marta.inventarios.criar(nome: 'Campus Modelo', ano: 2026);
    marta.patrimonios.inserirRecebidos([
      for (var i = 1; i <= 3; i++)
        patrimonioDeTeste(
          id: 'item-$i',
          inventarioId: inventario.id,
          tombo: '$i',
          sala: 'Sala $i',
        ),
    ]);
    marta.patrimonios.registrarVerificacao(
      patrimonio: marta.patrimonios.porId('item-1')!,
      config: const ConfiguracaoLevantamento(sala: 'Diretoria'),
      usuarioNome: 'Marta Lima',
    );
    davi = Aparelho('Davi');
    davi.banco.gravarConfig(Config.usuarioNome, 'Davi Rocha');
    recebidos = RecebidosDeTeste();
  });

  tearDown(() async {
    marta.fechar();
    davi.fechar();
    await pasta.delete(recursive: true);
  });

  /// O arquivo como chega ao aparelho: uma cópia temporária, que a tela
  /// apaga ao sair.
  String arquivoDaMarta() {
    final caminho =
        '${pasta.path}/marta-${DateTime.now().microsecondsSinceEpoch}.db';
    CopiaDeSeguranca.exportar(
      marta.banco,
      caminho,
      inventarioId: inventario.id,
    );
    return caminho;
  }

  Future<void> abrir(WidgetTester tester) async {
    final c = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(davi.banco),
        sonsProvider.overrideWithValue(SonsMudos()),
        arquivosRecebidosProvider.overrideWithValue(recebidos),
      ],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: c, child: const AplicativoSlap()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a lista vazia oferece receber um arquivo', (tester) async {
    await abrir(tester);
    expect(find.text(rotuloReceberArquivo), findsOneWidget);
    expect(find.text(rotuloImportar), findsOneWidget);
  });

  testWidgets('arquivo aberto de fora: mostra o que traz e recebe', (
    tester,
  ) async {
    await abrir(tester);
    final caminho = arquivoDaMarta();
    recebidos.chegar(caminho);
    await tester.pumpAndSettle();

    expect(find.byType(TelaReceberArquivo), findsOneWidget);
    expect(find.textContaining('de Marta Lima'), findsOneWidget);
    expect(find.text('Campus Modelo — 2026'), findsOneWidget);
    expect(find.textContaining('novo neste aparelho'), findsOneWidget);
    expect(find.textContaining('Nada é apagado'), findsOneWidget);

    await tester.tap(find.text('Receber'));
    await tester.pumpAndSettle();

    expect(find.text('Dados recebidos'), findsOneWidget);
    expect(davi.inventarios.porId(inventario.id), isNotNull);
    expect(davi.patrimonios.progresso(inventario.id).verificados, 1);

    await tester.tap(find.text('Abrir o inventário'));
    await tester.pumpAndSettle();
    expect(find.byType(TelaDashboard), findsOneWidget);
    expect(tester.takeException(), isNull);

    expect(
      File(caminho).existsSync(),
      isFalse,
      reason: 'o temporário é apagado ao sair da tela',
    );
  });

  testWidgets('o arquivo que abriu o aplicativo também chega', (tester) async {
    recebidos.inicial = arquivoDaMarta();
    await abrir(tester);
    expect(find.byType(TelaReceberArquivo), findsOneWidget);
    expect(find.text('Campus Modelo — 2026'), findsOneWidget);
  });

  testWidgets('inventário que já está aqui recebe só o que falta', (
    tester,
  ) async {
    RedeSimulada.distribuir(marta, [davi], inventario);
    marta.patrimonios.registrarVerificacao(
      patrimonio: marta.patrimonios.porId('item-2')!,
      config: const ConfiguracaoLevantamento(sala: 'Biblioteca'),
      usuarioNome: 'Marta Lima',
    );
    await abrir(tester);
    recebidos.chegar(arquivoDaMarta());
    await tester.pumpAndSettle();

    expect(find.textContaining('já está neste aparelho'), findsOneWidget);
    await tester.tap(find.text('Receber'));
    await tester.pumpAndSettle();
    expect(find.textContaining('recebida'), findsOneWidget);
    expect(davi.patrimonios.progresso(inventario.id).verificados, 2);
  });

  testWidgets('arquivo que não é do SLAP é recusado sem mudar nada', (
    tester,
  ) async {
    await abrir(tester);
    final falso = File('${pasta.path}/foto.db')
      ..writeAsStringSync('não sou um banco');
    recebidos.chegar(falso.path);
    await tester.pumpAndSettle();

    expect(find.textContaining('não é do SLAP Mobile'), findsOneWidget);
    expect(find.text('Receber'), findsNothing);
    expect(davi.inventarios.listar(), isEmpty);
  });

  test('o nome do arquivo diz de quem e de quando, sem acento', () {
    expect(
      nomeDoArquivo(inventario, 'Marta Lima', DateTime(2026, 11, 27, 9, 5)),
      'slap-campus-modelo-2026-marta-lima-20261127-0905.slapcopia',
    );
  });

  test('a mensagem diz o que fazer e pede cuidado ao encaminhar', () {
    final texto = textoDoArquivo(inventario, 'Marta Lima');
    expect(texto, contains('Campus Modelo — 2026'));
    expect(texto, contains(rotuloReceberArquivo));
    expect(texto, contains('não encaminhe'));
  });
}
