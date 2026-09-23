import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../sync/entrar_inventario.dart';

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
            tooltip: 'Meus dados',
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
            onPressed: () => context.push('/identidade?inicial=false'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: inventarios.isEmpty
          ? const _Vazio()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
              itemCount: inventarios.length,
              itemBuilder: (context, i) {
                final inv = inventarios[i];
                return _CartaoInventario(inventarioId: inv.id);
              },
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'entrar',
            tooltip: 'Entrar em um inventário lendo o QR code',
            elevation: 1,
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerLowest,
            foregroundColor: Theme.of(context).colorScheme.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            onPressed: () => entrarEmInventario(context, ref),
            child: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'novo',
            onPressed: () => _criar(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Novo'),
          ),
        ],
      ),
      bottomNavigationBar: identidade.configurada
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                '${identidade.nome}'
                '${identidade.matricula == null ? '' : ' · ${identidade.matricula}'}',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            )
          : null,
    );
  }

  Future<void> _criar(BuildContext context, WidgetRef ref) async {
    final dados = await showDialog<({String nome, int ano})>(
      context: context,
      builder: (_) => const _DialogoNovoInventario(),
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
              '${progresso.concluido ? 'concluído' : '${formatarPercentual(progresso.percentual)}%'}';

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
              Text(situacao, style: tema.textTheme.bodySmall),
              if (conflitos > 0) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: erro),
                    const SizedBox(width: 7),
                    Text(
                      '$conflitos ${conflitos == 1 ? 'conflito' : 'conflitos'} '
                      'para conferir',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: erro,
                        fontWeight: FontWeight.w500,
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

class _Vazio extends StatelessWidget {
  const _Vazio();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              'Crie um inventário e importe a planilha do SUAP, ou leia o '
              'QR code de quem já criou para receber uma cópia.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogoNovoInventario extends StatefulWidget {
  const _DialogoNovoInventario();

  @override
  State<_DialogoNovoInventario> createState() => _DialogoNovoInventarioState();
}

class _DialogoNovoInventarioState extends State<_DialogoNovoInventario> {
  final _formulario = GlobalKey<FormState>();
  final _nome = TextEditingController();
  late final _ano = TextEditingController(text: '${DateTime.now().year}');

  @override
  void dispose() {
    _nome.dispose();
    _ano.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo inventário'),
      content: Form(
        key: _formulario,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nome,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Campus Picos — Biblioteca',
                // Nome + ano não são chave única: a mesma unidade pode ter
                // vários processos no mesmo ano.
                helperText: 'Texto livre. Pode repetir no mesmo ano.',
                helperMaxLines: 2,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ano,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ano'),
              validator: (v) {
                final ano = int.tryParse(v ?? '');
                if (ano == null || ano < 1990 || ano > 2100) {
                  return 'Ano inválido';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formulario.currentState!.validate()) return;
            Navigator.pop(context, (
              nome: _nome.text.trim(),
              ano: int.parse(_ano.text),
            ));
          },
          child: const Text('Criar'),
        ),
      ],
    );
  }
}
