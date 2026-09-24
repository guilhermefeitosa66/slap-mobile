import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/repos/inventarios.dart';
import 'protocolo.dart';

/// Mostra o QR code que dá entrada no inventário.
///
/// O código carrega a chave de sincronização. Quem o lê passa a poder baixar a
/// réplica e sincronizar — é o equivalente a ser incluído na comissão, sem
/// cadastro nem servidor.
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
              'Os dois aparelhos precisam estar na mesma rede local.',
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
