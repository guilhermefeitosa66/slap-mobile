import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../data/repos/conflitos.dart';

/// Conflitos: alterações concorrentes que ninguém decidiu.
///
/// A lista contém apenas concorrência de verdade — casos em que duas pessoas
/// alteraram o mesmo campo sem que nenhuma conhecesse a escrita da outra. Uma
/// alteração feita depois de sincronizar é atualização comum e não aparece
/// aqui; sem essa distinção, todo encontro entre aparelhos encheria a tela.
class TelaConflitos extends ConsumerWidget {
  final String inventarioId;

  const TelaConflitos({super.key, required this.inventarioId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(revisaoProvider);
    final conflitos = ref.read(conflitosProvider).listar(inventarioId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conflitos'),
        actions: [
          if (conflitos.isNotEmpty)
            TextButton(
              onPressed: () => _aceitarTodos(context, ref),
              child: const Text('Aceitar todos'),
            ),
        ],
      ),
      body: conflitos.isEmpty
          ? const _SemConflitos()
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                  child: Text(
                    'O valor em destaque já está valendo em todos os aparelhos. '
                    'Confira se foi a escolha certa.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final c in conflitos)
                  _CartaoConflito(
                    conflito: c,
                    aoResolver: (valor) => _resolver(context, ref, c, valor),
                  ),
              ],
            ),
    );
  }

  void _resolver(
    BuildContext context,
    WidgetRef ref,
    Conflito conflito,
    String? valor,
  ) {
    final identidade = ref.read(identidadeProvider);
    ref
        .read(conflitosProvider)
        .resolver(
          conflito: conflito,
          valorEscolhido: valor,
          usuarioNome: identidade.nome,
          usuarioMatricula: identidade.matricula,
        );
    ref.read(revisaoProvider.notifier).mudou();
  }

  Future<void> _aceitarTodos(BuildContext context, WidgetRef ref) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Aceitar todos?'),
        content: const Text(
          'Os valores que já estão valendo serão mantidos e os conflitos '
          'saem da lista. Nenhum dado é alterado.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aceitar'),
          ),
        ],
      ),
    );

    if (confirmou != true) return;
    ref.read(conflitosProvider).aceitarTodos(inventarioId);
    ref.read(revisaoProvider.notifier).mudou();
  }
}

class _CartaoConflito extends StatelessWidget {
  final Conflito conflito;
  final ValueChanged<String?> aoResolver;

  const _CartaoConflito({required this.conflito, required this.aoResolver});

  @override
  Widget build(BuildContext context) {
    final formato = DateFormat('dd/MM HH:mm');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              conflito.descricao ?? 'Tombo ${conflito.tombo}',
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              'Tombo ${conflito.tombo} · ${conflito.rotuloCampo}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _Opcao(
              valor: conflito.valorMantido,
              autor: conflito.vencedora.usuarioNome,
              quando: formato.format(conflito.vencedora.hlc.momento),
              vigente: true,
              aoEscolher: () => aoResolver(conflito.vencedora.valor),
            ),
            const SizedBox(height: 8),
            _Opcao(
              valor: conflito.valorPreterido,
              autor: conflito.perdedora.usuarioNome,
              quando: formato.format(conflito.perdedora.hlc.momento),
              vigente: false,
              aoEscolher: () => aoResolver(conflito.perdedora.valor),
            ),
          ],
        ),
      ),
    );
  }
}

class _Opcao extends StatelessWidget {
  final String valor;
  final String? autor;
  final String quando;

  /// O valor que o sistema já escolheu e que está valendo em todas as
  /// réplicas.
  final bool vigente;

  final VoidCallback aoEscolher;

  const _Opcao({
    required this.valor,
    required this.autor,
    required this.quando,
    required this.vigente,
    required this.aoEscolher,
  });

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    return InkWell(
      onTap: aoEscolher,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: vigente
              ? cores.primaryContainer
              : cores.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: vigente ? cores.primary : cores.outlineVariant,
            width: vigente ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    valor,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${autor ?? "desconhecido"} · $quando',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (vigente)
              Chip(
                label: const Text('Valendo'),
                labelStyle: TextStyle(fontSize: 11, color: cores.onPrimary),
                backgroundColor: cores.primary,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              )
            else
              const Text('Usar este'),
          ],
        ),
      ),
    );
  }
}

class _SemConflitos extends StatelessWidget {
  const _SemConflitos();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum conflito',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ninguém alterou o mesmo campo do mesmo patrimônio sem saber '
              'do outro.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
