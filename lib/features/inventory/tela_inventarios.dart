import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../sync/entrar_inventario.dart';
import 'acoes_inventario.dart';
import 'aviso_atualizacao.dart';

/// Lista dos inventários que existem neste aparelho.
class TelaInventarios extends ConsumerWidget {
  const TelaInventarios({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventarios = ref.watch(listaInventariosProvider);
    final identidade = ref.watch(identidadeProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Text(
          'Inventários',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        actions: [
          IconButton.outlined(
            tooltip: 'Meus dados e ajustes',
            icon: const Icon(Icons.person_outline),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surfaceContainerLowest,
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => context.push('/ajustes'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          const AvisoAtualizacao(),
          Expanded(
            child: inventarios.isEmpty
                ? _Vazio(
                    aoLerQr: () => entrarEmInventario(context, ref),
                    aoImportar: () => _criar(context, ref),
                  )
                : ListView.builder(
                    // Espaço para o botão flutuante não cobrir o último
                    // cartão.
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: inventarios.length,
                    itemBuilder: (context, i) {
                      final inv = inventarios[i];
                      return _CartaoInventario(inventarioId: inv.id);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _novo(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (identidade.configurada)
              Text(
                '${identidade.nome}'
                '${identidade.matricula == null ? '' : ' · ${identidade.matricula}'}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 2),
            const VersaoInstalada(),
          ],
        ),
      ),
    );
  }

  /// "Novo" pergunta de onde vem o inventário: de outro aparelho, pelo QR
  /// code, ou de uma planilha do SUAP.
  ///
  /// Antes o leitor de QR era um segundo botão flutuante, visível o tempo
  /// todo e sem dizer o que fazia — parecia um botão de câmera.
  Future<void> _novo(BuildContext context, WidgetRef ref) async {
    final origem = await showModalBottomSheet<OrigemInventario>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _FolhaNovo(),
    );
    if (origem == null || !context.mounted) return;

    switch (origem) {
      case OrigemInventario.lerQr:
        await entrarEmInventario(context, ref);
      case OrigemInventario.importar:
        await _criar(context, ref);
    }
  }

  Future<void> _criar(BuildContext context, WidgetRef ref) async {
    final dados = await showDialog<({String nome, int ano})>(
      context: context,
      builder: (_) => const DialogoInventario(
        titulo: 'Novo inventário',
        rotuloConfirmar: 'Criar',
      ),
    );
    if (dados == null || !context.mounted) return;

    final inv = ref
        .read(inventariosProvider)
        .criar(nome: dados.nome, ano: dados.ano);
    ref.read(revisaoProvider.notifier).mudou();

    if (context.mounted) await context.push('/inventario/${inv.id}/importar');
  }
}

class _CartaoInventario extends ConsumerWidget {
  final String inventarioId;

  const _CartaoInventario({required this.inventarioId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(inventarioProvider(inventarioId));
    if (inv == null) return const SizedBox.shrink();

    final progresso = ref.watch(progressoProvider(inventarioId));
    final conflitos = ref.watch(conflitosPendentesProvider(inventarioId));
    final tema = Theme.of(context);
    final erro = CoresResultado.of(context).naoLocalizado.texto;

    final situacao = progresso.total == 0
        ? 'Sem patrimônios importados'
        : '${formatarInteiro(progresso.verificados)} de '
              '${formatarInteiro(progresso.total)} · '
              '${progresso.concluido ? 'concluído' : '${formatarPercentual(progresso.percentual)}%'}'
              '${inv.encerrado ? ' · encerrado' : ''}';

    return Card(
      child: InkWell(
        onTap: () => context.push('/inventario/$inventarioId'),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(inv.nome, style: tema.textTheme.titleMedium),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${inv.ano}',
                    style: tema.textTheme.titleMedium?.copyWith(
                      fontSize: 15,
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              BarraProgresso(
                valor: progresso.total == 0 ? 0 : progresso.percentual / 100,
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  if (inv.encerrado) ...[
                    Icon(
                      Icons.lock_outline,
                      size: 15,
                      color: tema.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(situacao, style: tema.textTheme.bodySmall),
                  ),
                ],
              ),
              if (conflitos > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: erro),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        '$conflitos ${conflitos == 1 ? 'conflito' : 'conflitos'} '
                        'para conferir',
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: erro,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// De onde vem um inventário novo.
enum OrigemInventario {
  /// Cópia de um inventário criado em outro aparelho, pela rede local.
  lerQr,

  /// Inventário novo, com a planilha do SUAP.
  importar,
}

/// Rótulos das duas origens, os mesmos na folha e no estado vazio.
const rotuloLerQr = 'Ler o QR code de outro aparelho';
const rotuloImportar = 'Importar de arquivo';

/// Folha aberta por "Novo". Devolve a origem escolhida, ou `null`.
class _FolhaNovo extends StatelessWidget {
  const _FolhaNovo();

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Text('Novo inventário', style: tema.textTheme.titleLarge),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text(rotuloLerQr),
            // A condição da rede vai aqui, antes de abrir a câmera: é a
            // causa mais comum de "não encontrou ninguém".
            subtitle: const Text(
              'Recebe uma cópia pela rede local. Os dois aparelhos precisam '
              'estar na mesma rede Wi-Fi.',
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 6,
            ),
            onTap: () => Navigator.pop(context, OrigemInventario.lerQr),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text(rotuloImportar),
            subtitle: const Text(
              'Cria o inventário com nome e ano e importa a planilha do '
              'SUAP ou do inventario.ifpi.edu.br.',
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 6,
            ),
            onTap: () => Navigator.pop(context, OrigemInventario.importar),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _Vazio extends StatelessWidget {
  final VoidCallback aoLerQr;
  final VoidCallback aoImportar;

  const _Vazio({required this.aoLerQr, required this.aoImportar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 112),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum inventário neste aparelho',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Receba uma cópia de quem já criou o inventário, ou crie um e '
              'importe a planilha do SUAP.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // As mesmas duas opções da folha do "Novo", à mão: quem abre o
            // aplicativo pela primeira vez não tem por que procurar um botão.
            FilledButton.icon(
              onPressed: aoLerQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text(rotuloLerQr),
            ),
            const SizedBox(height: 8),
            Text(
              'Os dois aparelhos precisam estar na mesma rede Wi-Fi.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: aoImportar,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text(rotuloImportar),
            ),
          ],
        ),
      ),
    );
  }
}
