import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';

/// Identificação do usuário deste aparelho.
///
/// Não há login nem senha. O aplicativo funciona offline e cada celular é uma
/// réplica independente: exigir autenticação contra um servidor contrariaria a
/// premissa do projeto. O que se precisa saber é a quem atribuir cada
/// verificação nos relatórios e na auditoria.
class TelaIdentidade extends ConsumerStatefulWidget {
  final bool primeiraVez;

  const TelaIdentidade({super.key, this.primeiraVez = true});

  @override
  ConsumerState<TelaIdentidade> createState() => _TelaIdentidadeState();
}

class _TelaIdentidadeState extends ConsumerState<TelaIdentidade> {
  final _formulario = GlobalKey<FormState>();
  late final TextEditingController _nome;
  late final TextEditingController _matricula;

  @override
  void initState() {
    super.initState();
    final identidade = ref.read(identidadeProvider);
    _nome = TextEditingController(text: identidade.nome ?? '');
    _matricula = TextEditingController(text: identidade.matricula ?? '');
  }

  @override
  void dispose() {
    _nome.dispose();
    _matricula.dispose();
    super.dispose();
  }

  void _salvar() {
    if (!_formulario.currentState!.validate()) return;

    ref
        .read(identidadeProvider.notifier)
        .definir(nome: _nome.text, matricula: _matricula.text);

    if (!mounted) return;
    if (widget.primeiraVez) {
      context.go('/');
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final dispositivo = ref.watch(bancoProvider).dispositivoId;

    return Scaffold(
      appBar: widget.primeiraVez
          ? null
          : AppBar(title: const Text('Meus dados')),
      body: Form(
        key: _formulario,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            24,
            widget.primeiraVez ? MediaQuery.paddingOf(context).top + 40 : 8,
            24,
            24,
          ),
          children: [
            if (widget.primeiraVez) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: IconeCodigoBarras(
                    tamanho: 28,
                    cor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Inventário\npatrimonial',
                style: Theme.of(
                  context,
                ).textTheme.headlineLarge?.copyWith(fontSize: 30, height: 1.15),
              ),
              const SizedBox(height: 8),
              Text(
                'Seu nome fica gravado neste aparelho e acompanha cada '
                'patrimônio que você verificar. Não há senha.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
            ],
            TextFormField(
              controller: _nome,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Como você aparece nos relatórios',
              ),
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofocus: widget.primeiraVez,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _matricula,
              decoration: const InputDecoration(
                labelText: 'Matrícula (opcional)',
                hintText: 'Identificador funcional',
              ),
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _salvar(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvar,
              icon: const Icon(Icons.check),
              label: Text(widget.primeiraVez ? 'Começar' : 'Salvar'),
            ),
            const SizedBox(height: 32),
            _Rodape(dispositivo: dispositivo),
          ],
        ),
      ),
    );
  }
}

class _Rodape extends StatelessWidget {
  final String dispositivo;

  const _Rodape({required this.dispositivo});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 8),
        Text('Identificador deste aparelho', style: estilo),
        const SizedBox(height: 4),
        SelectableText(
          dispositivo,
          style: estiloCodigo(
            context,
            tamanho: 12.5,
          ).copyWith(color: estilo?.color, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text(
          'Gerado na primeira execução e usado para identificar este aparelho '
          'durante a sincronização. Não muda se você alterar seu nome.',
          style: estilo,
        ),
      ],
    );
  }
}
