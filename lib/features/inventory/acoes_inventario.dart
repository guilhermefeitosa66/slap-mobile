import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/formato.dart';
import '../../data/repos/inventarios.dart';

/// Ações de manutenção de um inventário, com as confirmações que pedem.

/// Encerra o inventário, depois de dizer quantos itens ficam como não
/// localizados.
Future<void> encerrarInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final progresso = ref.read(progressoProvider(inventario.id));
  final pendentes = progresso.pendentes;

  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Encerrar o inventário?'),
      content: Text(
        '${pendentes == 0 ? 'Todos os ${formatarInteiro(progresso.total)} itens foram verificados.' : '${formatarInteiro(pendentes)} ${pendentes == 1 ? 'item ainda não foi verificado e ficará' : 'itens ainda não foram verificados e ficarão'} como não localizados nos relatórios.'}\n\n'
        'O levantamento fica bloqueado neste aparelho e nos outros, depois '
        'que sincronizarem. É possível reabrir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(contexto, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(contexto, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Encerrar'),
        ),
      ],
    ),
  );
  if (confirmou != true) return;

  ref.read(inventariosProvider).encerrar(inventario.id);
  ref.read(revisaoProvider.notifier).mudou();
}

/// Reabre um inventário encerrado.
Future<void> reabrirInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Reabrir o inventário?'),
      content: const Text(
        'O levantamento volta a ser permitido neste aparelho e nos outros, '
        'depois que sincronizarem. A reabertura fica registrada no histórico, '
        'como o encerramento.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(contexto, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(contexto, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Reabrir'),
        ),
      ],
    ),
  );
  if (confirmou != true) return;

  ref.read(inventariosProvider).reabrir(inventario.id);
  ref.read(revisaoProvider.notifier).mudou();
}
