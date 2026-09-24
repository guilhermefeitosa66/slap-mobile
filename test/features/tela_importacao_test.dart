import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/banco.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/data/repos/operacoes.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/import/tela_importacao.dart';

import '../apoio/app_de_teste.dart';

/// Arquivo entregue pelo seletor falso.
final class ArquivoDeTeste extends PlatformFile {
  final String nome;
  final Uint8List bytes;

  ArquivoDeTeste(this.nome, this.bytes);

  @override
  String get name => nome;

  @override
  Uri get uri => Uri.parse('file:///teste/$nome');

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);
}

/// Seletor do sistema substituído: devolve o arquivo que o teste escolher.
class SeletorDeTeste extends FilePickerPlatform {
  PlatformFile? proximo;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => proximo;
}

void main() {
  late Banco banco;
  late Inventario inventario;
  late SeletorDeTeste seletor;
  late FilePickerPlatform original;

  setUp(() {
    banco = Banco.emMemoria();
    inventario = RepositorioInventarios(
      banco,
      RepositorioOperacoes(banco),
    ).criar(nome: 'Campus', ano: 2026);
    original = FilePickerPlatform.instance;
    seletor = SeletorDeTeste();
    FilePickerPlatform.instance = seletor;
  });

  tearDown(() {
    FilePickerPlatform.instance = original;
    banco.fechar();
  });

  /// A planilha como o SUAP exporta: título antes da tabela, e dois EDs.
  Uint8List planilha() {
    final linhas = [
      'Relatório de bens;;;;;',
      'Nº;Tombo;Código de Barras;ED;Descrição;Sala',
      for (var i = 1; i <= 12; i++)
        '$i;${(23100 + i).toString().padLeft(6, '0')};-${887100 + i};'
            '${i <= 9 ? '44905242' : '44905218'};'
            '${i <= 9 ? 'CADEIRA $i' : 'LIVRO $i'};Biblioteca',
    ];
    return Uint8List.fromList(utf8.encode(linhas.join('\n')));
  }

  /// Etapas em isolate terminam em tempo real, fora do relógio do teste.
  Future<void> esperarAte(WidgetTester tester, Finder alvo) async {
    for (var i = 0; i < 100 && alvo.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(alvo, findsWidgets);
  }

  Future<void> abrirImportacao(WidgetTester tester) async {
    await montar(
      tester,
      Builder(
        builder: (contexto) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(contexto).push(
              MaterialPageRoute<void>(
                builder: (_) => TelaImportacao(inventarioId: inventario.id),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
      banco: banco,
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('escolher, conferir colunas, marcar EDs e importar', (
    tester,
  ) async {
    seletor.proximo = ArquivoDeTeste('bens.csv', planilha());
    await abrirImportacao(tester);

    // 1. Arquivo.
    await tester.tap(find.text('Escolher arquivo'));
    await esperarAte(tester, find.text('Confira as colunas'));

    // 2. Mapeamento: reconhecido pelo nome, com amostra do conteúdo.
    expect(
      find.textContaining('bens.csv · 12 linhas de dados'),
      findsOneWidget,
    );
    expect(find.textContaining('Exemplo: 023101'), findsOneWidget);
    // Os seletores seguem a ordem da planilha do SLAP: código de barras,
    // tombo, ED…
    // Rótulos que não se repetem como cabeçalho da planilha de teste — os que
    // se repetem apareceriam duas vezes, no campo e no seletor — e que cabem
    // na tela sem rolar.
    final alturaCodigo = tester.getTopLeft(find.text('Código de barras')).dy;
    final alturaEd = tester.getTopLeft(find.text('Elemento de despesa')).dy;
    expect(alturaCodigo, lessThan(alturaEd));
    await tester.tap(find.text('Continuar'));

    await esperarAte(tester, find.text('Elementos de despesa'));

    // 3. EDs: material bibliográfico fora.
    expect(find.text('12 patrimônios encontrados'), findsOneWidget);
    expect(find.text('12 entrarão no inventário'), findsOneWidget);
    await tester.tap(find.text('ED 44905218'));
    await tester.pump();
    expect(find.text('9 entrarão no inventário'), findsOneWidget);

    // 4. Confirmar.
    await tester.tap(find.text('Importar'));
    await esperarAte(tester, find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('12 itens importados'), findsOneWidget);

    final repo = RepositorioPatrimonios(banco, RepositorioOperacoes(banco));
    final progresso = repo.progresso(inventario.id);
    expect(progresso.total, 9);
    expect(progresso.ignorados, 3);
    expect(
      RepositorioInventarios(
        banco,
        RepositorioOperacoes(banco),
      ).porId(inventario.id)!.edsExcluidos,
      ['44905218'],
    );
    expect(
      repo
          .procurar(
            inventarioId: inventario.id,
            codigo: '887101',
            modo: ModoLeitura.codigoBarras,
          )
          .resultado,
      ResultadoLeitura.sucesso,
      reason: 'o código negativo do SUAP fica encontrável',
    );
  });

  testWidgets('desistir no seletor volta sem erro', (tester) async {
    seletor.proximo = null;
    await abrirImportacao(tester);
    await tester.tap(find.text('Escolher arquivo'));
    await tester.pumpAndSettle();
    expect(find.text('Escolha a planilha do inventário'), findsOneWidget);
    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('arquivo .xls antigo é recusado com orientação', (tester) async {
    seletor.proximo = ArquivoDeTeste('bens.xls', Uint8List.fromList([1, 2]));
    await abrirImportacao(tester);
    await tester.tap(find.text('Escolher arquivo'));
    await esperarAte(tester, find.byType(MaterialBanner));
    expect(find.textContaining('.xlsx'), findsWidgets);
  });
}
