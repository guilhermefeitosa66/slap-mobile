import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../../data/repos/patrimonios.dart';

/// Elementos de despesa do inventário, já gravados no aparelho.
final resumoEdsProvider = Provider.family<List<ResumoEd>, String>((ref, id) {
  ref.watch(revisaoProvider);
  return ref.watch(patrimoniosProvider).resumoPorEd(id);
});

/// Configurações de um inventário já criado.
///
/// Nasceu de um esquecimento comum: importar a planilha sem desmarcar o
/// material bibliográfico da biblioteca e só notar com a coleta em andamento.
/// Aqui o ED sai do inventário sem perder o que já foi levantado, e sem
/// recomeçar do zero.
class TelaConfiguracoesInventario extends ConsumerWidget {
  final String inventarioId;

  const TelaConfiguracoesInventario({super.key, required this.inventarioId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(inventarioProvider(inventarioId));
    if (inv == null) {
      return const Scaffold(
        body: Center(child: Text('Inventário não encontrado.')),
      );
    }
    final eds = ref.watch(resumoEdsProvider(inventarioId));
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Elementos de despesa', style: tema.textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Desligue o que não entra no inventário — material bibliográfico, '
            'por exemplo. Nada é apagado: os itens saem das contagens, dos '
            'pendentes e dos relatórios, e voltam como estavam se o elemento '
            'for ligado de novo. Vale para todos os aparelhos na próxima '
            'troca de dados.',
          ),
          const SizedBox(height: 12),
          if (inv.encerrado) ...[
            CaixaDeAviso(
              texto: 'Inventário encerrado. Reabra para alterar.',
              icone: Icons.lock_outline,
              tom: CoresResultado.of(context).jaVerificado,
            ),
            const SizedBox(height: 12),
          ],
          if (eds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Nenhum patrimônio importado ainda.'),
            )
          else
            CartaoAgrupado(
              linhas: [
                for (final ed in eds)
                  SwitchListTile(
                    value: !ed.foraDoInventario,
                    onChanged: inv.encerrado
                        ? null
                        : (incluir) => incluir
                              ? _devolver(context, ref, ed)
                              : _tirar(context, ref, ed),
                    title: Text(rotuloEd(ed.ed)),
                    subtitle: Text(_descricao(ed)),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  String _descricao(ResumoEd ed) => [
    '${formatarInteiro(ed.itens)} ${ed.itens == 1 ? 'item' : 'itens'}',
    if (ed.verificados > 0)
      '${formatarInteiro(ed.verificados)} '
          '${ed.verificados == 1 ? 'verificado' : 'verificados'}',
    if (ed.foraDoInventario) 'fora do inventário',
  ].join(' · ');

  Future<void> _tirar(BuildContext context, WidgetRef ref, ResumoEd ed) async {
    final confirmou = await confirmarRemocaoEd(context, ed);
    if (!confirmou || !context.mounted) return;

    // Lidos agora: o "Desfazer" pode ser tocado depois de sair da tela.
    final inventarios = ref.read(inventariosProvider);
    final revisao = ref.read(revisaoProvider.notifier);

    inventarios.alterarEdsExcluidos(inventarioId, excluir: [ed.ed]);
    revisao.mudou();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${rotuloEd(ed.ed)} fora do inventário'),
        // Com ação, o SnackBar ficaria até ser fechado, e seguiria a pessoa
        // pelas outras telas oferecendo um "Desfazer" fora de contexto.
        persist: false,
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () {
            inventarios.alterarEdsExcluidos(inventarioId, incluir: [ed.ed]);
            revisao.mudou();
          },
        ),
      ),
    );
  }

  /// Devolver não perde nada, por isso não pede confirmação.
  void _devolver(BuildContext context, WidgetRef ref, ResumoEd ed) {
    ref
        .read(inventariosProvider)
        .alterarEdsExcluidos(inventarioId, incluir: [ed.ed]);
    ref.read(revisaoProvider.notifier).mudou();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${rotuloEd(ed.ed)} de volta ao inventário')),
    );
  }
}

/// Como o ED aparece para a pessoa.
String rotuloEd(String ed) => ed.isEmpty ? 'Sem elemento de despesa' : 'ED $ed';

/// Pede confirmação para tirar um ED do inventário.
///
/// O que a pessoa precisa registrar antes de confirmar fica em destaque:
/// quantos itens saem e quanto levantamento deixa de contar.
Future<bool> confirmarRemocaoEd(BuildContext context, ResumoEd ed) async {
  final itens = formatarInteiro(ed.itens);
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) {
      final esquema = Theme.of(contexto).colorScheme;
      return AlertDialog(
        title: Text('Remover ${rotuloEd(ed.ed)}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CaixaDeAviso(
                texto: ed.itens == 1
                    ? '1 item sai do inventário: das contagens, dos '
                          'pendentes e dos relatórios, em todos os aparelhos.'
                    : '$itens itens saem do inventário: das contagens, dos '
                          'pendentes e dos relatórios, em todos os aparelhos.',
              ),
              const SizedBox(height: 12),
              if (ed.verificados > 0) ...[
                Text(
                  ed.verificados == 1
                      ? '1 deles já foi verificado. A verificação fica '
                            'guardada e volta junto com o item.'
                      : '${formatarInteiro(ed.verificados)} deles já foram '
                            'verificados. As verificações ficam guardadas e '
                            'voltam junto com os itens.',
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Para desfazer, ligue o elemento de novo aqui ou marque-o '
                'ao importar a planilha outra vez.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            style: FilledButton.styleFrom(
              backgroundColor: esquema.error,
              foregroundColor: esquema.onError,
              minimumSize: const Size(0, 48),
            ),
            child: const Text('Remover'),
          ),
        ],
      );
    },
  );
  return confirmou == true;
}
