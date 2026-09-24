import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/repos/inventarios.dart';
import 'anuncio.dart';
import 'protocolo.dart';

/// Os dois jeitos de convidar alguém para um inventário.
enum OpcaoCompartilhar {
  /// QR code na tela, para quem está ao lado ler com a câmera.
  qr,

  /// Link pela folha de compartilhamento do sistema, para quem está longe.
  link,
}

/// Rótulos das duas opções, os mesmos na folha e nos testes.
const rotuloQr = 'Mostrar o QR code';
const rotuloLink = 'Enviar um link';

/// A condição que explica quase toda falha de entrada em campo.
const avisoRedeCompartilhar =
    'Os dois aparelhos precisam estar na mesma rede Wi-Fi, e este aplicativo '
    'precisa ficar aberto até o outro entrar.';

/// Abre a folha de compartilhamento do inventário.
///
/// Enquanto ela está aberta, este aparelho anuncia-se na rede e atende
/// pedidos: sem isso, quem recebeu o link não teria a quem pedir entrada.
Future<void> compartilharInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final opcao = await showModalBottomSheet<OpcaoCompartilhar>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _FolhaCompartilhar(inventario: inventario),
  );
  if (opcao == null || !context.mounted) return;

  switch (opcao) {
    case OpcaoCompartilhar.qr:
      await mostrarQrDoInventario(context, inventario);
    case OpcaoCompartilhar.link:
      await enviarLinkDoInventario(ref, inventario);
  }
}

/// Manda o link pela folha de compartilhamento do sistema.
Future<void> enviarLinkDoInventario(
  WidgetRef ref,
  Inventario inventario,
) async {
  final convite = ConviteLink.de(
    inventario,
    dispositivo: ref.read(bancoProvider).dispositivoId,
  );
  await SharePlus.instance.share(
    ShareParams(subject: convite.titulo, text: textoDoConvite(convite)),
  );
}

/// A mensagem que acompanha o link.
///
/// Diz o que o link é e o que vai acontecer — inclusive que quem mandou ainda
/// precisa aceitar —, porque o link chega solto numa conversa, longe de
/// qualquer tela do aplicativo.
String textoDoConvite(ConviteLink convite) =>
    'Entre no inventário ${convite.titulo} do SLAP Mobile:\n\n'
    '${convite.codificar()}\n\n'
    'Abra o link com os dois celulares na mesma rede Wi-Fi. Eu preciso '
    'aceitar o seu pedido aqui no meu aparelho para você entrar.';

/// Folha com as duas opções. Devolve a escolhida, ou `null`.
class _FolhaCompartilhar extends ConsumerStatefulWidget {
  final Inventario inventario;

  const _FolhaCompartilhar({required this.inventario});

  @override
  ConsumerState<_FolhaCompartilhar> createState() => _FolhaCompartilharState();
}

class _FolhaCompartilharState extends ConsumerState<_FolhaCompartilhar> {
  /// Guardado aqui, e não lido de novo no `dispose`: o `ref` depende do
  /// `BuildContext`, que já não vale quando a folha está sendo desmontada.
  late final AnuncioEntrada _anuncio;

  @override
  void initState() {
    super.initState();
    // O anúncio sobe junto com a folha e continua por alguns minutos depois
    // dela: o pedido de entrada costuma chegar quando o celular já voltou
    // para o bolso.
    _anuncio = ref.read(anuncioEntradaProvider)..abrir();
  }

  @override
  void dispose() {
    _anuncio.fechar();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    // Rolável: com a fonte do sistema ampliada, ou em tela baixa, as duas
    // opções e o aviso não cabem na altura que a folha recebe.
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
              child: Text(
                'Compartilhar inventário',
                style: tema.textTheme.titleLarge,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 2, 24, 12),
              child: Text(
                widget.inventario.titulo,
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tema.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text(rotuloQr),
              subtitle: const Text(
                'Para quem está ao seu lado ler com a câmera.',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 6,
              ),
              onTap: () => Navigator.pop(context, OpcaoCompartilhar.qr),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text(rotuloLink),
              // O que o link não leva é o que importa dizer: é o que torna
              // seguro mandá-lo por mensagem.
              subtitle: const Text(
                'Mande por mensagem. O link não contém a chave do inventário: '
                'você ainda aceita ou recusa o pedido aqui.',
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 6,
              ),
              onTap: () => Navigator.pop(context, OpcaoCompartilhar.link),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.wifi_tethering,
                    size: 18,
                    color: tema.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      avisoRedeCompartilhar,
                      style: tema.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mostra o QR code que dá entrada no inventário.
///
/// O código carrega a chave de sincronização — diferente do link, que não a
/// carrega. Quem o lê já poderia baixar a réplica, mas o pedido de entrada
/// passa pela origem do mesmo jeito: um só fluxo de aceite, dois jeitos de
/// chegar a ele.
Future<void> mostrarQrDoInventario(
  BuildContext context,
  Inventario inventario,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DialogoQr(inventario: inventario),
  );
}

class _DialogoQr extends StatelessWidget {
  final Inventario inventario;

  const _DialogoQr({required this.inventario});

  @override
  Widget build(BuildContext context) {
    final convite = ConviteInventario.de(inventario).codificar();

    return AlertDialog(
      title: const Text('Compartilhar inventário'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              inventario.titulo,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              // Fundo branco fixo: em tema escuro, um QR sobre fundo escuro
              // não é lido por leitor nenhum.
              color: Colors.white,
              // Largura e altura fixas, e não só `size`: o `AlertDialog` mede
              // o conteúdo por largura intrínseca, e o `QrImageView` usa um
              // `LayoutBuilder`, que não responde a essa medida. Sem o
              // `SizedBox` a exceção interrompe o layout do diálogo inteiro,
              // e só a barreira escurecida aparece.
              child: SizedBox(
                width: 240,
                height: 240,
                child: QrImageView(
                  data: convite,
                  version: QrVersions.auto,
                  size: 240,
                  backgroundColor: Colors.white,
                  // Tolerância alta: o código é lido da tela de um celular
                  // por outro celular, muitas vezes com reflexo e mão trêmula.
                  errorCorrectionLevel: QrErrorCorrectLevel.H,
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No outro aparelho, toque em Novo → Ler o QR code de outro '
              'aparelho e aponte a câmera para este código.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              avisoRedeCompartilhar,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Este código contém a chave de acesso ao inventário. '
              'Mostre apenas a quem vai participar.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}
