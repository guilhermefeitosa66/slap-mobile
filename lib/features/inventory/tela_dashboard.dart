import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/componentes.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
          children: [
            if (vazio)
              _CartaoImportar(inventarioId: inventarioId)
            else ...[
              _CartaoProgresso(progresso: progresso),
              const SizedBox(height: 8),
              _Grupos(inventarioId: inventarioId, progresso: progresso),
              if (conflitos > 0) ...[
                const SizedBox(height: 12),
                _AvisoConflitos(
                  inventarioId: inventarioId,
                  quantidade: conflitos,
                ),
              ],
              const SizedBox(height: 12),
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
              icon: const IconeCodigoBarras(),
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
    final tema = Theme.of(context);

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
                  formatarPercentual(progresso.percentual),
                  style: tema.textTheme.displaySmall,
                ),
                const SizedBox(width: 6),
                Text(
                  '%',
                  style: tema.textTheme.titleLarge?.copyWith(
                    color: tema.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (progresso.concluido)
                  Chip(
                    avatar: Icon(
                      Icons.check,
                      size: 18,
                      color: CoresResultado.of(context).registrado.texto,
                    ),
                    label: const Text('Concluído'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            BarraProgresso(
              valor: progresso.total == 0 ? 0 : progresso.percentual / 100,
              espessura: 10,
            ),
            const SizedBox(height: 12),
            Text(
              '${formatarInteiro(progresso.verificados)} verificados · '
              '${formatarInteiro(progresso.pendentes)} pendentes · '
              '${formatarInteiro(progresso.total)} no total',
              style: tema.textTheme.bodyMedium,
            ),
            if (progresso.ignorados > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${formatarInteiro(progresso.ignorados)} fora do inventário '
                'por elemento de despesa',
                style: tema.textTheme.bodySmall,
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
    final cores = CoresResultado.of(context);
    final tema = Theme.of(context);

    final grupos = [
      (Classificacao.ok, 'Itens OK', progresso.ok, 'Sem alteração no SUAP'),
      (
        Classificacao.divergente,
        'Divergentes',
        progresso.divergentes,
        'Precisam de atualização',
      ),
      (
        Classificacao.naoLocalizado,
        'Não localizados',
        progresso.naoLocalizados,
        'Ainda não encontrados',
      ),
    ];

    return CartaoAgrupado(
      linhas: [
        for (final (classificacao, titulo, quantidade, descricao) in grupos)
          ListTile(
            leading: IconeEmTom(
              icone: CoresResultado.icone(classificacao),
              tom: cores.de(classificacao),
            ),
            title: Text(titulo, style: tema.textTheme.titleSmall),
            subtitle: Text(descricao),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatarInteiro(quantidade),
                  style: tema.textTheme.titleLarge?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 4),
                const SetaNavegacao(),
              ],
            ),
            onTap: () => context.push(
              '/inventario/$inventarioId/itens?grupo=${classificacao.name}',
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
    final tom = CoresResultado.of(context).naoLocalizado;
    final tema = Theme.of(context);

    return Material(
      color: tom.fundo,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/inventario/$inventarioId/conflitos'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: tom.texto),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$quantidade ${quantidade == 1 ? 'conflito' : 'conflitos'}',
                      style: tema.textTheme.titleSmall?.copyWith(
                        color: tom.texto,
                      ),
                    ),
                    Text(
                      'Duas pessoas alteraram o mesmo campo sem saber uma '
                      'da outra.',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tom.texto,
                      ),
                    ),
                  ],
                ),
              ),
              SetaNavegacao(cor: tom.texto),
            ],
          ),
        ),
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

    return CartaoAgrupado(
      linhas: [
        for (final (icone, titulo, descricao, rota) in acoes)
          ListTile(
            leading: Icon(icone),
            title: Text(titulo),
            subtitle: Text(descricao),
            trailing: const SetaNavegacao(),
            onTap: () => context.push('/inventario/$inventarioId/$rota'),
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
