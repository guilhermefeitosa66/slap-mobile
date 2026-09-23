import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
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
        title: const Text('Inventários'),
        actions: [
          IconButton(
            tooltip: 'Meus dados',
            icon: const Icon(Icons.person_outline),
            onPressed: () => context.push('/identidade?inicial=false'),
          ),
        ],
      ),
      body: inventarios.isEmpty
          ? const _Vazio()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
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
          FloatingActionButton.small(
            heroTag: 'entrar',
            tooltip: 'Entrar em um inventário',
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

    if (context.mounted) context.push('/inventario/${inv.id}/importar');
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

    return Card(
      child: InkWell(
        onTap: () => context.push('/inventario/$inventarioId'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      inv.nome,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${inv.ano}',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: progresso.total == 0 ? 0 : progresso.percentual / 100,
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                progresso.total == 0
                    ? 'Sem patrimônios importados'
                    : '${progresso.verificados} de ${progresso.total} '
                          '(${progresso.percentual.toStringAsFixed(1)}%)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (conflitos > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$conflitos ${conflitos == 1 ? 'conflito' : 'conflitos'} '
                      'para conferir',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
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
