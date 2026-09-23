import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import 'cliente.dart';
import 'descoberta.dart';
import 'protocolo.dart';

/// Entra num inventário criado em outro aparelho.
///
/// Lê o QR code, procura na rede local quem tem aquele inventário e baixa a
/// réplica inicial. A câmera já é permissão do projeto, então o pareamento não
/// acrescenta nenhuma exigência ao usuário.
Future<void> entrarEmInventario(BuildContext context, WidgetRef ref) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const _TelaEntrar()));
}

class _TelaEntrar extends ConsumerStatefulWidget {
  const _TelaEntrar();

  @override
  ConsumerState<_TelaEntrar> createState() => _TelaEntrarState();
}

class _TelaEntrarState extends ConsumerState<_TelaEntrar> {
  final _controlador = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );

  ConviteInventario? _convite;
  String _situacao = '';
  String? _erro;
  bool _ocupado = false;

  @override
  void dispose() {
    _controlador.dispose();
    super.dispose();
  }

  Future<void> _aoLer(BarcodeCapture captura) async {
    if (_ocupado || _convite != null) return;

    for (final codigo in captura.barcodes) {
      final texto = codigo.rawValue;
      if (texto == null) continue;

      final convite = ConviteInventario.decodificar(texto);
      // QR de outro aplicativo: ignorar em silêncio, porque apontar a câmera
      // para qualquer código é o caso comum.
      if (convite == null) continue;

      setState(() {
        _convite = convite;
        _ocupado = true;
      });
      await _baixar(convite);
      return;
    }
  }

  Future<void> _baixar(ConviteInventario convite) async {
    final inventarios = ref.read(inventariosProvider);

    if (inventarios.porId(convite.inventarioId) != null) {
      setState(() {
        _erro = 'Este inventário já está neste aparelho.';
        _ocupado = false;
      });
      return;
    }

    setState(() => _situacao = 'Procurando aparelhos na rede local…');

    final servidor = ref.read(servidorSyncProvider);
    final porta = await servidor.iniciar();

    final descoberta = Descoberta(
      dispositivoId: ref.read(bancoProvider).dispositivoId,
      usuarioNome: () => ref.read(identidadeProvider).nome,
      porta: porta,
    );

    try {
      await descoberta.iniciar();

      // Descoberta na rede não é instantânea: o anúncio precisa circular e ser
      // respondido. Tentar uma vez só falharia quase sempre.
      final encontrados = await _aguardarPares(descoberta);
      if (encontrados.isEmpty) {
        setState(() {
          _erro =
              'Nenhum aparelho encontrado na rede.\n\n'
              'Verifique se os dois estão no mesmo Wi-Fi. Algumas redes '
              'institucionais isolam os aparelhos entre si — nesse caso, use '
              'um ponto de acesso compartilhado por um dos celulares.';
          _ocupado = false;
        });
        return;
      }

      setState(() => _situacao = 'Baixando o inventário…');

      final cliente = ref.read(clienteSyncProvider);
      Object? ultimaFalha;

      // Vários aparelhos podem ter o inventário; basta um responder. Os que
      // não participam recusam a chave, e isso não é erro.
      for (final par in encontrados) {
        try {
          final pacote = await cliente.baixarPacote(
            par: par,
            inventarioId: convite.inventarioId,
            chaveSync: convite.chaveSync,
          );

          inventarios.registrarRecebido(pacote.inventario);
          ref.read(patrimoniosProvider).inserirRecebidos(pacote.patrimonios);
          ref
              .read(operacoesProvider)
              .reaplicarEdsExcluidos(pacote.inventario.id);

          // O pacote traz só os dados do SUAP. O levantamento feito até aqui
          // vem pelo log, e já com o par à mão: quem começa a ler precisa ver
          // o que os outros já leram — e, se este aparelho já participou
          // antes, recuperar o próprio trabalho antes de continuar.
          if (mounted) setState(() => _situacao = 'Recebendo o levantamento…');
          try {
            await cliente.sincronizar(
              par: par,
              inventarioId: pacote.inventario.id,
              chaveSync: convite.chaveSync,
            );
          } on FalhaSync {
            // O inventário já está aqui; a tela de sincronização resolve.
          }
          ref.read(revisaoProvider.notifier).mudou();

          if (!mounted) return;
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${pacote.inventario.nome}: '
                '${pacote.patrimonios.length} patrimônios recebidos de '
                '${par.rotulo}',
              ),
            ),
          );
          return;
        } catch (e) {
          ultimaFalha = e;
        }
      }

      setState(() {
        _erro =
            'Nenhum dos ${encontrados.length} aparelhos encontrados tem '
            'este inventário.\n\n$ultimaFalha';
        _ocupado = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Falha ao entrar no inventário: $e';
        _ocupado = false;
      });
    } finally {
      await descoberta.dispose();
    }
  }

  Future<List<Par>> _aguardarPares(Descoberta descoberta) async {
    for (var tentativa = 0; tentativa < 10; tentativa++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (descoberta.pares.isNotEmpty) return descoberta.pares;
      if (mounted) {
        setState(
          () => _situacao =
              'Procurando aparelhos na rede local… (${tentativa + 1}/10)',
        );
      }
    }
    return descoberta.pares;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar em um inventário')),
      body: _convite == null ? _leitor() : _andamento(),
    );
  }

  Widget _leitor() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _controlador,
            onDetect: _aoLer,
            errorBuilder: (context, erro) => ColoredBox(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    erro.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Autorize o acesso à câmera para ler o QR code.'
                        : 'Não foi possível abrir a câmera.',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aponte para o QR code exibido no aparelho que criou o inventário.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _andamento() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _convite!.nome,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            Text('${_convite!.ano}'),
            const SizedBox(height: 32),
            if (_erro == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(_situacao, textAlign: TextAlign.center),
            ] else ...[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => setState(() {
                  _erro = null;
                  _convite = null;
                }),
                child: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
