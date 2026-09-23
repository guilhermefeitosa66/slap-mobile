import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../domain/divergencia.dart';
import '../sync/compartilhar_inventario.dart';

/// Visão geral de um inventário: onde ele está e o que fazer em seguida.
class TelaDashboard extends ConsumerWidget {
  final String inventarioId;

  const TelaDashboard({super.key, required this.inventarioId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(inventarioProvider(inventarioId));
    if (inv == null) {
      return const Scaffold(
        body: Center(child: Text('Inventário não encontrado.')),
      );
    }

    final progresso = ref.watch(progressoProvider(inventarioId));
    final conflitos = ref.watch(conflitosPendentesProvider(inventarioId));
    final vazio = progresso.total == 0 && progresso.ignorados == 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.nome, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Compartilhar inventário',
            icon: const Icon(Icons.qr_code_2),
            onPressed: () => mostrarQrDoInventario(context, inv),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.read(revisaoProvider.notifier).mudou(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            if (vazio)
              _CartaoImportar(inventarioId: inventarioId)
            else ...[
              _CartaoProgresso(progresso: progresso),
              const SizedBox(height: 8),
              _Grupos(inventarioId: inventarioId, progresso: progresso),
              if (conflitos > 0) ...[
                const SizedBox(height: 8),
                _AvisoConflitos(
                  inventarioId: inventarioId,
                  quantidade: conflitos,
                ),
              ],
              const SizedBox(height: 16),
              _Acoes(inventarioId: inventarioId),
            ],
          ],
        ),
      ),
      floatingActionButton: vazio
          ? null
          : FloatingActionButton.extended(
              onPressed: () =>
                  context.push('/inventario/$inventarioId/levantamento'),
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Levantar'),
            ),
    );
  }
}

class _CartaoProgresso extends StatelessWidget {
  final ProgressoInventario progresso;

  const _CartaoProgresso({required this.progresso});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  // Percentual fracionário, ao contrário da divisão inteira do
                  // SLAP, que mostra 99% durante todo o último 1% do trabalho.
                  progresso.percentual.toStringAsFixed(1),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text('%', style: TextStyle(fontSize: 20)),
                const Spacer(),
                if (progresso.concluido)
                  const Chip(
                    avatar: Icon(Icons.check, size: 18),
                    label: Text('Concluído'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: progresso.total == 0 ? 0 : progresso.percentual / 100,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 12),
            Text(
              '${progresso.verificados} verificados · '
              '${progresso.pendentes} pendentes · '
              '${progresso.total} no total',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (progresso.ignorados > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${progresso.ignorados} fora do inventário por elemento de despesa',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Os três grupos do resultado final.
class _Grupos extends StatelessWidget {
  final String inventarioId;
  final ProgressoInventario progresso;

  const _Grupos({required this.inventarioId, required this.progresso});

  @override
  Widget build(BuildContext context) {
    final grupos = [
      (Classificacao.ok, progresso.ok, 'Sem alteração no SUAP'),
      (
        Classificacao.divergente,
        progresso.divergentes,
        'Precisam de atualização',
      ),
      (
        Classificacao.naoLocalizado,
        progresso.naoLocalizados,
        'Não encontrados',
      ),
    ];

    return Column(
      children: [
        for (final (classificacao, quantidade, descricao) in grupos)
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: CoresResultado.de(
                  classificacao,
                ).withValues(alpha: 0.15),
                child: Icon(
                  CoresResultado.icone(classificacao),
                  color: CoresResultado.de(classificacao),
                ),
              ),
              title: Text(classificacao.rotulo),
              subtitle: Text(descricao),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$quantidade',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              onTap: () => context.push(
                '/inventario/$inventarioId/itens?grupo=${classificacao.name}',
              ),
            ),
          ),
      ],
    );
  }
}

class _AvisoConflitos extends StatelessWidget {
  final String inventarioId;
  final int quantidade;

  const _AvisoConflitos({required this.inventarioId, required this.quantidade});

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    return Card(
      color: cores.errorContainer,
      child: ListTile(
        leading: Icon(
          Icons.warning_amber_rounded,
          color: cores.onErrorContainer,
        ),
        title: Text(
          '$quantidade ${quantidade == 1 ? 'conflito' : 'conflitos'}',
          style: TextStyle(color: cores.onErrorContainer),
        ),
        subtitle: Text(
          'Duas pessoas alteraram o mesmo campo sem saber uma da outra.',
          style: TextStyle(color: cores.onErrorContainer),
        ),
        trailing: Icon(Icons.chevron_right, color: cores.onErrorContainer),
        onTap: () => context.push('/inventario/$inventarioId/conflitos'),
      ),
    );
  }
}

class _Acoes extends StatelessWidget {
  final String inventarioId;

  const _Acoes({required this.inventarioId});

  @override
  Widget build(BuildContext context) {
    final acoes = [
      (
        Icons.sync,
        'Sincronizar',
        'Trocar dados com outros aparelhos',
        'sincronizar',
      ),
      (
        Icons.description_outlined,
        'Relatórios',
        'Exportar em XLSX ou CSV',
        'relatorios',
      ),
      (
        Icons.list_alt,
        'Todos os itens',
        'Buscar e conferir patrimônios',
        'itens',
      ),
      (
        Icons.upload_file,
        'Importar planilha',
        'Acrescentar itens do SUAP',
        'importar',
      ),
    ];

    return Column(
      children: [
        for (final (icone, titulo, descricao, rota) in acoes)
          Card(
            child: ListTile(
              leading: Icon(icone),
              title: Text(titulo),
              subtitle: Text(descricao),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/inventario/$inventarioId/$rota'),
            ),
          ),
      ],
    );
  }
}

class _CartaoImportar extends StatelessWidget {
  final String inventarioId;

  const _CartaoImportar({required this.inventarioId});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.upload_file,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Importe a planilha do SUAP',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text(
              'Aceita XLSX e CSV. As colunas são reconhecidas pelo nome, '
              'em qualquer ordem.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () =>
                  context.push('/inventario/$inventarioId/importar'),
              icon: const Icon(Icons.folder_open),
              label: const Text('Escolher arquivo'),
            ),
          ],
        ),
      ),
    );
  }
}
