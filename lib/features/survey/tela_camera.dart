import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../core/codigo.dart';
import '../../core/sons.dart';
import '../../data/repos/patrimonios.dart';
import 'estado_levantamento.dart';

/// Leitura contínua pela câmera.
///
/// A câmera **não fecha entre um patrimônio e outro**. O usuário anda pela
/// sala apontando para as etiquetas, e cada código reconhecido é processado
/// na hora, com o retorno sonoro de sempre.
///
/// O processamento é imediato, e não adiado para um botão "OK" ao final: é o
/// que permite avisar na hora que um código não foi localizado, enquanto a
/// pessoa ainda está diante do bem e pode conferir a etiqueta. Uma fila
/// processada só no fim obrigaria a refazer o caminho.
class TelaCamera extends ConsumerStatefulWidget {
  final String inventarioId;

  const TelaCamera({super.key, required this.inventarioId});

  @override
  ConsumerState<TelaCamera> createState() => _TelaCameraState();
}

class _TelaCameraState extends ConsumerState<TelaCamera> {
  late final MobileScannerController _controlador;

  /// Códigos já processados nesta sessão de câmera.
  ///
  /// A câmera reconhece o mesmo código dezenas de vezes por segundo enquanto
  /// ele estiver no quadro. Sem isto, um único patrimônio geraria uma saraivada
  /// de bipes de "já verificado".
  final _processados = <String>{};

  final _lidos = <LeituraRegistrada>[];
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _controlador = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 250,
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.itf,
        BarcodeFormat.codabar,
        BarcodeFormat.qrCode,
      ],
    );
  }

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _aoDetectar(BarcodeCapture captura) async {
    if (_ocupado) return;

    final config = ref.read(configuracaoProvider(widget.inventarioId));
    if (config == null) return;

    for (final codigo in captura.barcodes) {
      final texto = codigo.rawValue;
      if (texto == null || texto.trim().isEmpty) continue;

      final chave = chaveBusca(texto);
      if (chave.isEmpty || !_processados.add(chave)) continue;

      _ocupado = true;
      await _processar(texto, config);
      _ocupado = false;
    }
  }

  Future<void> _processar(String texto, ConfiguracaoLevantamento config) async {
    final repo = ref.read(patrimoniosProvider);
    final modo = ref.read(modoLeituraProvider);

    final leitura = repo.procurar(
      inventarioId: widget.inventarioId,
      codigo: texto,
      modo: modo,
    );

    LeituraRegistrada registro;

    switch (leitura.resultado) {
      case ResultadoLeitura.naoLocalizado:
        await ref.read(sonsProvider).tocar(Som.naoLocalizado);
        registro = LeituraRegistrada(leitura: leitura, codigoLido: texto);

      case ResultadoLeitura.jaVerificado:
        // Pela câmera não se pede confirmação: interromper o fluxo com um
        // diálogo derrubaria o ritmo. O item aparece marcado na lista, e a
        // regravação, se necessária, é feita pelo campo de digitação.
        await ref.read(sonsProvider).tocar(Som.jaVerificado);
        registro = LeituraRegistrada(leitura: leitura, codigoLido: texto);

      case ResultadoLeitura.sucesso:
        final identidade = ref.read(identidadeProvider);
        final depois = repo.registrarVerificacao(
          patrimonio: leitura.patrimonio!,
          config: config,
          usuarioNome: identidade.nome,
          usuarioMatricula: identidade.matricula,
        );
        ref.read(revisaoProvider.notifier).mudou();
        await ref.read(sonsProvider).tocar(Som.sucesso);
        registro = LeituraRegistrada(
          leitura: leitura,
          codigoLido: texto,
          depois: depois,
        );
    }

    ref
        .read(historicosProvider.notifier)
        .registrar(widget.inventarioId, registro);
    if (mounted) setState(() => _lidos.insert(0, registro));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(configuracaoProvider(widget.inventarioId));
    final sucessos = _lidos
        .where((l) => l.resultado == ResultadoLeitura.sucesso)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lidos: $sucessos'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controlador.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Trocar câmera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controlador.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (config != null)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '${config.sala} · ${config.conservacao.rotulo} · '
                '${config.situacao.rotulo}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Expanded(
            flex: 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controlador,
                  onDetect: (captura) => _aoDetectar(captura),
                  errorBuilder: (context, erro) => _ErroCamera(erro: erro),
                ),
                const _Mira(),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _lidos.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Aponte para as etiquetas. A câmera continua aberta '
                        'entre um patrimônio e outro.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _lidos.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _LinhaCamera(registro: _lidos[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.check),
          label: Text(
            sucessos == 0 ? 'Concluir' : 'Concluir ($sucessos registrados)',
          ),
        ),
      ),
    );
  }
}

class _LinhaCamera extends StatelessWidget {
  final LeituraRegistrada registro;

  const _LinhaCamera({required this.registro});

  @override
  Widget build(BuildContext context) {
    final (cor, icone) = switch (registro.resultado) {
      ResultadoLeitura.sucesso => (CoresResultado.sucesso, Icons.check_circle),
      ResultadoLeitura.jaVerificado => (
        CoresResultado.alerta,
        Icons.replay_circle_filled,
      ),
      ResultadoLeitura.naoLocalizado => (CoresResultado.erro, Icons.error),
    };

    return ListTile(
      dense: true,
      leading: Icon(icone, color: cor),
      title: Text(
        registro.patrimonio?.descricao ?? 'Código ${registro.codigoLido}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        registro.patrimonio == null
            ? 'Não localizado neste inventário'
            : 'Tombo ${registro.patrimonio!.tombo}',
        style: TextStyle(color: cor),
      ),
    );
  }
}

class _Mira extends StatelessWidget {
  const _Mira();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 260,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white70, width: 3),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

class _ErroCamera extends StatelessWidget {
  final MobileScannerException erro;

  const _ErroCamera({required this.erro});

  @override
  Widget build(BuildContext context) {
    final semPermissao =
        erro.errorCode == MobileScannerErrorCode.permissionDenied;

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              Text(
                semPermissao
                    ? 'O aplicativo precisa da câmera para ler os códigos de '
                          'barras. Autorize o acesso nas configurações do '
                          'aparelho.'
                    : 'Não foi possível abrir a câmera.\n'
                          '${erro.errorDetails?.message ?? ''}',
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'A leitura pelo campo de digitação e por leitor externo '
                'continua funcionando.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
