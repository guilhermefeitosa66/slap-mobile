@Tags(['capturas'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:slap_mobile/app/providers.dart';
import 'package:slap_mobile/app/tema.dart';
import 'package:slap_mobile/core/atualizacao.dart';
import 'package:slap_mobile/data/repos/patrimonios.dart';
import 'package:slap_mobile/features/divergence/tela_itens.dart';
import 'package:slap_mobile/features/identity/tela_identidade.dart';
import 'package:slap_mobile/features/import/tela_importacao.dart';
import 'package:slap_mobile/features/inventory/tela_dashboard.dart';
import 'package:slap_mobile/features/inventory/tela_inventarios.dart';
import 'package:slap_mobile/features/reports/tela_relatorios.dart';
import 'package:slap_mobile/features/survey/configuracao_sheet.dart';
import 'package:slap_mobile/features/survey/estado_levantamento.dart';
import 'package:slap_mobile/features/survey/tela_camera.dart';
import 'package:slap_mobile/features/survey/tela_levantamento.dart';
import 'package:slap_mobile/features/sync/anuncio.dart';
import 'package:slap_mobile/features/sync/cliente.dart';
import 'package:slap_mobile/features/sync/descoberta.dart';
import 'package:slap_mobile/features/sync/servidor.dart';
import 'package:slap_mobile/features/sync/tela_sincronizacao.dart';

import 'cenario.dart';

/// Capturas das telas que o site e o manual mostram, com dados de
/// demonstração.
///
/// São as treze de `docs/imagens/` (a lista está em
/// `tool/reduzir_capturas.py`), no tamanho do iPhone de 6,3 polegadas:
/// 1206 × 2622, com a área da barra de status e a do indicador de início
/// reservadas, porque o site as mostra dentro de uma moldura de celular, que
/// desenha essas duas coisas. Saem em `build/capturas-site/`; depois,
///
///     python3 tool/reduzir_capturas.py build/capturas-site 1206
///
/// grava em `docs/imagens/`. Gerar:
///
///     flutter test --run-skipped --tags capturas --update-goldens test/capturas/site_test.dart
void main() {
  const destino = '../../build/capturas-site';

  // iPhone de 6,3 polegadas: 402 × 874 pontos, 3 pixels por ponto. A barra
  // de status com a Dynamic Island ocupa 62 pontos; o indicador de início, 34.
  const tamanho = Size(402, 874);
  const densidade = 3.0;

  setUpAll(carregarFontes);

  Future<void> capturar(
    WidgetTester tester, {
    required String nome,
    required Widget Function(ProviderContainer) tela,
    void Function(ProviderContainer)? preparar,
    Future<void> Function(WidgetTester, ProviderContainer)? depois,
    List<Override> trocas = const [],
    bool barraClara = false,
  }) async {
    debugDisableShadows = false;

    tester.view.physicalSize = tamanho * densidade;
    tester.view.devicePixelRatio = densidade;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    tester.view.viewPadding = const FakeViewPadding(
      top: 62 * 3,
      bottom: 34 * 3,
    );
    addTearDown(tester.view.reset);

    final cenario = Cenario();
    addTearDown(cenario.fechar);

    final container = ProviderContainer(
      overrides: [
        bancoProvider.overrideWithValue(cenario.banco),
        sonsProvider.overrideWithValue(SonsMudos()),
        verificadorAtualizacaoProvider.overrideWithValue(
          VerificadorAtualizacao(buscar: (_) async => null),
        ),
        ...trocas,
      ],
    );
    addTearDown(container.dispose);
    preparar?.call(container);

    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Stack(
              children: [
                MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: temaClaro,
                  darkTheme: temaEscuro,
                  themeMode: ThemeMode.light,
                  home: Builder(builder: (_) => tela(container)),
                ),
                _BarraDeStatus(clara: barraClara),
                _IndicadorDeInicio(claro: barraClara),
              ],
            ),
          ),
        ),
      );
      await _assentar(tester);
      await depois?.call(tester, container);
      await _assentar(tester);

      await expectLater(
        find.byType(Stack).first,
        matchesGoldenFile('$destino/$nome.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('identidade', (tester) async {
    await capturar(
      tester,
      nome: 'identidade',
      tela: (_) => const TelaIdentidade(),
      // Sem o cursor piscando e a alça de seleção no nome.
      depois: (_, _) async => FocusManager.instance.primaryFocus?.unfocus(),
    );
  });

  testWidgets('inventários', (tester) async {
    await capturar(
      tester,
      nome: 'inventarios',
      tela: (_) => const TelaInventarios(),
    );
  });

  testWidgets('importação', (tester) async {
    final original = FilePickerPlatform.instance;
    final planilha = File(
      'docs/loja/planilha-demonstracao.xlsx',
    ).readAsBytesSync();
    FilePickerPlatform.instance = _Seletor(
      _Arquivo('bens-campus-picos.xlsx', planilha),
    );
    addTearDown(() => FilePickerPlatform.instance = original);

    await capturar(
      tester,
      nome: 'importacao',
      tela: (c) => TelaImportacao(inventarioId: _vazio(c)),
      preparar: (c) => c
          .read(inventariosProvider)
          .criar(nome: 'Campus Picos — Almoxarifado', ano: 2026),
      depois: (tester, _) async {
        await tester.tap(find.text('Escolher arquivo'));
        await _esperar(tester, find.text('Confira as colunas'));
      },
    );
  });

  testWidgets('painel', (tester) async {
    await capturar(
      tester,
      nome: 'painel',
      tela: (c) => TelaDashboard(inventarioId: _geral(c)),
    );
  });

  testWidgets('compartilhar', (tester) async {
    await capturar(
      tester,
      nome: 'compartilhar',
      trocas: [anuncioEntradaProvider.overrideWith(_AnuncioQuieto.new)],
      tela: (c) => TelaDashboard(inventarioId: _geral(c)),
      depois: (tester, _) async {
        await tester.tap(find.byTooltip('Compartilhar inventário'));
      },
    );
  });

  testWidgets('configuração', (tester) async {
    await capturar(
      tester,
      nome: 'configuracao',
      preparar: _levantamentoEmAndamento,
      tela: (c) => TelaLevantamento(inventarioId: _geral(c)),
      depois: (tester, c) async {
        final elemento = tester.element(find.byType(TelaLevantamento));
        unawaited(
          abrirConfiguracao(elemento, elemento as WidgetRef, _geral(c)),
        );
      },
    );
  });

  testWidgets('levantamento', (tester) async {
    await capturar(
      tester,
      nome: 'levantamento',
      preparar: _levantamentoEmAndamento,
      tela: (c) => TelaLevantamento(inventarioId: _geral(c)),
    );
  });

  testWidgets('câmera', (tester) async {
    final original = MobileScannerPlatform.instance;
    final camera = _CameraDeDemonstracao();
    MobileScannerPlatform.instance = camera;
    addTearDown(() => MobileScannerPlatform.instance = original);

    await capturar(
      tester,
      nome: 'camera',
      barraClara: true,
      preparar: _levantamentoEmAndamento,
      tela: (c) => TelaCamera(inventarioId: _geral(c)),
      depois: (tester, _) async {
        // Duas etiquetas pendentes, uma já lida e uma de outro inventário.
        for (final codigo in ['887350', '887120', '887351', '990412']) {
          camera.ler(codigo);
          await tester.pump(const Duration(milliseconds: 300));
        }
      },
    );
  });

  testWidgets('sincronização', (tester) async {
    await capturar(
      tester,
      nome: 'sincronizacao',
      trocas: [
        servidorSyncProvider.overrideWith(_ServidorQuieto.new),
        criarDescobertaProvider.overrideWithValue(
          _DescobertaDeDemonstracao.new,
        ),
      ],
      tela: (c) => TelaSincronizacao(inventarioId: _geral(c)),
    );
  });

  testWidgets('itens', (tester) async {
    await capturar(
      tester,
      nome: 'itens',
      tela: (c) => TelaItens(inventarioId: _geral(c)),
    );
  });

  testWidgets('filtros', (tester) async {
    await capturar(
      tester,
      nome: 'filtros',
      tela: (c) => TelaItens(inventarioId: _geral(c)),
      depois: (tester, _) async {
        await tester.tap(find.byIcon(Icons.filter_list));
      },
    );
  });

  testWidgets('detalhe', (tester) async {
    await capturar(
      tester,
      nome: 'detalhe',
      tela: (c) => TelaItens(inventarioId: _geral(c)),
      depois: (tester, c) async {
        // O sexto item mudou de sala no levantamento: o detalhe mostra a
        // divergência em laranja.
        final item = c.read(patrimoniosProvider).todos(_geral(c))[5];
        unawaited(
          abrirDetalhePatrimonio(
            tester.element(find.byType(TelaItens)),
            item.id,
          ),
        );
      },
    );
  });

  testWidgets('relatórios', (tester) async {
    await capturar(
      tester,
      nome: 'relatorios',
      tela: (c) => TelaRelatorios(inventarioId: _geral(c)),
    );
  });
}

/// Deixa animações e carregamentos terminarem sem exigir que tudo pare:
/// um indicador girando impediria o `pumpAndSettle`.
Future<void> _assentar(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Etapas em isolate terminam em tempo real, fora do relógio do teste.
Future<void> _esperar(WidgetTester tester, Finder alvo) async {
  for (var i = 0; i < 300 && alvo.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(alvo, findsWidgets);
}

String _geral(ProviderContainer c) => c
    .read(listaInventariosProvider)
    .firstWhere((i) => i.nome.endsWith('Patrimônio Geral'))
    .id;

String _vazio(ProviderContainer c) => c
    .read(listaInventariosProvider)
    .firstWhere((i) => i.nome.endsWith('Almoxarifado'))
    .id;

/// Configuração aplicada e as últimas leituras, como em `capturas_test.dart`.
void _levantamentoEmAndamento(ProviderContainer c) {
  final id = _geral(c);
  const config = ConfiguracaoLevantamento(
    sala: 'Auditório',
    responsavel: 'Elisa Prado',
  );
  c.read(configuracoesProvider.notifier).definir(id, config);

  final repo = c.read(patrimoniosProvider);
  final historico = c.read(historicosProvider.notifier);

  Leitura ler(String codigo) =>
      repo.procurar(inventarioId: id, codigo: codigo, modo: ModoLeitura.tombo);

  // Ordem de leitura: a mais recente fica no topo.
  for (final codigo in ['023348', '023349']) {
    final pendente = ler(codigo);
    final depois = repo.registrarVerificacao(
      patrimonio: pendente.patrimonio!,
      config: config,
      usuarioNome: 'Ana Souza',
    );
    historico.registrar(
      id,
      LeituraRegistrada(leitura: pendente, codigoLido: codigo, depois: depois),
    );
  }
  historico.registrar(
    id,
    LeituraRegistrada(
      leitura: const Leitura(resultado: ResultadoLeitura.naoLocalizado),
      codigoLido: '887401',
    ),
  );
  historico.registrar(
    id,
    LeituraRegistrada(leitura: ler('023101'), codigoLido: '023101'),
  );
  final pendente = ler('023352');
  final depois = repo.registrarVerificacao(
    patrimonio: pendente.patrimonio!,
    config: config,
    usuarioNome: 'Ana Souza',
  );
  historico.registrar(
    id,
    LeituraRegistrada(leitura: pendente, codigoLido: '023352', depois: depois),
  );
}

/// Arquivo entregue pelo seletor falso.
final class _Arquivo extends PlatformFile {
  final String nome;
  final Uint8List bytes;

  _Arquivo(this.nome, this.bytes);

  @override
  String get name => nome;

  @override
  Uri get uri => Uri.parse('file:///demonstracao/$nome');

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

class _Seletor extends FilePickerPlatform {
  final PlatformFile arquivo;

  _Seletor(this.arquivo);

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
  }) async => arquivo;
}

/// Servidor de sincronização que não abre porta: a captura não tem rede.
class _ServidorQuieto extends ServidorSync {
  _ServidorQuieto(Ref ref)
    : super(
        banco: ref.watch(bancoProvider),
        ops: ref.watch(operacoesProvider),
        inventarios: ref.watch(inventariosProvider),
        patrimonios: ref.watch(patrimoniosProvider),
      );

  @override
  Future<int> iniciar() async => 41_234;
}

/// Anúncio que não encosta na rede.
class _AnuncioQuieto extends AnuncioEntrada {
  _AnuncioQuieto(Ref ref)
    : super(
        servidor: _ServidorQuieto(ref),
        banco: ref.watch(bancoProvider),
        usuarioNome: () => 'Ana Souza',
      );

  @override
  Future<void> abrir() async {}

  @override
  void fechar() {}
}

/// Dois colegas na mesma rede, achados sem mDNS nem multicast.
class _DescobertaDeDemonstracao extends Descoberta {
  _DescobertaDeDemonstracao({
    required super.dispositivoId,
    required super.usuarioNome,
    required super.porta,
  }) : super(vias: const {});

  @override
  Future<void> iniciar() async {
    adicionar(
      const Par(
        dispositivoId: 'b71c2e90d4a1',
        usuarioNome: 'Bruno Carvalho',
        host: '192.168.0.23',
        porta: 41234,
        origens: {'mdns'},
      ),
    );
    adicionar(
      const Par(
        dispositivoId: 'c4f09a3b7e52',
        usuarioNome: 'Carla Menezes',
        host: '192.168.0.31',
        porta: 41234,
        origens: {'mdns', 'beacon'},
      ),
    );
  }
}

/// Câmera sem câmera: desenha uma etiqueta de patrimônio no lugar do quadro
/// e entrega os códigos que o teste mandar ler.
class _CameraDeDemonstracao extends MobileScannerPlatform {
  final _codigos = StreamController<BarcodeCapture?>.broadcast();

  void ler(String codigo) => _codigos.add(
    BarcodeCapture(
      barcodes: [Barcode(rawValue: codigo, format: BarcodeFormat.code128)],
    ),
  );

  @override
  Stream<BarcodeCapture?> get barcodesStream => _codigos.stream;

  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();

  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();

  @override
  Widget buildCameraView() => const _QuadroDeCamera();

  @override
  Future<MobileScannerViewAttributes> start(StartOptions startOptions) async =>
      const MobileScannerViewAttributes(
        cameraDirection: CameraFacing.back,
        currentTorchMode: TorchState.off,
        size: Size(1080, 1920),
        numberOfCameras: 2,
      );

  @override
  Future<void> stop() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> toggleTorch() async {}

  @override
  Future<void> updateScanWindow(Rect? window) async {}

  @override
  Future<void> setZoomScale(double zoomScale) async {}

  @override
  Future<void> resetZoomScale() async {}
}

/// Uma mesa de madeira com a plaqueta de patrimônio, no lugar da imagem da
/// câmera.
class _QuadroDeCamera extends StatelessWidget {
  const _QuadroDeCamera();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.1),
          radius: 1.1,
          colors: [Color(0xFF6B5039), Color(0xFF3D2C1E), Color(0xFF1C140D)],
          stops: [0, 0.55, 1],
        ),
      ),
      // A vista é desenhada no tamanho do quadro da câmera (1080 × 1920) e
      // reduzida para caber: por isso a etiqueta é ampliada aqui.
      child: Center(
        child: Transform.rotate(
          angle: -0.035,
          child: Transform.scale(scale: 2.2, child: const _Etiqueta()),
        ),
      ),
    );
  }
}

class _Etiqueta extends StatelessWidget {
  const _Etiqueta();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 228,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE9E7E1), Color(0xFFC9C6BE)],
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x88000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'PATRIMÔNIO',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2B2B2B),
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 34,
            width: double.infinity,
            child: CustomPaint(painter: _Barras('887350')),
          ),
          const SizedBox(height: 3),
          const Text(
            '887350',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 3,
              color: Color(0xFF1F1F1F),
            ),
          ),
        ],
      ),
    );
  }
}

/// Barras com cara de Code 128, derivadas do texto: não precisam ser
/// legíveis, só parecer uma etiqueta de verdade.
class _Barras extends CustomPainter {
  final String texto;

  _Barras(this.texto);

  @override
  void paint(Canvas canvas, Size size) {
    final larguras = <int>[2, 1, 1, 2, 3, 1];
    for (final unidade in texto.codeUnits) {
      for (var b = 0; b < 6; b++) {
        larguras.add(1 + ((unidade >> b) + b) % 3);
      }
    }
    larguras.addAll([2, 3, 3, 1, 1, 1, 2]);
    final total = larguras.fold<int>(0, (a, b) => a + b);
    final modulo = size.width / total;
    final tinta = Paint()..color = const Color(0xFF151515);
    var x = 0.0;
    for (var i = 0; i < larguras.length; i++) {
      final largura = larguras[i] * modulo;
      if (i.isEven) {
        canvas.drawRect(Rect.fromLTWH(x, 0, largura, size.height), tinta);
      }
      x += largura;
    }
  }

  @override
  bool shouldRepaint(_Barras antigo) => antigo.texto != texto;
}

/// A barra de status do iPhone: hora à esquerda da Dynamic Island, sinal,
/// Wi-Fi e bateria à direita. A ilha em si é da moldura, desenhada no site.
class _BarraDeStatus extends StatelessWidget {
  final bool clara;

  const _BarraDeStatus({required this.clara});

  @override
  Widget build(BuildContext context) {
    final cor = clara ? Colors.white : const Color(0xFF14201E);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 59,
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(52, 4, 28, 0),
          child: Row(
            children: [
              Text(
                '10:00',
                style: TextStyle(
                  fontFamily: 'Public Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                  letterSpacing: -0.2,
                  color: cor,
                  height: 1,
                ),
              ),
              const Spacer(),
              Icon(Icons.signal_cellular_alt, size: 19, color: cor),
              const SizedBox(width: 5),
              Icon(Icons.wifi, size: 19, color: cor),
              const SizedBox(width: 6),
              _Bateria(cor: cor),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bateria extends StatelessWidget {
  final Color cor;

  const _Bateria({required this.cor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 25,
          height: 12.5,
          padding: const EdgeInsets.all(1.6),
          decoration: BoxDecoration(
            border: Border.all(color: cor.withValues(alpha: 0.4), width: 1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cor,
              borderRadius: BorderRadius.circular(2.2),
            ),
          ),
        ),
        const SizedBox(width: 1.2),
        Container(
          width: 1.6,
          height: 4.5,
          decoration: BoxDecoration(
            color: cor.withValues(alpha: 0.45),
            borderRadius: const BorderRadius.horizontal(
              right: Radius.circular(1),
            ),
          ),
        ),
      ],
    );
  }
}

/// A barra do gesto de início, no pé da tela.
class _IndicadorDeInicio extends StatelessWidget {
  final bool claro;

  const _IndicadorDeInicio({required this.claro});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 8,
      child: IgnorePointer(
        child: Center(
          child: Container(
            width: 139,
            height: 5,
            decoration: BoxDecoration(
              color: claro ? Colors.white : const Color(0xFF14201E),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );
  }
}
